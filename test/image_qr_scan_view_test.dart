import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tronclass/widget/image_qr_scan_view.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Future<void> showScanner(
    WidgetTester tester, {
    required Future<XFile?> Function() pick,
    required Future<List<String>> Function(XFile) decode,
    required ValueChanged<String> onResult,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ImageQrScanView(
            pickImage: pick,
            decodeImage: decode,
            onResult: onResult,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('opens picker on entry; cancellation allows retry', (
    tester,
  ) async {
    var picks = 0;
    await showScanner(
      tester,
      pick: () async {
        picks++;
        return null;
      },
      decode: (_) async => throw StateError('must not decode cancellation'),
      onResult: (_) => fail('must not submit cancellation'),
    );
    expect(picks, 1);
    await tester.tap(find.text('选择图片扫码'));
    await tester.pumpAndSettle();
    expect(picks, 2);
  });

  testWidgets('one QR reaches existing result handler once', (tester) async {
    final results = <String>[];
    await showScanner(
      tester,
      pick: () async => XFile('test.png'),
      decode: (_) async => ['test-code', 'test-code'],
      onResult: results.add,
    );
    expect(results, ['test-code']);
    expect(find.text('识别完成，可选择其他图片继续扫码'), findsOneWidget);
  });

  for (final entry in <List<String>, String>{
    []: '未识别到二维码',
    ['one', 'two']: '图片中有多个二维码',
  }.entries) {
    testWidgets('rejects ${entry.value}', (tester) async {
      await showScanner(
        tester,
        pick: () async => XFile('test.png'),
        decode: (_) async => entry.key,
        onResult: (_) => fail('must not submit ambiguous/empty image'),
      );
      expect(find.textContaining(entry.value), findsOneWidget);
    });
  }

  testWidgets('decode failure is recoverable', (tester) async {
    await showScanner(
      tester,
      pick: () async => XFile('broken.png'),
      decode: (_) async => throw StateError('bad image'),
      onResult: (_) => fail('must not submit failed image'),
    );
    expect(find.textContaining('图片读取或识别失败'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNotNull,
    );
  });

  testWidgets('leaving during decode does not deliver a result', (
    tester,
  ) async {
    final decoded = Completer<List<String>>();
    await tester.pumpWidget(
      MaterialApp(
        home: ImageQrScanView(
          pickImage: () async => XFile('test.png'),
          decodeImage: (_) => decoded.future,
          onResult: (_) => fail('must not submit after leaving'),
        ),
      ),
    );
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    decoded.complete(['code']);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  group('macOS clipboard images', () {
    void macTest(String name, WidgetTesterCallback callback) => testWidgets(
      name,
      callback,
      variant: TargetPlatformVariant({TargetPlatform.macOS}),
    );
    const channel = MethodChannel('tronclass/clipboard_image');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    tearDown(() {
      messenger.setMockMethodCallHandler(channel, null);
    });

    Future<void> paste(WidgetTester tester) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pump();
    }

    macTest('Command+V decodes bytes without a file picker or automatic read', (
      tester,
    ) async {
      var reads = 0;
      final results = <String>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'readImage');
        reads++;
        return Uint8List.fromList([1, 2, 3]);
      });
      await showScanner(
        tester,
        pick: () async => throw StateError('picker must stay closed'),
        decode: (file) async {
          expect(await file.readAsBytes(), [1, 2, 3]);
          return ['clipboard-code'];
        },
        onResult: results.add,
      );
      expect(reads, 0);
      await paste(tester);
      await tester.pumpAndSettle();
      expect(reads, 1);
      expect(results, ['clipboard-code']);
    });

    macTest('paste button reports a clipboard without an image', (
      tester,
    ) async {
      messenger.setMockMethodCallHandler(channel, (_) async => null);
      await showScanner(
        tester,
        pick: () async => null,
        decode: (_) async => throw StateError('no image to decode'),
        onResult: (_) => fail('must not submit an empty clipboard'),
      );
      await tester.tap(find.text('粘贴图片扫码（⌘V）'));
      await tester.pumpAndSettle();
      expect(find.textContaining('剪贴板中没有图片'), findsOneWidget);
    });

    macTest('repeated paste during decoding runs only once', (tester) async {
      var reads = 0;
      final decoded = Completer<List<String>>();
      final results = <String>[];
      messenger.setMockMethodCallHandler(channel, (_) async {
        reads++;
        return Uint8List.fromList([1]);
      });
      await showScanner(
        tester,
        pick: () async => null,
        decode: (_) => decoded.future,
        onResult: results.add,
      );
      await paste(tester);
      await paste(tester);
      expect(reads, 1);
      decoded.complete(['code']);
      await tester.pumpAndSettle();
      expect(results, ['code']);
    });

    macTest('clipboard failure is recoverable', (tester) async {
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => throw PlatformException(code: 'unavailable'),
      );
      await showScanner(
        tester,
        pick: () async => null,
        decode: (_) async => [],
        onResult: (_) => fail('must not submit failed clipboard read'),
      );
      await paste(tester);
      await tester.pumpAndSettle();
      expect(find.textContaining('剪贴板读取失败'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, '粘贴图片扫码（⌘V）'),
            )
            .onPressed,
        isNotNull,
      );
    });

    macTest('copied file access failure is not reported as an unclear QR', (
      tester,
    ) async {
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => throw PlatformException(code: 'clipboard_read_failed'),
      );
      await showScanner(
        tester,
        pick: () async => null,
        decode: (_) async => throw StateError('must not decode a file icon'),
        onResult: (_) => fail('must not submit failed file read'),
      );
      await paste(tester);
      await tester.pumpAndSettle();
      expect(find.textContaining('无法读取复制的图片'), findsOneWidget);
    });

    macTest('leaving during clipboard read ignores the result', (tester) async {
      final read = Completer<Uint8List>();
      messenger.setMockMethodCallHandler(channel, (_) => read.future);
      await showScanner(
        tester,
        pick: () async => null,
        decode: (_) async => throw StateError('must not decode after leaving'),
        onResult: (_) => fail('must not submit after leaving'),
      );
      await paste(tester);
      await tester.pumpWidget(const SizedBox.shrink());
      read.complete(Uint8List.fromList([1]));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
