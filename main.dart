import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Your website.
const String kSiteUrl = 'https://expressdataplug.com/account/';

/// WhatsApp number in international format, digits only, no "+".
/// Example Nigeria: 2348012345678  (CHANGE THIS)
const String kWhatsApp = '2347083407885';
const String kWhatsAppMessage = 'Hello ExpressDataPlug, I need help.';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'ExpressDataPlug',
      theme: ThemeData(colorSchemeSeed: const Color(0xFFED2024), useMaterial3: true),
      home: const WebScreen(),
    );
  }
}

class WebScreen extends StatefulWidget {
  const WebScreen({super.key});

  @override
  State<WebScreen> createState() => _WebScreenState();
}

class _WebScreenState extends State<WebScreen> {
  late final WebViewController _controller;
  final LocalAuthentication _auth = LocalAuthentication();
  final FlutterSecureStorage _store = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  bool _loading = true;
  bool _failed = false;
  Map<String, String>? _pending; // credentials typed on the login page

  // Runs inside the website: adds a fingerprint button to the login form and
  // reports the typed email/password back to the app.
  static const String _injectJs = r'''
(function(){
  if (window.__edpInit) return; window.__edpInit = true;
  function pw(){ return document.querySelector('input[formcontrolname="password"]'); }
  function em(){ return document.querySelector('input[formcontrolname="email"]'); }
  function send(o){ try { App.postMessage(JSON.stringify(o)); } catch(e){} }
  function addBtn(){
    var p = pw(); if (!p || document.getElementById('edp-fp')) return;
    var form = p.closest('form'); if (!form) return;
    var b = document.createElement('button');
    b.id = 'edp-fp'; b.type = 'button';
    b.className = 'btn btn-outline-primary btn-block mt-1';
    b.textContent = 'Login with fingerprint';
    b.onclick = function(){ send({t:'fp'}); };
    form.appendChild(b);
  }
  function capture(){
    var p = pw(), e = em();
    if (p && e && p.value && e.value) send({t:'creds', e:e.value, p:p.value});
  }
  document.addEventListener('submit', capture, true);
  document.addEventListener('click', function(ev){
    var t = ev.target && ev.target.closest ? ev.target.closest('button.btn-primary') : null;
    if (t && t.id !== 'edp-fp') capture();
  }, true);
  new MutationObserver(addBtn).observe(document.documentElement, {childList:true, subtree:true});
  addBtn();
})();
''';

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel('App', onMessageReceived: _onWebMessage)
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (_) => setState(() {
          _loading = true;
          _failed = false;
        }),
        onPageFinished: (url) async {
          setState(() => _loading = false);
          await _controller.runJavaScript(_injectJs);
          // Logged in successfully -> offer to save for fingerprint login.
          if (url.contains('/dashboard') && _pending != null) {
            final creds = _pending!;
            _pending = null;
            _offerSave(creds);
          }
        },
        onWebResourceError: (e) {
          if (e.isForMainFrame ?? true) setState(() => _failed = true);
        },
      ))
      ..loadRequest(Uri.parse(kSiteUrl));
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _onWebMessage(JavaScriptMessage m) async {
    try {
      final data = jsonDecode(m.message) as Map<String, dynamic>;
      if (data['t'] == 'creds') {
        _pending = {'e': data['e'] as String, 'p': data['p'] as String};
      } else if (data['t'] == 'fp') {
        await _fingerprintLogin();
      }
    } catch (_) {}
  }

  Future<void> _offerSave(Map<String, String> creds) async {
    final savedEmail = await _store.read(key: 'email');
    final savedPass = await _store.read(key: 'pass');
    if (savedEmail == creds['e'] && savedPass == creds['p']) return;
    if (!mounted) return;
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Enable fingerprint login?'),
        content: const Text(
            'Next time you can sign in with your fingerprint. Your details are stored encrypted on this phone only.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Not now')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Enable')),
        ],
      ),
    );
    if (yes == true) {
      await _store.write(key: 'email', value: creds['e']);
      await _store.write(key: 'pass', value: creds['p']);
      _snack('Fingerprint login enabled');
    }
  }

  Future<void> _fingerprintLogin() async {
    final email = await _store.read(key: 'email');
    final pass = await _store.read(key: 'pass');
    if (email == null || pass == null) {
      _snack('First sign in with your email and password, then choose Enable.');
      return;
    }
    try {
      final supported = await _auth.isDeviceSupported();
      if (!supported) {
        _snack('Set up a fingerprint or screen lock on your phone first.');
        return;
      }
      final ok = await _auth.authenticate(
        localizedReason: 'Sign in to ExpressDataPlug',
        options: const AuthenticationOptions(biometricOnly: false, stickyAuth: true),
      );
      if (!ok) return;
      final js = '''
(function(){
  function setV(el, v){
    var s = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set;
    s.call(el, v);
    el.dispatchEvent(new Event('input', {bubbles:true}));
    el.dispatchEvent(new Event('change', {bubbles:true}));
  }
  var e = document.querySelector('input[formcontrolname="email"]');
  var p = document.querySelector('input[formcontrolname="password"]');
  if (!e || !p) return;
  setV(e, ${jsonEncode(email)});
  setV(p, ${jsonEncode(pass)});
  setTimeout(function(){
    var f = p.closest('form');
    var b = f && f.querySelector('button.btn-primary:not(#edp-fp)');
    if (b) b.click();
  }, 250);
})();
''';
      await _controller.runJavaScript(js);
    } catch (e) {
      _snack('Fingerprint failed. Please sign in with your password.');
    }
  }

  Future<void> _openWhatsApp() async {
    if (kWhatsApp.contains('X')) {
      _snack('WhatsApp number is not set yet.');
      return;
    }
    final uri = Uri.parse('https://wa.me/$kWhatsApp?text=${Uri.encodeComponent(kWhatsAppMessage)}');
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok) _snack('Could not open WhatsApp.');
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _controller.canGoBack()) _controller.goBack();
      },
      child: Scaffold(
        body: SafeArea(
          child: Stack(
            children: [
              WebViewWidget(controller: _controller),
              if (_loading) const Center(child: CircularProgressIndicator()),
              if (_failed)
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Could not load the page.'),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: () => _controller.loadRequest(Uri.parse(kSiteUrl)),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              Positioned(
                right: 16,
                bottom: 20,
                child: FloatingActionButton(
                  heroTag: 'wa',
                  backgroundColor: const Color(0xFF25D366),
                  foregroundColor: Colors.white,
                  onPressed: _openWhatsApp,
                  child: const Icon(Icons.chat),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
