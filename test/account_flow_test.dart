import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:tronclass/auth/account_manager_controller.dart';
import 'package:tronclass/auth/account_manager_page.dart';
import 'package:tronclass/auth/login_page.dart';
import 'package:tronclass/auth/org_search_page.dart';
import 'package:tronclass/auth/saved_account_storage.dart';
import 'package:tronclass/data/get_storage.dart';
import 'package:tronclass/data/model/tron_org.dart';
import 'package:tronclass/data/org_store.dart';
import 'package:tronclass/routes.dart';
import 'package:tronclass/path.dart';

class FixtureAccounts extends AccountManagerController {
  FixtureAccounts(this.current);
  final bool current;
  @override
  void onInit() {
    currentUsername.value = current ? 'fixture' : 'another-user';
    accounts.assignAll([
      SavedAccount(
        username: 'fixture',
        displayName: '测试用户',
        org: AppOrg.guet,
        loginMethod: LoginMethod.webView,
        updatedAt: DateTime(2026, 10, 30),
      ),
    ]);
  }

  @override
  bool hasSession(SavedAccount account) => true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  setUpAll(() async {
    temp = await Directory.systemTemp.createTemp('tronclass-account-flow-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => temp.path,
        );
    applicationSupportDirectory = temp;
    getStorage = GetStorage('fixture', temp.path);
    await getStorage.initStorage;
    await getStorage.write(GetStorageKeys.lastLoginUsername, 'existing-user');
  });
  tearDown(() async => Get.reset());
  tearDownAll(() async => temp.delete(recursive: true));

  Future<void> showAccounts(WidgetTester tester, {bool current = true}) async {
    tester.view.physicalSize = const Size(300, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    Get.put<AccountManagerController>(FixtureAccounts(current));
    await tester.pumpWidget(
      GetMaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.2)),
          child: child!,
        ),
        home: const AccountManagerPage(),
        getPages: AppRoute.routes
            .where(
              (r) =>
                  r.name == AppRoute.orgSearchPage ||
                  r.name == AppRoute.loginPage,
            )
            .toList(),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final current in [true, false]) {
    testWidgets('account buttons wrap without overflow, current=$current', (
      tester,
    ) async {
      await showAccounts(tester, current: current);
      expect(tester.takeException(), isNull);
      expect(find.text('删除'), findsOneWidget);
      expect(find.text('重新登录'), findsOneWidget);
      expect(find.text(current ? '退出' : '切换'), findsOneWidget);
      final card = tester.getRect(find.byType(Card));
      for (final finder in [
        find.widgetWithText(TextButton, '删除'),
        find.byType(FilledButton),
      ]) {
        final button = tester.getRect(finder);
        expect(button.left, greaterThanOrEqualTo(card.left));
        expect(button.right, lessThanOrEqualTo(card.right));
      }
    });
  }

  testWidgets('add account opens school selection without old credentials', (
    tester,
  ) async {
    await showAccounts(tester);
    await tester.tap(find.text('添加账号'));
    await tester.pumpAndSettle();
    expect(find.byType(OrgSearchPage), findsOneWidget);
    expect(find.byType(LoginPage), findsNothing);
    expect(find.text('选择学校'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      isEmpty,
    );
    Get.back();
    await tester.pumpAndSettle();
    expect(find.byType(AccountManagerPage), findsOneWidget);
    expect(
      getStorage.read<String>(GetStorageKeys.lastLoginUsername),
      'existing-user',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('password form names selected school and starts empty', (
    tester,
  ) async {
    const school = TronOrg(
      id: 123,
      orgName: '测试学校',
      apiUrl: 'https://school.example',
      ntfUrl: '',
    );
    await tester.pumpWidget(
      GetMaterialApp(
        home: const Scaffold(body: Text('fixture')),
        getPages: AppRoute.routes
            .where((r) => r.name == AppRoute.loginPage)
            .toList(),
      ),
    );
    Get.toNamed(AppRoute.loginPage, arguments: {'org': school, 'username': ''});
    await tester.pumpAndSettle();
    expect(find.text('测试学校'), findsOneWidget);
    for (final field in tester.widgetList<TextFormField>(
      find.byType(TextFormField),
    )) {
      expect(field.controller!.text, isEmpty);
    }
    await tester.tap(find.widgetWithText(ElevatedButton, '登录'));
    await tester.pumpAndSettle();
    expect(find.text('账号不能为空'), findsOneWidget);
    expect(find.text('密码不能为空'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('new school form does not reuse another form credentials', (
    tester,
  ) async {
    const otherSchool = TronOrg(
      id: 456,
      orgName: '另一所测试学校',
      apiUrl: 'https://other.example',
      ntfUrl: '',
    );
    await tester.pumpWidget(
      GetMaterialApp(
        home: const Scaffold(body: Text('fixture')),
        getPages: AppRoute.routes
            .where(
              (r) =>
                  r.name == AppRoute.loginPage ||
                  r.name == AppRoute.orgSearchPage,
            )
            .toList(),
      ),
    );
    Get.toNamed(
      AppRoute.loginPage,
      arguments: {
        'org': AppOrg.guet,
        'username': 'previous-student',
        'password': 'fixture-password',
      },
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextFormField>(find.byType(TextFormField).first)
          .controller!
          .text,
      'previous-student',
    );
    await tester.tap(find.text('更换学校'));
    await tester.pumpAndSettle();
    Get.toNamed(
      AppRoute.loginPage,
      arguments: {'org': otherSchool, 'username': ''},
    );
    await tester.pumpAndSettle();
    expect(find.text('另一所测试学校'), findsOneWidget);
    for (final field in tester.widgetList<TextFormField>(
      find.byType(TextFormField),
    )) {
      expect(field.controller!.text, isEmpty);
    }
    expect(tester.takeException(), isNull);
  });
}
