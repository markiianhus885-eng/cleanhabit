import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n.dart';
import '../theme.dart';
import '../widgets.dart';

class McpSetupScreen extends StatefulWidget {
  const McpSetupScreen({super.key});
  @override
  State<McpSetupScreen> createState() => _McpSetupScreenState();
}

class _McpSetupScreenState extends State<McpSetupScreen> {
  final _email = TextEditingController();

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  String get _config {
    final email = _email.text.trim().isEmpty ? 'your_email' : _email.text.trim();
    return '''{
  "mcpServers": {
    "cleanhabit": {
      "command": "python",
      "args": ["mcp_server.py"],
      "env": {
        "CLEANHABIT_URL": "https://cleanhabit.myroapp.org",
        "CLEANHABIT_EMAIL": "$email",
        "CLEANHABIT_PASSWORD": "your_password"
      }
    }
  }
}''';
  }

  void _copy() {
    Clipboard.setData(ClipboardData(text: _config));
    showSnack(context, context.t('mcp_copied'));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ch;
    return Scaffold(
      backgroundColor: c.pageBg,
      appBar: chAppBar(context, context.t('mcp_title')),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
          children: [
            Text(context.t('mcp_desc'),
                style: TextStyle(fontSize: 13.5, color: c.textSecondary, height: 1.4)),
            const SizedBox(height: 20),
            Text(context.t('mcp_email_label'),
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: c.textFaint)),
            const SizedBox(height: 6),
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              style: TextStyle(color: c.textPrimary),
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: context.t('mcp_email_ph'),
                hintStyle: TextStyle(color: c.textFaint),
                filled: true,
                fillColor: c.card,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 20),
            Text(context.t('mcp_config_label'),
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: c.textFaint)),
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: c.card,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: c.divider),
              ),
              child: SelectableText(
                _config,
                style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    height: 1.5,
                    color: c.textPrimary),
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _copy,
                icon: const Icon(Icons.copy_rounded, size: 18),
                label: Text(context.t('mcp_copy_btn')),
              ),
            ),
            const SizedBox(height: 20),
            Text(context.t('mcp_hint'),
                style: TextStyle(fontSize: 12, color: c.textFaint, height: 1.4)),
          ],
        ),
      ),
    );
  }
}
