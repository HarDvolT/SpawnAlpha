import 'dart:io';
import 'dart:typed_data';

/// Whether the MP4 at [file] has a sound track: a `trak` whose `hdlr` is
/// `soun`. Null when the file can't be read as MP4.
///
/// Reads only box headers and the `moov` box, so it is quick on long takes.
Future<bool?> mp4HasAudioTrack(File file) async {
  RandomAccessFile? raf;
  try {
    raf = await file.open();
    final length = await raf.length();
    var offset = 0;
    while (offset + 8 <= length) {
      await raf.setPosition(offset);
      final header = await raf.read(16);
      if (header.length < 8) return null;
      final view = ByteData.sublistView(header);
      var size = view.getUint32(0);
      final type = String.fromCharCodes(header.sublist(4, 8));
      var headerSize = 8;
      if (size == 1) {
        if (header.length < 16) return null;
        size = view.getUint64(8);
        headerSize = 16;
      } else if (size == 0) {
        size = length - offset;
      }
      if (size < headerSize) return null;
      if (type == 'moov') {
        await raf.setPosition(offset + headerSize);
        final moov = await raf.read(size - headerSize);
        return moovHasAudioTrack(moov);
      }
      offset += size;
    }
    return null;
  } on FileSystemException {
    return null;
  } finally {
    await raf?.close();
  }
}

/// Whether the body of a `moov` box holds a sound track.
bool moovHasAudioTrack(Uint8List moov) {
  for (final trak in _boxes(moov, 'trak')) {
    for (final mdia in _boxes(trak, 'mdia')) {
      for (final hdlr in _boxes(mdia, 'hdlr')) {
        // hdlr: version and flags (4), pre-defined (4), handler type (4).
        if (hdlr.length >= 12 && String.fromCharCodes(hdlr.sublist(8, 12)) == 'soun') return true;
      }
    }
  }
  return false;
}

/// The bodies of the child boxes of [data] with [type].
Iterable<Uint8List> _boxes(Uint8List data, String type) sync* {
  final view = ByteData.sublistView(data);
  var offset = 0;
  while (offset + 8 <= data.length) {
    var size = view.getUint32(offset);
    var headerSize = 8;
    if (size == 1 && offset + 16 <= data.length) {
      size = view.getUint64(offset + 8);
      headerSize = 16;
    } else if (size == 0) {
      size = data.length - offset;
    }
    if (size < headerSize || offset + size > data.length) return;
    if (String.fromCharCodes(data.sublist(offset + 4, offset + 8)) == type) {
      yield Uint8List.sublistView(data, offset + headerSize, offset + size);
    }
    offset += size;
  }
}
