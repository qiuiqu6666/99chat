// ignore_for_file: must_be_immutable

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:tencent_cloud_chat_uikit/base_widgets/tim_ui_kit_base.dart';
import 'package:tencent_cloud_chat_uikit/base_widgets/tim_ui_kit_statelesswidget.dart';

class TIMUIKitFileIcon extends TIMUIKitStatelessWidget {
  final String? fileFormat;
  final double? size;

  TIMUIKitFileIcon({this.size, this.fileFormat, Key? key}) : super(key: key);

  Widget _getFileIcon(double tileSize) {
    return Image.asset(
      'assets/wenjian.png',
      width: tileSize,
      height: tileSize,
      fit: BoxFit.contain,
    );
  }

  @override
  Widget tuiBuild(BuildContext context, TUIKitBuildValue value) {
    final tileSize = size ?? 50;
    return SizedBox(
      height: tileSize,
      width: tileSize,
      child: _getFileIcon(tileSize),
    );
  }
}
