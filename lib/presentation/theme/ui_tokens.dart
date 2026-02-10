import 'package:flutter/material.dart';

/// Centralized UI tokens for a cohesive look/feel.
///
/// Why:
/// - Keeps spacing/radius/durations consistent across screens.
/// - Makes “design changes” cheap and low-risk.
final class UiTokens {
  UiTokens._();

  // Spacing scale (4-pt grid)
  static const double s0 = 0;
  static const double s4 = 4;
  static const double s8 = 8;
  static const double s12 = 12;
  static const double s16 = 16;
  static const double s20 = 20;
  static const double s24 = 24;
  static const double s32 = 32;

  // Radii
  static const double r10 = 10;
  static const double r12 = 12;
  static const double r16 = 16;
  static const double r20 = 20;
  static const double r24 = 24;

  // Motion
  static const Duration durFast = Duration(milliseconds: 140);
  static const Duration durMed = Duration(milliseconds: 220);
  static const Duration durSlow = Duration(milliseconds: 360);

  static const Curve curveStandard = Curves.easeOutCubic;
  static const Curve curveEmphasized = Curves.easeInOutCubic;

  // Layout
  static const EdgeInsets pagePadding =
      EdgeInsets.symmetric(horizontal: s16, vertical: s12);
  static const EdgeInsets sectionPadding =
      EdgeInsets.fromLTRB(s16, s16, s16, s8);
}

/// Subtle elevation that works in light/dark without heavy shadows.
BoxShadow softShadow(BuildContext context) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return BoxShadow(
    blurRadius: 18,
    spreadRadius: 0,
    offset: const Offset(0, 10),
    color: (isDark ? Colors.black : Colors.black).withOpacity(isDark ? 0.20 : 0.08),
  );
}

