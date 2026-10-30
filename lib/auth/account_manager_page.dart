import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:tronclass/auth/account_manager_controller.dart';
import 'package:tronclass/auth/saved_account_storage.dart';
import 'package:tronclass/data/backup/backup_actions.dart';
import 'package:tronclass/routes.dart';

class AccountManagerPage extends StatelessWidget {
  const AccountManagerPage({super.key});

  @override
  Widget build(BuildContext context) {
    return GetBuilder<AccountManagerController>(
      init: AccountManagerController(),
      builder: (controller) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('管理账号'),
            actions: [
              IconButton(
                onPressed: controller.loadAccounts,
                icon: const Icon(Icons.refresh),
              ),
              PopupMenuButton<int>(
                tooltip: '备份',
                onSelected: (value) async {
                  if (value == 0) {
                    await BackupActions.export();
                  } else {
                    await BackupActions.import();
                    controller.loadAccounts();
                  }
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: 0,
                    child: ListTile(
                      leading: Icon(Icons.upload_file),
                      title: Text('导出数据'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  PopupMenuItem(
                    value: 1,
                    child: ListTile(
                      leading: Icon(Icons.download),
                      title: Text('导入数据'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ],
              ),
            ],
          ),
          body: Obx(() {
            final accounts = controller.accounts;
            final isProcessing = controller.isProcessing.value;
            final currentUser = controller.currentUsername.value;
            if (accounts.isEmpty) {
              return const Center(child: Text('暂无保存的账号，登录后可自动保存'));
            }
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemBuilder: (context, index) {
                final account = accounts[index];
                final isCurrent = account.username == currentUser;
                final hasSession = controller.hasSession(account);
                return Card(
                  clipBehavior: Clip.antiAlias,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 姓名（学号）单独一行，太长就省略，别把「当前」挤没
                        Row(
                          children: [
                            const Icon(Icons.person_outline, size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                account.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ),
                            if (isCurrent) _CurrentBadge(),
                          ],
                        ),
                        const SizedBox(height: 8),
                        _InfoLine(
                          icon: Icons.school_outlined,
                          text: account.org.orgName,
                        ),
                        const SizedBox(height: 4),
                        _InfoLine(
                          icon: account.loginMethod == LoginMethod.password
                              ? Icons.password_outlined
                              : Icons.public_outlined,
                          text: account.loginMethodLabel,
                        ),
                        const SizedBox(height: 4),
                        _InfoLine(
                          icon: hasSession
                              ? Icons.verified_user_outlined
                              : Icons.gpp_maybe_outlined,
                          text: hasSession ? '登录态还在，可直接切换' : '没有登录态，需要登录',
                          highlight: !hasSession,
                        ),
                        const SizedBox(height: 4),
                        _InfoLine(
                          icon: Icons.schedule_outlined,
                          text:
                              '最近更新 '
                              '${account.updatedAt.toLocal().toString().split('.').first}',
                        ),
                        const Divider(height: 20),
                        Wrap(
                          alignment: WrapAlignment.end,
                          spacing: 4,
                          runSpacing: 4,
                          children: [
                            if (isCurrent)
                              TextButton.icon(
                                onPressed: isProcessing
                                    ? null
                                    : controller.logoutCurrent,
                                icon: const Icon(Icons.logout, size: 18),
                                label: const Text('退出'),
                              ),
                            TextButton.icon(
                              onPressed: isProcessing
                                  ? null
                                  : () async {
                                      final confirmed = await _confirmDeletion(
                                        context,
                                        account.label,
                                      );
                                      if (confirmed == true) {
                                        controller.deleteAccount(
                                          account.username,
                                        );
                                      }
                                    },
                              icon: const Icon(Icons.delete_outline, size: 18),
                              label: const Text('删除'),
                              style: TextButton.styleFrom(
                                foregroundColor: Theme.of(
                                  context,
                                ).colorScheme.error,
                              ),
                            ),
                            // 登录态还在就直接切，别让人白登一次
                            if (hasSession && !isCurrent)
                              TextButton.icon(
                                onPressed: isProcessing
                                    ? null
                                    : () =>
                                          controller.loginWithAccount(account),
                                icon: const Icon(Icons.refresh, size: 18),
                                label: const Text('重新登录'),
                              ),
                            FilledButton.tonalIcon(
                              onPressed: isProcessing
                                  ? null
                                  : () => hasSession && !isCurrent
                                        ? controller.switchToAccount(account)
                                        : controller.loginWithAccount(account),
                              icon: Icon(
                                hasSession && !isCurrent
                                    ? Icons.swap_horiz
                                    : Icons.login,
                                size: 18,
                              ),
                              label: Text(
                                hasSession && !isCurrent
                                    ? '切换'
                                    : (isCurrent ? '重新登录' : '登录'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemCount: accounts.length,
            );
          }),
          bottomNavigationBar: Obx(
            () => controller.isProcessing.value
                ? const LinearProgressIndicator()
                : const SizedBox.shrink(),
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () async {
              final result = await Get.toNamed(AppRoute.orgSearchPage);
              if (result == true) {
                controller.loadAccounts();
                Get.back(result: true);
              }
            },
            icon: const Icon(Icons.add),
            label: const Text('添加账号'),
          ),
        );
      },
    );
  }

  Future<bool?> _confirmDeletion(BuildContext context, String username) {
    return showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('删除账号'),
          content: Text('确定要删除账号 $username 吗？此操作不可撤销。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('删除'),
            ),
          ],
        );
      },
    );
  }
}

/// 「当前」小标签。
class _CurrentBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '当前',
        style: TextStyle(color: scheme.onPrimaryContainer, fontSize: 12),
      ),
    );
  }
}

/// 卡片里的一行说明：一个小图标加一段文字，长了自己换行。
class _InfoLine extends StatelessWidget {
  const _InfoLine({
    required this.icon,
    required this.text,
    this.highlight = false,
  });

  final IconData icon;
  final String text;

  /// 需要用户注意的信息（比如登录态没了）用强调色。
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = highlight ? scheme.error : scheme.onSurfaceVariant;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: highlight ? scheme.error : scheme.outline),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: color),
          ),
        ),
      ],
    );
  }
}
