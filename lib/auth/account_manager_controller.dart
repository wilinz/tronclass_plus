import 'package:get/get.dart';

import 'package:tronclass/auth/web_login_credential.dart';
import 'package:tronclass/auth/auth_controller.dart';
import 'package:tronclass/auth/generic_login.dart';
import 'package:tronclass/auth/saved_account_storage.dart';
import 'package:tronclass/common/toast.dart';
import 'package:tronclass/data/changke_client.dart';
import 'package:tronclass/data/get_storage.dart';
import 'package:tronclass/data/org_store.dart';
import 'package:tronclass/data/service/tronclass.dart';
import 'package:tronclass/routes.dart';

class AccountManagerController extends GetxController {
  final accounts = <SavedAccount>[].obs;
  final isProcessing = false.obs;
  final currentUsername = ''.obs;

  @override
  void onInit() {
    super.onInit();
    loadAccounts();
    refreshCurrentUser();
  }

  void loadAccounts() {
    accounts.assignAll(SavedAccountStorage.loadAccounts());
    refreshCurrentUser();
  }

  void refreshCurrentUser() {
    final stored = getStorage.read<String>(GetStorageKeys.lastLoginUsername);
    currentUsername.value = stored ?? '';
  }

  /// 这个账号还留着会话没有——留着才能直接切过去。
  bool hasSession(SavedAccount account) => ChangkeClient.hasStoredSession(
    username: account.username,
    org: account.org,
  );

  /// 直接切过去：登录态本来就存着，能用就不用重登。
  /// 会话过期了就照实说，让用户自己决定要不要重新登录。
  Future<void> switchToAccount(SavedAccount account) async {
    if (isProcessing.value) return;
    isProcessing.value = true;
    try {
      await AppOrg.setCurrent(account.org);
      final client = ChangkeClient.getInstance(
        username: account.username,
        org: account.org,
      );
      if (!client.isLoggedIn) {
        toastFailure0('这个账号还没有登录过，先登录一次');
        return;
      }

      final profile = await TronClassService.probeSession(
        client.dio,
        apiUrl: account.org.apiUrl,
      );
      if (profile == null) {
        toastFailure0('登录已过期，需要重新登录');
        return;
      }

      final name = profile['name'];
      await getStorage.write(
        GetStorageKeys.lastLoginUsername,
        account.username,
      );
      refreshCurrentUser();
      if (Get.isRegistered<AuthController>()) {
        Get.find<AuthController>().refreshState();
      }
      toastSuccess0(
        '已切换到 ${name is String && name.isNotEmpty ? name : account.username}',
      );
      Get.back(result: true);
    } catch (e) {
      toastFailure0('切换失败：$e');
    } finally {
      isProcessing.value = false;
    }
  }

  /// 退出当前账号：只清掉这套会话，账号本身还在列表里。
  void logoutCurrent() {
    if (Get.isRegistered<AuthController>()) {
      Get.find<AuthController>().logout();
    } else {
      ChangkeClient.instance.logout();
    }
    loadAccounts();
    toastSuccess0('已退出当前账号');
  }

  Future<void> deleteAccount(String username) async {
    await SavedAccountStorage.removeAccount(username);
    loadAccounts();
  }

  Future<void> loginWithAccount(SavedAccount account) async {
    // 账号是跟着学校走的，先把当前学校切成它自己的，
    // 否则接口地址和会话会对不上。
    await AppOrg.setCurrent(account.org);
    isProcessing.value = true;
    final password = SavedAccountStorage.decryptPassword(account);
    isProcessing.value = false;

    // 当初怎么登进来的，就还怎么登：网页登录的账号回认证页去登，
    // 存过的账号密码带过去，落到那张快速填充卡片上。
    if (account.loginMethod == LoginMethod.webView) {
      final ok = await GenericLogin.run(
        account.org,
        credential: WebLoginCredential(
          username: account.username,
          password: password ?? '',
        ),
      );
      refreshCurrentUser();
      if (ok) Get.back(result: true);
      return;
    }

    final args = {
      'org': account.org,
      'username': account.username,
      if (password != null && password.isNotEmpty) 'password': password,
    };

    final result = await Get.toNamed(AppRoute.loginPage, arguments: args);
    refreshCurrentUser();
    if (result == true) {
      Get.back(result: true);
    }
  }
}
