import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'package:tronclass/data/changke_client.dart';
import 'package:tronclass/data/get_storage.dart';

class WebViewArgs {
  final String url;

  WebViewArgs({required this.url});
}

Future<void> _setupWebViewCookie(String? url) async {
  final cookieManager = WebViewCookieManager();

  final urls = [
    if (url != null) url,
    'https://cas.guet.edu.cn',
    'https://cas.guet.edu.cn/authserver',
  ];

  for (final target in urls) {
    final uri = Uri.parse(target);
    final cookies = await ChangkeClient.instance.cookieJar.loadForRequest(uri);

    for (final cookie in cookies) {
      final domain = cookie.domain ?? uri.host;
      await cookieManager.setCookie(
        WebViewCookie(
          name: cookie.name,
          value: cookie.value,
          domain: domain,
          path: cookie.path ?? '/',
        ),
      );
    }
  }
}

class WebView extends StatefulWidget {
  final WebViewArgs args;

  const WebView({super.key, required this.args});

  @override
  State<WebView> createState() => WebViewState();
}

class WebViewState extends State<WebView> {
  bool isInit = false;
  bool isMobileMode = false;
  bool shouldClearCache = false;
  int _webViewAttempt = 0;

  final GetStorage storage = getStorage;

  @override
  void initState() {
    super.initState();
    init();
  }

  bool _isLargeScreen(BuildContext context) {
    final mediaQuery = MediaQuery.maybeOf(context);
    if (mediaQuery == null) {
      return false;
    }
    return mediaQuery.size.width >= 600;
  }

