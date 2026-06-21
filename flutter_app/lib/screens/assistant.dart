import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:permission_handler/permission_handler.dart';

import '../api.dart';
import '../l10n.dart';
import '../state.dart';
import '../theme.dart';
import '../widgets.dart';

const Map<String, String> _sttLocale = {
  'en': 'en_US',
  'pl': 'pl_PL',
  'uk': 'uk_UA',
};
const Map<String, String> _ttsLocale = {
  'en': 'en-US',
  'pl': 'pl-PL',
  'uk': 'uk-UA',
};

class AssistantScreen extends StatefulWidget {
  const AssistantScreen({super.key});
  @override
  State<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends State<AssistantScreen> {
  final SpeechToText _speech = SpeechToText();
  final FlutterTts _tts = FlutterTts();
  final TextEditingController _text = TextEditingController();

  late String _voiceLang;
  bool _listening = false;
  bool _busy = false;
  String _heard = '';
  String _reply = '';
  String? _replyKind; // 'ok' | 'warn'

  @override
  void initState() {
    super.initState();
    _voiceLang = context.read<AppState>().lang;
  }

  @override
  void dispose() {
    _speech.cancel();
    _tts.stop();
    _text.dispose();
    super.dispose();
  }

  Future<void> _toggleListen() async {
    if (_listening) {
      await _speech.stop();
      setState(() => _listening = false);
      return;
    }
    // Capture localized strings before any async gap.
    final micDenied = context.t('mic_denied');
    final micUnavailable = context.t('mic_unavailable');

    try {
      final granted = await Permission.microphone.request();
      if (!granted.isGranted) {
        _setReply(micDenied, 'warn');
        return;
      }
      final ok = await _speech.initialize(
        onStatus: (s) {
          if (s == 'done' || s == 'notListening') {
            if (mounted) setState(() => _listening = false);
          }
        },
        onError: (_) {
          if (mounted) setState(() => _listening = false);
        },
      );
      if (!ok) {
        _setReply(micUnavailable, 'warn');
        return;
      }
      setState(() {
        _listening = true;
        _heard = '';
        _reply = '';
      });
      await _speech.listen(
        listenOptions: SpeechListenOptions(
            partialResults: true, localeId: _sttLocale[_voiceLang]),
        onResult: (r) {
          setState(() => _heard = r.recognizedWords);
          if (r.finalResult && r.recognizedWords.trim().isNotEmpty) {
            _send(r.recognizedWords);
          }
        },
      );
    } catch (_) {
      if (mounted) {
        setState(() => _listening = false);
        _setReply(micUnavailable, 'warn');
      }
    }
  }

  Future<void> _send(String transcript) async {
    final t = transcript.trim();
    if (t.isEmpty) return;
    final netErr = context.t('net_error');
    final app = context.read<AppState>();
    final msgs = {
      'add_task': context.t('voice_added'),
      'complete_task': context.t('voice_completed'),
      'unknown': context.t('didnt_understand'),
    };
    setState(() {
      _busy = true;
      _heard = t;
      _listening = false;
    });
    try {
      final res = await app.voice(t);
      final action = res['action']?.toString() ?? 'unknown';
      final msg = msgs[action] ?? msgs['unknown']!;
      _setReply(msg, action == 'unknown' ? 'warn' : 'ok');
      await _speak(msg);
    } on ApiException catch (e) {
      _setReply(e.message, 'warn');
    } catch (_) {
      _setReply(netErr, 'warn');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _setReply(String msg, String kind) {
    if (!mounted) return;
    setState(() {
      _reply = msg;
      _replyKind = kind;
    });
  }

  Future<void> _speak(String text) async {
    try {
      await _tts.setLanguage(_ttsLocale[_voiceLang] ?? 'en-US');
      await _tts.speak(text);
    } catch (_) {/* TTS optional */}
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ch;
    return Scaffold(
      backgroundColor: c.pageBg,
      appBar: chAppBar(context, context.t('assistant_title')),
      body: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          child: Column(
            children: [
              // Language picker
              Segmented(
                labels: kLangs.map((l) => kLangNames[l]!).toList(),
                index: kLangs.indexOf(_voiceLang).clamp(0, kLangs.length - 1),
                onChanged: (i) => setState(() => _voiceLang = kLangs[i]),
              ),
              const SizedBox(height: 24),

              Expanded(
                child: Center(
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Mic button
                        GestureDetector(
                          onTap: _busy ? null : _toggleListen,
                          child: Container(
                            width: 120,
                            height: 120,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _listening ? c.accent : c.card,
                              boxShadow: [
                                BoxShadow(
                                  color: c.accent.withValues(
                                      alpha: _listening ? 0.45 : 0.18),
                                  blurRadius: _listening ? 28 : 14,
                                  spreadRadius: _listening ? 4 : 0,
                                )
                              ],
                            ),
                            child: Icon(
                              _listening ? Icons.mic : Icons.mic_none_rounded,
                              size: 52,
                              color: _listening ? Colors.white : c.accent,
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),
                        Text(
                          _listening
                              ? context.t('listening')
                              : context.t('tap_to_speak'),
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: c.textPrimary),
                        ),
                        const SizedBox(height: 8),
                        if (_heard.isEmpty && _reply.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Text(context.t('assistant_hint'),
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    fontSize: 13, color: c.textSecondary)),
                          ),
                        if (_heard.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          _bubble(c, '“$_heard”', c.card, c.textPrimary),
                        ],
                        if (_busy) ...[
                          const SizedBox(height: 16),
                          const Loader(),
                        ],
                        if (_reply.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          _bubble(
                            c,
                            _reply,
                            _replyKind == 'ok' ? c.successPillBg : c.card,
                            _replyKind == 'ok' ? c.successPillText : c.textPrimary,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),

              // Text fallback
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _text,
                      style: TextStyle(color: c.textPrimary),
                      textInputAction: TextInputAction.send,
                      onSubmitted: (v) {
                        _send(v);
                        _text.clear();
                      },
                      decoration: InputDecoration(
                        hintText: context.t('type_command'),
                        hintStyle: TextStyle(color: c.textFaint),
                        filled: true,
                        fillColor: c.card,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 14),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  GestureDetector(
                    onTap: _busy
                        ? null
                        : () {
                            _send(_text.text);
                            _text.clear();
                          },
                    child: Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                          color: c.accent,
                          borderRadius: BorderRadius.circular(14)),
                      child: const Icon(Icons.send, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bubble(ChColors c, String text, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(16)),
      child: Text(text,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: fg)),
    );
  }
}
