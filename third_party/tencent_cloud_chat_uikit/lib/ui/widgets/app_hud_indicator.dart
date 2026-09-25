import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// Shared compact HUD artwork for UID lookups and media saves.
class AppHudIndicator extends StatelessWidget {
  const AppHudIndicator({super.key});

  @override
  Widget build(BuildContext context) => Container(
        width: 84,
        height: 84,
        decoration: BoxDecoration(
          color: const Color(0xCC4A4A4A),
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Center(
          child: CupertinoActivityIndicator(
            key: ValueKey('app_hud_indicator'),
            radius: 16,
            color: Colors.white,
          ),
        ),
      );
}
