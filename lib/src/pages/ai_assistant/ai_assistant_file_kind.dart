import 'package:flutter/material.dart';
import 'package:tencent_cloud_chat_demo/src/pages/ai_assistant/ai_assistant_models.dart';

class AiAssistantFileKinds {
  AiAssistantFileKinds._();

  static AiAssistantFileKind fromName(String fileName) {
    final trimmed = fileName.trim();
    final dot = trimmed.lastIndexOf('.');
    if (dot < 0 || dot == trimmed.length - 1) {
      return AiAssistantFileKind.unknown;
    }
    switch (trimmed.substring(dot + 1).toLowerCase()) {
      case 'pdf':
        return AiAssistantFileKind.pdf;
      case 'doc':
      case 'docx':
        return AiAssistantFileKind.word;
      case 'xls':
      case 'xlsx':
      case 'csv':
        return AiAssistantFileKind.excel;
      case 'ppt':
      case 'pptx':
        return AiAssistantFileKind.ppt;
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
      case 'webp':
      case 'heic':
        return AiAssistantFileKind.image;
      case 'mp4':
      case 'mov':
      case 'webm':
      case 'avi':
      case 'mkv':
        return AiAssistantFileKind.video;
      case 'mp3':
      case 'wav':
      case 'm4a':
      case 'aac':
        return AiAssistantFileKind.audio;
      case 'txt':
      case 'md':
        return AiAssistantFileKind.text;
      case 'zip':
      case 'rar':
      case '7z':
        return AiAssistantFileKind.archive;
      default:
        return AiAssistantFileKind.unknown;
    }
  }

  static IconData icon(AiAssistantFileKind kind) {
    switch (kind) {
      case AiAssistantFileKind.pdf:
        return Icons.picture_as_pdf;
      case AiAssistantFileKind.word:
        return Icons.description_outlined;
      case AiAssistantFileKind.excel:
        return Icons.table_chart_outlined;
      case AiAssistantFileKind.ppt:
        return Icons.slideshow_outlined;
      case AiAssistantFileKind.image:
        return Icons.image_outlined;
      case AiAssistantFileKind.video:
        return Icons.videocam_outlined;
      case AiAssistantFileKind.audio:
        return Icons.audiotrack_outlined;
      case AiAssistantFileKind.text:
        return Icons.article_outlined;
      case AiAssistantFileKind.archive:
        return Icons.folder_zip_outlined;
      case AiAssistantFileKind.unknown:
        return Icons.insert_drive_file_outlined;
    }
  }

  static Color color(AiAssistantFileKind kind) {
    switch (kind) {
      case AiAssistantFileKind.pdf:
        return const Color(0xFFE60022);
      case AiAssistantFileKind.word:
        return const Color(0xFF2B579A);
      case AiAssistantFileKind.excel:
        return const Color(0xFF217346);
      case AiAssistantFileKind.ppt:
        return const Color(0xFFD24726);
      case AiAssistantFileKind.image:
        return const Color(0xFF7C3AED);
      case AiAssistantFileKind.video:
        return const Color(0xFF0EA5E9);
      case AiAssistantFileKind.audio:
        return const Color(0xFFDB2777);
      case AiAssistantFileKind.text:
        return const Color(0xFF4B5563);
      case AiAssistantFileKind.archive:
        return const Color(0xFFCA8A04);
      case AiAssistantFileKind.unknown:
        return const Color(0xFF6B7280);
    }
  }

  static String badge(AiAssistantFileKind kind) {
    switch (kind) {
      case AiAssistantFileKind.pdf:
        return 'PDF';
      case AiAssistantFileKind.word:
        return 'DOC';
      case AiAssistantFileKind.excel:
        return 'XLS';
      case AiAssistantFileKind.ppt:
        return 'PPT';
      case AiAssistantFileKind.image:
        return 'IMG';
      case AiAssistantFileKind.video:
        return 'VID';
      case AiAssistantFileKind.audio:
        return 'AUD';
      case AiAssistantFileKind.text:
        return 'TXT';
      case AiAssistantFileKind.archive:
        return 'ZIP';
      case AiAssistantFileKind.unknown:
        return 'FILE';
    }
  }
}
