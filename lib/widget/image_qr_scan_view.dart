import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wxscan/wxscan.dart';

Future<XFile?> _pickQrImage() => openFile(
  confirmButtonText: '识别二维码',
  acceptedTypeGroups: const [
    XTypeGroup(
      label: '二维码图片',
      extensions: ['png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp'],
      uniformTypeIdentifiers: [
        'public.png',
        'public.jpeg',
        'com.compuserve.gif',
        'org.webmproject.webp',
        'com.microsoft.bmp',
      ],
    ),
  ],
);

Future<List<String>> _decodeQrImage(XFile file) async {
  final bytes = await file.readAsBytes();
  final detect = await rootBundle.load('assets/models/detect.tflite');
  final sr = await rootBundle.load('assets/models/sr.tflite');
  return WxScanner.use(
    (scanner) async {
      final outcome = await scanner.scanImage(bytes);
      return outcome.results.map((result) => result.text).toList();
    },
    detectModel: detect.buffer.asUint8List(),
    srModel: sr.buffer.asUint8List(),
  );
}

class ImageQrScanView extends StatefulWidget {
  const ImageQrScanView({
    super.key,
    required this.onResult,
    this.pickImage = _pickQrImage,
    this.decodeImage = _decodeQrImage,
  });

  final ValueChanged<String> onResult;
  final Future<XFile?> Function() pickImage;
  final Future<List<String>> Function(XFile) decodeImage;

  @override
  State<ImageQrScanView> createState() => _ImageQrScanViewState();
}

class _ImageQrScanViewState extends State<ImageQrScanView> {
  static const _clipboardChannel = MethodChannel('tronclass/clipboard_image');
  bool get _canPaste => defaultTargetPlatform == TargetPlatform.macOS;
  bool _busy = false;
  String _message = '选择相册中导出的图片或二维码截图';

  @override
  void initState() {
    super.initState();
    if (_canPaste) {
      _message = '选择图片，或按 Command+V 粘贴二维码截图';
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _scanImage();
    });
  }

  Future<void> _scanImage({bool fromClipboard = false}) async {
    if (_busy || ModalRoute.of(context)?.isCurrent == false) return;
    setState(() => _busy = true);
    try {
      XFile? file;
      if (fromClipboard) {
        final bytes = await _clipboardChannel.invokeMethod<Uint8List>(
          'readImage',
        );
        if (!mounted) return;
        if (bytes == null || bytes.isEmpty) {
          setState(() => _message = '剪贴板中没有图片，请先复制图片或截图到剪贴板');
          return;
        }
        file = XFile.fromData(
          bytes,
          mimeType: 'image/png',
          name: 'clipboard.png',
        );
      } else {
        file = await widget.pickImage();
      }
      if (!mounted || file == null) return;
      setState(() => _message = '正在识别图片中的二维码…');
      final codes = (await widget.decodeImage(file)).toSet().toList();
      if (!mounted) return;
      if (codes.isEmpty) {
        setState(() => _message = '未识别到二维码，请选择更清晰的图片');
      } else if (codes.length > 1) {
        setState(() => _message = '图片中有多个二维码，请裁剪保留需要签到的二维码后重试');
      } else {
        setState(() => _message = '识别完成，可选择其他图片继续扫码');
        widget.onResult(codes.single);
      }
    } on PlatformException catch (error) {
      if (mounted) {
        setState(
          () => _message = error.code == 'clipboard_read_failed'
              ? '无法读取复制的图片，请只复制一张图片，或使用选择图片入口'
              : '剪贴板读取失败，请重试或使用选择图片入口',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() => _message = '图片读取或识别失败，请选择 PNG、JPEG 等格式的图片重试');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {
      if (_canPaste)
        const SingleActivator(LogicalKeyboardKey.keyV, meta: true): () =>
            _scanImage(fromClipboard: true),
    },
    child: Focus(
      autofocus: true,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_busy)
                const CircularProgressIndicator()
              else
                Icon(
                  Icons.image_outlined,
                  size: 64,
                  color: Theme.of(context).colorScheme.primary,
                ),
              const SizedBox(height: 24),
              if (_canPaste) ...[
                FilledButton.icon(
                  onPressed: _busy
                      ? null
                      : () => _scanImage(fromClipboard: true),
                  icon: const Icon(Icons.content_paste),
                  label: const Text('粘贴图片扫码（⌘V）'),
                ),
                const SizedBox(height: 12),
              ],
              Text(_message, textAlign: TextAlign.center),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _busy ? null : _scanImage,
                icon: const Icon(Icons.photo_library_outlined),
                label: const Text('选择图片扫码'),
              ),
              const SizedBox(height: 12),
              const Text('图片仅在本机识别', textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    ),
  );
}
