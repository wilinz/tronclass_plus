import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:tronclass/auth/account_manager_page.dart';
import 'package:tronclass/auth/login_page.dart';
import 'package:tronclass/auth/org_search_page.dart';
import 'package:tronclass/auth/webview_login_page.dart';
import 'package:tronclass/tronclass/number_rollcalls/number_rollcalls_page.dart';
import 'package:tronclass/tronclass/qr_rollcalls/qr_rollcalls_page.dart';
import 'package:tronclass/tronclass/radar_rollcalls/location_picker_page.dart';
import 'package:tronclass/tronclass/radar_rollcalls/radar_rollcalls_page.dart';
import 'package:tronclass/tronclass/rollcalls/rollcalls.dart';
import 'package:tronclass/tronclass/tronclass.dart';
import 'package:tronclass/webview/webview.dart';

class AppRoute {
  static final navigatorKey = GlobalKey<NavigatorState>();

  static const String tronClassPage = '/';
  static const String rollcallListPage = '/rollcalls';
  static const String numberRollcallsPage = '/number-rollcalls';
  static const String radarRollcallsPage = '/radar-rollcalls';
  static const String qrRollcallsPage = '/qr-rollcalls';
  static const String mapLocationPickerPage = '/map-picker';
  static const String webView = '/webview';
  static const String loginPage = '/login';
  static const String accountManagerPage = '/account-manager';

  /// 通用登录：搜学校
  static const String orgSearchPage = '/org-search';

  /// 通用登录：统一身份认证 WebView
  static const String webviewLoginPage = '/webview-login';

  static final List<GetPage<dynamic>> routes = [
    GetPage(name: tronClassPage, page: () => const TronClassPage()),
    GetPage(name: rollcallListPage, page: () => const RollcallListPage()),
    GetPage(
      name: numberRollcallsPage,
      page: () =>
          NumberRollcallsPage(args: _requireArgs<NumberRollcallsPageArgs>()),
    ),
    GetPage(
      name: radarRollcallsPage,
      page: () =>
          RadarRollcallsPage(args: _requireArgs<RadarRollcallsPageArgs>()),
    ),
    GetPage(name: qrRollcallsPage, page: () => const QrRollcallsPage()),
    GetPage(
      name: mapLocationPickerPage,
      page: () =>
          LocationPickerPage(args: _requireArgs<LocationPickerPageArgs>()),
    ),
    GetPage(name: loginPage, page: () => const LoginPage()),
    GetPage(name: accountManagerPage, page: () => const AccountManagerPage()),
    GetPage(name: orgSearchPage, page: () => const OrgSearchPage()),
    GetPage(
      name: webviewLoginPage,
      page: () => WebViewLoginPage(args: _requireArgs<WebViewLoginArgs>()),
    ),
    GetPage(
      name: webView,
      page: () => WebView(args: _requireArgs<WebViewArgs>()),
    ),
  ];
}

T _requireArgs<T>() {
  final args = Get.arguments;
  if (args is T) return args;
  throw ArgumentError(
    'Expected arguments of type $T but got ${args.runtimeType}',
  );
}
