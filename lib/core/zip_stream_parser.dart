import 'dart:io';
import 'dart:typed_data';

/// 单次任务内复用的 ZIP 流式解析器。
/// 负责：搜索 Local File Header → 提取文件名 → 流式 DEFLATE 解压 → 落盘 → 累计偏移。
class ZipStreamParser {
  final String localRootDir;
  final void Function(String path, String localPath, int cumulativeOffset) onFileReady;

  final _headerScanBuf = BytesBuilder();
  final _fileOutBuf = BytesBuilder();

  int _consumedBytes = 0;

  _EntryState _state = _EntryState.searchingHeader;
  String? _currentName;
  RawZLibFilter? _inflater;

  ZipStreamParser({required this.localRootDir, required this.onFileReady});

  Future<void> feed(Uint8List chunk) async {
    _headerScanBuf.add(chunk);
    await _drain();
  }

  Future<void> finish() async {
    await _drain();
    if (_state == _EntryState.inflating) {
      await _finishCurrentEntry();
    }
  }

  Future<void> _drain() async {
    while (true) {
      if (_state == _EntryState.searchingHeader) {
        if (!_tryParseHeader()) return;
      } else if (_state == _EntryState.inflating) {
        if (!await _pumpInflate()) return;
      } else if (_state == _EntryState.entryDone) {
        await _finishCurrentEntry();
      }
    }
  }

  /// 在缓冲区中搜索并解析 Local File Header。成功则进入 inflating 状态。
  bool _tryParseHeader() {
    final buf = _headerScanBuf.toBytes();

    int start = -1;
    for (var i = 0; i + 4 <= buf.length; i++) {
      if (buf[i] == 0x50 && buf[i + 1] == 0x4B && buf[i + 2] == 0x03 && buf[i + 3] == 0x04) {
        start = i;
        break;
      }
    }

    if (start < 0) {
      // 保留最后 3 字节，防止签名跨块
      final keep = buf.length > 3 ? buf.sublist(buf.length - 3) : buf;
      _headerScanBuf.clear();
      _headerScanBuf.add(keep);
      return false;
    }

    // 头部至少 30 字节
    if (buf.length < start + 30) return false;

    final header = ByteData.sublistView(buf, start);
    final nameLen = header.getUint16(26, Endian.little);
    final extraLen = header.getUint16(28, Endian.little);
    final totalHeader = 30 + nameLen + extraLen;

    if (buf.length < start + totalHeader) return false;

    final nameBytes = buf.sublist(start + 30, start + 30 + nameLen);
    final name = String.fromCharCodes(nameBytes);

    // 截掉头部字节，保留剩余数据（剩余数据属于当前条目的压缩数据）
    final remaining = buf.sublist(start + totalHeader);
    _headerScanBuf.clear();
    _headerScanBuf.add(remaining);
    _consumedBytes += start + totalHeader;

    _currentName = name;
    _fileOutBuf.clear();
    _inflater = RawZLibFilter.inflateFilter(raw: true);
    _state = _EntryState.inflating;
    return true;
  }

  /// 把缓冲区数据喂给解压器。
  /// 关键：不依赖 filter.ended（不存在），而是在缓冲区中搜索下一个 PK\x03\x04 来判断条目边界。
  Future<bool> _pumpInflate() async {
    final buf = _headerScanBuf.toBytes();
    if (buf.isEmpty) return false;

    // 在缓冲区中搜索下一个文件头签名，以此判断当前条目的压缩数据是否已经完整到达
    int nextHeader = -1;
    for (var i = 0; i + 4 <= buf.length; i++) {
      if (buf[i] == 0x50 && buf[i + 1] == 0x4B && buf[i + 2] == 0x03 && buf[i + 3] == 0x04) {
        nextHeader = i;
        break;
      }
    }

    if (nextHeader < 0) {
      // 还没看到下一个文件头，说明当前条目数据可能不完整。
      // 保守策略：暂时不消费缓冲区，等更多数据到达。
      // 但如果缓冲区很大（比如超过 1MB），可以先把前面大部分喂给解压器，保留尾部几个字节。
      if (buf.length > 1024 * 1024) {
        final feedLen = buf.length - 16; // 保留尾部 16 字节防止签名跨块
        if (feedLen > 0) {
          _headerScanBuf.clear();
          _headerScanBuf.add(buf.sublist(feedLen));
          final filter = _inflater!;
          filter.process(buf.sublist(0, feedLen), 0, feedLen);
          final out = filter.processed(flush: false);
          if (out != null && out.isNotEmpty) {
            _fileOutBuf.add(out);
            _consumedBytes += out.length;
          }
        }
      }
      return false;
    }

    // 找到了下一个文件头。nextHeader 之前的字节属于当前条目的压缩数据。
    if (nextHeader > 0) {
      final filter = _inflater!;
      filter.process(buf.sublist(0, nextHeader), 0, nextHeader);
      final out = filter.processed(flush: false);
      if (out != null && out.isNotEmpty) {
        _fileOutBuf.add(out);
        _consumedBytes += out.length;
      }
    }

    // 更新缓冲区：只保留从下一个文件头开始的数据
    _headerScanBuf.clear();
    _headerScanBuf.add(buf.sublist(nextHeader));

    // 当前条目数据已完整，进入收尾状态
    _state = _EntryState.entryDone;
    return true;
  }

  Future<void> _finishCurrentEntry() async {
    final filter = _inflater;
    if (filter != null) {
      // 用 end: true 收尾，获取剩余输出
      final out = filter.processed(end: true);
      if (out != null && out.isNotEmpty) {
        _fileOutBuf.add(out);
      }
    }

    final name = _currentName;
    if (name != null && name.isNotEmpty && !name.endsWith('/')) {
      final normalized = _stripTopPrefix(name);
      final file = File('$localRootDir/$normalized');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(_fileOutBuf.takeBytes());
      onFileReady(name, file.path, _consumedBytes);
    }

    _inflater = null;
    _currentName = null;
    _state = _EntryState.searchingHeader;
  }

  String _stripTopPrefix(String name) {
    final idx = name.indexOf('/');
    if (idx >= 0 && idx < name.length - 1) {
      return name.substring(idx + 1);
    }
    return name;
  }
}

enum _EntryState { searchingHeader, inflating, entryDone }
