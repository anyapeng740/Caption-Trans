import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:file_picker/file_picker.dart';
import '../services/settings_service.dart';
import '../services/translation/translation_service.dart';
import '../blocs/transcription/transcription_bloc.dart';
import '../blocs/transcription/transcription_event.dart';
import '../blocs/transcription/transcription_state.dart';
import '../blocs/translation/translation_bloc.dart';
import '../blocs/translation/translation_event.dart';
import '../blocs/translation/translation_state.dart';
import '../core/constants.dart';
import 'package:caption_trans/l10n/app_localizations.dart';
import '../core/utils/srt_parser.dart';
import '../models/translation_config.dart';
import 'widgets/video_picker_card.dart';
import 'widgets/transcription_panel.dart';
import 'widgets/translation_panel.dart';
import 'widgets/subtitle_preview.dart';
import 'widgets/settings_dialog.dart';

/// Main application page with step-by-step workflow.
class HomePage extends StatefulWidget {
  final void Function(Locale) onLocaleChanged;
  final SettingsService settingsService;

  const HomePage({
    super.key,
    required this.onLocaleChanged,
    required this.settingsService,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String _selectedModel = AppConstants.defaultWhisperModel;
  String _targetLanguage = 'zh';
  String _apiKey = '';
  String _targetModel = 'gemini-2.0-flash';
  String _llmProvider = 'Gemini (Google)';
  String _llmBaseUrl =
      'https://generativelanguage.googleapis.com/v1beta/openai';
  bool _bilingual = true;
  int _batchSize = 25;
  List<String> _availableModels = [];
  bool _isLoadingModels = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  void _loadSettings() {
    setState(() {
      _apiKey = widget.settingsService.geminiApiKey;
      _targetModel = widget.settingsService.geminiModel;
      _llmProvider = widget.settingsService.llmProvider;
      _llmBaseUrl = widget.settingsService.llmBaseUrl;
      _targetLanguage = widget.settingsService.targetLanguage;
      _bilingual = widget.settingsService.bilingual;
      _batchSize = widget.settingsService.batchSize;
    });

    if (_apiKey.isNotEmpty) {
      _fetchModels();
    }
  }

  Future<void> _fetchModels() async {
    if (_apiKey.isEmpty) return;

    setState(() => _isLoadingModels = true);
    try {
      final service = TranslationService();
      final models = await service.listModels(
        TranslationConfig(
          providerId: _llmProvider,
          apiKey: _apiKey,
          baseUrl: _llmBaseUrl,
          sourceLanguage: 'en', // dummy
          targetLanguage: 'zh', // dummy
        ),
      );

      if (mounted) {
        setState(() {
          _availableModels = models;
          if (!_availableModels.contains(_targetModel)) {
            if (_availableModels.isNotEmpty) {
              _targetModel = _availableModels.first;
            }
          }
          _isLoadingModels = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _availableModels = [_targetModel];
          _isLoadingModels = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to fetch models. Check Base URL or API Key.'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      body: Column(
        children: [
          _buildAppBar(context, l10n),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 900),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Step 1: Video Selection
                      _buildSectionHeader(
                        context,
                        icon: Icons.video_library_rounded,
                        title: 'Step 1: ${l10n.stepSelectVideo}',
                        number: '1',
                      ),
                      const SizedBox(height: 12),
                      BlocBuilder<TranscriptionBloc, TranscriptionState>(
                        builder: (context, state) {
                          return VideoPickerCard(
                            selectedFileName: _getFileName(state),
                            onPickVideo: () => _pickVideo(context),
                            onClear: state is! TranscriptionInitial
                                ? () => context.read<TranscriptionBloc>().add(
                                    const ResetTranscription(),
                                  )
                                : null,
                          );
                        },
                      ),

                      const SizedBox(height: 32),

                      // Step 2: Transcription
                      _buildSectionHeader(
                        context,
                        icon: Icons.mic_rounded,
                        title: 'Step 2: ${l10n.stepExtractSubtitles}',
                        number: '2',
                      ),
                      const SizedBox(height: 12),
                      BlocBuilder<TranscriptionBloc, TranscriptionState>(
                        builder: (context, state) {
                          return TranscriptionPanel(
                            state: state,
                            selectedModel: _selectedModel,
                            onModelChanged: (model) =>
                                setState(() => _selectedModel = model),
                            onStartTranscription: () {
                              context.read<TranscriptionBloc>().add(
                                StartTranscription(modelName: _selectedModel),
                              );
                            },
                          );
                        },
                      ),

                      const SizedBox(height: 32),

                      // Step 3: Translation
                      _buildSectionHeader(
                        context,
                        icon: Icons.translate_rounded,
                        title: 'Step 3: ${l10n.stepTranslate}',
                        number: '3',
                      ),
                      const SizedBox(height: 12),
                      BlocConsumer<TranslationBloc, TranslationState>(
                        listener: (context, state) {
                          if (state is TranslationError) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(state.message),
                                backgroundColor: Colors.red.shade700,
                              ),
                            );
                          }
                        },
                        builder: (context, translationState) {
                          return BlocBuilder<
                            TranscriptionBloc,
                            TranscriptionState
                          >(
                            builder: (context, transcriptionState) {
                              return TranslationPanel(
                                transcriptionState: transcriptionState,
                                translationState: translationState,
                                llmProvider: _llmProvider,
                                llmBaseUrl: _llmBaseUrl,
                                onLlmProviderChanged: (provider) {
                                  setState(() {
                                    _llmProvider = provider;
                                    _targetModel = ''; // reset model
                                  });
                                  widget.settingsService.setLlmProvider(
                                    provider,
                                  );
                                  if (_apiKey.isNotEmpty) {
                                    _fetchModels();
                                  }
                                },
                                onLlmBaseUrlChanged: (url) {
                                  setState(() => _llmBaseUrl = url);
                                  widget.settingsService.setLlmBaseUrl(url);
                                },
                                onCheckModels: () => _fetchModels(),
                                targetLanguage: _targetLanguage,
                                apiKey: _apiKey,
                                targetModel: _targetModel,
                                availableModels: _availableModels,
                                isLoadingModels: _isLoadingModels,
                                onTargetLanguageChanged: (lang) {
                                  setState(() => _targetLanguage = lang);
                                  widget.settingsService.setTargetLanguage(
                                    lang,
                                  );
                                },
                                onApiKeyChanged: (key) {
                                  setState(() => _apiKey = key);
                                  widget.settingsService.setGeminiApiKey(key);
                                  _fetchModels();
                                },
                                onTargetModelChanged: (model) {
                                  setState(() => _targetModel = model);
                                  widget.settingsService.setGeminiModel(model);
                                },
                                batchSize: _batchSize,
                                onBatchSizeChanged: (size) {
                                  setState(() => _batchSize = size);
                                  widget.settingsService.setBatchSize(size);
                                },
                                onStartTranslation: () {
                                  if (transcriptionState
                                      is TranscriptionComplete) {
                                    context.read<TranslationBloc>().add(
                                      StartTranslation(
                                        segments:
                                            transcriptionState.result.segments,
                                        config: TranslationConfig(
                                          providerId: _llmProvider,
                                          apiKey: _apiKey,
                                          baseUrl: _llmBaseUrl,
                                          model: _targetModel,
                                          sourceLanguage: transcriptionState
                                              .result
                                              .language,
                                          targetLanguage: _targetLanguage,
                                          batchSize: _batchSize,
                                        ),
                                      ),
                                    );
                                  }
                                },
                              );
                            },
                          );
                        },
                      ),

                      const SizedBox(height: 32),

                      // Step 4: Preview & Export
                      _buildSectionHeader(
                        context,
                        icon: Icons.subtitles_rounded,
                        title: 'Step 4: ${l10n.stepPreviewExport}',
                        number: '4',
                      ),
                      const SizedBox(height: 12),
                      _buildPreviewAndExport(context),

                      const SizedBox(height: 48),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppBar(BuildContext context, AppLocalizations l10n) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Theme.of(context).colorScheme.primary,
                  Theme.of(context).colorScheme.tertiary,
                ],
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.closed_caption_rounded,
              color: Colors.white,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            l10n.appName,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
              letterSpacing: -0.5,
            ),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.settings_rounded),
            onPressed: () => _showSettings(context),
            tooltip: l10n.settings,
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String number,
  }) {
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: Theme.of(
              context,
            ).colorScheme.primary.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Center(
            child: Text(
              number,
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 8),
        Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
      ],
    );
  }

  Widget _buildPreviewAndExport(BuildContext context) {
    return BlocBuilder<TranslationBloc, TranslationState>(
      builder: (context, translationState) {
        return BlocBuilder<TranscriptionBloc, TranscriptionState>(
          builder: (context, transcriptionState) {
            final segments = translationState is TranslationComplete
                ? translationState.translatedSegments
                : (transcriptionState is TranscriptionComplete
                      ? transcriptionState.result.segments
                      : null);

            return SubtitlePreview(
              segments: segments,
              hasTranslation: translationState is TranslationComplete,
              bilingual: _bilingual,
              onBilingualChanged: (v) {
                setState(() => _bilingual = v);
                widget.settingsService.setBilingual(v);
              },
              onExportOriginal: segments != null
                  ? () => _exportSrt(context, segments, false, false)
                  : null,
              onExportTranslated: translationState is TranslationComplete
                  ? () => _exportSrt(context, segments!, true, false)
                  : null,
              onExportBilingual: translationState is TranslationComplete
                  ? () => _exportSrt(context, segments!, false, true)
                  : null,
            );
          },
        );
      },
    );
  }

  String? _getFileName(TranscriptionState state) {
    if (state is VideoSelected) return state.fileName;
    if (state is ModelDownloading) return state.fileName;
    if (state is AudioExtracting) return state.fileName;
    if (state is Transcribing) return state.fileName;
    if (state is TranscriptionComplete) return state.fileName;
    if (state is TranscriptionError) return state.fileName;
    return null;
  }

  Future<void> _pickVideo(BuildContext context) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: AppConstants.videoExtensions,
    );

    if (result != null && result.files.single.path != null) {
      if (context.mounted) {
        context.read<TranscriptionBloc>().add(
          SelectVideo(result.files.single.path!),
        );
        context.read<TranslationBloc>().add(const ResetTranslation());
      }
    }
  }

  Future<void> _exportSrt(
    BuildContext context,
    List<dynamic> segments,
    bool translatedOnly,
    bool bilingual,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final srtContent = SrtParser.generate(
      segments.cast(),
      useTranslation: translatedOnly,
      bilingual: bilingual,
    );

    final suffix = bilingual
        ? '_bilingual'
        : (translatedOnly ? '_translated' : '_original');

    final outputPath = await FilePicker.platform.saveFile(
      dialogTitle: l10n.exportSrt,
      fileName: 'subtitles$suffix.srt',
      type: FileType.custom,
      allowedExtensions: ['srt'],
    );

    if (outputPath != null) {
      await File(outputPath).writeAsString(srtContent);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.exportedTo(outputPath)),
            backgroundColor: Colors.green.shade700,
          ),
        );
      }
    }
  }

  void _showSettings(BuildContext context) {
    final locale = Localizations.localeOf(context);
    showDialog(
      context: context,
      builder: (_) => SettingsDialog(
        currentLocale: locale,
        onLocaleChanged: widget.onLocaleChanged,
      ),
    );
  }
}
