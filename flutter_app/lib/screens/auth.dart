import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api.dart';
import '../l10n.dart';
import '../state.dart';
import '../theme.dart';
import '../widgets.dart';

enum _Mode { login, create, join }

// Same Web OAuth client as the backend/web app verify against — Android's
// google_sign_in issues an ID token audienced for this client when given
// as serverClientId, so the server only ever needs to check one audience.
const _googleWebClientId =
    '957970436165-nddupot9otscvlm15ual30fagrkfaj5b.apps.googleusercontent.com';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  _Mode _mode = _Mode.login;
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _email = TextEditingController();
  final _displayName = TextEditingController();
  final _householdName = TextEditingController();
  final _token = TextEditingController();

  bool _busy = false;
  bool _gdpr = false;
  bool _obscurePassword = true;
  String? _error;

  // For join: looked-up members to claim
  List<Map<String, dynamic>> _lookupMembers = [];
  String? _selectedMemberId;
  String? _lookedUpName;

  // Email verification step, shown after register() returns
  // pending_verification — see _submit()/_verifyCode()/_resendCode().
  bool _verifying = false;
  String? _pendingEmail;
  Map<String, dynamic>? _pendingRegisterBody;
  final _code = TextEditingController();

  // Google sign-in: shown when /api/auth/google says the email is brand
  // new and needs a create/join household choice — see
  // _handleGoogleSignIn()/_completeGoogleSetup().
  final _googleSignIn = GoogleSignIn(serverClientId: _googleWebClientId);
  bool _googleNeedsSetup = false;
  bool _googleBusy = false;
  String? _googleIdToken;
  String? _googleEmail;
  _Mode _googleSetupMode = _Mode.create;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    _email.dispose();
    _displayName.dispose();
    _householdName.dispose();
    _token.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _handleGoogleSignIn() async {
    setState(() {
      _googleBusy = true;
      _error = null;
    });
    try {
      final account = await _googleSignIn.signIn();
      if (account == null) return; // user cancelled the picker
      final auth = await account.authentication;
      final idToken = auth.idToken;
      if (idToken == null) {
        setState(() => _error = context.t('net_retry'));
        return;
      }
      if (!mounted) return;
      final res = await context.read<AppState>().googleAuth(idToken);
      if (res['needs_setup'] == true && mounted) {
        setState(() {
          _googleIdToken = idToken;
          _googleEmail = res['email']?.toString();
          _googleNeedsSetup = true;
          _googleSetupMode = _Mode.create;
          final suggested = res['suggested_name']?.toString() ?? '';
          if (suggested.isNotEmpty) _displayName.text = suggested;
        });
      }
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = context.t('net_retry'));
    } finally {
      if (mounted) setState(() => _googleBusy = false);
    }
  }

  Future<void> _completeGoogleSetup() async {
    final extra = <String, dynamic>{
      'action': _googleSetupMode == _Mode.join ? 'join' : 'create',
    };
    if (_googleSetupMode == _Mode.join) {
      if (_selectedMemberId == null) {
        setState(() => _error = context.t('pick_who'));
        return;
      }
      extra['token'] = _token.text.trim().toUpperCase();
      extra['member_id'] = _selectedMemberId;
    } else {
      extra['household_name'] = _householdName.text.trim().isEmpty
          ? 'My Family'
          : _householdName.text.trim();
      extra['display_name'] = _displayName.text.trim();
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<AppState>().googleAuth(_googleIdToken!, extra);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = context.t('net_retry'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _lookup() async {
    final token = _token.text.trim().toUpperCase();
    if (token.length != 6) {
      setState(() => _error = context.t('enter_code6'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final api = context.read<AppState>().api;
      final res = await api.householdLookup(token);
      setState(() {
        _lookedUpName = res['name']?.toString();
        _lookupMembers =
            (res['members'] as List?)?.cast<Map<String, dynamic>>() ?? [];
        _selectedMemberId = null;
      });
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = context.t('net_retry'));
    } finally {
      setState(() => _busy = false);
    }
  }

  static final _emailRe = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  Future<void> _submit() async {
    final app = context.read<AppState>();
    final password = _password.text;
    if (password.isEmpty) {
      setState(() => _error = context.t('enter_email_pass'));
      return;
    }
    if (_mode == _Mode.login) {
      final identifier = _username.text.trim();
      if (identifier.isEmpty || !_emailRe.hasMatch(identifier)) {
        setState(() => _error = context.t('enter_email'));
        return;
      }
    } else {
      final email = _email.text.trim();
      if (email.isEmpty || !_emailRe.hasMatch(email)) {
        setState(() => _error = context.t('enter_email'));
        return;
      }
      if (!_gdpr) {
        setState(() => _error = context.t('gdpr_required'));
        return;
      }
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      switch (_mode) {
        case _Mode.login:
          await app.login(_username.text.trim(), password);
        case _Mode.create:
          final body = {
            'password': password,
            'email': _email.text.trim(),
            'action': 'create',
            'display_name': _displayName.text.trim(),
            'household_name': _householdName.text.trim().isEmpty
                ? 'My Family'
                : _householdName.text.trim(),
          };
          await _registerAndMaybeVerify(app, body);
        case _Mode.join:
          if (_selectedMemberId == null) {
            setState(() => _error = context.t('pick_who'));
            return;
          }
          final body = {
            'password': password,
            'email': _email.text.trim(),
            'action': 'join',
            'token': _token.text.trim().toUpperCase(),
            'member_id': _selectedMemberId,
          };
          await _registerAndMaybeVerify(app, body);
      }
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = context.t('net_retry'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _registerAndMaybeVerify(
      AppState app, Map<String, dynamic> body) async {
    final res = await app.register(body);
    if (res['pending_verification'] == true && mounted) {
      setState(() {
        _verifying = true;
        _pendingEmail = res['email']?.toString() ?? body['email'] as String?;
        _pendingRegisterBody = body;
      });
    }
  }

  Future<void> _verifyCode() async {
    final code = _code.text.trim();
    if (code.length != 6) {
      setState(() => _error = context.t('enter_code6_digits'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<AppState>().verifyEmail(_pendingEmail!, code);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = context.t('net_retry'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resendCode() async {
    if (_pendingRegisterBody == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<AppState>().register(_pendingRegisterBody!);
      if (mounted) showSnack(context, context.t('code_resent'));
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = context.t('net_retry'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ch;
    if (_verifying) return _buildVerifyScreen(context, c);
    if (_googleNeedsSetup) return _buildGoogleSetupScreen(context, c);
    return Scaffold(
      backgroundColor: c.pageBg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Logo mark
                  Center(
                    child: Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        gradient: c.accentGradient,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Icon(Icons.home_rounded,
                          color: Colors.white, size: 34),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text('CleanHabit',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          color: c.textPrimary,
                          letterSpacing: -0.5)),
                  const SizedBox(height: 4),
                  Text(
                    context.t(_mode == _Mode.login
                        ? 'welcome_back'
                        : _mode == _Mode.create
                            ? 'start_family'
                            : 'join_family'),
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 15, color: c.textSecondary),
                  ),
                  const SizedBox(height: 24),

                  _segmented(c),
                  const SizedBox(height: 18),

                  AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_mode == _Mode.join) ...[
                          _field(c, _token, context.t('family_code_hint'),
                              caps: true),
                          const SizedBox(height: 10),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: _busy ? null : _lookup,
                              child: Text(context.t('lookup_family'),
                                  style: TextStyle(color: c.accent)),
                            ),
                          ),
                          if (_lookedUpName != null) ...[
                            Text(context.t('who_are_you', {'name': _lookedUpName!}),
                                style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: c.textPrimary)),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: _lookupMembers.map((m) {
                                final id = m['id'].toString();
                                final sel = id == _selectedMemberId;
                                return GestureDetector(
                                  onTap: () =>
                                      setState(() => _selectedMemberId = id),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: sel ? c.accent : c.pageBg,
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: Text(
                                      '${m['emoji']} ${m['name']}',
                                      style: TextStyle(
                                          color: sel
                                              ? Colors.white
                                              : c.textPrimary,
                                          fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                            const SizedBox(height: 12),
                          ],
                        ],
                        if (_mode == _Mode.create) ...[
                          _field(c, _displayName, context.t('your_name')),
                          const SizedBox(height: 10),
                          _field(c, _householdName, context.t('family_name')),
                          const SizedBox(height: 10),
                        ],
                        if (_mode == _Mode.login) ...[
                          _field(c, _username, context.t('email'),
                              keyboardType: TextInputType.emailAddress),
                          const SizedBox(height: 10),
                          _field(c, _password, context.t('password'),
                              obscure: _obscurePassword,
                              suffixIcon: _passwordToggle(c, _obscurePassword,
                                  () => setState(() =>
                                      _obscurePassword = !_obscurePassword))),
                        ] else ...[
                          _field(c, _email, context.t('email'),
                              keyboardType: TextInputType.emailAddress),
                          const SizedBox(height: 10),
                          _field(c, _password, context.t('password'),
                              obscure: _obscurePassword,
                              suffixIcon: _passwordToggle(c, _obscurePassword,
                                  () => setState(() =>
                                      _obscurePassword = !_obscurePassword))),
                          const SizedBox(height: 12),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                width: 24,
                                height: 24,
                                child: Checkbox(
                                  value: _gdpr,
                                  activeColor: c.accent,
                                  onChanged: (v) =>
                                      setState(() => _gdpr = v ?? false),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: GestureDetector(
                                  onTap: () =>
                                      setState(() => _gdpr = !_gdpr),
                                  child: RichText(
                                    text: TextSpan(
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: c.textSecondary,
                                          height: 1.5),
                                      children: [
                                        TextSpan(
                                            text: context.t('gdpr_accept')),
                                        WidgetSpan(
                                          child: GestureDetector(
                                            onTap: () => launchUrl(Uri.parse(
                                                'https://cleanhabit.myroapp.org/privacy')),
                                            child: Text(
                                              context.t('privacy_policy'),
                                              style: TextStyle(
                                                  fontSize: 12,
                                                  color: c.accent,
                                                  decoration: TextDecoration
                                                      .underline),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                        if (_mode == _Mode.login) ...[
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: () => _showForgotPassword(context, c),
                              child: Text(context.t('forgot_password'),
                                  style: TextStyle(
                                      color: c.accent, fontSize: 13)),
                            ),
                          ),
                        ],
                        if (_error != null) ...[
                          const SizedBox(height: 12),
                          Text(_error!,
                              style: const TextStyle(
                                  color: Color(0xFFB3261E), fontSize: 13)),
                        ],
                        const SizedBox(height: 16),
                        SizedBox(
                          height: 50,
                          child: FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: c.accent,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14)),
                            ),
                            onPressed: _busy ? null : _submit,
                            child: _busy
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2.5, color: Colors.white))
                                : Text(
                                    context.t(_mode == _Mode.login
                                        ? 'login'
                                        : 'create_account'),
                                    style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white)),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(child: Divider(color: c.divider)),
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 10),
                              child: Text(context.t('or'),
                                  style: TextStyle(
                                      fontSize: 12, color: c.textSecondary)),
                            ),
                            Expanded(child: Divider(color: c.divider)),
                          ],
                        ),
                        const SizedBox(height: 14),
                        SizedBox(
                          height: 50,
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(color: c.divider),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14)),
                            ),
                            onPressed: _googleBusy ? null : _handleGoogleSignIn,
                            icon: _googleBusy
                                ? SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: c.textSecondary))
                                : const Text('G',
                                    style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w800,
                                        color: Color(0xFF4285F4))),
                            label: Text(context.t('continue_with_google'),
                                style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: c.textPrimary)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildVerifyScreen(BuildContext context, ChColors c) {
    return Scaffold(
      backgroundColor: c.pageBg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Center(child: Text('📧', style: TextStyle(fontSize: 44))),
                  const SizedBox(height: 12),
                  Text(context.t('verify_email_title'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: c.textPrimary)),
                  const SizedBox(height: 6),
                  Text(
                    context.t('verify_email_desc', {'email': _pendingEmail ?? ''}),
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, color: c.textSecondary),
                  ),
                  const SizedBox(height: 24),
                  AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextField(
                          controller: _code,
                          keyboardType: TextInputType.number,
                          maxLength: 6,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 8,
                              color: c.textPrimary),
                          decoration: InputDecoration(
                            counterText: '',
                            hintText: '000000',
                            hintStyle: TextStyle(color: c.textFaint),
                            filled: true,
                            fillColor: c.pageBg,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 12),
                          Text(_error!,
                              style: const TextStyle(
                                  color: Color(0xFFB3261E), fontSize: 13)),
                        ],
                        const SizedBox(height: 16),
                        SizedBox(
                          height: 50,
                          child: FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: c.accent,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14)),
                            ),
                            onPressed: _busy ? null : _verifyCode,
                            child: _busy
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2.5, color: Colors.white))
                                : Text(context.t('verify_confirm'),
                                    style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white)),
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextButton(
                          onPressed: _busy ? null : _resendCode,
                          child: Text(context.t('resend_code'),
                              style: TextStyle(color: c.accent)),
                        ),
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => setState(() {
                                    _verifying = false;
                                    _error = null;
                                    _code.clear();
                                  }),
                          child: Text(context.t('cancel'),
                              style: TextStyle(color: c.textSecondary)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGoogleSetupScreen(BuildContext context, ChColors c) {
    Widget seg(String label, _Mode m) {
      final sel = _googleSetupMode == m;
      return Expanded(
        child: GestureDetector(
          onTap: () => setState(() {
            _googleSetupMode = m;
            _error = null;
          }),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: sel ? c.card : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(label,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontWeight: sel ? FontWeight.w700 : FontWeight.w600,
                    color: sel ? c.textPrimary : c.textSecondary,
                    fontSize: 13.5)),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: c.pageBg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Center(child: Text('🏠', style: TextStyle(fontSize: 44))),
                  const SizedBox(height: 12),
                  Text(context.t('google_setup_title'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: c.textPrimary)),
                  const SizedBox(height: 6),
                  Text(_googleEmail ?? '',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 14, color: c.textSecondary)),
                  const SizedBox(height: 18),
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Theme.of(context).brightness == Brightness.light
                          ? const Color(0xFFEBEFEC)
                          : c.card,
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Row(children: [
                      seg(context.t('create'), _Mode.create),
                      seg(context.t('join'), _Mode.join),
                    ]),
                  ),
                  const SizedBox(height: 18),
                  AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_googleSetupMode == _Mode.join) ...[
                          _field(c, _token, context.t('family_code_hint'),
                              caps: true),
                          const SizedBox(height: 10),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: _busy ? null : _lookup,
                              child: Text(context.t('lookup_family'),
                                  style: TextStyle(color: c.accent)),
                            ),
                          ),
                          if (_lookedUpName != null) ...[
                            Text(context.t('who_are_you', {'name': _lookedUpName!}),
                                style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: c.textPrimary)),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: _lookupMembers.map((m) {
                                final id = m['id'].toString();
                                final sel = id == _selectedMemberId;
                                return GestureDetector(
                                  onTap: () =>
                                      setState(() => _selectedMemberId = id),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: sel ? c.accent : c.pageBg,
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: Text(
                                      '${m['emoji']} ${m['name']}',
                                      style: TextStyle(
                                          color: sel
                                              ? Colors.white
                                              : c.textPrimary,
                                          fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                            const SizedBox(height: 12),
                          ],
                        ] else ...[
                          _field(c, _displayName, context.t('your_name')),
                          const SizedBox(height: 10),
                          _field(c, _householdName, context.t('family_name')),
                          const SizedBox(height: 10),
                        ],
                        if (_error != null) ...[
                          const SizedBox(height: 8),
                          Text(_error!,
                              style: const TextStyle(
                                  color: Color(0xFFB3261E), fontSize: 13)),
                        ],
                        const SizedBox(height: 16),
                        SizedBox(
                          height: 50,
                          child: FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: c.accent,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14)),
                            ),
                            onPressed: _busy ? null : _completeGoogleSetup,
                            child: _busy
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2.5, color: Colors.white))
                                : Text(context.t('join_cleanhabit'),
                                    style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white)),
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => setState(() {
                                    _googleNeedsSetup = false;
                                    _googleIdToken = null;
                                    _error = null;
                                  }),
                          child: Text(context.t('cancel'),
                              style: TextStyle(color: c.textSecondary)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _segmented(ChColors c) {
    Widget seg(String label, _Mode m) {
      final sel = _mode == m;
      return Expanded(
        child: GestureDetector(
          onTap: () => setState(() {
            _mode = m;
            _error = null;
          }),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: sel ? c.card : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              boxShadow: sel && Theme.of(context).brightness == Brightness.light
                  ? [
                      const BoxShadow(
                          color: Color(0x0F142819),
                          blurRadius: 2,
                          offset: Offset(0, 1))
                    ]
                  : null,
            ),
            child: Text(label,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontWeight: sel ? FontWeight.w700 : FontWeight.w600,
                    color: sel ? c.textPrimary : c.textSecondary,
                    fontSize: 13.5)),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.light
            ? const Color(0xFFEBEFEC)
            : c.card,
        borderRadius: BorderRadius.circular(13),
      ),
      child: Row(children: [
        seg(context.t('login'), _Mode.login),
        seg(context.t('create'), _Mode.create),
        seg(context.t('join'), _Mode.join),
      ]),
    );
  }

  void _showForgotPassword(BuildContext context, ChColors c) {
    final emailCtrl = TextEditingController();
    final codeCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    int step = 0;
    String? err;
    bool obscureNewPass = true;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => PopScope(
          canPop: false,
          child: AlertDialog(
          backgroundColor: c.card,
          title: Text('🔐 ${context.t('forgot_password')}',
              style: TextStyle(color: c.textPrimary, fontSize: 17)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (step == 0) ...[
                Text(context.t('forgot_desc'),
                    style:
                        TextStyle(fontSize: 13, color: c.textSecondary)),
                const SizedBox(height: 12),
                _field(c, emailCtrl, context.t('email'),
                    keyboardType: TextInputType.emailAddress),
              ] else ...[
                Text(context.t('enter_code_desc'),
                    style:
                        TextStyle(fontSize: 13, color: c.textSecondary)),
                const SizedBox(height: 6),
                Text(context.t('check_spam'),
                    style: TextStyle(fontSize: 12, color: c.textFaint)),
                const SizedBox(height: 12),
                TextField(
                  controller: codeCtrl,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 8,
                      color: c.textPrimary),
                  decoration: InputDecoration(
                    hintText: '000000',
                    hintStyle: TextStyle(color: c.textFaint),
                    counterText: '',
                    filled: true,
                    fillColor: c.pageBg,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 10),
                _field(c, passCtrl, context.t('new_password'),
                    obscure: obscureNewPass,
                    suffixIcon: _passwordToggle(c, obscureNewPass,
                        () => setS(() => obscureNewPass = !obscureNewPass))),
              ],
              if (err != null) ...[
                const SizedBox(height: 8),
                Text(err!,
                    style: const TextStyle(
                        color: Color(0xFFB3261E), fontSize: 13)),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(context.t('cancel'),
                  style: TextStyle(color: c.textSecondary)),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: c.accent),
              onPressed: () async {
                final api = context.read<AppState>().api;
                if (step == 0) {
                  try {
                    await api.forgotPassword(emailCtrl.text.trim());
                    setS(() { step = 1; err = null; });
                  } on ApiException catch (e) {
                    setS(() => err = e.message);
                  } catch (e) {
                    setS(() => err = e.toString());
                  }
                } else {
                  try {
                    await api.resetPassword(
                      emailCtrl.text.trim(),
                      codeCtrl.text.trim(),
                      passCtrl.text,
                    );
                    if (ctx.mounted) Navigator.pop(ctx);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(context.t('pass_changed')),
                        backgroundColor: Colors.green,
                      ));
                    }
                  } catch (e) {
                    setS(() => err = e.toString());
                  }
                }
              },
              child: Text(
                step == 0 ? context.t('send_code') : context.t('save'),
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
        ),
      ),
    );
  }

  Widget _field(ChColors c, TextEditingController ctrl, String hint,
      {bool obscure = false, bool caps = false,
      TextInputType? keyboardType, Widget? suffixIcon}) {
    return TextField(
      controller: ctrl,
      obscureText: obscure,
      keyboardType: keyboardType,
      textCapitalization:
          caps ? TextCapitalization.characters : TextCapitalization.none,
      style: TextStyle(color: c.textPrimary),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: c.textFaint),
        filled: true,
        fillColor: c.pageBg,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: c.accent, width: 1.5),
        ),
        suffixIcon: suffixIcon,
      ),
    );
  }

  Widget _passwordToggle(ChColors c, bool obscured, VoidCallback onTap) {
    return IconButton(
      icon: Icon(obscured ? Icons.visibility_off : Icons.visibility,
          color: c.textFaint, size: 20),
      onPressed: onTap,
    );
  }
}
