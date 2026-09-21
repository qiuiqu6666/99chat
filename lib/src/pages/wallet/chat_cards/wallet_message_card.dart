import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:tencent_cloud_chat_demo/src/ui/app_tokens.dart';
import 'package:tencent_cloud_chat_uikit/ui/utils/platform.dart';

class WalletMessageCard extends StatelessWidget {
  final String title;
  final String subTitle;
  final Color color;
  final String footer;
  final Color footerColor;
  final String? leadingAsset;
  final VoidCallback? onTap;

  const WalletMessageCard({
    super.key,
    required this.title,
    required this.subTitle,
    required this.color,
    required this.footer,
    required this.footerColor,
    this.leadingAsset,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDesktop = PlatformUtils().isDesktop;
    final titleSize = isDesktop ? 16.0 : 18.sp;
    final subtitleSize = isDesktop ? 13.0 : 14.sp;
    final footerSize = isDesktop ? 12.0 : 13.sp;
    final borderRadius = BorderRadius.circular(AppTokens.rLg.r);
    return InkWell(
      onTap: onTap,
      borderRadius: borderRadius,
      child: Container(
        width: double.infinity,
        constraints: BoxConstraints(minHeight: 118.h),
        decoration: BoxDecoration(
          color: color,
          borderRadius: borderRadius,
          border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 14.h),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (leadingAsset != null) ...[
                    Container(
                      width: 34.w,
                      height: 34.w,
                      alignment: Alignment.center,
                      child: Image.asset(
                        leadingAsset!,
                        width: 28.w,
                        height: 28.w,
                        fit: BoxFit.contain,
                      ),
                    ),
                    SizedBox(width: 10.w),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: titleSize,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        SizedBox(height: 8.h),
                        Text(
                          subTitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.88),
                            fontSize: subtitleSize,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 10.h),
              decoration: BoxDecoration(
                color: footerColor,
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(AppTokens.rLg.r),
                  bottomRight: Radius.circular(AppTokens.rLg.r),
                ),
              ),
              child: Text(
                footer,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.9),
                  fontSize: footerSize,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
