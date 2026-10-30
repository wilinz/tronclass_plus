import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:get/get.dart';

import 'package:tronclass/auth/auth_controller.dart';
import 'package:tronclass/data/changke_client.dart';
import 'package:tronclass/data/org_store.dart';
import 'package:tronclass/routes.dart';
import 'package:tronclass/webview/webview.dart';

import 'tronclass_controller.dart';

class TronClassPage extends StatelessWidget {
  const TronClassPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final c = Get.put(ChangkeController());
    final auth = Get.put(AuthController());
    final rawTheme = Theme.of(context);
    final theme = rawTheme.copyWith(
      colorScheme: rawTheme.colorScheme.copyWith(
        onPrimary: Colors.white,
        primary: Color(0xff1DB6C2),
      ),
    );
    return Theme(
      data: theme,
      child: Builder(
        builder: (context) {
          return Scaffold(
            appBar: AppBar(
              title: Obx(
                () => Text(
                  auth.orgName.value.isEmpty
                      ? AppOrg.current.orgName
                      : auth.orgName.value,
                ),
              ),
              centerTitle: true,
            ),
            bottomNavigationBar: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: FilledButton(
                  onPressed: () {
                    // 桂电有单独的移动门户，其他学校直接开畅课网页版
                    final url = AppOrg.isGuet
                        ? "https://mobile.guet.edu.cn"
                        : AppOrg.current.apiUrl;
                    Get.toNamed(
                      AppRoute.webView,
                      arguments: WebViewArgs(url: url),
                    )?.then((_) => auth.refreshState());
                  },
                  style: ButtonStyle(
                    shape: WidgetStateProperty.all(
                      RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    backgroundColor: WidgetStateProperty.all(
                      Theme.of(context).colorScheme.primary,
                    ),
                    elevation: WidgetStateProperty.all(0), // 关闭按钮自身的阴影
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12.0),
                    child: Text(
                      "完整版请点此打开网页版",
                      style: TextStyle(
                        fontSize: 16,
                        color: Theme.of(context).colorScheme.onPrimary,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            body: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 夜间提示
                    Obx(() {
                      return Text(
                        c.greeting.value,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      );
                    }),

                    const SizedBox(height: 16),

                    // 上方两个卡片按钮（扫码、签到）
                    Container(
                      padding: EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerLowest,
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.05),
                            blurRadius: 10,
                            spreadRadius: 1,
                            offset: Offset(0, 0), // 可根据需要调整阴影偏移
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: buildCardWithSemiCircle(
                              buttonGradient: LinearGradient(
                                colors: [Color(0xFF00BBBD), Color(0xFF0EB0D4)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                transform: GradientRotation(
                                  234.32 * 3.1416 / 180,
                                ), // 传入的角度
                              ),
                              icon: SvgPicture.asset(
                                "assets/images/scan_code.svg",
                                color: Colors.white,
                              ),
                              label: "扫码",
                              onTap: () async {
                                if (await _ensureLoggedIn()) {
                                  Get.toNamed(AppRoute.qrRollcallsPage);
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: buildCardWithSemiCircle(
                              buttonGradient: LinearGradient(
                                colors: [Color(0xFF59BE30), Color(0xFF44BE30)],
                                stops: [-0.0063, 1.0064],
                                // 设置颜色位置（%转换为0到1之间的值）
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                transform: GradientRotation(
                                  266.66 * 3.1416 / 180,
                                ), // 设置渐变角度
                              ),
                              icon: SvgPicture.asset(
                                "assets/images/sign.svg",
                                color: Colors.white,
                              ),
                              label: "签到",
                              onTap: () async {
                                if (await _ensureLoggedIn()) {
                                  Get.toNamed(AppRoute.rollcallListPage);
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    const SizedBox(height: 24),

                    Obx(() {
                      final loggedIn = auth.isLoggedIn.value;
                      final scheme = Theme.of(context).colorScheme;
                      return Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          // 跟上面那张扫码/签到卡一个底色，别自成一格
                          color: scheme.surfaceContainerLowest,
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.05),
                              blurRadius: 10,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  loggedIn
                                      ? Icons.verified_user
                                      : Icons.lock_outline,
                                  color: loggedIn
                                      ? scheme.primary
                                      : scheme.error,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        loggedIn
                                            ? auth.accountLabel.value
                                            : '还没有登录',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(
                                          context,
                                        ).textTheme.titleMedium,
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        loggedIn
                                            ? [
                                                    auth.orgName.value,
                                                    auth.loginMethodLabel.value,
                                                  ]
                                                  .where((e) => e.isNotEmpty)
                                                  .join(' · ')
                                            : '登录后才能签到',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              color: scheme.onSurfaceVariant,
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                if (loggedIn) ...[
                                  const Spacer(),
                                  // 退出、删除这些都归管理页，首页只留入口
                                  FilledButton.tonal(
                                    onPressed: () async {
                                      final result = await Get.toNamed(
                                        AppRoute.accountManagerPage,
                                      );
                                      if (result == true) auth.refreshState();
                                    },
                                    child: const Text('管理账号'),
                                  ),
                                ] else ...[
                                  const Spacer(),
                                  FilledButton(
                                    onPressed: () async {
                                      final result = await Get.toNamed(
                                        AppRoute.orgSearchPage,
                                      );
                                      if (result == true) auth.refreshState();
                                    },
                                    child: const Text('登录'),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      );
                    }),

                    const SizedBox(height: 80),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<bool> _ensureLoggedIn() async {
    if (ChangkeClient.instance.isLoggedIn) return true;
    final result = await Get.toNamed(AppRoute.orgSearchPage);
    return result == true;
  }

  /// 构建卡片按钮
  Widget _buildCardButton({
    required LinearGradient gradient, // 传入完整的渐变对象
    required Widget icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        height: 64,
        decoration: BoxDecoration(
          gradient: gradient, // 使用外部传入的渐变
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            icon,
            const SizedBox(width: 8),
            Text(label, style: TextStyle(color: Colors.white)),
          ],
        ),
      ),
    );
  }

  Widget buildCardWithSemiCircle({
    required LinearGradient buttonGradient,
    required Widget icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Stack(
        clipBehavior: Clip.hardEdge, // 防止溢出显示
        children: [
          // 按钮主体
          _buildCardButton(
            gradient: buttonGradient,
            icon: icon,
            label: label,
            onTap: onTap,
          ),
          // 左上角半圆
          Positioned(
            top: -15, // 类似 -.9375rem
            left: -15,
            child: Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.white.withOpacity(0.2),
                    Colors.white.withOpacity(0.0),
                  ],
                  stops: [0.0, 0.9623],
                ),
              ),
            ),
          ),
          // 右下角半圆
          Positioned(
            right: -15,
            bottom: -15,
            child: Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.white.withOpacity(0.5),
                    Colors.white.withOpacity(0.0),
                  ],
                  stops: [0.0, 0.9623],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
