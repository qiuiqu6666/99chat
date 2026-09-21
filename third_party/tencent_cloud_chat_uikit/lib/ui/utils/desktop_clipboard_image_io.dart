import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:ffi/ffi.dart';

const _cfDib = 8;
const _cfHdrop = 15;
const _gmemMoveable = 0x0002;
const _gmemDdeShare = 0x2000;
const _maxClipboardEdge = 4096;

typedef _OpenClipboardNative = Int32 Function(IntPtr);
typedef _OpenClipboardDart = int Function(int);
typedef _EmptyClipboardNative = Int32 Function();
typedef _EmptyClipboardDart = int Function();
typedef _CloseClipboardNative = Int32 Function();
typedef _CloseClipboardDart = int Function();
typedef _RegisterClipboardFormatNative = Uint32 Function(Pointer<Utf16>);
typedef _RegisterClipboardFormatDart = int Function(Pointer<Utf16>);
typedef _SetClipboardDataNative = IntPtr Function(Uint32, IntPtr);
typedef _SetClipboardDataDart = int Function(int, int);
typedef _GlobalAllocNative = IntPtr Function(Uint32, IntPtr);
typedef _GlobalAllocDart = int Function(int, int);
typedef _GlobalLockNative = Pointer<Void> Function(IntPtr);
typedef _GlobalLockDart = Pointer<Void> Function(int);
typedef _GlobalUnlockNative = Int32 Function(IntPtr);
typedef _GlobalUnlockDart = int Function(int);
typedef _GlobalFreeNative = IntPtr Function(IntPtr);
typedef _GlobalFreeDart = int Function(int);

Future<bool> writeImagePathToClipboard(String path) async {
  try {
    final file = File(path);
    if (!file.existsSync()) {
      return false;
    }
    final raf = await file.open();
    final head = await raf.read(16);
    await raf.close();
    if (!_looksLikeImageHead(head)) {
      return false;
    }
    final bytes = await file.readAsBytes();
    return copyBytesToImageClipboard(bytes, filePath: path);
  } catch (_) {
    return false;
  }
}

bool _looksLikeImageHead(List<int> bytes) {
  if (bytes.length < 12) {
    return false;
  }
  if (bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) {
    return true;
  }
  if (bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4E &&
      bytes[3] == 0x47) {
    return true;
  }
  if (bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46) {
    return true;
  }
  if (bytes[0] == 0x42 && bytes[1] == 0x4D) {
    return true;
  }
  if (bytes[0] == 0x52 &&
      bytes[1] == 0x49 &&
      bytes[2] == 0x46 &&
      bytes[3] == 0x46 &&
      bytes[8] == 0x57 &&
      bytes[9] == 0x45 &&
      bytes[10] == 0x42 &&
      bytes[11] == 0x50) {
    return true;
  }
  if (bytes[4] == 0x66 &&
      bytes[5] == 0x74 &&
      bytes[6] == 0x79 &&
      bytes[7] == 0x70) {
    final brand = String.fromCharCodes(bytes.sublist(8, 12)).toLowerCase();
    return brand == 'heic' ||
        brand == 'heix' ||
        brand == 'mif1' ||
        brand == 'msf1' ||
        brand == 'avif' ||
        brand == 'avis';
  }
  return false;
}

Future<bool> copyBytesToImageClipboard(
  Uint8List bytes, {
  String? filePath,
}) async {
  if (bytes.isEmpty) {
    return false;
  }
  final encoded = await _encodeClipboardImages(bytes);
  if (encoded == null) {
    return false;
  }
  if (Platform.isWindows) {
    return _setClipboardWin(
      png: encoded.png,
      dib: encoded.dib,
      filePath: filePath,
    );
  }
  if (Platform.isMacOS) {
    return _setClipboardMac(encoded.png);
  }
  return false;
}

class _ClipboardImages {
  const _ClipboardImages({required this.png, required this.dib});

  final Uint8List png;
  final Uint8List dib;
}

Future<_ClipboardImages?> _encodeClipboardImages(Uint8List bytes) async {
  try {
    var targetWidth = 0;
    var targetHeight = 0;
    final probe = await ui.instantiateImageCodec(bytes);
    final probeFrame = await probe.getNextFrame();
    final src = probeFrame.image;
    final maxEdge = src.width > src.height ? src.width : src.height;
    if (maxEdge > _maxClipboardEdge) {
      final scale = _maxClipboardEdge / maxEdge;
      targetWidth = (src.width * scale).round().clamp(1, _maxClipboardEdge);
      targetHeight = (src.height * scale).round().clamp(1, _maxClipboardEdge);
    }
    src.dispose();
    final codec = targetWidth > 0
        ? await ui.instantiateImageCodec(
            bytes,
            targetWidth: targetWidth,
            targetHeight: targetHeight,
          )
        : await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final image = frame.image;
    final pngData = await image.toByteData(format: ui.ImageByteFormat.png);
    final rgbaData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final dib = _encodeDib(
      width: image.width,
      height: image.height,
      rgba: rgbaData?.buffer.asUint8List(),
    );
    image.dispose();
    final png = pngData?.buffer.asUint8List();
    if (png == null || png.isEmpty || dib == null || dib.isEmpty) {
      return null;
    }
    return _ClipboardImages(png: Uint8List.fromList(png), dib: dib);
  } catch (_) {
    return null;
  }
}

