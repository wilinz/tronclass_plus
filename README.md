# TronClass Plus

> macOS fork：本仓库增加了桌面图片/剪贴板扫码、学校来源校验、原生窗口与网页交互修复。
> 安装包见 [Releases](https://github.com/xyzxyq/tronclass_plus/releases)，构建与签名说明见 [macOS 发布说明](docs/macos-release.md)。

TronClass Plus 是非官方的 Tronclass 客户端，主打签到、雷达点名、二维码签到等场景，同时提供多账号、Web
门户和地图定位等工具，支持 Android / iOS / macOS / Windows / Web。

最初是给桂电写的，现在**所有用畅课的学校都能用**：内置学校检索，选中后按该校自己的方式登录；桂电那条不用打开网页的账号密码直登通道仍然保留。

## 核心功能

- **多学校支持**：搜学校 ➜ 选学校 ➜ 登录。接口地址、通知地址、身份认证配置都跟着选中的学校走，不再写死某一所。
- **两种登录方式**，选完学校自动分流：
    - 有统一身份认证的学校：打开该校自己的登录页面，账号密码、短信、扫码、企业微信怎么登都行；页面上浮一张**可拖动的账号密码卡片**，账号密码各能一键复制，并会**启发式自动填充**（认可见的密码框、按它前面的输入框找账号框，避开验证码/搜索框，只填不提交）。
    - 没有统一身份认证的学校（公有云上的都是）：直接提交账号密码，需要验证码的会弹出验证码，点图可换一张。
- **多账号管理**：会话按「学校 + 账号」隔离，登录态还在就**直接切换、不用重新登录**；列表显示姓名（学号）、所属学校、登录方式和登录态是否还在。
- **加密备份**：一键导出 / 导入全部数据（账号、会话、cookie）。密码经 PBKDF2-HMAC-SHA256（12 万次迭代）派生密钥，AES-256-CBC 加密并附 HMAC 校验，先验后解，密码错或文件被改都能直接判出来。导出时可选保存到任意位置或分享出去。
- **雷达点名助手**：动画反馈、状态提示，一键重试，异常信息清晰可见。
- **地图定位**：MapLibre 矢量地图（瓦片来自 OpenFreeMap，数据是 OpenStreetMap）的地点选择器，支持逆地理编码、WGS84 ➜ GCJ-02 自动转换。
- **Tronclass Web 入口**：内置 WebView 同步 Cookie、验证码弹窗、桌面/移动 UA 切换、缓存清理。
- **二维码 / 数字签到**：独立页面快速扫码或填码，配合 ChangkeClient 完成后台请求。

## 关于设备标识

请求头里的机型、系统版本、build 号以及签到用的 deviceId，都是**每个账号首次使用时随机生成一次、之后固定**，不读取本机任何真实设备信息：同一个账号始终表现为同一台设备（本来就该这样），不同账号之间也看不出关联。

## 踩坑记录

- **扫码用 [wxscan](https://github.com/wilinz/wxscan)（`wxscan_live`）**：CNN 检测 + 超分的 `wechat_qrcode` Rust 实现，小码、远码都能读。需要本机装有 rustup（首次构建时 build hook 自己编译 Rust 并拉 TFLite 库），CNN 权重放在 `assets/models/`（来自 [wxscan-weights](https://github.com/wilinz/wxscan-weights)），缺权重只是掉检测率，不会构建失败。
- **AGP 9 下选不了文件**：`file_picker` 和官方 `file_selector` 的 Android 端都要求 `android.builtInKotlin=true`，而本工程是 AGP 9 且一堆插件仍在自己 apply KGP，开了会连锁失败。备份的存取因此没引第三方依赖，直接在 `MainActivity.kt` 里走系统 SAF（`tronclass/storage_access` 方法通道），选文件和选保存位置都交给系统，App 也不需要存储权限。
- **提示别用 `Get.snackbar`**：它会往路由栈里压一层，紧跟其后的 `Get.back()` 弹掉的是这层提示而不是页面——表现就是「明明登录成功了，页面却一动不动」。统一用 fluttertoast。

## 下载
[https://github.com/wilinz/tronclass_puls/releases](https://github.com/wilinz/tronclass_puls/releases)

## 开发

1. 安装 Flutter 3.47.0+（建议使用 fvm 管理），并确保 `rustup` 在 PATH 里（wxscan 的 build hook 首次构建要编 Rust）
2. 执行 `flutter pub get` 拉取依赖
3. 根据目标平台运行：`flutter run -d android` / `-d ios` / `-d macos` / `-d windows` / `-d chrome`
4. 如需地图或 Web 功能，请确认本地网络可访问对应服务（中国大陆地区可能需要科学上网）

## 依赖栈

- Flutter + GetX 状态管理
- webview_flutter / maplibre_gl / geolocator / geocoding
- encrypt + get_storage 密钥存储
- wxscan_live 扫码（wechat_qrcode 的 Rust 实现）
- dio, share_plus, permission_handler 等常用插件

## TODO

1. 公有云学校（账号密码直登那条）缺真实账号验证，目前只做过静态分析和联调准备。
2. 同一域名下多所公有云学校来回切换时，服务端是否接受各自留存的会话，还需实测。

## 截图

| TronClass Portal                                    | Rollcall List                                          |
|-----------------------------------------------------|--------------------------------------------------------|
| ![Radar](screenshot/Screenshot_20251113_023442.png) | ![Accounts](screenshot/Screenshot_20251113_023532.png) |
| Map Picker                                          | Number Rollcall                                        |
| ![Map](screenshot/Screenshot_20251113_031906.png)   | ![Portal](screenshot/Screenshot_20251113_023610.png)   |
| QR Rollcall                                         | Account Manager                                        |
| ![Login](screenshot/Screenshot_20251113_025551.png) | ![QR](screenshot/Screenshot_20251113_030024.png)       |

------

## English

TronClass Plus is an unofficial Flutter client that streamlines everyday campus tasks. It focuses on
fast sign-ins, radar rollcalls, QR check-ins, and a polished multi-account experience across
Android, iOS, macOS, Windows, and the web.

It started out for a single school, but **works with any school on TronClass** now: search for your
school, pick it, and sign in the way that school supports. The original password-only shortcut for
Guilin University of Electronic Technology is still there.

## Key Features

- **Any School** – Built-in school search. API host, notification host and identity settings all
  follow the selected school instead of being hard-coded.
- **Two Sign-in Paths**, picked automatically once you choose a school:
    - Schools with a unified identity provider: their own sign-in page opens, so password, SMS, QR
      and enterprise IM all keep working. A **draggable credential card** floats above the page with
      one-tap copy for account and password, plus **heuristic autofill** (finds the visible password
      field, takes the input before it as the account field, skips captcha/search boxes, and only
      fills — never submits).
    - Schools without one (everything on the shared cloud): account and password are submitted
      directly, with a captcha dialog where required (tap the image for a new one).
- **Multi-Account Switcher** – Sessions are isolated per *school + account*, so switching to an
  account whose session is still alive takes no re-login at all. The list shows the person's name,
  school, sign-in method and whether the session is still valid.
- **Encrypted Backup** – Export/import everything (accounts, sessions, cookies) in one file. The
  password is stretched with PBKDF2-HMAC-SHA256 (120k iterations), the payload is AES-256-CBC
  encrypted and HMAC-authenticated, and the MAC is verified *before* decryption, so a wrong password
  or a tampered file is reported as such. Save anywhere or share it out.
- **Radar Rollcall Assistant** – Visual radar animation with retry guidance and backend status
  tracking.
- **Interactive Map Picker** – Choose rollcall coordinates on MapLibre vector tiles (served by OpenFreeMap, OpenStreetMap data), reverse-geocode
  addresses, and automatically convert WGS84 ➜ GCJ-02 before submission.
- **Tronclass Web Portal** – Built-in WebView (webview_flutter) with cookie sync, captcha handling,
  user-agent switching, and cache cleaning.
- **QR & Number Rollcalls** – Dedicated workflows for fast classroom check-ins, including scanning
  and manual code entry.
- **Toast & Notification Helpers** – Custom toast utility, localized messaging, and graceful error
  states.

## About Device Identifiers

The device model, OS version and build number in the request headers, along with the `deviceId` sent
with rollcall check-ins, are **generated randomly once per account and then kept stable**. Nothing is
read from the real device: one account always looks like the same phone (as it should), and two
accounts never look related.

## Getting Started

1. **Environment** – Install Flutter 3.35.0+ with fvm (`fvm install 3.35.0`).
2. **Dependencies** – `flutter pub get`
3. **Platform Setup**
    - Android: `flutter run -d android`
    - iOS: `cd ios && pod install && cd ..`
    - Desktop/Web: `flutter run -d macos` / `-d windows` / `-d chrome`
4. **Config** – Ensure `assets/` and `fonts/` listed in `pubspec.yaml` are kept in sync when adding
   images or localization files.

## Project Structure

```
lib/
├── auth/              # 登录页、账号管理、两条登录流程与凭据卡片
│   ├── generic_login.dart      # 统一身份认证：认证页取 code ➜ 换 token ➜ 换会话
│   ├── public_login.dart       # 账号密码直登（含验证码）
│   ├── login_session.dart      # 两条流程共用的收尾与错误翻译
│   ├── credential_card.dart    # 认证页上可拖动、可复制的账号密码卡片
│   ├── autofill_script.dart    # 启发式自动填充脚本
│   └── org_search_page.dart    # 学校检索
├── data/              # 网络客户端、接口服务、存储
│   ├── changke_client.dart     # 按「学校 + 账号」隔离的会话与 CookieJar
│   ├── org_store.dart          # 当前选中的学校
│   ├── user_agent.dart         # 每账号固定的设备标识与请求头
│   └── backup/                 # 加密导入导出 + 系统 SAF 通道
├── tronclass/         # 功能页面（雷达、二维码、数字签到、首页）
├── utils/             # 坐标转换等工具
└── webview/           # 带 Cookie 同步和验证码处理的 WebView 封装
```

## Tech Stack

- **Flutter + GetX** for reactive state and navigation
- **webview_flutter** for the embedded Tronclass portal
- **maplibre_gl + geolocator + geocoding** for selecting and reverse-geocoding locations
- **encrypt + pointycastle + get_storage** for secure multi-account storage and encrypted backups
- **share_plus, permission_handler, dio** for platform capabilities and networking

------

欢迎 Issue / PR 交流改进，祝使用愉快!
