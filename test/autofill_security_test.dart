import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tronclass/auth/autofill_scope.dart';
import 'package:tronclass/auth/autofill_script.dart';
import 'package:tronclass/auth/web_login_credential.dart';
import 'package:tronclass/data/model/tron_org.dart';

void main() {
  const config = IdentityConfig(
    authServerUrl: 'https://identity.school.example/auth',
    realm: 'school-a',
    resource: 'TronClassApp',
  );
  final scope = AutofillScope.fromIdentityConfig(config)!;
  const credential = WebLoginCredential(
    username: 'student"\\name',
    password: 'secret\n"\\value',
  );
  final script = buildAutofillScript(credential, scope: scope);

  Map<String, dynamic> execute(
    String url, {
    bool iframe = false,
    bool tamperString = false,
  }) {
    // Node executes the actual generated JavaScript with a small instrumented DOM.
    final result = Process.runSync('node', [
      'test/support/autofill_dom.cjs',
      jsonEncode({
        'script': script,
        'url': url,
        'iframe': iframe,
        'tamperString': tamperString,
      }),
    ]);
    expect(result.exitCode, 0, reason: '${result.stderr}');
    return jsonDecode(result.stdout as String) as Map<String, dynamic>;
  }

  for (final url in [
    config.authorizationEndpoint,
    'https://identity.school.example/auth/realms/school-a/login-actions/authenticate?session_code=abc',
    'https://IDENTITY.school.example:443/auth/realms/school-a/login#step',
  ]) {
    test('selected school fills correctly: $url', () {
      expect(scope.allows(url), isTrue);
      final result = execute(url);
      expect(result['result'], 'user,pass');
      expect(result['username'], credential.username);
      expect(result['password'], credential.password);
      expect(result['events'], 6);
    });
  }

  for (final url in [
    'https://attacker.example/auth/realms/school-a/login',
    'https://identity.school.example.attacker.example/auth/realms/school-a/login',
    'https://child.identity.school.example/auth/realms/school-a/login',
    'http://identity.school.example/auth/realms/school-a/login',
    'https://identity.school.example:444/auth/realms/school-a/login',
    'https://identity.school.example@attacker.example/auth/realms/school-a/login',
    'https://identity.school.example/auth/realms/school-b/login',
    'https://identity.school.example/auth/realms/school-a-evil/login',
    'https://identity.school.example/auth/realms/school-a/../school-b/login',
    'https://identity.school.example/auth/realms/school-a/%2e%2e/school-b/login',
    'https://identity.school.example/auth/realms/',
    'https://identity.school.example/unrelated',
    'about:blank',
    'data:text/html,test',
  ]) {
    test('untrusted document receives no credentials: $url', () {
      expect(scope.allows(url), isFalse);
      // Also models navigation AFTER the native URL check: the same generated
      // credential script must reject the new document independently.
      final result = execute(url);
      expect(result['result'], 'blocked-origin');
      expect(result['reads'], 0);
      expect(result['username'], '');
      expect(result['password'], '');
      expect(result['events'], 0);
    });
  }

  test('script refuses execution in a frame', () {
    final result = execute(config.authorizationEndpoint, iframe: true);
    expect(result['result'], 'blocked-origin');
    expect(result['reads'], 0);
  });

  test('page-overridden string methods cannot bypass realm guard', () {
    final result = execute(
      'https://identity.school.example/auth/realms/school-b/login',
      tamperString: true,
    );
    expect(result['result'], 'blocked-origin');
    expect(result['reads'], 0);
  });

  test('short paths cannot inherit missing realm characters', () {
    final result = execute(
      'https://identity.school.example/auth/realms/',
      tamperString: true,
    );
    expect(result['result'], 'blocked-origin');
    expect(result['reads'], 0);
  });

  test('missing or malformed current URLs fail closed', () {
    for (final url in [
      null,
      '',
      'https://[invalid',
      'https://user@identity.school.example/auth/realms/school-a/login',
      r'https://identity.school.example\@attacker.example/login',
    ]) {
      expect(scope.allows(url), isFalse);
    }
  });

  test('invalid school configuration disables autofill', () {
    for (final server in [
      'http://identity.school.example/auth',
      'https://user@identity.school.example/auth',
      'https://identity.school.example/auth?redirect=other',
      'https://identity.school.example/auth#other',
      'https://[invalid',
      '',
    ]) {
      expect(
        AutofillScope.fromIdentityConfig(
          IdentityConfig(
            authServerUrl: server,
            realm: 'school-a',
            resource: 'app',
          ),
        ),
        isNull,
      );
    }
    for (final realm in ['', '.', '..', '../school-b', 'school%2fb', r'a\b']) {
      expect(
        AutofillScope.fromIdentityConfig(
          IdentityConfig(
            authServerUrl: config.authServerUrl,
            realm: realm,
            resource: 'app',
          ),
        ),
        isNull,
      );
    }
  });
}
