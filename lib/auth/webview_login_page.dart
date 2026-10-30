import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'package:tronclass/auth/autofill_script.dart';
import 'package:tronclass/auth/autofill_scope.dart';
import 'package:tronclass/auth/credential_card.dart';
import 'package:tronclass/auth/web_login_credential.dart';
import 'package:tronclass/data/model/tron_org.dart';
import 'package:tronclass/common/toast.dart';
import 'package:tronclass/data/user_agent.dart';

/// OIDC 回调地址。这个页面本身没有内容，不需要它加载成功，
/// 跳到这个地址就说明 code 已经在 URL 上了。
const kTronCallbackUrl =
    'https://mobile-download.tronclass.com.cn/callback.html';

class WebViewLoginArgs {
  const WebViewLoginArgs({required this.org, this.credential});

  final TronOrg org;

  /// 用户事先填的账号密码，只在所选学校认证范围内自动填充。
  final WebLoginCredential? credential;
}

/// 通用登录：把学校的统一身份认证页原样丢进 WebView，用户怎么登都行
/// （账号密码、短信、扫码、企业微信……），我们只等它跳回 callback 带 code。
class WebViewLoginPage extends StatefulWidget {
  const WebViewLoginPage({super.key, required this.args});

  final WebViewLoginArgs args;

  @override
  State<WebViewLoginPage> createState() => _WebViewLoginPageState();
}

class _WebViewLoginPageState extends State<WebViewLoginPage> {
  WebViewController? _controller;
  int _progress = 0;
  bool _finished = false;

  /// 这一页已经自动填过了，别在后续的 onPageFinished 里反复覆盖用户的修改。
  bool _autofilled = false;
  int _autofillGeneration = 0;
  late final AutofillScope? _autofillScope = AutofillScope.fromIdentityConfig(
    _org.identityConfig!,
  );

  TronOrg get _org => widget.args.org;

  WebLoginCredential? get _credential {
    final credential = widget.args.credential;
    return (credential == null || credential.isEmpty) ? null : credential;
  }

  String get _authUrl {
    final config = _org.identityConfig!;
    final uri = Uri.parse(config.authorizationEndpoint).replace(
      queryParameters: {
        'scope': 'openid',
        'response_type': 'code',
        'redirect_uri': kTronCallbackUrl,
        'client_id': config.resource,
      },
    );
    return uri.toString();
  }

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    // 每次登录都从干净的会话开始：否则统一身份认证那边的 SSO 会话还在，
    // 想换个账号登也会被直接放行成上一个人。
    await WebViewCookieManager().clearCookies();

    final controller = WebViewController()
      ..setUserAgent(AppUserAgent.webView(widget.args.credential?.username))
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (p) {
            if (mounted) setState(() => _progress = p);
          },
          onNavigationRequest: (request) {
            if (request.isMainFrame) _cancelAutofill();
            if (_handleCallback(request.url)) {
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
          // 有的 IdP 是 302 到 callback 之后才触发 onPageStarted，
          // onNavigationRequest 在个别机型上也可能不回调，这里再兜一层。
          onPageStarted: (url) {
            _cancelAutofill();
            _handleCallback(url);
          },
          onPageFinished: (url) {
            if (_handleCallback(url)) return;
            _autofill();
          },
        ),
      );
    await controller.loadRequest(
      Uri.parse(_authUrl),
      headers: const {'X-Requested-With': kWebViewRequestedWith},
    );
    if (!mounted) return;
    setState(() => _controller = controller);
  }

  void _cancelAutofill() {
    _autofillGeneration++;
    _autofilled = false;
  }

  /// 试着把账号密码填进页面。登录页常常是脚本渲染出来的，
  /// 所以填不上就隔一会儿再试，别只试一次。
  Future<void> _autofill({bool byUser = false}) async {
    final credential = _credential;
    final controller = _controller;
    if (credential == null || controller == null) return;
    if (_autofilled && !byUser) return;

    final scope = _autofillScope;
    if (scope == null) {
      if (byUser) toastFailure0('学校认证地址无效，已禁用自动填充');
      return;
    }
    final generation = ++_autofillGeneration;
    bool active() => mounted && !_finished && generation == _autofillGeneration;
    final script = buildAutofillScript(credential, scope: scope);
    for (var attempt = 0; attempt < 6; attempt++) {
      if (!active()) return;
      try {
        final url = await controller.currentUrl();
        if (!active()) return;
        if (!scope.allows(url)) {
          if (byUser) toastFailure0('当前页面不在该校认证范围内，已阻止填充');
          return;
        }
        final raw = await controller.runJavaScriptReturningResult(script);
        if (!active()) return;
        final filled = raw.toString();
        if (filled.contains('blocked-origin')) {
          if (byUser) toastFailure0('当前页面不在该校认证范围内，已阻止填充');
          return;
        }
        if (const {
          'user',
          'pass',
          'user,pass',
          '"user"',
          '"pass"',
          '"user,pass"',
        }.contains(filled)) {
          _autofilled = true;
          if (byUser) toastSuccess0('已填入账号密码');
          return;
        }
      } catch (_) {
        // 页面还没准备好，等下一轮
      }
      if (byUser) break;
      await Future.delayed(const Duration(milliseconds: 500));
    }
    if (byUser && active()) toastFailure0('这个认证页面没找到账号密码框');
  }

  /// 跳到回调地址就收网。返回 true 表示这一跳被我们截下了。
  bool _handleCallback(String url) {
    if (_finished) return true;
    if (!url.startsWith(kTronCallbackUrl)) return false;

    final uri = Uri.parse(url);
    // code 一般在 query 上；个别 IdP 会塞在 fragment 里。
    final params = <String, String>{
      ...uri.queryParameters,
      if (uri.fragment.isNotEmpty) ...Uri.splitQueryString(uri.fragment),
    };

    final code = params['code'];
    _finished = true;
    if (code == null || code.isEmpty) {
      Get.back<Object?>(
        result: WebViewLoginFailure(
          params['error_description'] ?? params['error'] ?? '登录被取消',
        ),
      );
    } else {
      Get.back<Object?>(result: code);
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Scaffold(
      appBar: AppBar(
        title: Text(_org.orgName),
        actions: [
          IconButton(
            tooltip: '重新开始',
            icon: const Icon(Icons.refresh),
            onPressed: () => controller?.loadRequest(
              Uri.parse(_authUrl),
              headers: const {'X-Requested-With': kWebViewRequestedWith},
            ),
          ),
        ],
        bottom: _progress > 0 && _progress < 100
            ? PreferredSize(
                preferredSize: const Size.fromHeight(2),
                child: LinearProgressIndicator(value: _progress / 100),
              )
            : null,
      ),
      body: controller == null
          ? const Center(child: CircularProgressIndicator())
          : LayoutBuilder(
              builder: (context, constraints) {
                final credential = _credential;
                return Stack(
                  children: [
                    Positioned.fill(
                      child: WebViewWidget(controller: controller),
                    ),
                    if (credential != null)
                      CredentialCard(
                        credential: credential,
                        onAutofill: () => _autofill(byUser: true),
                        viewSize: Size(
                          constraints.maxWidth,
                          constraints.maxHeight,
                        ),
                      ),
                  ],
                );
              },
            ),
    );
  }
}

/// WebView 那边明确失败了（用户取消、IdP 报错），带上原因回去。
class WebViewLoginFailure {
  const WebViewLoginFailure(this.message);

  final String message;

  @override
  String toString() => message;
}
