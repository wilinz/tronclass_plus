import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:tronclass/auth/generic_login.dart';
import 'package:tronclass/auth/web_login_credential.dart';
import 'package:tronclass/data/model/tron_org.dart';
import 'package:tronclass/data/org_store.dart';
import 'package:tronclass/data/service/org_service.dart';
import 'package:tronclass/data/user_agent.dart';
import 'package:tronclass/routes.dart';

/// 搜学校 → 选学校 → 打开对应的统一身份认证 WebView 登录。
class OrgSearchPage extends StatefulWidget {
  const OrgSearchPage({super.key});

  @override
  State<OrgSearchPage> createState() => _OrgSearchPageState();
}

class _OrgSearchPageState extends State<OrgSearchPage> {
  final _dio = Dio(
    BaseOptions(
      headers: AppUserAgent.apiHeaders(AppUserAgent.anonymousAccount),
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
      responseType: ResponseType.json,
    ),
  );
  final _keywordController = TextEditingController();

  Timer? _debounce;
  List<TronOrg> _results = const [];
  bool _isSearching = false;
  String? _error;
  String _keyword = '';

  @override
  void dispose() {
    _debounce?.cancel();
    _keywordController.dispose();
    _dio.close();
    super.dispose();
  }

  void _onKeywordChanged(String value) {
    _keyword = value.trim();
    _debounce?.cancel();
    if (_keyword.isEmpty) {
      setState(() {
        _results = const [];
        _error = null;
        _isSearching = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 400), _search);
  }

  Future<void> _search() async {
    final keyword = _keyword;
    if (keyword.isEmpty) return;
    setState(() {
      _isSearching = true;
      _error = null;
    });
    try {
      final orgs = await OrgService.search(_dio, keyword);
      if (!mounted || keyword != _keyword) return;
      setState(() {
        _results = orgs;
        _isSearching = false;
      });
    } catch (e) {
      if (!mounted || keyword != _keyword) return;
      setState(() {
        _isSearching = false;
        _error = '搜索失败：$e';
      });
    }
  }

  Future<void> _pick(TronOrg org) async {
    final ok = org.supportsIdentityLogin
        ? await GenericLogin.run(org, credential: const WebLoginCredential())
        : await Get.toNamed(
                AppRoute.loginPage,
                arguments: {'org': org, 'username': ''},
              ) ==
              true;
    if (ok && mounted) Get.back(result: true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('选择学校')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: TextField(
              controller: _keywordController,
              autofocus: true,
              textInputAction: TextInputAction.search,
              onChanged: _onKeywordChanged,
              onSubmitted: (_) => _search(),
              decoration: InputDecoration(
                labelText: '学校名称',
                hintText: '可以搜中文名，也可以搜英文缩写',
                prefixIcon: const Icon(Icons.school_outlined),
                suffixIcon: _isSearching
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : null,
                border: const OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(16)),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '先选择学校，再进入该校的认证页面或账号密码登录。',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(child: _buildBody(context)),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final error = _error;
    if (error != null) {
      return _Hint(
        icon: Icons.error_outline,
        text: error,
        action: TextButton(onPressed: _search, child: const Text('重试')),
      );
    }
    if (_keyword.isEmpty) {
      return _Hint(
        icon: Icons.search,
        text: '输入学校名称开始搜索\n当前学校：${AppOrg.current.orgName}',
      );
    }
    if (_results.isEmpty) {
      return _Hint(
        icon: _isSearching
            ? Icons.hourglass_empty
            : Icons.sentiment_dissatisfied,
        text: _isSearching ? '正在搜索...' : '没找到这所学校，换个关键词试试',
      );
    }

    return ListView.separated(
      itemCount: _results.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final org = _results[index];
        // 两条路都能登：有统一身份认证的开认证页，其余直接提交账号密码
        final byIdentity = org.supportsIdentityLogin;
        final note = byIdentity
            ? '统一身份认证登录'
            : (org.requiresCaptcha ? '账号密码登录，需要验证码' : '账号密码登录');
        return ListTile(
          leading: Icon(
            byIdentity ? Icons.account_balance_outlined : Icons.password,
          ),
          title: Text(org.orgName),
          subtitle: Text('${org.apiUrl}\n$note'),
          isThreeLine: true,
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _pick(org),
        );
      },
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint({required this.icon, required this.text, this.action});

  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.outline;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: color),
            const SizedBox(height: 12),
            Text(
              text,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: color),
            ),
            if (action != null) ...[const SizedBox(height: 8), action!],
          ],
        ),
      ),
    );
  }
}
