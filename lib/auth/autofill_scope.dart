import 'package:tronclass/data/model/tron_org.dart';

/// 只信任所选学校配置中的 HTTPS 来源及其 Keycloak realm。
/// 重定向不会扩大权限；外部 CAS 等来源需要单独核实后才能支持。
class AutofillScope {
  const AutofillScope._(this.origin, this.pathPrefix);

  final String origin;
  final String pathPrefix;

  static AutofillScope? fromIdentityConfig(IdentityConfig config) {
    final server = _httpsUri(config.authServerUrl);
    final realm = config.realm;
    if (server == null ||
        server.hasQuery ||
        server.hasFragment ||
        realm.isEmpty ||
        realm == '.' ||
        realm == '..' ||
        realm.contains(RegExp(r'[/\\%]'))) {
      return null;
    }
    final segments = server.pathSegments.toList();
    if (segments.isNotEmpty && segments.last.isEmpty) segments.removeLast();
    final realmUri = server.replace(
      pathSegments: [...segments, 'realms', realm, ''],
    );
    return AutofillScope._(realmUri.origin, realmUri.path);
  }

  bool allows(String? url) {
    final uri = _httpsUri(url);
    return uri != null &&
        uri.origin == origin &&
        uri.path.startsWith(pathPrefix);
  }

  static Uri? _httpsUri(String? url) {
    if (url == null || url.contains(RegExp(r'[\s\\]'))) return null;
    final uri = Uri.tryParse(url);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      return null;
    }
    return uri;
  }
}
