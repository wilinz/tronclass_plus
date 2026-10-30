# macOS 1.7.0

本版基于 wilinz/tronclass_plus，发布到 xyzxyq/tronclass_plus。

## 安装

下载 Release 中的 Apple Silicon（arm64）DMG，打开后将 `TronClass Plus.app` 拖入 Applications。此包要求 macOS 15 或更新版本，不支持 Intel Mac；扫码依赖中 TensorFlow Lite 二进制的最低系统版本为 macOS 15。原生透明玻璃仅在 macOS 26 及以上启用。运行验证在 macOS 27.0.1 开发机器进行，未逐个验证旧版系统。

此版本使用临时签名（ad-hoc），没有 Developer ID 证书，也未经过 Apple 公证。macOS Gatekeeper 可能阻止首次打开；请先核对下载来源和 SHA-256，再按系统“隐私与安全性”界面的提示处理，不需要关闭系统安全保护。

## 本版变更

- 自动填充限定到对应学校的 HTTPS 认证来源及 realm，拒绝不匹配页面和 iframe。
- 桌面扫码支持选图、截图粘贴及 Finder 复制图片文件，优先解码原始文件。
- macOS 手机比例窗口、原生窗口按钮、灵动岛拖动和透明玻璃波纹。
- 修复 WebView 初始化加载失败、鼠标坐标错位及边框动画干扰悬停的问题。
- 修复账号管理按钮溢出；添加账号先选学校，新学校表单不复用旧账号密码。

## 构建与测试

本次验证使用 Xcode 27、Flutter 3.50.0-0.2.pre（beta，revision 9c0b99ee21）、Dart 3.14 beta 和 Rust 1.95 工具链。最低 SDK 约束见 pubspec.yaml，其他 Flutter 版本未在本次发布中验证。依赖中的 Rust native asset 需要 Cargo。macOS 27 下禁用 wxscan 符号剥离的设置已保存在 pubspec.yaml。

```sh
flutter pub get
flutter test
FLUTTER_MACOS_ARM64_ONLY=true flutter build macos --release --target lib/main.dart
codesign --force --sign - --entitlements macos/Runner/Release.entitlements build/macos/Build/Products/Release/tronclass.app
codesign --verify --deep --strict build/macos/Build/Products/Release/tronclass.app
```

请在 APFS 工作目录构建，避免外置卷生成的 AppleDouble `._` 元数据影响签名。发布包只包含构建后的应用与安装说明，不包含开发机的账号、Cookie 或用户配置。

本次 beta 工具链首次编译 wxscan 构建 hook 时触发 Dart `ForInLowering` 编译器崩溃；构建复用了同一依赖、同一 SDK 和 package 配置下先前生成的 hook 编译缓存，再执行 Release 原生构建及应用 AOT 编译。未修改依赖源码，发布包也不包含这个构建缓存。此环境的无缓存构建仍受工具链问题影响，不能声称已验证干净环境下的可复现构建。

本次通过 53 项 Flutter 测试和 13 项 macOS RunnerTests。测试范围包括自动填充安全边界、图片/剪贴板处理、账号流程、窗口布局和原生 WebView 坐标。发布包为 arm64 Release AOT 构建，临时签名仅保留发布 entitlements，不包含调试器授权。上述检查不等同于已完成整个项目的安全审计。
