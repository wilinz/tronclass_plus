import 'dart:convert';

import 'package:tronclass/auth/autofill_scope.dart';
import 'package:tronclass/auth/web_login_credential.dart';

/// 生成往认证页里填账号密码的脚本。
///
/// 各校的登录页长得都不一样，这里只能按特征猜：先找可见的密码框，
/// 再在它前面找一个像账号的输入框；找不到就按 name/id/placeholder
/// 里的关键词打分挑一个。验证码、搜索之类的框会被排除。
///
/// 只填值，不提交——短信、扫码、企业微信那些登录方式还得用户自己点。
String buildAutofillScript(
  WebLoginCredential credential, {
  required AutofillScope scope,
}) {
  final user = jsonEncode(credential.username);
  final pass = jsonEncode(credential.password);
  final origin = jsonEncode(scope.origin);
  final pathPrefix = jsonEncode(scope.pathPrefix);
  return '''
(function () {
  try {
    // 原生检查后仍可能导航，必须在实际执行的文档中再次校验。
    if (this.top !== this || this.location.protocol !== 'https:' ||
        this.location.origin !== $origin) {
      return 'blocked-origin';
    }
    // 不调用页面可覆写的 String 方法来决定是否释放凭据。
    var path = this.location.pathname, prefix = $pathPrefix;
    if (path.length < prefix.length) return 'blocked-origin';
    for (var p = 0; p < prefix.length; p++) {
      if (path[p] !== prefix[p]) return 'blocked-origin';
    }
    var USER = $user, PASS = $pass;

    function visible(el) {
      if (!el || el.disabled || el.readOnly) return false;
      var r = el.getBoundingClientRect();
      if (r.width <= 1 || r.height <= 1) return false;
      var s = window.getComputedStyle(el);
      return s.visibility !== 'hidden' && s.display !== 'none' && s.opacity !== '0';
    }

    // 直接改 value 的话 Vue/React 不认，得走原型上的 setter 再补事件。
    function setValue(el, value) {
      var proto = el instanceof HTMLTextAreaElement
        ? HTMLTextAreaElement.prototype
        : HTMLInputElement.prototype;
      var setter = Object.getOwnPropertyDescriptor(proto, 'value').set;
      el.focus();
      setter.call(el, value);
      el.dispatchEvent(new Event('input', { bubbles: true }));
      el.dispatchEvent(new Event('change', { bubbles: true }));
      el.dispatchEvent(new KeyboardEvent('keyup', { bubbles: true }));
      el.blur();
    }

    function hay(el) {
      return [el.name, el.id, el.placeholder, el.className,
              el.getAttribute('aria-label'), el.getAttribute('autocomplete')]
        .filter(Boolean).join(' ').toLowerCase();
    }

    var GOOD = ['user','account','login','uname','uid','sid','stu','no',
                'mobile','phone','email','学号','工号','账号','帐号','用户名','手机'];
    var BAD  = ['captcha','verify','vcode','checkcode','search','query',
                'answer','otp','dynamic','验证码','短信','搜索'];

    function bad(el) {
      var h = hay(el);
      for (var i = 0; i < BAD.length; i++) if (h.indexOf(BAD[i]) >= 0) return true;
      return false;
    }

    function score(el) {
      var h = hay(el), s = 0;
      for (var i = 0; i < GOOD.length; i++) if (h.indexOf(GOOD[i]) >= 0) s += 2;
      var t = (el.type || 'text').toLowerCase();
      if (t === 'text' || t === 'tel' || t === 'email') s += 1;
      return s;
    }

    var all = Array.prototype.slice.call(document.querySelectorAll('input'));
    var pwd = all.filter(function (el) {
      return (el.type || '').toLowerCase() === 'password' && visible(el);
    })[0] || null;

    var candidates = all.filter(function (el) {
      var t = (el.type || 'text').toLowerCase();
      return ['text','tel','email'].indexOf(t) >= 0 && visible(el) && !bad(el);
    });

    var userEl = null;
    if (pwd) {
      // 同一个表单里、排在密码框前面的那个，通常就是账号框
      var scope = pwd.form
        ? Array.prototype.slice.call(pwd.form.querySelectorAll('input'))
        : all;
      var before = scope.slice(0, scope.indexOf(pwd)).filter(function (el) {
        return candidates.indexOf(el) >= 0;
      });
      if (before.length) userEl = before[before.length - 1];
    }
    if (!userEl && candidates.length) {
      userEl = candidates.slice().sort(function (a, b) { return score(b) - score(a); })[0];
      if (score(userEl) <= 0) userEl = null;
    }

    var filled = [];
    if (userEl && USER) { setValue(userEl, USER); filled.push('user'); }
    if (pwd && PASS) { setValue(pwd, PASS); filled.push('pass'); }
    return filled.join(',');
  } catch (e) {
    return 'error:' + e;
  }
})();
''';
}
