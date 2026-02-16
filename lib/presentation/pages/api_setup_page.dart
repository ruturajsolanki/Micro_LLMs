import 'package:flutter/material.dart';

import '../../core/di/injection.dart';
import '../../data/services/cloud_api_key_storage.dart';
import '../../data/services/groq_api_service.dart';
import '../../data/services/gemini_api_service.dart';
import '../theme/ui_tokens.dart';

/// API key setup page for V2 cloud mode.
///
/// Shows when the built-in key fails or when the user navigates here
/// from settings. The user can enter their own Groq / Gemini key.
class ApiSetupPage extends StatefulWidget {
  const ApiSetupPage({super.key});

  @override
  State<ApiSetupPage> createState() => _ApiSetupPageState();
}

class _ApiSetupPageState extends State<ApiSetupPage> {
  final _groqController = TextEditingController();
  final _geminiController = TextEditingController();
  bool _validating = false;
  String? _groqStatus;
  String? _geminiStatus;
  bool _usingDefault = true;

  CloudApiKeyStorage get _keyStorage => sl<CloudApiKeyStorage>();
  GroqApiService get _groqApi => sl<GroqApiService>();
  GeminiApiService get _geminiApi => sl<GeminiApiService>();

  @override
  void initState() {
    super.initState();
    _loadExistingKeys();
  }

  Future<void> _loadExistingKeys() async {
    // Only load user-set keys (not the built-in default)
    final groq = await _keyStorage.getUserGroqApiKey();
    final gemini = await _keyStorage.getGeminiApiKey();
    _usingDefault = await _keyStorage.isUsingDefaultGroqKey();

    if (groq != null && groq.isNotEmpty) {
      _groqController.text = groq;
    }
    if (gemini != null && gemini.isNotEmpty) {
      _geminiController.text = gemini;
    }
    if (mounted) setState(() {});
  }

  Future<void> _validateAndSave() async {
    final groqKey = _groqController.text.trim();
    final geminiKey = _geminiController.text.trim();

    if (groqKey.isEmpty && geminiKey.isEmpty) {
      setState(() {
        _groqStatus = 'Please enter at least one API key.';
      });
      return;
    }

    setState(() {
      _validating = true;
      _groqStatus = null;
      _geminiStatus = null;
    });

    bool anySaved = false;

    // Validate Groq key
    if (groqKey.isNotEmpty) {
      try {
        final valid = await _groqApi.validateApiKey(groqKey);
        if (valid) {
          await _keyStorage.setGroqApiKey(groqKey);
          _groqStatus = 'Groq API key validated and saved.';
          anySaved = true;
        } else {
          _groqStatus = 'Invalid Groq API key.';
        }
      } catch (e) {
        _groqStatus = 'Groq validation failed: $e';
      }
    }

    // Validate Gemini key
    if (geminiKey.isNotEmpty) {
      try {
        final valid = await _geminiApi.validateApiKey(geminiKey);
        if (valid) {
          await _keyStorage.setGeminiApiKey(geminiKey);
          _geminiStatus = 'Gemini API key validated and saved.';
          anySaved = true;
        } else {
          _geminiStatus = 'Invalid Gemini API key.';
        }
      } catch (e) {
        _geminiStatus = 'Gemini validation failed: $e';
      }
    }

    if (!mounted) return;
    setState(() => _validating = false);

    if (anySaved && mounted) {
      // Pop back so the calling page (V2Home) can re-check connectivity
      Navigator.of(context).pop();
    }
  }

  @override
  void dispose() {
    _groqController.dispose();
    _geminiController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('API Setup'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: UiTokens.pagePadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 16),

              // Info about default key
              if (_usingDefault) ...[
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.orange.withOpacity(0.2),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.info_outline,
                          size: 20, color: Colors.orange),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'A built-in API key is included but may hit rate limits. '
                          'Enter your own free Groq key for unlimited use.\n\n'
                          'Get one at console.groq.com',
                          style: tt.bodySmall?.copyWith(
                            color: cs.onSurface.withOpacity(0.7),
                            height: 1.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
              ],

              // Header
              Text(
                'Enter Your API Key',
                style:
                    tt.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: UiTokens.s8),
              Text(
                'Your key will be stored securely on-device.',
                style: tt.bodyMedium?.copyWith(
                  color: cs.onSurface.withOpacity(0.6),
                ),
              ),

              const SizedBox(height: 28),

              // Groq section
              _buildKeySection(
                icon: Icons.bolt_rounded,
                title: 'Groq API Key',
                subtitle:
                    'Ultra-fast inference (Llama 3.3 70B + Whisper STT)',
                controller: _groqController,
                hint: 'gsk_...',
                status: _groqStatus,
                accentColor: cs.primary,
              ),

              const SizedBox(height: 24),

              // Gemini section
              _buildKeySection(
                icon: Icons.auto_awesome_rounded,
                title: 'Gemini API Key (optional)',
                subtitle: 'Google Gemini 2.0 Flash for evaluation',
                controller: _geminiController,
                hint: 'AIza...',
                status: _geminiStatus,
                accentColor: Colors.blue,
              ),

              const SizedBox(height: 36),

              // Save button
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton.icon(
                  onPressed: _validating ? null : _validateAndSave,
                  icon: _validating
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child:
                              CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check_rounded),
                  label: Text(
                      _validating ? 'Validating...' : 'Save & Continue'),
                ),
              ),

              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildKeySection({
    required IconData icon,
    required String title,
    required String subtitle,
    required TextEditingController controller,
    required String hint,
    required String? status,
    required Color accentColor,
  }) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(UiTokens.s16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: accentColor, size: 24),
                const SizedBox(width: UiTokens.s12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: tt.titleSmall),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: tt.bodySmall?.copyWith(
                          color: cs.onSurface.withOpacity(0.6),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: UiTokens.s12),
            TextField(
              controller: controller,
              obscureText: true,
              enableSuggestions: false,
              autocorrect: false,
              decoration: InputDecoration(
                hintText: hint,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(UiTokens.r12),
                ),
              ),
            ),
            if (status != null) ...[
              const SizedBox(height: UiTokens.s8),
              Text(
                status,
                style: tt.bodySmall?.copyWith(
                  color: status.contains('validated')
                      ? Colors.green
                      : cs.error,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
