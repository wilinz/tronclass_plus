import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:tronclass/data/changke_client.dart';
import 'package:tronclass/data/get_storage.dart';
import 'package:tronclass/path.dart';
import 'package:tronclass/webview/webview.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

class TestWebPlatform extends WebViewPlatform {
  bool failLoad = false;
  bool hangLoad = false;
  int backgrounds = 0;
  final loaded = <Uri>[];
  late TestNavigation navigation;
  @override
  PlatformWebViewController createPlatformWebViewController(
    PlatformWebViewControllerCreationParams params,
  ) => TestController(params, this);
  @override
  PlatformNavigationDelegate createPlatformNavigationDelegate(
    PlatformNavigationDelegateCreationParams params,
  ) => navigation = TestNavigation(params);
  @override
  PlatformWebViewCookieManager createPlatformCookieManager(
    PlatformWebViewCookieManagerCreationParams params,
  ) => TestCookies(params);
  @override
  PlatformWebViewWidget createPlatformWebViewWidget(
    PlatformWebViewWidgetCreationParams params,
  ) => TestWebWidget(params);
}

class TestCookies extends PlatformWebViewCookieManager {
  TestCookies(super.params) : super.implementation();
  @override
  Future<void> setCookie(WebViewCookie cookie) async {}
  @override
  Future<bool> clearCookies() async => false;
}

class TestController extends PlatformWebViewController {
  TestController(super.params, this.owner) : super.implementation();
  final TestWebPlatform owner;
  @override
  Future<void> setOnPlatformPermissionRequest(
    void Function(PlatformWebViewPermissionRequest) callback,
  ) async {}
  @override
  Future<void> setJavaScriptMode(JavaScriptMode mode) async {}
  @override
  Future<void> setBackgroundColor(Color color) {
    owner.backgrounds++;
    if (defaultTargetPlatform == TargetPlatform.macOS) {
      throw UnimplementedError('opaque is not implemented on macOS');
    }
    return Future.value();
  }

  @override
  Future<void> setPlatformNavigationDelegate(
    PlatformNavigationDelegate handler,
  ) async {}
  @override
  Future<void> setUserAgent(String? agent) async {}
  @override
  Future<void> loadRequest(LoadRequestParams params) async {
    if (owner.failLoad) throw StateError('fixture load failure');
    if (owner.hangLoad) return Completer<void>().future;
    owner.loaded.add(params.uri);
  }

  @override
  Future<String?> getTitle() async => '测试网页';
}

class TestNavigation extends PlatformNavigationDelegate {
  TestNavigation(super.params) : super.implementation();
  void Function(WebResourceError)? error;
  PageEventCallback? finished;
  @override
  Future<void> setOnNavigationRequest(NavigationRequestCallback cb) async {}
  @override
  Future<void> setOnPageStarted(PageEventCallback cb) async {}
  @override
  Future<void> setOnPageFinished(PageEventCallback cb) async {
    finished = cb;
  }

  @override
  Future<void> setOnProgress(ProgressCallback cb) async {}
  @override
  Future<void> setOnWebResourceError(void Function(WebResourceError) cb) async {
    error = cb;
  }
}

class TestWebWidget extends PlatformWebViewWidget {
  TestWebWidget(super.params) : super.implementation();
  @override
  Widget build(BuildContext context) => const Text('网页内容');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  late TestWebPlatform platform;
  setUpAll(() async {
    temp = await Directory.systemTemp.createTemp('tronclass-webview-test-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => temp.path,
        );
    applicationSupportDirectory = temp;
    getStorage = GetStorage('webview-test', temp.path);
    await getStorage.initStorage;
    await getStorage.write(GetStorageKeys.isMobileMode, true);
    await ChangkeClient.getInstance(
      username: 'fixture',
    ).cookieJar.loadForRequest(Uri.parse('https://example.test'));
  });
  tearDownAll(() async {
    await temp.delete(recursive: true);
  });
  setUp(() {
    platform = TestWebPlatform();
    WebViewPlatform.instance = platform;
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    Get.reset();
  });
  Future<void> show(WidgetTester tester) async {
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    await tester.pumpWidget(
      GetMaterialApp(
        home: WebView(args: WebViewArgs(url: 'https://example.test')),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets('macOS skips unsupported background API and loads webpage', (
    tester,
  ) async {
    await show(tester);
    expect(platform.backgrounds, 0);
    expect(platform.loaded, [Uri.parse('https://example.test')]);
    expect(find.text('网页内容'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('Android retains background configuration', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await show(tester);
    expect(platform.backgrounds, 1);
    expect(platform.loaded, hasLength(1));
  });
  testWidgets('initialization failure replaces spinner with retry', (
    tester,
  ) async {
    platform.failLoad = true;
    await show(tester);
    expect(find.text('网页组件初始化失败，请重试'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    platform.failLoad = false;
    await tester.tap(find.text('重试'));
    await tester.pump();
    await tester.pump();
    expect(find.text('网页内容'), findsOneWidget);
  });
  testWidgets('initialization timeout can be retried', (tester) async {
    platform.hangLoad = true;
    await show(tester);
    await tester.pump(const Duration(seconds: 21));
    expect(find.text('网页组件初始化超时，请重试'), findsOneWidget);
    platform.hangLoad = false;
    await tester.tap(find.text('重试'));
    await tester.pump();
    await tester.pump();
    expect(find.text('网页内容'), findsOneWidget);
  });
  testWidgets(
    'main frame errors are shown but subresource failures are ignored',
    (tester) async {
      await show(tester);
      platform.navigation.error!(
        const WebResourceError(
          errorCode: -1009,
          description: 'offline',
          isForMainFrame: false,
        ),
      );
      await tester.pump();
      expect(find.text('网页内容'), findsOneWidget);
      platform.navigation.error!(
        const WebResourceError(
          errorCode: -1009,
          description: 'offline',
          isForMainFrame: true,
        ),
      );
      await tester.pump();
      expect(find.text('网页加载失败，请检查网络后重试'), findsOneWidget);
    },
  );
}
