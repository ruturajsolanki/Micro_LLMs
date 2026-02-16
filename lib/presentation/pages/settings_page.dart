import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../core/constants/app_constants.dart';
import '../../core/di/injection.dart';
import '../../domain/entities/app_settings.dart';
import '../../domain/entities/speech_to_text_engine.dart';
import '../../domain/entities/text_to_speech_engine.dart';
import '../../domain/services/stt_model_catalog.dart';
import '../../domain/services/stt_model_path_resolver.dart';
import '../../data/services/model_download_service.dart';
import '../../data/services/stt_model_download_service.dart';
import '../../domain/repositories/voice_repository.dart';
import '../blocs/model/model_bloc.dart';
import '../blocs/settings/settings_bloc.dart';
import '../theme/ui_tokens.dart';

/// Settings page for configuring app behavior.
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: BlocBuilder<SettingsBloc, SettingsState>(
        builder: (context, state) {
          if (!state.isLoaded) {
            return const Center(child: CircularProgressIndicator());
          }
          
          return ListView(
            padding: UiTokens.pagePadding,
            children: [
              _buildSection(
                context: context,
                title: 'Languages',
                children: [
                  _buildLanguageTile(
                    context: context,
                    title: 'Source Language',
                    subtitle: 'Your input language',
                    value: state.settings.sourceLanguage,
                    onChanged: (value) {
                      context.read<SettingsBloc>().add(
                        SourceLanguageChanged(language: value),
                      );
                    },
                  ),
                  _buildLanguageTile(
                    context: context,
                    title: 'Target Language',
                    subtitle: 'Translation language',
                    value: state.settings.targetLanguage,
                    onChanged: (value) {
                      context.read<SettingsBloc>().add(
                        TargetLanguageChanged(language: value),
                      );
                    },
                  ),
                ],
              ),
              
              _buildSection(
                context: context,
                title: 'Voice',
                children: [
                  SwitchListTile.adaptive(
                    title: const Text('Voice Input'),
                    subtitle: const Text('Enable speech-to-text'),
                    value: state.settings.voiceInputEnabled,
                    onChanged: (_) {
                      context.read<SettingsBloc>().add(const VoiceInputToggled());
                    },
                  ),
                  ListTile(
                    title: const Text('Speech-to-Text Engine'),
                    subtitle: const Text('Choose offline engine for voice input'),
                    trailing: DropdownButton<SpeechToTextEngine>(
                      value: state.settings.speechToTextEngine,
                      underline: const SizedBox.shrink(),
                      items: SpeechToTextEngine.values
                          .map((e) => DropdownMenuItem(
                                value: e,
                                child: Text(e.displayName),
                              ))
                          .toList(),
                      onChanged: (engine) {
                        if (engine != null) {
                          context.read<SettingsBloc>().add(
                                SpeechToTextEngineChanged(engine: engine),
                              );
                        }
                      },
                    ),
                  ),
                  AnimatedSize(
                    duration: UiTokens.durMed,
                    curve: UiTokens.curveStandard,
                    child: state.settings.speechToTextEngine ==
                            SpeechToTextEngine.androidSpeechRecognizer
                        ? SwitchListTile.adaptive(
                            title: const Text('Offline-only Speech-to-Text'),
                            subtitle: const Text(
                              'Never uses the internet. Requires offline speech pack installed on your device.',
                            ),
                            value: state.settings.voiceSttOfflineOnly,
                            onChanged: (_) {
                              context
                                  .read<SettingsBloc>()
                                  .add(const VoiceSttOfflineOnlyToggled());
                            },
                          )
                        : const SizedBox.shrink(),
                  ),
                  AnimatedSize(
                    duration: UiTokens.durMed,
                    curve: UiTokens.curveStandard,
                    child: state.settings.speechToTextEngine ==
                            SpeechToTextEngine.whisperCpp
                        ? Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ListTile(
                                title: const Text('Whisper Model'),
                                subtitle: const Text(
                                  'Select the offline Whisper model. Download below.',
                                ),
                                trailing: DropdownButton<String>(
                                  value: state.settings.whisperModelId,
                                  underline: const SizedBox.shrink(),
                                  items: const [
                                    DropdownMenuItem(
                                      value: 'base',
                                      child: Text('Base (faster)'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'small',
                                      child: Text('Small (better accuracy)'),
                                    ),
                                  ],
                                  onChanged: (id) {
                                    if (id != null) {
                                      context
                                          .read<SettingsBloc>()
                                          .add(WhisperModelChanged(modelId: id));
                                    }
                                  },
                                ),
                              ),
                              _WhisperModelManagerTile(
                                modelId: state.settings.whisperModelId,
                                threads: state.settings.inferenceThreads,
                              ),
                            ],
                          )
                        : const SizedBox.shrink(),
                  ),
                  SwitchListTile.adaptive(
                    title: const Text('Voice Output'),
                    subtitle: const Text('Enable text-to-speech'),
                    value: state.settings.voiceOutputEnabled,
                    onChanged: (_) {
                      context.read<SettingsBloc>().add(const VoiceOutputToggled());
                    },
                  ),
                  ListTile(
                    title: const Text('Text-to-Speech Engine'),
                    subtitle: const Text('Choose voice output engine'),
                    trailing: DropdownButton<TextToSpeechEngine>(
                      value: state.settings.textToSpeechEngine,
                      underline: const SizedBox.shrink(),
                      items: TextToSpeechEngine.values
                          .map((e) => DropdownMenuItem(
                                value: e,
                                child: Text(e.displayName),
                              ))
                          .toList(),
                      onChanged: (engine) {
                        if (engine != null) {
                          context
                              .read<SettingsBloc>()
                              .add(TextToSpeechEngineChanged(engine: engine));
                        }
                      },
                    ),
                  ),
                  AnimatedSize(
                    duration: UiTokens.durMed,
                    curve: UiTokens.curveStandard,
                    child: state.settings.textToSpeechEngine ==
                            TextToSpeechEngine.elevenLabs
                        ? _ElevenLabsConfigTile(
                            voiceId: state.settings.elevenLabsVoiceId,
                            language: state.settings.targetLanguage,
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
              
              _buildSection(
                context: context,
                title: 'Model',
                children: [
                  _buildTemperatureSlider(context, state.settings),
                  _buildLastGenerationStats(context),
                  _buildModelSelector(context, state.settings),
                  _buildModelInfo(context),
                ],
              ),
              
              _buildSection(
                context: context,
                title: 'Appearance',
                children: [
                  _buildThemeTile(context, state.settings),
                ],
              ),
              
              _buildSection(
                context: context,
                title: 'Tools',
                children: [
                  ListTile(
                    title: const Text('Voice Benchmark'),
                    subtitle: const Text('Record speech & evaluate summarization'),
                    leading: const Icon(Icons.speed_outlined),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.pushNamed(context, '/benchmark'),
                  ),
                  ListTile(
                    title: const Text('System Prompts'),
                    subtitle: const Text('Edit evaluation, safety & injection prompts'),
                    leading: const Icon(Icons.tune_rounded),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.pushNamed(context, '/system-prompts'),
                  ),
                  ListTile(
                    title: const Text('Device Compatibility'),
                    subtitle: const Text('Check which models work on your device'),
                    leading: const Icon(Icons.memory_outlined),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.pushNamed(context, '/device-compatibility'),
                  ),
                ],
              ),
              
              _buildSection(
                context: context,
                title: 'Advanced',
                children: [
                  ListTile(
                    title: const Text('Reset to Defaults'),
                    leading: const Icon(Icons.restore),
                    onTap: () => _showResetConfirmation(context),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
  
  Widget _buildSection({
    required BuildContext context,
    required String title,
    required List<Widget> children,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: UiTokens.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(
              left: UiTokens.s4,
              right: UiTokens.s4,
              bottom: UiTokens.s8,
              top: UiTokens.s8,
            ),
            child: Text(
              title.toUpperCase(),
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: cs.primary,
                    letterSpacing: 1.0,
                  ),
            ),
          ),
          Card(
            margin: EdgeInsets.zero,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(UiTokens.r16),
              child: Column(
                children: [
                  for (int i = 0; i < children.length; i++) ...[
                    children[i],
                    if (i != children.length - 1)
                      Divider(height: 1, color: cs.onSurface.withOpacity(0.06)),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildLanguageTile({
    required BuildContext context,
    required String title,
    required String subtitle,
    required String value,
    required void Function(String) onChanged,
  }) {
    return ListTile(
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: DropdownButton<String>(
        value: value,
        underline: const SizedBox.shrink(),
        items: LanguageConstants.supportedLanguages.entries
            .map((e) => DropdownMenuItem(
                  value: e.key,
                  child: Text(e.value),
                ))
            .toList(),
        onChanged: (newValue) {
          if (newValue != null) {
            onChanged(newValue);
          }
        },
      ),
    );
  }
  
  Widget _buildTemperatureSlider(BuildContext context, AppSettings settings) {
    return ListTile(
      title: const Text('Temperature'),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Controls randomness: ${settings.temperature.toStringAsFixed(1)}'),
          Slider(
            value: settings.temperature,
            min: 0.0,
            max: 2.0,
            divisions: 20,
            label: settings.temperature.toStringAsFixed(1),
            onChanged: (value) {
              context.read<SettingsBloc>().add(
                TemperatureChanged(temperature: value),
              );
            },
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Focused',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                ),
              ),
              Text(
                'Creative',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
  
  Widget _buildModelInfo(BuildContext context) {
    return BlocBuilder<ModelBloc, ModelState>(
      builder: (context, state) {
        if (state.modelInfo == null) {
          return const ListTile(
            title: Text('Model'),
            subtitle: Text('No model loaded'),
          );
        }
        
        final info = state.modelInfo!;
        return ListTile(
          title: const Text('Model'),
          subtitle: Text(
            '${info.parameterCount} • ${info.quantization}\n'
            'Context: ${info.contextSize} tokens\n'
            'Size: ${info.sizeFormatted}',
          ),
          isThreeLine: true,
          trailing: state.isReady
              ? const Icon(Icons.check_circle, color: Colors.green)
              : const Icon(Icons.error_outline, color: Colors.orange),
        );
      },
    );
  }

  Widget _buildLastGenerationStats(BuildContext context) {
    // Stored by ChatBloc into Hive settings box.
    return FutureBuilder<List<dynamic>>(
      future: _readLastGenStats(),
      builder: (context, snapshot) {
        final tokens = snapshot.data?[0] as int? ?? 0;
        final ms = snapshot.data?[1] as int? ?? 0;
        final tps = (ms > 0) ? (tokens / (ms / 1000.0)) : 0.0;

        return ListTile(
          title: const Text('Last response'),
          subtitle: ms > 0
              ? Text('$tokens tokens • ${ms}ms • ${tps.toStringAsFixed(1)} t/s')
              : const Text('No generation stats yet'),
          leading: const Icon(Icons.insights),
        );
      },
    );
  }

  Future<List<dynamic>> _readLastGenStats() async {
    // Read directly from Hive box via SettingsBloc state is not available here.
    // We store it in the settings box using platform-independent Hive.
    // ignore: invalid_use_of_protected_member
    final box = await Hive.openBox<dynamic>('settings');
    final tokens = box.get('lastGenTokens') as int?;
    final ms = box.get('lastGenDurationMs') as int?;
    return [tokens ?? 0, ms ?? 0];
  }

  Widget _buildModelSelector(BuildContext context, AppSettings settings) {
    return FutureBuilder<List<DownloadedModel>>(
      future: ModelDownloadService().getDownloadedModels(),
      builder: (context, snapshot) {
        final models = snapshot.data ?? const <DownloadedModel>[];

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const ListTile(
            title: Text('Active model'),
            subtitle: Text('Loading downloaded models...'),
          );
        }

        if (models.isEmpty) {
          return const ListTile(
            title: Text('Active model'),
            subtitle: Text('No downloaded models found'),
          );
        }

        final items = <DropdownMenuItem<String?>>[
          const DropdownMenuItem<String?>(
            value: null,
            child: Text('Default model'),
          ),
          ...models.map((m) => DropdownMenuItem<String?>(
                value: m.filePath,
                child: Text(m.displayName),
              )),
        ];

        return ListTile(
          title: const Text('Active model'),
          subtitle: Text(
            settings.selectedModelPath == null
                ? 'Default model'
                : (models.firstWhere(
                      (m) => m.filePath == settings.selectedModelPath,
                      orElse: () => models.first,
                    ).displayName),
          ),
          trailing: DropdownButton<String?>(
            value: settings.selectedModelPath,
            underline: const SizedBox.shrink(),
            items: items,
            onChanged: (value) {
              context.read<SettingsBloc>().add(
                    SelectedModelChanged(modelPath: value),
                  );

              // Reload model immediately if one is already loaded/ready
              final threads = settings.inferenceThreads;
              final ctx = settings.contextWindowSize;

              context.read<ModelBloc>().add(const ModelUnloadRequested());
              if (value != null) {
                context.read<ModelBloc>().add(
                      ModelLoadFromPathRequested(
                        modelPath: value,
                        contextSize: ctx,
                        threads: threads,
                      ),
                    );
              } else {
                context.read<ModelBloc>().add(
                      ModelLoadRequested(
                        contextSize: ctx,
                        threads: threads,
                      ),
                    );
              }
            },
          ),
        );
      },
    );
  }
  
  Widget _buildThemeTile(BuildContext context, AppSettings settings) {
    return ListTile(
      title: const Text('Theme'),
      trailing: SegmentedButton<ThemePreference>(
        segments: const [
          ButtonSegment(
            value: ThemePreference.system,
            icon: Icon(Icons.brightness_auto),
          ),
          ButtonSegment(
            value: ThemePreference.light,
            icon: Icon(Icons.light_mode),
          ),
          ButtonSegment(
            value: ThemePreference.dark,
            icon: Icon(Icons.dark_mode),
          ),
        ],
        selected: {settings.themePreference},
        onSelectionChanged: (selected) {
          context.read<SettingsBloc>().add(
            ThemeChanged(theme: selected.first),
          );
        },
      ),
    );
  }
  
  void _showResetConfirmation(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset Settings'),
        content: const Text(
          'Are you sure you want to reset all settings to their defaults?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              context.read<SettingsBloc>().add(const SettingsResetRequested());
            },
            child: const Text('Reset'),
          ),
        ],
      ),
    );
  }
}

class _WhisperModelManagerTile extends StatefulWidget {
  final String modelId;
  final int threads;

  const _WhisperModelManagerTile({
    required this.modelId,
    required this.threads,
  });

  @override
  State<_WhisperModelManagerTile> createState() => _WhisperModelManagerTileState();
}

class _WhisperModelManagerTileState extends State<_WhisperModelManagerTile> {
  StreamSubscription? _sub;
  DownloadEvent? _lastEvent;
  String? _message;

  SttModelDownloadService get _downloadService => sl<SttModelDownloadService>();
  SttModelPathResolver get _pathResolver => sl<SttModelPathResolver>();
  VoiceRepository get _voiceRepo => sl<VoiceRepository>();

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _startDownload() async {
    await _sub?.cancel();
    setState(() {
      _lastEvent = null;
      _message = null;
    });

    _sub = _downloadService.downloadModel(widget.modelId).listen((e) {
      setState(() => _lastEvent = e);
    }, onError: (e) {
      setState(() => _message = e.toString());
    });
  }

  Future<void> _cancelDownload() async {
    _downloadService.cancelDownload();
    await _sub?.cancel();
    _sub = null;
  }

  Future<void> _loadIntoMemory() async {
    final path = await _pathResolver.resolveWhisperModelPath(widget.modelId);
    if (path == null) {
      setState(() => _message = 'Model not downloaded yet.');
      return;
    }

    final res = await _voiceRepo.loadWhisperModel(
      modelPath: path,
      threads: widget.threads,
    );

    res.fold(
      (f) => setState(() => _message = f.message),
      (_) => setState(() => _message = 'Whisper model loaded into memory.'),
    );
  }

  Future<void> _unloadFromMemory() async {
    await _voiceRepo.unloadWhisperModel();
    setState(() => _message = 'Whisper model unloaded.');
  }

  @override
  Widget build(BuildContext context) {
    final option = SttModelCatalog.findById(widget.modelId);

    return FutureBuilder<bool>(
      future: _downloadService.isModelDownloaded(widget.modelId),
      builder: (context, snapshot) {
        final downloaded = snapshot.data ?? false;
        final e = _lastEvent;

        final isDownloading = e is DownloadStarted || e is DownloadProgress;
        final progress = e is DownloadProgress ? e.progress : null;
        final subtitle = option == null
            ? 'Offline STT model'
            : '${option.name} • ${(option.sizeBytes / (1024 * 1024)).toStringAsFixed(0)} MB';

        return ListTile(
          title: const Text('Whisper model download'),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(subtitle),
              if (isDownloading && progress != null) ...[
                const SizedBox(height: 8),
                LinearProgressIndicator(value: progress),
                const SizedBox(height: 4),
                Text(
                  '${(progress * 100).toStringAsFixed(1)}%',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ] else if (downloaded) ...[
                const SizedBox(height: 4),
                Text(
                  'Downloaded',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ] else ...[
                const SizedBox(height: 4),
                Text(
                  'Not downloaded',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              if (_message != null) ...[
                const SizedBox(height: 6),
                Text(
                  _message!,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
          trailing: Wrap(
            spacing: 8,
            children: [
              if (!downloaded && !isDownloading)
                IconButton(
                  tooltip: 'Download',
                  icon: const Icon(Icons.download),
                  onPressed: _startDownload,
                ),
              if (isDownloading)
                IconButton(
                  tooltip: 'Cancel download',
                  icon: const Icon(Icons.close),
                  onPressed: _cancelDownload,
                ),
              if (downloaded)
                IconButton(
                  tooltip: 'Load into memory',
                  icon: const Icon(Icons.play_arrow),
                  onPressed: _loadIntoMemory,
                ),
              if (downloaded)
                IconButton(
                  tooltip: 'Unload from memory',
                  icon: const Icon(Icons.eject),
                  onPressed: _unloadFromMemory,
                ),
            ],
          ),
        );
      },
    );
  }
}

class _ElevenLabsConfigTile extends StatefulWidget {
  final String voiceId;
  final String language;

  const _ElevenLabsConfigTile({
    required this.voiceId,
    required this.language,
  });

  @override
  State<_ElevenLabsConfigTile> createState() => _ElevenLabsConfigTileState();
}

class _ElevenLabsConfigTileState extends State<_ElevenLabsConfigTile> {
  final _apiKeyController = TextEditingController();
  bool _savingKey = false;
  String? _status;

  VoiceRepository get _voiceRepo => sl<VoiceRepository>();

  @override
  void dispose() {
    _apiKeyController.dispose();
    super.dispose();
  }

  Future<void> _saveKey() async {
    final key = _apiKeyController.text.trim();
    if (key.isEmpty) {
      setState(() => _status = 'API key cannot be empty.');
      return;
    }

    setState(() {
      _savingKey = true;
      _status = null;
    });

    final res = await _voiceRepo.setElevenLabsApiKey(key);
    if (!mounted) return;

    res.fold(
      (f) => setState(() => _status = f.message),
      (_) => setState(() => _status = 'API key saved securely.'),
    );

    setState(() => _savingKey = false);
  }

  Future<void> _testVoice() async {
    setState(() => _status = null);

    final res = await _voiceRepo.synthesize(
      engine: TextToSpeechEngine.elevenLabs,
      text: 'Hello! This is ElevenLabs voice output.',
      language: widget.language,
      elevenLabsVoiceId: widget.voiceId,
    );

    if (!mounted) return;
    res.fold(
      (f) => setState(() => _status = f.message),
      (_) => setState(() => _status = 'Playing…'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(UiTokens.s16, 0, UiTokens.s16, UiTokens.s12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'ElevenLabs requires internet + an API key.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: cs.onSurface.withOpacity(0.65),
                ),
          ),
          const SizedBox(height: UiTokens.s8),
          TextField(
            controller: _apiKeyController,
            obscureText: true,
            enableSuggestions: false,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'ElevenLabs API key',
              hintText: 'Paste your xi-api-key here',
            ),
          ),
          const SizedBox(height: UiTokens.s8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _savingKey ? null : _saveKey,
                  child: Text(_savingKey ? 'Saving…' : 'Save API key'),
                ),
              ),
              const SizedBox(width: UiTokens.s12),
              Expanded(
                child: ElevatedButton(
                  onPressed: _testVoice,
                  child: const Text('Test voice'),
                ),
              ),
            ],
          ),
          const SizedBox(height: UiTokens.s8),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Voice ID: ${widget.voiceId}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: cs.onSurface.withOpacity(0.70),
                      ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              TextButton(
                onPressed: () async {
                  final controller = TextEditingController(text: widget.voiceId);
                  final newId = await showDialog<String>(
                    context: context,
                    builder: (context) {
                      return AlertDialog(
                        title: const Text('ElevenLabs Voice ID'),
                        content: TextField(
                          controller: controller,
                          decoration: const InputDecoration(
                            hintText: 'Enter a voice_id',
                          ),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Cancel'),
                          ),
                          ElevatedButton(
                            onPressed: () => Navigator.pop(
                              context,
                              controller.text.trim(),
                            ),
                            child: const Text('Save'),
                          ),
                        ],
                      );
                    },
                  );

                  if (!context.mounted) return;
                  if (newId != null && newId.isNotEmpty) {
                    context
                        .read<SettingsBloc>()
                        .add(ElevenLabsVoiceChanged(voiceId: newId));
                    setState(() => _status = 'Voice ID updated.');
                  }
                },
                child: const Text('Change'),
              ),
            ],
          ),
          if (_status != null) ...[
            const SizedBox(height: UiTokens.s4),
            Text(
              _status!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: cs.onSurface.withOpacity(0.70),
                  ),
            ),
          ],
        ],
      ),
    );
  }
}
