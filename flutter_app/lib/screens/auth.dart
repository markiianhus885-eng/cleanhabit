import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api.dart';
import '../l10n.dart';
import '../state.dart';
import '../theme.dart';
import '../widgets.dart';

enum _Mode { login, create, join }

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  _Mode _mode = _Mode.login;
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _displayName = TextEditingController();
  final _householdName = TextEditingController();
  final _token = TextEditingController();

  bool _busy = false;
  String? _error;

  // For join: looked-up members to claim
  List<Map<String, dynamic>> _lookupMembers = [];
  String? _selectedMemberId;
  String? _lookedUpName;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    _displayName.dispose();
    _householdName.dispose();
    _token.dispose();
    super.dispose();
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

  Future<void> _submit() async {
    final app = context.read<AppState>();
    final username = _username.text.trim();
    final password = _password.text;
    if (username.isEmpty || password.isEmpty) {
      setState(() => _error = context.t('enter_user_pass'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      switch (_mode) {
        case _Mode.login:
          await app.login(username, password);
        case _Mode.create:
          await app.register({
            'username': username,
            'password': password,
            'action': 'create',
            'display_name': _displayName.text.trim(),
            'household_name': _householdName.text.trim().isEmpty
                ? 'My Family'
                : _householdName.text.trim(),
          });
        case _Mode.join:
          if (_selectedMemberId == null) {
            setState(() => _error = context.t('pick_who'));
            return;
          }
          await app.register({
            'username': username,
            'password': password,
            'action': 'join',
            'token': _token.text.trim().toUpperCase(),
            'member_id': _selectedMemberId,
          });
      }
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
                        color: c.accent,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Icon(Icons.cleaning_services_rounded,
                          color: Colors.white, size: 32),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text('CleanHouse',
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
                        _field(c, _username, context.t('username')),
                        const SizedBox(height: 10),
                        _field(c, _password, context.t('password'),
                            obscure: true),
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

  Widget _field(ChColors c, TextEditingController ctrl, String hint,
      {bool obscure = false, bool caps = false}) {
    return TextField(
      controller: ctrl,
      obscureText: obscure,
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
      ),
    );
  }
}
