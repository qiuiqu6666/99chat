import 'dart:io';
import 'dart:typed_data';

class XfyunAudioFileInfo {
  const XfyunAudioFileInfo({
    required this.dataOffset,
    required this.dataLength,
    required this.sampleRate,
    required this.channels,
    required this.bitsPerSample,
  });

  final int dataOffset;
  final int dataLength;
  final int sampleRate;
  final int channels;
  final int bitsPerSample;

  int get bytesPerSecond => sampleRate * channels * bitsPerSample ~/ 8;
  bool get isXfyunPcm =>
      sampleRate == XfyunAudioUtils.defaultSampleRate &&
      channels == 1 &&
      bitsPerSample == 16;
}

class XfyunAudioUtils {
  XfyunAudioUtils._();

  static const int defaultSampleRate = 8000;

  static Future<XfyunAudioFileInfo?> inspectFile(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      return null;
    }
    final length = await file.length();
    if (length <= 0) {
      return null;
    }

    final reader = await file.open();
    try {
      final riffHeader = await reader.read(12);
      if (riffHeader.length < 12 || !_isWav(riffHeader)) {
        return XfyunAudioFileInfo(
          dataOffset: 0,
          dataLength: length,
          sampleRate: defaultSampleRate,
          channels: 1,
          bitsPerSample: 16,
        );
      }

      int? sampleRate;
      int? channels;
      int? bitsPerSample;
      int? dataOffset;
      int? dataLength;
      var position = 12;
      while (position + 8 <= length) {
        await reader.setPosition(position);
        final chunkHeader = await reader.read(8);
        if (chunkHeader.length < 8) {
          break;
        }
        final chunkId = String.fromCharCodes(chunkHeader.sublist(0, 4));
        final declaredSize = ByteData.sublistView(
          chunkHeader,
        ).getUint32(4, Endian.little);
        final chunkDataOffset = position + 8;
        final remaining = length - chunkDataOffset;
        if (declaredSize > remaining) {
          return null;
        }

        if (chunkId == 'fmt ' && declaredSize >= 16) {
          final formatBytes = await reader.read(16);
          if (formatBytes.length < 16) {
            return null;
          }
          final format = ByteData.sublistView(formatBytes);
          if (format.getUint16(0, Endian.little) != 1) {
            return null;
          }
          channels = format.getUint16(2, Endian.little);
          sampleRate = format.getUint32(4, Endian.little);
          bitsPerSample = format.getUint16(14, Endian.little);
        } else if (chunkId == 'data') {
          dataOffset = chunkDataOffset;
          dataLength = declaredSize;
          if (sampleRate != null) {
            break;
          }
        }

        position =
            chunkDataOffset + declaredSize + (declaredSize.isOdd ? 1 : 0);
      }

      if (sampleRate == null ||
          channels == null ||
          bitsPerSample == null ||
          dataOffset == null ||
          dataLength == null ||
          sampleRate <= 0 ||
          channels <= 0 ||
          bitsPerSample <= 0 ||
          dataLength <= 0) {
        return null;
      }
      return XfyunAudioFileInfo(
        dataOffset: dataOffset,
        dataLength: dataLength,
        sampleRate: sampleRate,
        channels: channels,
        bitsPerSample: bitsPerSample,
      );
    } finally {
      await reader.close();
    }
  }

  static Future<Uint8List?> readPcmBytes(String path) async {
    final info = await inspectFile(path);
    if (info == null || info.dataLength <= 0) {
      return null;
    }
    final reader = await File(path).open();
    try {
      await reader.setPosition(info.dataOffset);
      return reader.read(info.dataLength);
    } finally {
      await reader.close();
    }
  }

  static Uint8List? extractPcmFromWav(Uint8List bytes) {
    if (!_isWav(bytes)) {
      return bytes;
    }
    var position = 12;
    while (position + 8 <= bytes.length) {
      final chunkSize = ByteData.sublistView(
        bytes,
        position + 4,
        position + 8,
      ).getUint32(0, Endian.little);
      final dataOffset = position + 8;
      if (chunkSize > bytes.length - dataOffset) {
        return null;
      }
      final chunkId = String.fromCharCodes(
        bytes.sublist(position, position + 4),
      );
      if (chunkId == 'data') {
        return Uint8List.sublistView(bytes, dataOffset, dataOffset + chunkSize);
      }
      position = dataOffset + chunkSize + (chunkSize.isOdd ? 1 : 0);
    }
    return null;
  }

  static int estimateDurationMs(
    Uint8List pcmBytes, {
    int sampleRate = defaultSampleRate,
  }) {
    if (pcmBytes.isEmpty || sampleRate <= 0) {
      return 0;
    }
    final bytesPerSecond = sampleRate * 2;
    return ((pcmBytes.length / bytesPerSecond) * 1000).ceil();
  }

  static Future<int> estimateWavDurationSec(String path) async {
    try {
      final info = await inspectFile(path);
      final bytesPerSecond = info?.bytesPerSecond ?? 0;
      if (info == null || bytesPerSecond <= 0) {
        return 0;
      }
      return (info.dataLength / bytesPerSecond).ceil().clamp(1, 3600);
    } catch (_) {
      return 0;
    }
  }

  static bool _isWav(List<int> bytes) {
    if (bytes.length < 12) {
      return false;
    }
    return String.fromCharCodes(bytes.sublist(0, 4)) == 'RIFF' &&
        String.fromCharCodes(bytes.sublist(8, 12)) == 'WAVE';
  }
}
