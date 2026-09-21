import 'package:flutter/material.dart';

/// 与 App 设置页一致的返回箭头。
class TIMUIKitBackButton extends StatelessWidget {
  final Color? color;
  final VoidCallback? onPressed;

  const TIMUIKitBackButton({
    super.key,
    this.color,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.arrow_back_ios_new_rounded),
      color: color,
      onPressed: onPressed ?? () => Navigator.of(context).maybePop(),
    );
  }
}
