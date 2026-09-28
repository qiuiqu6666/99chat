import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:tencent_cloud_chat_demo/src/utils/app_version.dart';

import 'api_client.dart';
import 'package:tencent_cloud_chat_demo/utils/api_response_util.dart';

class FeedbackDiagnosticsNotAccepted implements Exception {
  const FeedbackDiagnosticsNotAccepted();
}

enum FeedbackType {
  suggestion('suggestion', '建议'),
  bug('bug', '错误'),
  other('other', '其他');

  const FeedbackType(this.value, this.label);

  final String value;
  final String label;
}

class FeedbackScreenshot {
  const FeedbackScreenshot({
    required this.filename,
    required this.bytes,
  });

  final String filename;
  final Uint8List bytes;
}

class FeedbackSubmitResult {
  const FeedbackSubmitResult({
    required this.id,
    required this.type,
    required this.content,
    required this.screenshotUrls,
    required this.clientVersion,
    required this.createdAt,
  });

  final int id;
  final String type;
  final String content;
  final List<String> screenshotUrls;
  final String clientVersion;
  final DateTime? createdAt;

  factory FeedbackSubmitResult.fromJson(Map<String, dynamic> json) {
    final urls = json['screenshotUrls'];
    return FeedbackSubmitResult(
      id: json['id'] as int? ?? 0,
      type: json['type']?.toString() ?? '',
      content: json['content']?.toString() ?? '',
      screenshotUrls: urls is List
          ? urls.map((e) => e.toString()).where((e) => e.isNotEmpty).toList()
          : const [],
      clientVersion: json['clientVersion']?.toString() ?? '',
      createdAt: _parseDateTime(json['createdAt']),
    );
  }

  static DateTime? _parseDateTime(Object? value) {
    final raw = value?.toString().trim() ?? '';
    if (raw.isEmpty) return null;
    return DateTime.tryParse(raw);
  }
}

class FeedbackApi {
  FeedbackApi._();

  static final FeedbackApi instance = FeedbackApi._();

  Dio get _dio => ApiClient.instance.dio;

  Future<FeedbackSubmitResult> submit({
    required FeedbackType type,
    required String content,
    String? clientVersion,
    List<FeedbackScreenshot> screenshots = const [],
    Uint8List? diagnostics,
  }) async {
    final resolvedClientVersion = clientVersion?.trim().isNotEmpty == true
        ? clientVersion!.trim()
        : await AppVersion.getClientVersion();
    final form = FormData.fromMap({
      'type': type.value,
      'content': content.trim(),
      'clientVersion': resolvedClientVersion,
    });

    for (final screenshot in screenshots) {
      form.files.add(
        MapEntry(
          'screenshots',
          MultipartFile.fromBytes(
            screenshot.bytes,
            filename: screenshot.filename,
          ),
        ),
      );
    }

    if (diagnostics != null) {
      if (diagnostics.length > 2 * 1024 * 1024) {
        throw ArgumentError('Diagnostic report exceeds 2 MB');
      }
      form.files.add(MapEntry(
          'diagnostics',
          MultipartFile.fromBytes(
            diagnostics,
            filename: 'chat-recovery.txt',
          )));
      form.fields.add(const MapEntry('diagnosticsConsent', 'true'));
    }

    final res = await _dio.post(
      '/feedback',
      data: form,
      options: Options(contentType: 'multipart/form-data'),
    );

    final raw = unwrapApiPayload(res.data);
    final map = raw is Map<String, dynamic>
        ? raw
        : raw is Map
            ? Map<String, dynamic>.from(raw)
            : <String, dynamic>{};
    if (diagnostics != null && map['diagnosticsAttached'] != true) {
      throw const FeedbackDiagnosticsNotAccepted();
    }
    return FeedbackSubmitResult.fromJson(map);
  }
}
