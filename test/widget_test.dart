// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:tronclass/data/get_storage.dart';
import 'package:tronclass/path.dart';

import 'package:tronclass/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  setUpAll(() async {
    temp = await Directory.systemTemp.createTemp('tronclass-root-test-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => temp.path,
        );
    applicationSupportDirectory = temp;
    getStorage = GetStorage('root-test', temp.path);
    await getStorage.initStorage;
  });
  tearDown(() => Get.reset());
  tearDownAll(() async => temp.delete(recursive: true));
  testWidgets('App renders root page', (tester) async {
    await tester.pumpWidget(const TronClassPlusApp());
    await tester.pumpAndSettle();

    expect(find.byType(TronClassPlusApp), findsOneWidget);
  });
}
