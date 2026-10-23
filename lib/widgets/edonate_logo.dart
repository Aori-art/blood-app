import 'package:flutter/material.dart';

import '../app_colors.dart';

/// The eDonate brand mark (Dugtong on the crimson rounded square), shown next
/// to the "eDonate" wordmark.
class EdonateLogo extends StatelessWidget {
  static const String asset = 'assets/branding/edonate_logo_rounded_512.png';

  final double size;
  const EdonateLogo({super.key, this.size = 36});

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return Image.asset(
      asset,
      width: size,
      height: size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      semanticLabel: 'eDonate logo',
      // Decode at the size it is shown, not at 512 px.
      cacheWidth: (size * dpr).round(),
      // If the asset is missing, the previous mark: a water drop on the
      // brand gradient.
      errorBuilder: (_, _, _) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(size * 10 / 36),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: AppColors.primaryGradient,
          ),
        ),
        alignment: Alignment.center,
        child: Icon(Icons.water_drop, color: Colors.white, size: size / 2),
      ),
    );
  }
}
