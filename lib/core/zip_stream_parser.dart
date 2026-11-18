import 'dart:io';
import 'dart:typed_data';

// ===================== 内置 CRC32 IEEE (ZIP 使用的标准CRC32) =====================
class _Crc32 {
  static final List<int> _table = () {
    final t = List<int>.filled(256, 0);
    for (int i = 0; i < 256; i++) {
      int c = i;
      for (int j = 0; j < 8; j++) {
        c = (c & 1) != 0 ? (0xEDB88320 ^ (c >> 1)) : (c >> 1);
      }
      t[i] = c;
    }
    return t;
  }();

  static int update(int crc, Uint8List data) {
    int c = crc;
    for (final b in data) {
      c = _table[(c ^ b) & 0xFF] ^ (c >> 8);
    }
    return c;
  }

  static int finish(int crc) => crc ^ 0xFFFFFFFF;
}
// ==============================================================================

enum _EntryState { searchingHeader, inflating, entryDone }

class ZipStreamParser {
  final String localRootDir;
  final void Function(String path, String localPath, int streamOffset) onFileReady;
  final void Function(Object err)? onError;

  ZipStreamParser({required this.localRootDir, required this.onFileReady, this.onError});

  final _scanBuf = BytesBuilder();
  int _scanCursor = 0;
  int _globalStreamOffset = 0;

  _EntryState _state = _EntryState.searchingHeader;
  String? _currentName;
  bool _isUtf8Name = false;
  RawZLibFilter? _inflater;
  RandomAccessFile? _raf;
  int _entryStartOffset = 0;
  int _crcAcc = 0xFFFFFFFF;

  Future<void> feed(Uint8List chunk) async {
    _scanBuf.add(chunk);
    await _drain();
  }

  Future<void> finish() async {
    await _drain();
    if (_state == _EntryState.inflating) {
      await _abortCurrentEntry();
      throw StateError('ZIP stream truncated: unfinished entry');
    }
  }

  Future<void> _drain() async {
    while (true) {
      try {
        switch (_state) {
          case _EntryState.searchingHeader:
            final ok = await _tryParseLocalFileHeader();
            if (!ok) return;
            break;
          case _EntryState.inflating:
            final ok = await _pumpInflate();
            if (!ok) return;
            break;
          case _EntryState.entryDone:
            await _finishCurrentEntry();
            break;
        }
      } catch (e) {
        onError?.call(e);
        await _abortCurrentEntry();
        _state = _EntryState.searchingHeader;
        _scanCursor = 0;
      }
    }
  }

  Future<bool> _tryParseLocalFileHeader() async {
    final buf = _scanBuf.toBytes();
    const magicLfh = 0x04034b50;
    final pos = _findMagic(buf, _scanCursor, magicLfh);
    if (pos < 0) {
      _trimScanBuffer();
      return false;
    }
    _entryStartOffset = _globalStreamOffset + pos;
    if (buf.length < pos + 30) return false;

    final bd = ByteData.sublistView(buf, pos);
    final flag = bd.getUint16(6, Endian.little);
    final method = bd.getUint16(8, Endian.little);
    final nameLen = bd.getUint16(26, Endian.little);
    final extraLen = bd.getUint16(28, Endian.little);
    final totalHeaderLen = 30 + nameLen + extraLen;
    if (buf.length < pos + totalHeaderLen) return false;

    if (method != 8) {
      throw UnsupportedError('unsupported compression method $method, only deflate(8)');
    }
    if ((flag & (1 << 2)) == 0) {
      throw UnsupportedError('ZIP entry without data descriptor (bit3=0), not github archive');
    }
    _isUtf8Name = (flag & (1 << 10)) != 0;

    final nameBytes = buf.sublist(pos + 30, pos + 30 + nameLen);
    _currentName = _isUtf8Name ? String.fromCharCodes(nameBytes) : String.fromCharCodes(nameBytes);

    final remain = buf.sublist(pos + totalHeaderLen);
    _scanBuf.clear();
    _scanBuf.add(remain);
    _scanCursor = 0;
    _globalStreamOffset += pos + totalHeaderLen;

    _inflater = RawZLibFilter.inflateFilter(raw: true);
    _crcAcc = 0xFFFFFFFF;
    _raf = null;
    _state = _EntryState.inflating;
    return true;
  }

