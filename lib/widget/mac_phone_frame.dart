import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Phone layout widened to match 1.56x width and 1.44x height without stretching text.
class MacPhoneFrame extends StatelessWidget {
  const MacPhoneFrame({super.key, required this.child});

  static const screenSize = Size(446 * 1.56 / 1.44 - 44, 874);
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = MacPhoneFrame.screenSize.width + 44;
        final scale = math.min(
          constraints.maxWidth / width,
          constraints.maxHeight / 938,
        );
        final displaySize = MacPhoneFrame.screenSize * scale;
        final safeArea = EdgeInsets.only(top: 96 * scale, bottom: 34 * scale);
        return Center(
          child: SizedBox(
            width: width * scale,
            height: 938 * scale,
            child: Stack(
              children: [
                // Only decoration is transformed; native web content uses window coordinates.
                Positioned.fill(
                  child: FittedBox(
                    child: SizedBox(
                      width: width,
                      height: 938,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 32, 12, 12),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(62),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x0C091D28),
                                blurRadius: 10,
                                offset: Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Stack(
                            children: [
                              // Keep the rim below platform views so it cannot block native input.
                              Positioned.fill(
                                child: IgnorePointer(
                                  child: RepaintBoundary(
                                    child: CustomPaint(
                                      painter: _GlassRimPainter(
                                        highContrast: media.highContrast,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 22 * scale,
                  top: 42 * scale,
                  width: displaySize.width,
                  height: displaySize.height,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(52 * scale),
                    child: RepaintBoundary(
                      key: const ValueKey('phone-display'),
                      child: MediaQuery(
                        data: media.copyWith(
                          size: displaySize,
                          padding: safeArea,
                          viewPadding: safeArea,
                        ),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            child,
                            Positioned(
                              left: 0,
                              right: 0,
                              top: 0,
                              height: 62 * scale,
                              child: IgnorePointer(
                                child: FittedBox(
                                  child: SizedBox(
                                    width: MacPhoneFrame.screenSize.width,
                                    height: 62,
                                    child: const _PhoneStatusBar(),
                                  ),
                                ),
                              ),
                            ),
                            Positioned(
                              left: (displaySize.width - 134 * scale) / 2,
                              width: 134 * scale,
                              bottom: 9 * scale,
                              child: IgnorePointer(
                                child: Container(
                                  key: const ValueKey('phone-home-indicator'),
                                  height: 5 * scale,
                                  decoration: BoxDecoration(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurface,
                                    borderRadius: BorderRadius.circular(
                                      4 * scale,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _PhoneStatusBar extends StatelessWidget {
  const _PhoneStatusBar();

  @override
  Widget build(BuildContext context) {
    final ink = Theme.of(context).colorScheme.onSurface;
    return ExcludeSemantics(
      child: SizedBox(
        height: 62,
        child: Stack(
          children: [
            Align(
              alignment: Alignment.topCenter,
              child: Container(
                key: const ValueKey('phone-dynamic-island'),
                margin: const EdgeInsets.only(top: 12),
                width: 98,
                height: 30,
                decoration: BoxDecoration(
                  color: const Color(0xFF08090B),
                  borderRadius: BorderRadius.circular(18),
                ),
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 9),
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [Color(0xFF172C42), Color(0xFF080A0F)],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 17,
              right: 25,
              child: Row(
                children: [
                  Icon(Icons.signal_cellular_alt_rounded, size: 22, color: ink),
                  const SizedBox(width: 4),
                  Icon(Icons.wifi_rounded, size: 21, color: ink),
                  const SizedBox(width: 5),
                  Container(
                    key: const ValueKey('phone-battery'),
                    width: 30,
                    height: 15,
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      border: Border.all(color: ink.withValues(alpha: 0.5)),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: ink,
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                  ),
                  Container(
                    width: 2.5,
                    height: 6,
                    color: ink.withValues(alpha: 0.5),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GlassRimPainter extends CustomPainter {
  const _GlassRimPainter({required this.highContrast});
  final bool highContrast;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    final outer = RRect.fromRectAndRadius(
      bounds.deflate(1),
      const Radius.circular(61),
    );
    final inner = RRect.fromRectAndRadius(
      bounds.deflate(9),
      const Radius.circular(53),
    );
    final ring = Path()
      ..fillType = PathFillType.evenOdd
      ..addRRect(outer)
      ..addRRect(inner);
    canvas.save();
    canvas.clipPath(ring);
    canvas.drawRect(
      bounds,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0x28FFFFFF), Color(0x00FFFFFF), Color(0x14FFFFFF)],
        ).createShader(bounds),
    );
    canvas.restore();
    canvas.drawRRect(
      outer,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.32)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8,
    );
    canvas.drawRRect(
      inner,
      Paint()
        ..color = const Color(0x33253940)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
  }

  @override
  bool shouldRepaint(_GlassRimPainter oldDelegate) =>
      oldDelegate.highContrast != highContrast;
}