  Future<void> init() async {
    final contextForCalc = Get.context ?? context;
    final isLargeScreen = _isLargeScreen(contextForCalc);

    bool? storedMobileMode = storage.read<bool>(GetStorageKeys.isMobileMode);

    if (storedMobileMode == null) {
      storedMobileMode = !isLargeScreen;
      storage.write(GetStorageKeys.isMobileMode, storedMobileMode);
    }

    isMobileMode = storedMobileMode;

    final isClearWebViewSession =
        storage.read<bool>(GetStorageKeys.isCleanWebSession) ?? false;
    shouldClearCache = isClearWebViewSession;
    if (isClearWebViewSession) {
      printInfo(info: '正在重置 webview');
      storage.write(GetStorageKeys.isCleanWebSession, false);
      await WebViewCookieManager().clearCookies();
    }

    await _setupWebViewCookie(widget.args.url);

    if (!mounted) return;
    setState(() {
      isInit = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return isInit
        ? _WebView(
            key: ValueKey(_webViewAttempt),
            onRetry: () => setState(() => _webViewAttempt++),
            args: widget.args,
            storage: storage,
            isMobileMode: isMobileMode,
            shouldClearCache: shouldClearCache,
          )
        : Scaffold(
            appBar: AppBar(title: Text('加载中')),
            body: Center(child: CircularProgressIndicator()),
          );
  }
}

class _WebView extends StatefulWidget {
  final WebViewArgs args;
  final bool isMobileMode;
  final GetStorage storage;
  final bool shouldClearCache;
  final VoidCallback onRetry;

  const _WebView({
    super.key,
    required this.onRetry,
    required this.args,
    required this.storage,
    required this.isMobileMode,
    required this.shouldClearCache,
  });

  @override
  State<_WebView> createState() => _WebViewState();
}

class _WebViewState extends State<_WebView> {
  final androidDesktopModeUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

  final iosDesktopModeUserAgent =
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Version/17.0 Safari/537.36';

  final androidMobileModeUserAgent =
      'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36';

  final iosMobileModeUserAgent =
      'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/537.36 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/537.36';

  String get desktopModeUserAgent =>
      GetPlatform.isIOS ? iosDesktopModeUserAgent : androidDesktopModeUserAgent;

  String get mobileModeUserAgent =>
      GetPlatform.isIOS ? iosMobileModeUserAgent : androidMobileModeUserAgent;

  late bool isMobileMode = widget.isMobileMode;
  WebViewController? webViewController;
  bool controllerReady = false;
  String? loadError;
  double progress = 0;
  String url = '';
  String? title;

  @override
  void initState() {
    super.initState();
    url = widget.args.url;
    _initController();
  }

  Future<void> _initController() async {
    try {
      final controller = await _createController().timeout(
        const Duration(seconds: 20),
      );
      if (!mounted) return;
      setState(() {
        webViewController = controller;
        controllerReady = true;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        loadError = error is TimeoutException
            ? '网页组件初始化超时，请重试'
            : '网页组件初始化失败，请重试';
      });
    }
  }

  Future<WebViewController> _createController() async {
    final controller = WebViewController(
      onPermissionRequest: _handlePermissionRequest,
    );

    await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
    // WKWebView's opacity/background setters are only implemented on iOS.
    if (defaultTargetPlatform != TargetPlatform.macOS) {
      await controller.setBackgroundColor(Colors.transparent);
    }
    await controller.setNavigationDelegate(
      NavigationDelegate(
        onPageStarted: (url) {
          if (!mounted) return;
          setState(() {
            this.url = url;
          });
        },
        onPageFinished: (url) async {
          final currentTitle = await controller.getTitle().catchError(
            (_) => null,
          );
          if (!mounted) return;
          setState(() {
            this.url = url;
            title = currentTitle;
            progress = 1;
          });
        },
        onProgress: (progress) {
          if (!mounted) return;
          setState(() {
            this.progress = progress / 100;
          });
        },
        onWebResourceError: (error) {
          if (!mounted || error.isForMainFrame == false) return;
          setState(() => loadError = '网页加载失败，请检查网络后重试');
        },
        onNavigationRequest: (request) async {
          final uri = Uri.parse(request.url);
          if (!_isSupportedScheme(uri.scheme)) {
            if (await canLaunchUrl(uri)) {
              await launchUrl(uri);
              return NavigationDecision.prevent;
            }
          }
          return NavigationDecision.navigate;
        },
      ),
    );

    await controller.setUserAgent(
      isMobileMode ? mobileModeUserAgent : desktopModeUserAgent,
    );

    if (widget.shouldClearCache) {
      await controller.clearCache();
      await controller.clearLocalStorage();
    }

    await controller.loadRequest(Uri.parse(widget.args.url));

    return controller;
  }

  bool _isSupportedScheme(String scheme) {
    return const {
      'http',
      'https',
      'file',
      'chrome',
      'data',
      'javascript',
      'about',
    }.contains(scheme);
  }

  Future<void> _handlePermissionRequest(
    WebViewPermissionRequest request,
  ) async {
    final requiresMedia = request.types.any(
      (type) =>
          type == WebViewPermissionResourceType.camera ||
          type == WebViewPermissionResourceType.microphone,
    );

    if (!requiresMedia) {
      await request.grant();
      return;
    }

    final statuses = await [Permission.camera, Permission.microphone].request();

    final granted = statuses.values.every(
      (status) => status == PermissionStatus.granted,
    );

    if (granted) {
      await request.grant();
    } else {
      await request.deny();
    }
  }

  Future<void> share(
    BuildContext context, {
    required String subject,
    required String text,
  }) async {
    final box = context.findRenderObject() as RenderBox?;
    final origin = box != null
        ? box.localToGlobal(Offset.zero) & box.size
        : null;
    await SharePlus.instance.share(
      ShareParams(
        text: text,
        subject: subject.isNotEmpty ? subject : null,
        sharePositionOrigin: origin,
      ),
    );
  }

  List<Widget> buildMobileActions1(BuildContext context) {
    return [
      IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: controllerReady
            ? () async {
                if (await webViewController!.canGoBack()) {
                  webViewController!.goBack();
                }
              }
            : null,
      ),
      IconButton(
        icon: const Icon(Icons.arrow_forward),
        onPressed: controllerReady
            ? () async {
                if (await webViewController!.canGoForward()) {
                  webViewController!.goForward();
                }
              }
            : null,
      ),
    ];
  }

  List<Widget> buildMobileActions(BuildContext context) {
    return [
      ...buildMobileActions1(context),
      PopupMenuButton<int>(
        onSelected: (value) {
          switch (value) {
            case 0:
              setState(() {
                isMobileMode = !isMobileMode;
                widget.storage.write(GetStorageKeys.isMobileMode, isMobileMode);
              });
              webViewController?.setUserAgent(
                isMobileMode ? mobileModeUserAgent : desktopModeUserAgent,
              );
              webViewController?.reload();
              break;
            case 1:
              webViewController?.reload();
              break;
            case 2:
              share(context, subject: '', text: url);
              break;
            case 3:
              _exitWebView();
              break;
          }
        },
        itemBuilder: (context) => [
          PopupMenuItem(
            value: 0,
            child: Text(isMobileMode ? '切换为桌面端网页' : '切换为移动端网页'),
          ),
          const PopupMenuItem(value: 1, child: Text('刷新')),
          const PopupMenuItem(value: 2, child: Text('分享链接')),
          const PopupMenuItem(value: 3, child: Text('退出网页')),
        ],
      ),
    ];
  }

  List<Widget> buildDesktopActions(BuildContext context) {
    return [
      TextButton(
        onPressed: () {
          setState(() {
            isMobileMode = !isMobileMode;
            widget.storage.write(GetStorageKeys.isMobileMode, isMobileMode);
          });
          webViewController?.setUserAgent(
            isMobileMode ? mobileModeUserAgent : desktopModeUserAgent,
          );
          webViewController?.reload();
        },
        child: Text(isMobileMode ? '切换为桌面端网页' : '切换为移动端网页'),
      ),
      ...buildMobileActions1(context),
      IconButton(
        icon: const Icon(Icons.refresh),
        onPressed: controllerReady
            ? () {
                webViewController?.reload();
              }
            : null,
      ),
      IconButton(
        icon: const Icon(Icons.share),
        onPressed: controllerReady
            ? () => share(context, subject: '', text: url)
            : null,
      ),
      IconButton(
        icon: const Icon(Icons.close),
        tooltip: '退出网页',
        onPressed: _exitWebView,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await _handleBackPressed();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            title ??
                (loadError != null
                    ? '加载失败'
                    : progress >= 1
                    ? '网页版'
                    : '加载中'),
          ),
          actions: MediaQuery.sizeOf(context).width < 600
              ? buildMobileActions(context)
              : buildDesktopActions(context),
        ),
        body: Column(
          children: [
            Expanded(
              child: Stack(
                children: [
                  if (loadError != null)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(loadError!, textAlign: TextAlign.center),
                            const SizedBox(height: 16),
                            FilledButton(
                              onPressed: widget.onRetry,
                              child: const Text('重试'),
                            ),
                          ],
                        ),
                      ),
                    )
                  else if (controllerReady && webViewController != null)
                    WebViewWidget(controller: webViewController!)
                  else
                    const Center(child: CircularProgressIndicator()),
                  if (loadError == null && progress < 1.0)
                    LinearProgressIndicator(value: progress),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleBackPressed() async {
    if (webViewController != null && controllerReady) {
      final canGoBack = await webViewController!.canGoBack();
      if (canGoBack) {
        webViewController!.goBack();
        return;
      }
    }

    _exitWebView();
  }

  void _exitWebView() {
    if (mounted) {
      Get.back();
    }
  }
}