  Future<bool> _pumpInflate() async {
    final buf = _scanBuf.toBytes();
    const magicDd = 0x08074b50;
    final ddPos = _findMagic(buf, _scanCursor, magicDd);
    if (ddPos < 0) {
      final feedUpTo = buf.length - 3;
      if (feedUpTo > _scanCursor) {
        final slice = buf.sublist(_scanCursor, feedUpTo);
        await _feedInflater(slice);
        _scanCursor = feedUpTo;
      }
      _trimScanBuffer();
      return false;
    }

    if (ddPos > _scanCursor) {
      final slice = buf.sublist(_scanCursor, ddPos);
      await _feedInflater(slice);
    }

    if (buf.length < ddPos + 16) return false;
    final ddView = ByteData.sublistView(buf, ddPos + 4);
    final expectedCrc = ddView.getUint32(0, Endian.little);

    await _finalizeInflater();
    final actualCrc = _Crc32.finish(_crcAcc);
    if (actualCrc != expectedCrc) {
      throw StateError(
        'CRC mismatch for entry ${_currentName}: calc 0x${actualCrc.toRadixString(16)}, expected 0x${expectedCrc.toRadixString(16)}',
      );
    }

    final remain = buf.sublist(ddPos + 16);
    _scanBuf.clear();
    _scanBuf.add(remain);
    _scanCursor = 0;
    _globalStreamOffset += ddPos + 16;

    _state = _EntryState.entryDone;
    return true;
  }

  Future<void> _feedInflater(Uint8List data) async {
    final filter = _inflater!;
    filter.process(data, 0, data.length);
    List<int>? rawOut;
    while ((rawOut = filter.processed(flush: false)) != null && rawOut!.isNotEmpty) {
      final out = Uint8List.fromList(rawOut);
      await _writeOutput(out);
    }
  }

  Future<void> _finalizeInflater() async {
    final filter = _inflater!;
    List<int>? rawOut = filter.processed(end: true);
    while (rawOut != null && rawOut.isNotEmpty) {
      final out = Uint8List.fromList(rawOut);
      await _writeOutput(out);
      rawOut = filter.processed(end: true);
    }
  }

  Future<void> _writeOutput(Uint8List data) async {
    final name = _currentName!;
    if (name.endsWith('/')) return;
    if (_raf == null) {
      final rel = _stripTopPrefix(name);
      final localPath = '$localRootDir/$rel';
      final f = File(localPath);
      await f.parent.create(recursive: true);
      _raf = await f.open(mode: FileMode.write);
    }
    await _raf!.writeFrom(data);
    _crcAcc = _Crc32.update(_crcAcc, data);
  }

  Future<void> _finishCurrentEntry() async {
    final name = _currentName!;
    if (_raf != null) {
      await _raf!.close();
      final rel = _stripTopPrefix(name);
      final localPath = '$localRootDir/$rel';
      onFileReady(name, localPath, _entryStartOffset);
    }
    await _abortCurrentEntry();
    _state = _EntryState.searchingHeader;
  }

  Future<void> _abortCurrentEntry() async {
    if (_raf != null) {
      try {
        await _raf!.close();
      } catch (_) {}
      _raf = null;
    }
    _inflater = null;
    _currentName = null;
    _crcAcc = 0xFFFFFFFF;
  }

  int _findMagic(Uint8List buf, int startIdx, int magic) {
    final b0 = magic & 0xFF;
    final b1 = (magic >> 8) & 0xFF;
    final b2 = (magic >> 16) & 0xFF;
    final b3 = (magic >> 24) & 0xFF;
    for (int i = startIdx; i + 3 < buf.length; i++) {
      if (buf[i] == b0 && buf[i + 1] == b1 && buf[i + 2] == b2 && buf[i + 3] == b3) {
        return i;
      }
    }
    return -1;
  }

  void _trimScanBuffer() {
    final buf = _scanBuf.toBytes();
    if (buf.length <= 3) return;
    final tail = buf.sublist(buf.length - 3);
    _scanBuf.clear();
    _scanBuf.add(tail);
    _scanCursor = 0;
  }

  String _stripTopPrefix(String name) {
    final slash = name.indexOf('/');
    if (slash > 0 && slash < name.length - 1) {
      return name.substring(slash + 1);
    }
    return name;
  }

  Future<void> abort() async {
    if (_raf != null) {
      await _raf!.close();
      _raf = null;
    }
    _inflater = null;
    _state = _EntryState.searchingHeader;
  }
}
