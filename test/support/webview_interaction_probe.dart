// Local-only macOS platform-view fixture; no accounts or network requests.
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:tronclass/widget/mac_phone_frame.dart';
import 'package:webview_flutter/webview_flutter.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  var frames = 0;
  SchedulerBinding.instance.addPersistentFrameCallback((_) => frames++);
  const MethodChannel('tronclass/probe').setMethodCallHandler((call) async {
    if (call.method == 'frameCount') return frames;
    throw MissingPluginException();
  });
  final controller = WebViewController()
    ..setJavaScriptMode(JavaScriptMode.unrestricted)
    ..loadHtmlString('''<!doctype html><html><head>
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>body {margin:0;padding:24px;font:18px sans-serif} button,input {padding:12px;font:18px sans-serif} .spacer {height:1800px}</style>
</head><body>
<button id="tap" onclick="this.textContent='Clicked'">Test click</button><br><br>
<input id="input" aria-label="Test input" placeholder="Test input">
<div class="spacer">Scroll test</div><p>Bottom of page</p>
<script>window.probeReady=true</script></body></html>''');
  runApp(
    MaterialApp(
      builder: (_, child) => MacPhoneFrame(child: child!),
      home: Scaffold(
        appBar: AppBar(title: const Text('Local WebView test')),
        body: WebViewWidget(controller: controller),
      ),
    ),
  );
}
