import 'package:flutter/material.dart';
import 'package:tencent_cloud_chat_demo/src/ui/components/app_search_bar.dart';

/// Same search surface for a contact search entry and an editable group filter.
class DirectorySearchBar extends StatelessWidget {
  const DirectorySearchBar(
      {super.key,
      required this.hint,
      this.controller,
      this.onChanged,
      this.onTap});
  final String hint;
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: AppSearchBar(
            hint: hint,
            controller: controller,
            onChanged: onChanged,
            onTap: onTap,
            readOnly: onTap != null,
            minHeight: 44,
            fontSize: 15),
      );
}
