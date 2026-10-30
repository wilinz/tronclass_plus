import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:kt_dart/kt.dart';
import 'package:tronclass/data/changke_client.dart';
import 'package:vibration/vibration.dart';

import '../../../../data/service/tronclass.dart';
import '../../../../data/util/changke.dart';
import '../../widget/wx_scan_view.dart';
import '../../widget/image_qr_scan_view.dart';
import '../common.dart';
import 'sign_result.dart';

class QrRollcallsPage extends StatefulWidget {
  const QrRollcallsPage({super.key});

  @override
  State<QrRollcallsPage> createState() => _QrRollcallsPageState();
}

class _QrRollcallsPageState extends State<QrRollcallsPage> {
  final _scanController = WxScanViewController();

  bool hasCustomVibrationsSupport = false;

  @override
  void initState() {
    super.initState();
    if (GetPlatform.isMobile) initAsync();
  }

  @override
  void dispose() {
    _scanController.dispose();
    super.dispose();
  }

  initAsync() async {
    (await Vibration.hasCustomVibrationsSupport()).let((it) {
      if (mounted) {
        setState(() {
          hasCustomVibrationsSupport = it;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (GetPlatform.isDesktop) {
      return Scaffold(
        appBar: AppBar(title: const Text('图片扫码签到')),
        body: ImageQrScanView(onResult: _handleScanResult),
      );
    }
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        iconTheme: const IconThemeData(color: Colors.white),
        backgroundColor: Colors.transparent,
        titleTextStyle: const TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
        elevation: 0,
        actions: [
          // 手电筒跟着相机确认的状态走，而不是跟着"我们请求了什么"走：
          // 没有闪光灯的机器按多少次都是关着的。
          ListenableBuilder(
            listenable: _scanController,
            builder: (context, _) => _scanController.hasTorch
                ? IconButton(
                    onPressed: _scanController.toggleTorch,
                    icon: Icon(_scanController.torchEnabled
                        ? Icons.flash_off_outlined
                        : Icons.flash_on_outlined),
                  )
                : const SizedBox.shrink(),
          ),
        ],
        title: const Text("二维码签到"),
      ),
      body: WxScanView(
        controller: _scanController,
        onResult: (result) => _handleScanResult(result.text),
        onError: _handleScanError,
      ),
    );
  }

  void _handleScanError(Object error) {
    if (!mounted) return;
    Get.to(() => ChangkeSignResult(
          successful: false,
          message: error is WxScanPermissionDenied
              ? "请允许相机权限才能进行扫描二维码"
              : "初始化失败，请重试",
        ))?.then((_) {
      // 返回后退出页面
      if (mounted) Get.back();
    });
  }

  // 处理扫描结果
  void _handleScanResult(String text) {
    if (GetPlatform.isMobile) {
      if (hasCustomVibrationsSupport) {
        Vibration.vibrate(duration: 100);
      } else {
        Vibration.vibrate();
      }
    }

    try {
      final codeData = parseChangkeScanUrl(text);

      if (codeData is! Map) {
        _failAndRescan("二维码格式错误");
        return;
      }

      final rollcallId = codeData['rollcallId']?.toString();
      final data = codeData['data'];

      if (rollcallId == null || data == null) {
        _failAndRescan("二维码格式错误");
        return;
      }

      // 立即导航到签到结果页面，显示"正在签到中"
      Get.to(() => QrSignResultPage(
            rollcallId: rollcallId,
            data: data,
            onBack: () {
              Get.back(); // 返回到扫描页面
              _restartScan(); // 重新开始扫描
            },
          ))?.then((_) {
        // 无论如何返回都确保相机重启
        _restartScan();
      });
    } catch (e) {
      print("扫描处理错误: $e");
      _failAndRescan("处理扫描结果时出错");
    }
  }

  void _failAndRescan(String message) {
    if (!mounted) return;
    Get.to(() => ChangkeSignResult(successful: false, message: message))
        ?.then((_) => _restartScan());
  }

  // 重新开始扫描
  void _restartScan() {
    if (mounted) _scanController.resume();
  }
}

// 二维码签到结果页面
enum QrSignState { loading, success, failure }

class QrSignResultPage extends StatefulWidget {
  final String rollcallId;
  final String data;
  final VoidCallback? onBack;

  const QrSignResultPage({
    super.key,
    required this.rollcallId,
    required this.data,
    this.onBack,
  });

  @override
  State<QrSignResultPage> createState() => _QrSignResultPageState();
}

class _QrSignResultPageState extends State<QrSignResultPage> {
  QrSignState currentState = QrSignState.loading;
  String message = "正在签到中...";

  @override
  void initState() {
    super.initState();
    _performSignIn();
  }

  Future<void> _performSignIn() async {
    try {
      // 设备号跟着账号走，同一个账号每次签到都是同一台设备
      final deviceId = ChangkeClient.instance.deviceId;

      // 真实的API调用
      final response = await TronClassService.signQr(
        ChangkeClient.instance.dio,
        rollcallId: widget.rollcallId,
        data: widget.data,
        deviceId: deviceId,
      ).timeout(
        Duration(seconds: 30),
        onTimeout: () {
          throw Exception("网络请求超时");
        },
      );

      final responseData = response.data;
      final int? id = responseData?["id"];
      final String? status = responseData?["status"];
      final bool isSuccessful =
          response.statusCode == 200 && status == "on_call";

      if (mounted) {
        setState(() {
          currentState =
              isSuccessful ? QrSignState.success : QrSignState.failure;
          message = isSuccessful
              ? getMappingMessage("success")
              : getMappingMessage(responseData?['message'] ?? "failed");
        });
      }
    } catch (e) {
      print("签到错误: $e");
      if (mounted) {
        setState(() {
          currentState = QrSignState.failure;
          message = e.toString().contains("超时")
              ? "网络连接超时，请检查网络"
              : getMappingMessage("retry");
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Loading状态使用渐变背景
    if (currentState == QrSignState.loading) {
      return WillPopScope(
        onWillPop: () async {
          // Loading状态下如果用户返回，调用onBack回调
          if (widget.onBack != null) {
            widget.onBack!();
          } else {
            Get.back();
          }
          return false; // 阻止默认返回行为
        },
        child: Scaffold(
          body: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xFF01b9bb),
                  Color(0xFF29cbcd),
                ],
              ),
            ),
            child: SafeArea(
              child: Column(
                children: [
                  // 顶部标题栏
                  Container(
                    height: 60,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        IconButton(
                          onPressed: () {
                            // Loading状态下返回按钮调用onBack
                            if (widget.onBack != null) {
                              widget.onBack!();
                            } else {
                              Get.back();
                            }
                          },
                          icon: const Icon(Icons.arrow_back_ios,
                              color: Colors.white, size: 20),
                        ),
                        const Expanded(
                          child: Center(
                            child: Text(
                              '二维码签到',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w500,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 48),
                      ],
                    ),
                  ),
                  // 中间内容区域
                  Expanded(
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // Loading图标
                          Container(
                            height: 200,
                            child: const Center(
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 3,
                              ),
                            ),
                          ),
                          const SizedBox(height: 30),
                          // 标题
                          const Text(
                            '正在签到',
                            style: TextStyle(
                              fontSize: 18,
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 10),
                          // 消息
                          Text(
                            message,
                            style: const TextStyle(
                              fontSize: 14,
                              color: Colors.white,
                              fontWeight: FontWeight.w400,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    // 成功失败状态保持原有样式
    return Scaffold(
      appBar: AppBar(
        title: Text("二维码签到"),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 64.0, vertical: 32),
                      child: _buildStateWidget(),
                    ),
                    Text(_getStateTitle(),
                        style: Theme.of(context).textTheme.titleMedium),
                    SizedBox(height: 12),
                    Text(message)
                  ],
                ),
              ),
            ),
            Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 10,
                    spreadRadius: 1,
                    offset: Offset(0, 0),
                  ),
                ],
              ),
              child: FilledButton(
                onPressed: () {
                  if (currentState == QrSignState.success) {
                    // 成功时直接退出到上一级页面
                    Get.back();
                  } else {
                    // 失败时调用onBack回调（返回扫描页面）
                    if (widget.onBack != null) {
                      widget.onBack!();
                    } else {
                      Get.back();
                    }
                  }
                },
                style: ButtonStyle(
                  shape: WidgetStateProperty.all(
                    RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  backgroundColor: WidgetStateProperty.all(Color(
                      currentState == QrSignState.success
                          ? 0xff1DB6C2
                          : 0xffff4853)),
                  elevation: WidgetStateProperty.all(0),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12.0),
                  child: Text(currentState == QrSignState.success ? '完成' : '重试',
                      style: TextStyle(fontSize: 16)),
                ),
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildStateWidget() {
    switch (currentState) {
      case QrSignState.loading:
        return const Center(
          child: CircularProgressIndicator(
            color: Colors.white,
            strokeWidth: 3,
          ),
        );
      case QrSignState.success:
        return Image.asset(
          "assets/images/qr_sign_ok.png",
          fit: BoxFit.contain,
        );
      case QrSignState.failure:
        return Image.asset(
          "assets/images/qr_sign_failed.png",
          fit: BoxFit.contain,
        );
    }
  }

  String _getStateTitle() {
    switch (currentState) {
      case QrSignState.loading:
        return "正在签到";
      case QrSignState.success:
        return "签到结果";
      case QrSignState.failure:
        return "签到结果";
    }
  }
}
