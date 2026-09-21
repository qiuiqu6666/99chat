import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../settings/feedback_form_view.dart';

/// Presentation only. Complaint payloads and upload handling stay in the page.
class ComplaintFormView extends StatelessWidget {
  const ComplaintFormView(
      {super.key,
      required this.target,
      required this.reason,
      required this.controller,
      required this.screenshots,
      required this.maxScreenshots,
      required this.submitting,
      required this.embedded,
      required this.onSubmit,
      required this.onAddImage,
      required this.onRemoveImage});

  final String target;
  final String reason;
  final TextEditingController controller;
  final List<Uint8List> screenshots;
  final int maxScreenshots;
  final bool submitting;
  final bool embedded;
  final VoidCallback onSubmit;
  final VoidCallback onAddImage;
  final ValueChanged<int> onRemoveImage;

  @override
  Widget build(BuildContext context) => FeedbackFormView(
        target: target,
        reason: reason,
        controller: controller,
        attachments: screenshots,
        maxScreenshots: maxScreenshots,
        submitting: submitting,
        canSubmit: !submitting,
        embedded: embedded,
        onSubmit: onSubmit,
        onAddImage: onAddImage,
        onRemoveImage: onRemoveImage,
      );
}
