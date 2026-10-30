import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tronclass/widget/mac_phone_frame.dart';

void main() {
  Future<void> showPhone(
    WidgetTester tester, {
    Size size = const Size(446 * 1.56, 938 * 1.44),
    bool reducedMotion = false,
    Widget? home,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(disableAnimations: reducedMotion),
          child: MacPhoneFrame(child: child!),
        ),
        home: home ?? const Scaffold(body: SafeArea(child: Text('原页面'))),
      ),
    );
    await tester.pump();
  }

  testWidgets('display uses widened layout and safe areas', (tester) async {
    late MediaQueryData media;
    await showPhone(
      tester,
      home: Builder(
        builder: (context) {
          media = MediaQuery.of(context);
          return const Scaffold(body: Text('原页面'));
        },
      ),
    );
    expect(
      media.size.width,
      closeTo(MacPhoneFrame.screenSize.width * 1.44, 0.001),
    );
    expect(media.size.height, closeTo(874 * 1.44, 0.001));
    expect(
      media.size.aspectRatio,
      closeTo(MacPhoneFrame.screenSize.aspectRatio, 0.000001),
    );
    expect(media.padding.top, closeTo(96 * 1.44, 0.001));
    expect(media.padding.bottom, closeTo(34 * 1.44, 0.001));
    expect(media.padding.horizontal, 0);
    expect(find.byKey(const ValueKey('phone-dynamic-island')), findsOneWidget);
    expect(find.byKey(const ValueKey('phone-home-indicator')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('larger status icons fit beside the island', (tester) async {
    await showPhone(tester);
    final signal = tester.getRect(
      find.byIcon(Icons.signal_cellular_alt_rounded),
    );
    final wifi = tester.getRect(find.byIcon(Icons.wifi_rounded));
    final battery = tester.getRect(find.byKey(const ValueKey('phone-battery')));
    final island = tester.getRect(
      find.byKey(const ValueKey('phone-dynamic-island')),
    );
    final display = tester.getRect(find.byKey(const ValueKey('phone-display')));
    expect(signal.width, closeTo(22 * 1.44, 0.001));
    expect(wifi.width, closeTo(21 * 1.44, 0.001));
    expect(battery.width, closeTo(30 * 1.44, 0.001));
    expect(signal.left, greaterThan(island.right));
    expect(battery.right, lessThan(display.right));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'resizing scales the phone without changing display proportions',
    (tester) async {
      await showPhone(tester, size: const Size(312, 656));
      final display = tester.renderObject<RenderBox>(
        find.byKey(const ValueKey('phone-display')),
      );
      final start = display.localToGlobal(Offset.zero);
      final end = display.localToGlobal(
        Offset(display.size.width, display.size.height),
      );
      expect(
        (end.dx - start.dx) / (end.dy - start.dy),
        closeTo(MacPhoneFrame.screenSize.aspectRatio, 0.000001),
      );
      expect(end.dx, lessThanOrEqualTo(312));
      expect(end.dy, lessThanOrEqualTo(656));
      final unit = display.localToGlobal(const Offset(100, 100)) - start;
      expect(unit.dx, closeTo(100, 0.001));
      expect(unit.dy, closeTo(100, 0.001));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'wider window relayouts native content without a scale transform',
    (tester) async {
      await showPhone(tester, size: const Size(446 * 1.56, 938 * 1.44));
      final display = tester.renderObject<RenderBox>(
        find.byKey(const ValueKey('phone-display')),
      );
      final start = display.localToGlobal(Offset.zero);
      final end = display.localToGlobal(
        Offset(display.size.width, display.size.height),
      );
      expect(
        end.dx - start.dx,
        closeTo(MacPhoneFrame.screenSize.width * 1.44, 0.001),
      );
      expect(end.dy - start.dy, closeTo(874 * 1.44, 0.001));
      expect(start.dx, closeTo(22 * 1.44, 0.001));
      expect(start.dy, closeTo(42 * 1.44, 0.001));
      final unit = display.localToGlobal(const Offset(100, 100)) - start;
      expect(unit.dx, closeTo(100, 0.001));
      expect(unit.dy, closeTo(100, 0.001));
      expect(
        display.size.width,
        closeTo(MacPhoneFrame.screenSize.width * 1.44, 0.001),
      );
      expect(display.size.height, closeTo(874 * 1.44, 0.001));
    },
  );

  testWidgets(
    'decorations do not intercept controls and frame survives navigation',
    (tester) async {
      await showPhone(
        tester,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        Scaffold(appBar: AppBar(title: const Text('扫码页'))),
                  ),
                ),
                child: const Text('打开扫码'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开扫码'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('扫码页'), findsOneWidget);
      expect(find.byType(MacPhoneFrame), findsOneWidget);
      expect(
        find.byKey(const ValueKey('phone-dynamic-island')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Reduce Motion stops the decorative animation', (tester) async {
    await showPhone(tester, reducedMotion: true);
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pump(const Duration(seconds: 3));
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets(
    'decorative rim does not continuously recompose native web content',
    (tester) async {
      var builds = 0;
      await showPhone(
        tester,
        home: Builder(
          builder: (_) {
            builds++;
            return const Scaffold(body: Text('原页面'));
          },
        ),
      );
      final initial = builds;
      await tester.pump(const Duration(seconds: 2));
      expect(tester.binding.transientCallbackCount, 0);
      expect(builds, initial);
    },
  );
}