Uint8List? _encodeDib({
  required int width,
  required int height,
  required Uint8List? rgba,
}) {
  if (rgba == null || width <= 0 || height <= 0) {
    return null;
  }
  final stride = width * 4;
  if (rgba.length < stride * height) {
    return null;
  }
  final pixelBytes = stride * height;
  final out = Uint8List(40 + pixelBytes);
  final header = ByteData.sublistView(out);
  header.setUint32(0, 40, Endian.little);
  header.setInt32(4, width, Endian.little);
  header.setInt32(8, height, Endian.little);
  header.setUint16(12, 1, Endian.little);
  header.setUint16(14, 32, Endian.little);
  header.setUint32(16, 0, Endian.little);
  header.setUint32(20, pixelBytes, Endian.little);
  for (var y = 0; y < height; y++) {
    final srcRow = (height - 1 - y) * stride;
    final dstRow = 40 + y * stride;
    for (var x = 0; x < width; x++) {
      final si = srcRow + x * 4;
      final di = dstRow + x * 4;
      out[di] = rgba[si + 2];
      out[di + 1] = rgba[si + 1];
      out[di + 2] = rgba[si];
      out[di + 3] = rgba[si + 3];
    }
  }
  return out;
}

Uint8List _encodeHdrop(String path) {
  final pathUnits = path.codeUnits;
  final out = Uint8List(20 + (pathUnits.length + 2) * 2);
  final header = ByteData.sublistView(out);
  header.setUint32(0, 20, Endian.little);
  header.setInt32(16, 1, Endian.little);
  var offset = 20;
  for (final unit in pathUnits) {
    out[offset] = unit & 0xFF;
    out[offset + 1] = (unit >> 8) & 0xFF;
    offset += 2;
  }
  return out;
}

Future<bool> _setClipboardWin({
  required Uint8List png,
  required Uint8List dib,
  String? filePath,
}) async {
  final user32 = DynamicLibrary.open('user32.dll');
  final kernel32 = DynamicLibrary.open('kernel32.dll');
  final openClipboard =
      user32.lookupFunction<_OpenClipboardNative, _OpenClipboardDart>(
    'OpenClipboard',
  );
  final emptyClipboard =
      user32.lookupFunction<_EmptyClipboardNative, _EmptyClipboardDart>(
    'EmptyClipboard',
  );
  final closeClipboard =
      user32.lookupFunction<_CloseClipboardNative, _CloseClipboardDart>(
    'CloseClipboard',
  );
  final registerFormat = user32.lookupFunction<_RegisterClipboardFormatNative,
      _RegisterClipboardFormatDart>('RegisterClipboardFormatW');
  final setClipboardData =
      user32.lookupFunction<_SetClipboardDataNative, _SetClipboardDataDart>(
    'SetClipboardData',
  );
  final globalAlloc =
      kernel32.lookupFunction<_GlobalAllocNative, _GlobalAllocDart>(
    'GlobalAlloc',
  );
  final globalLock =
      kernel32.lookupFunction<_GlobalLockNative, _GlobalLockDart>('GlobalLock');
  final globalUnlock =
      kernel32.lookupFunction<_GlobalUnlockNative, _GlobalUnlockDart>(
    'GlobalUnlock',
  );
  final globalFree =
      kernel32.lookupFunction<_GlobalFreeNative, _GlobalFreeDart>('GlobalFree');

  final name = 'PNG'.toNativeUtf16();
  final pngFormat = registerFormat(name);
  malloc.free(name);
  if (pngFormat == 0) {
    return false;
  }

  var opened = false;
  for (var i = 0; i < 8; i++) {
    if (openClipboard(0) != 0) {
      opened = true;
      break;
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  if (!opened) {
    return false;
  }
  emptyClipboard();
  final dibHandle = _copyToGlobal(dib, globalAlloc, globalLock, globalUnlock);
  if (dibHandle == 0) {
    closeClipboard();
    return false;
  }
  if (setClipboardData(_cfDib, dibHandle) == 0) {
    globalFree(dibHandle);
    closeClipboard();
    return false;
  }
  final pngHandle = _copyToGlobal(png, globalAlloc, globalLock, globalUnlock);
  if (pngHandle != 0) {
    if (setClipboardData(pngFormat, pngHandle) == 0) {
      globalFree(pngHandle);
    }
  }
  if (filePath != null && filePath.isNotEmpty) {
    final dropHandle = _copyToGlobal(
      _encodeHdrop(filePath),
      globalAlloc,
      globalLock,
      globalUnlock,
    );
    if (dropHandle != 0) {
      if (setClipboardData(_cfHdrop, dropHandle) == 0) {
        globalFree(dropHandle);
      }
    }
  }
  closeClipboard();
  return true;
}

int _copyToGlobal(
  Uint8List bytes,
  _GlobalAllocDart globalAlloc,
  _GlobalLockDart globalLock,
  _GlobalUnlockDart globalUnlock,
) {
  final hMem = globalAlloc(_gmemMoveable | _gmemDdeShare, bytes.length);
  if (hMem == 0) {
    return 0;
  }
  final locked = globalLock(hMem);
  if (locked.address == 0) {
    return 0;
  }
  locked.cast<Uint8>().asTypedList(bytes.length).setAll(0, bytes);
  globalUnlock(hMem);
  return hMem;
}

Future<bool> _setClipboardMac(Uint8List png) async {
  try {
    final file = File(
      '${Directory.systemTemp.path}/media_clipboard_${DateTime.now().microsecondsSinceEpoch}.png',
    );
    await file.writeAsBytes(png, flush: true);
    final escaped = file.path.replaceAll(r'\', '/').replaceAll('"', r'\"');
    final result = await Process.run('osascript', [
      '-e',
      'set the clipboard to (read (POSIX file "$escaped") as «class PNGf»)',
    ]);
    try {
      await file.delete();
    } catch (_) {}
    return result.exitCode == 0;
  } catch (_) {
    return false;
  }
}
