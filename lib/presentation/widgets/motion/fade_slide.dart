import 'package:flutter/material.dart';

import '../../theme/ui_tokens.dart';

/// A small reusable “fade + slide” transition.
///
/// Works well for banners, small panels, and message appear animations.
class FadeSlide extends StatelessWidget {
  final Animation<double> animation;
  final Widget child;
  final Offset fromOffset;

  const FadeSlide({
    super.key,
    required this.animation,
    required this.child,
    this.fromOffset = const Offset(0, 0.06),
  });

  @override
  Widget build(BuildContext context) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: UiTokens.curveStandard,
      reverseCurve: Curves.easeInCubic,
    );

    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: fromOffset,
          end: Offset.zero,
        ).animate(curved),
        child: child,
      ),
    );
  }
}

/// Convenience transition builder for AnimatedSwitcher.
Widget fadeSlideSwitcherTransition(
  Widget child,
  Animation<double> animation, {
  Offset fromOffset = const Offset(0, 0.06),
}) {
  return FadeSlide(
    animation: animation,
    fromOffset: fromOffset,
    child: child,
  );
}

