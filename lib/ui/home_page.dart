import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../services/settings_service.dart';
import '../services/translation/translation_failure.dart';
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
import '../models/whisper_download_source.dart';
import 'widgets/download_source_dialog.dart';
import 'widgets/video_picker_card.dart';
import 'widgets/transcription_panel.dart';
import 'widgets/translation_panel.dart';
import 'widgets/subtitle_preview.dart';
import 'widgets/settings_dialog.dart';
import 'widgets/alist_audio_converter_dialog.dart';
import 'project_list_page.dart';
import '../models/project.dart';
import 'package:uuid/uuid.dart';
import '../blocs/project/project_bloc.dart';
import '../blocs/project/project_event.dart';
import '../blocs/project/project_state.dart';
import '../models/subtitle_segment.dart';
import '../services/update_service.dart';
import '../services/alist/alist_service.dart';
import '../services/alist/alist_audio_task_manager.dart';
import 'widgets/update_dialog.dart';
import 'widgets/alist_audio_task_center_dialog.dart';

enum _AListUploadMode { original, translated, bilingual }

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
  String _sourceVideoLanguage = 'ja';
  String _targetLanguage = 'zh';
  String _apiKey = '';
  String _targetModel = 'gemini-2.5-flash-lite';
  String _llmProvider = 'Gemini (Google)';
  String _llmBaseUrl =
      'https://generativelanguage.googleapis.com/v1beta/openai';
  bool _bilingual = true;
  int _batchSize = 15;
  List<String> _availableModels = [];
  bool _isLoadingModels = false;
  Map<String, ProviderCredential> _savedProviderCredentials = {};
  final UpdateService _updateService = UpdateService();

  Project? _activeProject;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkForUpdatesSilently();
    });
  }

  @override
  void dispose() {
    _updateService.dispose();
    super.dispose();
  }

  void _loadSettings() {
    final savedCredentials = widget.settingsService.llmProviderCredentials;
    final provider = widget.settingsService.llmProvider;
    final savedForProvider = savedCredentials[provider];

    setState(() {
      _savedProviderCredentials = savedCredentials;
      _targetModel = widget.settingsService.geminiModel;
      _llmProvider = provider;
      _llmBaseUrl =
          savedForProvider?.baseUrl ?? widget.settingsService.llmBaseUrl;
      _apiKey = savedForProvider?.apiKey ?? widget.settingsService.geminiApiKey;
      _targetLanguage = widget.settingsService.targetLanguage;
      _bilingual = widget.settingsService.bilingual;
      _batchSize = widget.settingsService.batchSize;
    });

    if (_apiKey.isNotEmpty) {
      _fetchModels();
    }
  }

  Future<void> _checkForUpdatesSilently() async {
    if (!UpdateService.supportsAutoUpdateCheck || !mounted) {
      return;
    }

    final lastCheckedAt = widget.settingsService.lastUpdateCheckAt;
    if (!UpdateService.shouldPerformAutoCheck(lastCheckedAt)) {
      return;
    }

    try {
      final result = await _updateService.checkForUpdates();
      await widget.settingsService.setLastUpdateCheckAt(DateTime.now());
      if (!mounted || !result.isUpdateAvailable) {
        return;
      }

      await showUpdateAvailableDialog(context, result);
    } catch (_) {
      await widget.settingsService.setLastUpdateCheckAt(DateTime.now());
    }
  }

  bool _isModelFetchFailed(List<String> models) {
    if (models.isEmpty) return true;
    final first = models.first.toLowerCase();
    return models.length == 1 &&
        first.contains('failed') &&
        first.contains('api key');
  }

  void _handleProviderChanged(String provider) {
    final savedCredential = _savedProviderCredentials[provider];
    final baseUrl =
        savedCredential?.baseUrl ?? (defaultLlmBaseUrls[provider] ?? '');
    final apiKey = savedCredential?.apiKey ?? '';

    setState(() {
      _llmProvider = provider;
      _llmBaseUrl = baseUrl;
      _apiKey = apiKey;
      _targetModel = '';
      _availableModels = [];
    });

    widget.settingsService.setLlmProvider(provider);
    widget.settingsService.setLlmBaseUrl(baseUrl);
    widget.settingsService.setGeminiApiKey(apiKey);
  }

  Future<void> _saveProviderCredentialIfNeeded() async {
    if (_llmProvider.isEmpty || _llmBaseUrl.isEmpty || _apiKey.isEmpty) return;

    final credential = ProviderCredential(
      baseUrl: _llmBaseUrl.trim(),
      apiKey: _apiKey.trim(),
    );
    await widget.settingsService.saveLlmProviderCredential(
      _llmProvider,
      credential,
    );

    if (mounted) {
      setState(() {
        _savedProviderCredentials[_llmProvider] = credential;
      });
    }
  }

  Future<void> _fetchModels({bool saveProviderCredential = false}) async {
    if (_apiKey.isEmpty) return;

    setState(() => _isLoadingModels = true);
    try {
      final service = TranslationService();
      final models = await service.listModels(
        TranslationConfig(
          providerId: _llmProvider,
          apiKey: _apiKey,
          baseUrl: _llmBaseUrl,
          sourceLanguage: 'ja', // dummy
          targetLanguage: 'zh', // dummy
        ),
      );
      final failed = _isModelFetchFailed(models);

      if (mounted) {
        setState(() {
          _availableModels = failed ? [] : models;
          if (!_availableModels.contains(_targetModel)) {
            if (_availableModels.isNotEmpty) {
              _targetModel = _availableModels.first;
            }
          }
          _isLoadingModels = false;
        });

        if (failed) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('获取模型列表失败，请检查 Base URL 或 API Key。'),
              backgroundColor: Colors.red.shade700,
            ),
          );
        } else if (saveProviderCredential) {
          await _saveProviderCredentialIfNeeded();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _availableModels = [];
          _isLoadingModels = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('获取模型列表失败，请检查 Base URL 或 API Key。'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    }
  }

  TranslationConfig? _buildCurrentTranslationConfig(
    TranscriptionState transcriptionState,
  ) {
    if (transcriptionState is! TranscriptionComplete) {
      return null;
    }

    return TranslationConfig(
      providerId: _llmProvider,
      apiKey: _apiKey,
      baseUrl: _llmBaseUrl,
      model: _targetModel,
      sourceLanguage: transcriptionState.result.language,
      targetLanguage: _targetLanguage,
      batchSize: _batchSize,
    );
  }

  List<SubtitleSegment>? _resolveEffectiveSegments(
    TranslationState translationState,
    TranscriptionState transcriptionState,
  ) {
    if (translationState is TranslationInProgress &&
        translationState.partialSegments != null) {
      return translationState.partialSegments;
    }

    if (translationState is TranslationComplete) {
      return translationState.translatedSegments;
    }

    if (translationState is TranslationCancelled &&
        translationState.partialSegments != null) {
      return translationState.partialSegments;
    }

    if (translationState is TranslationError &&
        translationState.partialSegments != null) {
      return translationState.partialSegments;
    }

    if (transcriptionState is TranscriptionComplete) {
      return transcriptionState.result.segments;
    }

    return null;
  }

  int _countSuccessfulTranslatedSegments(List<SubtitleSegment>? segments) {
    if (segments == null) {
      return 0;
    }

    return segments
        .where(
          (segment) =>
              segment.translatedText?.trim().isNotEmpty == true &&
              !isTranslationErrorText(segment.translatedText),
        )
        .length;
  }

  int _countFailedTranslatedSegments(List<SubtitleSegment>? segments) {
    if (segments == null) {
      return 0;
    }

    return segments
        .where((segment) => isTranslationErrorText(segment.translatedText))
        .length;
  }

  int _countVisibleTranslationSegments(List<SubtitleSegment>? segments) {
    if (segments == null) {
      return 0;
    }

    return segments
        .where((segment) => segment.translatedText?.trim().isNotEmpty == true)
        .length;
  }

  List<SubtitleSegment> _clearTranslatedSegments(
    List<SubtitleSegment> segments,
  ) {
    return segments
        .map((segment) => segment.copyWith(translatedText: null))
        .toList();
  }

  void _persistProjectTranslation(
    BuildContext context, {
    required List<SubtitleSegment> segments,
    TranslationConfig? config,
  }) {
    if (_activeProject == null) {
      return;
    }

    final updatedResult = _activeProject!.transcription.copyWith(
      segments: segments,
    );
    final updatedProject = _activeProject!.copyWith(
      transcription: updatedResult,
      updatedAt: DateTime.now(),
      translationConfig: config ?? _activeProject!.translationConfig,
    );

    _activeProject = updatedProject;
    context.read<ProjectBloc>().add(UpdateProject(updatedProject));
  }

  void _startTranslation(
    BuildContext context, {
    required TranslationState translationState,
    required TranscriptionState transcriptionState,
    bool restart = false,
    bool retryFailedOnly = false,
  }) {
    final config = _buildCurrentTranslationConfig(transcriptionState);
    final segments = _resolveEffectiveSegments(
      translationState,
      transcriptionState,
    );

    if (config == null || segments == null) {
      return;
    }

    context.read<TranslationBloc>().add(
      StartTranslation(
        segments: restart ? _clearTranslatedSegments(segments) : segments,
        config: config,
        retryFailedOnly: retryFailedOnly,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final platform = Theme.of(context).platform;
    final isMobilePlatform =
        platform == TargetPlatform.iOS || platform == TargetPlatform.android;

    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: <Widget>[
            SingleChildScrollView(
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
                        title: '第 1 步：${l10n.stepSelectVideo}',
                        number: '1',
                        trailing: IconButton(
                          icon: const Icon(Icons.settings_rounded),
                          onPressed: () => _showSettings(context),
                          tooltip: l10n.settings,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _buildStepOnePanels(isMobilePlatform),

                      const SizedBox(height: 32),

                      // Step 2: Transcription
                      _buildSectionHeader(
                        context,
                        icon: Icons.mic_rounded,
                        title: '第 2 步：${l10n.stepExtractSubtitles}',
                        number: '2',
                      ),
                      const SizedBox(height: 12),
                      BlocBuilder<TranscriptionBloc, TranscriptionState>(
                        builder: (context, state) {
                          return TranscriptionPanel(
                            state: state,
                            selectedModel: _selectedModel,
                            selectedSourceLanguage: _sourceVideoLanguage,
                            onModelChanged: (model) =>
                                setState(() => _selectedModel = model),
                            onSourceLanguageChanged: (language) =>
                                setState(() => _sourceVideoLanguage = language),
                            onStartTranscription: () {
                              _handleStartTranscription(context);
                            },
                          );
                        },
                      ),

                      const SizedBox(height: 32),

                      // Step 3: Translation
                      _buildSectionHeader(
                        context,
                        icon: Icons.translate_rounded,
                        title: '第 3 步：${l10n.stepTranslate}',
                        number: '3',
                      ),
                      const SizedBox(height: 12),
                      BlocConsumer<TranslationBloc, TranslationState>(
                        listener: (context, state) {
                          final transcriptionState = context
                              .read<TranscriptionBloc>()
                              .state;
                          final currentConfig = _buildCurrentTranslationConfig(
                            transcriptionState,
                          );

                          if (state is TranslationError) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(state.message),
                                backgroundColor: Colors.red.shade700,
                              ),
                            );
                            if (state.partialSegments != null) {
                              _persistProjectTranslation(
                                context,
                                segments: state.partialSegments!,
                                config: state.config ?? currentConfig,
                              );
                            }
                          } else if (state is TranslationInProgress &&
                              state.partialSegments != null) {
                            _persistProjectTranslation(
                              context,
                              segments: state.partialSegments!,
                              config: currentConfig,
                            );
                          } else if (state is TranslationComplete) {
                            _persistProjectTranslation(
                              context,
                              segments: state.translatedSegments,
                              config: state.config,
                            );
                          } else if (state is TranslationCancelled &&
                              state.partialSegments != null) {
                            _persistProjectTranslation(
                              context,
                              segments: state.partialSegments!,
                              config: state.config ?? currentConfig,
                            );
                          }
                        },
                        builder: (context, translationState) {
                          return BlocBuilder<
                            TranscriptionBloc,
                            TranscriptionState
                          >(
                            builder: (context, transcriptionState) {
                              final effectiveSegments =
                                  _resolveEffectiveSegments(
                                    translationState,
                                    transcriptionState,
                                  );
                              final translatedSegmentCount =
                                  _countSuccessfulTranslatedSegments(
                                    effectiveSegments,
                                  );
                              final failedSegmentCount =
                                  _countFailedTranslatedSegments(
                                    effectiveSegments,
                                  );
                              final totalSegmentCount =
                                  effectiveSegments?.length ?? 0;

                              return TranslationPanel(
                                transcriptionState: transcriptionState,
                                translationState: translationState,
                                translatedSegmentCount: translatedSegmentCount,
                                failedSegmentCount: failedSegmentCount,
                                totalSegmentCount: totalSegmentCount,
                                llmProvider: _llmProvider,
                                llmBaseUrl: _llmBaseUrl,
                                onLlmProviderChanged: (provider) {
                                  _handleProviderChanged(provider);
                                },
                                onLlmBaseUrlChanged: (url) {
                                  setState(() => _llmBaseUrl = url);
                                  widget.settingsService.setLlmBaseUrl(url);
                                },
                                onCheckModels: () {
                                  _fetchModels(saveProviderCredential: true);
                                },
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
                                  _startTranslation(
                                    context,
                                    translationState: translationState,
                                    transcriptionState: transcriptionState,
                                  );
                                },
                                onRetryFailedTranslation: failedSegmentCount > 0
                                    ? () {
                                        _startTranslation(
                                          context,
                                          translationState: translationState,
                                          transcriptionState:
                                              transcriptionState,
                                          retryFailedOnly: true,
                                        );
                                      }
                                    : null,
                                onRestartTranslation: () {
                                  _startTranslation(
                                    context,
                                    translationState: translationState,
                                    transcriptionState: transcriptionState,
                                    restart: true,
                                  );
                                },
                                onCancelTranslation: () {
                                  context.read<TranslationBloc>().add(
                                    const CancelTranslation(),
                                  );
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
                        title: '第 4 步：${l10n.stepPreviewExport}',
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
            _buildAudioTaskBubble(context),
          ],
        ),
      ),
    );
  }

  Widget _buildAudioTaskBubble(BuildContext context) {
    final AListAudioTaskManager manager = AListAudioTaskManager.instance;
    return AnimatedBuilder(
      animation: manager,
      builder: (BuildContext context, _) {
        if (!manager.hasTasks) {
          return const SizedBox.shrink();
        }
        final List<AListAudioBatchTask> activeBatches = manager.batches
            .where(
              (AListAudioBatchTask batch) =>
                  batch.status == AListAudioBatchStatus.queued ||
                  batch.status == AListAudioBatchStatus.running,
            )
            .toList();
        double progress = 1;
        if (activeBatches.isNotEmpty) {
          progress =
              activeBatches
                  .map((AListAudioBatchTask batch) => batch.progress)
                  .reduce((double a, double b) => a + b) /
              activeBatches.length;
        }
        final int badgeCount = manager.activeBatchCount;

        return Positioned(
          right: 24,
          bottom: 24,
          child: Tooltip(
            message: '后台任务',
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: () => showAListAudioTaskCenterDialog(context),
                child: SizedBox(
                  width: 68,
                  height: 68,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: <Widget>[
                      Positioned.fill(
                        child: CircularProgressIndicator(
                          value: progress,
                          strokeWidth: 3,
                          backgroundColor: Colors.white.withValues(alpha: 0.12),
                        ),
                      ),
                      Positioned.fill(
                        child: Padding(
                          padding: const EdgeInsets.all(6),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.surface,
                              shape: BoxShape.circle,
                              boxShadow: <BoxShadow>[
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.28),
                                  blurRadius: 12,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            child: Icon(
                              Icons.bubble_chart_rounded,
                              color: Theme.of(context).colorScheme.primary,
                              size: 28,
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        right: -2,
                        top: -2,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: badgeCount > 0
                                ? Theme.of(context).colorScheme.primary
                                : Colors.green,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            badgeCount > 0 ? '$badgeCount' : '✓',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildStepOnePanels(bool isMobilePlatform) {
    if (isMobilePlatform) {
      return Column(
        children: [
          _buildVideoPickerPanel(),
          const SizedBox(height: 12),
          _buildEmbeddedProjectList(),
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(flex: 1, child: _buildVideoPickerPanel()),
        const SizedBox(width: 16),
        Expanded(flex: 1, child: _buildEmbeddedProjectList()),
      ],
    );
  }

  Widget _buildVideoPickerPanel() {
    return BlocConsumer<TranscriptionBloc, TranscriptionState>(
      listener: (context, state) {
        if (state is TranscriptionComplete) {
          if (_activeProject == null ||
              _activeProject!.name != state.fileName) {
            // Create a new project when transcription finishes initially
            _activeProject = Project(
              id: const Uuid().v4(),
              name: state.fileName,
              videoPath: state.videoPath,
              sourceVideoLanguage: _sourceVideoLanguage,
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
              transcription: state.result,
              translationConfig: null,
            );
            context.read<ProjectBloc>().add(AddProject(_activeProject!));
          } else {
            // Update existing active project if for some reason transcription completes again
            // Should not really happen on normal resume since it bypasses extraction
          }
        } else if (state is TranscriptionInitial || state is VideoSelected) {
          _activeProject = null; // Reset on new video pick
        }
      },
      builder: (context, state) {
        return VideoPickerCard(
          selectedFileName: _getFileName(state),
          onPickVideo: () => _pickVideo(context),
          onOpenAListAudioConvert: () => _openAListAudioConverter(context),
          onClear: state is! TranscriptionInitial
              ? () => context.read<TranscriptionBloc>().add(
                  const ResetTranscription(),
                )
              : null,
        );
      },
    );
  }

  Widget _buildSectionHeader(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String number,
    Widget? trailing,
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
        Expanded(
          child: Text(
            title,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 8), trailing],
      ],
    );
  }

  Widget _buildPreviewAndExport(BuildContext context) {
    return BlocBuilder<TranslationBloc, TranslationState>(
      builder: (context, translationState) {
        return BlocBuilder<TranscriptionBloc, TranscriptionState>(
          builder: (context, transcriptionState) {
            final segments = _resolveEffectiveSegments(
              translationState,
              transcriptionState,
            );
            final hasTranslation =
                _countVisibleTranslationSegments(segments) > 0;

            return SubtitlePreview(
              segments: segments,
              hasTranslation: hasTranslation,
              bilingual: _bilingual,
              onBilingualChanged: (v) {
                setState(() => _bilingual = v);
                widget.settingsService.setBilingual(v);
              },
              onExportOriginal: segments != null
                  ? () => _exportSrt(context, segments, false, false)
                  : null,
              onExportTranslated: hasTranslation && segments != null
                  ? () => _exportSrt(context, segments, true, false)
                  : null,
              onExportBilingual: hasTranslation && segments != null
                  ? () => _exportSrt(context, segments, false, true)
                  : null,
              onUploadToAList: segments != null
                  ? () => _uploadCurrentSrtToAList(
                      context,
                      segments,
                      hasTranslation: hasTranslation,
                    )
                  : null,
            );
          },
        );
      },
    );
  }

  String? _getFileName(TranscriptionState state) {
    if (state is VideoSelected) return state.fileName;
    if (state is RuntimePreparing) return state.fileName;
    if (state is AudioTranscoding) return state.fileName;
    if (state is Transcribing) return state.fileName;
    if (state is TranscriptionComplete) return state.fileName;
    if (state is TranscriptionError) return state.fileName;
    return null;
  }

  Future<void> _pickVideo(BuildContext context) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: AppConstants.mediaExtensions,
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

  Future<void> _openAListAudioConverter(BuildContext context) async {
    await showAListAudioConverterDialog(
      context,
      settingsService: widget.settingsService,
    );
  }

  Future<bool> _ensureDownloadSourceSelected(BuildContext context) async {
    final WhisperDownloadSource? saved =
        widget.settingsService.whisperDownloadSource;
    if (saved != null) {
      return true;
    }

    final AppLocalizations l10n = AppLocalizations.of(context)!;
    final WhisperDownloadSource? selected = await showDownloadSourceDialog(
      context,
      title: l10n.downloadSourcePromptTitle,
      message: l10n.downloadSourcePromptMessage,
    );
    if (selected == null) {
      return false;
    }

    await widget.settingsService.setWhisperDownloadSource(selected);
    return true;
  }

  Future<void> _handleStartTranscription(BuildContext context) async {
    final bool ready = await _ensureDownloadSourceSelected(context);
    if (!ready || !context.mounted) {
      return;
    }

    context.read<TranscriptionBloc>().add(
      StartTranscription(
        modelName: _selectedModel,
        language: _sourceVideoLanguage,
      ),
    );
  }

  Future<void> _exportSrt(
    BuildContext context,
    List<SubtitleSegment> segments,
    bool translatedOnly,
    bool bilingual,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    try {
      final srtContent = SrtParser.generate(
        segments,
        useTranslation: translatedOnly,
        bilingual: bilingual,
      );

      final transcriptionState = context.read<TranscriptionBloc>().state;
      final selectedFileName = _getFileName(transcriptionState);
      final baseName = (selectedFileName != null && selectedFileName.isNotEmpty)
          ? p.basenameWithoutExtension(selectedFileName)
          : 'subtitles';
      final exportFileName = '$baseName.srt';

      // `saveFile` is desktop-friendly; mobile should use system share sheet.
      if (Platform.isAndroid || Platform.isIOS) {
        final tempDir = await getTemporaryDirectory();
        final outputPath = p.join(tempDir.path, exportFileName);
        await File(outputPath).writeAsString(srtContent);

        await SharePlus.instance.share(
          ShareParams(
            files: [XFile(outputPath, mimeType: 'application/x-subrip')],
            subject: exportFileName,
            text: exportFileName,
          ),
        );
        return;
      }

      final outputPath = await FilePicker.platform.saveFile(
        dialogTitle: l10n.exportSrt,
        fileName: exportFileName,
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
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('导出失败：$e'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    }
  }

  _AListUploadMode _resolveAListUploadMode({required bool hasTranslation}) {
    if (!hasTranslation) {
      return _AListUploadMode.original;
    }
    if (_bilingual) {
      return _AListUploadMode.bilingual;
    }
    return _AListUploadMode.translated;
  }

  Future<String?> _promptAListRemoteBasePath(BuildContext context) async {
    final TextEditingController controller = TextEditingController(
      text: widget.settingsService.alistUploadRemoteBase,
    );
    final String? result = await showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('上传到 AList'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text(
                '远端基准目录（示例：/115/nana/98tang/日本vr）',
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: controller,
                decoration: const InputDecoration(
                  isDense: true,
                  hintText: '/115/nana',
                ),
              ),
            ],
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(controller.text.trim()),
              child: const Text('上传'),
            ),
          ],
        );
      },
    );
    controller.dispose();
    return result;
  }

  Future<void> _uploadCurrentSrtToAList(
    BuildContext context,
    List<SubtitleSegment> segments, {
    required bool hasTranslation,
  }) async {
    final String savedBaseUrl = widget.settingsService.alistBaseUrl.trim();
    final String savedUsername = widget.settingsService.alistUsername.trim();
    final String savedPassword = widget.settingsService.alistPassword;
    if (savedBaseUrl.isEmpty || savedUsername.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('请先从 AList 选择过文件。'),
          backgroundColor: Colors.red.shade700,
        ),
      );
      return;
    }

    final String? remoteBaseInput = await _promptAListRemoteBasePath(context);
    if (remoteBaseInput == null || remoteBaseInput.trim().isEmpty) {
      return;
    }
    await widget.settingsService.setAListUploadRemoteBase(
      remoteBaseInput.trim(),
    );
    if (!context.mounted) return;

    final _AListUploadMode mode = _resolveAListUploadMode(
      hasTranslation: hasTranslation,
    );
    final bool useTranslation = mode != _AListUploadMode.original;
    final bool useBilingual = mode == _AListUploadMode.bilingual;
    final String srtContent = SrtParser.generate(
      segments,
      useTranslation: useTranslation,
      bilingual: useBilingual,
    );

    final TranscriptionState transcriptionState = context
        .read<TranscriptionBloc>()
        .state;
    final String? selectedFileName = _getFileName(transcriptionState);
    final String baseName =
        (selectedFileName != null && selectedFileName.isNotEmpty)
        ? p.basenameWithoutExtension(selectedFileName)
        : 'subtitles';
    final String uploadFileName = switch (mode) {
      _AListUploadMode.original => '$baseName.srt',
      _AListUploadMode.translated => '$baseName.translated.srt',
      _AListUploadMode.bilingual => '$baseName.bilingual.srt',
    };

    if (!context.mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 12),
            Text('正在上传到 AList...'),
          ],
        ),
      ),
    );

    final AListService service = AListService();
    try {
      final AListTarget target = service.normalizeBaseUrl(savedBaseUrl);
      final String token = await service.login(
        baseUrl: target.baseUrl,
        username: savedUsername,
        password: savedPassword,
      );

      final String remoteBase = service.normalizePath(remoteBaseInput);
      final String remotePath = service.normalizePath(
        '$remoteBase/$uploadFileName',
      );
      await service.ensureRemoteDir(
        baseUrl: target.baseUrl,
        token: token,
        remoteDir: p.posix.dirname(remotePath),
      );

      final Directory tempDir = await getTemporaryDirectory();
      final Directory uploadDir = Directory(
        p.join(tempDir.path, 'caption_trans', 'upload'),
      );
      await uploadDir.create(recursive: true);
      final String localSrtPath = p.join(
        uploadDir.path,
        '${DateTime.now().microsecondsSinceEpoch}_$uploadFileName',
      );
      await File(localSrtPath).writeAsString(srtContent);

      await service.uploadLocalFile(
        baseUrl: target.baseUrl,
        token: token,
        localPath: localSrtPath,
        remotePath: remotePath,
      );

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已上传到 AList：$remotePath'),
          backgroundColor: Colors.green.shade700,
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('上传到 AList 失败：$e'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    } finally {
      service.dispose();
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
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
        providerCredentials: _savedProviderCredentials,
        settingsService: widget.settingsService,
        onDeleteProviderCredential: (provider) async {
          await widget.settingsService.deleteLlmProviderCredential(provider);
          if (!mounted) return;

          setState(() {
            _savedProviderCredentials.remove(provider);
          });
        },
      ),
    );
  }

  Widget _buildEmbeddedProjectList() {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      height: 194, // Keep in sync with VideoPickerCard desktop height.
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                const Icon(Icons.history_rounded, size: 18),
                const SizedBox(width: 8),
                Text(
                  l10n.recentProjects,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => _openProjects(context),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 0,
                    ),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    l10n.viewAll,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: BlocBuilder<ProjectBloc, ProjectState>(
              builder: (context, state) {
                if (state is ProjectLoading) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (state is ProjectLoaded) {
                  final projects = state.projects;
                  if (projects.isEmpty) {
                    return Center(
                      child: Text(
                        l10n.noProjects,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.5),
                          fontSize: 13,
                        ),
                      ),
                    );
                  }

                  return ListView.builder(
                    padding: EdgeInsets.zero,
                    itemCount: projects.length > 5
                        ? 5
                        : projects.length, // Show top 5
                    itemBuilder: (context, index) {
                      final project = projects[index];
                      final isSelected = _activeProject?.id == project.id;

                      final total = project.transcription.segments.length;
                      final translated = project.transcription.segments
                          .where((s) => s.translatedText?.isNotEmpty == true)
                          .length;

                      return Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () => _loadProject(project),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? Theme.of(
                                      context,
                                    ).colorScheme.primary.withValues(alpha: 0.1)
                                  : null,
                              border: Border(
                                bottom: BorderSide(
                                  color: Colors.white.withValues(alpha: 0.05),
                                ),
                              ),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        project.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: isSelected
                                              ? FontWeight.bold
                                              : FontWeight.normal,
                                          color: isSelected
                                              ? Theme.of(
                                                  context,
                                                ).colorScheme.primary
                                              : null,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        l10n.progressLabel(translated, total),
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.white.withValues(
                                            alpha: 0.5,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (isSelected)
                                  Icon(
                                    Icons.check_circle_rounded,
                                    size: 16,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.primary,
                                  ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  );
                }
                return const SizedBox.shrink();
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openProjects(BuildContext context) async {
    final selectedProject = await Navigator.push<Project>(
      context,
      MaterialPageRoute(builder: (_) => const ProjectListPage()),
    );
    if (selectedProject != null) {
      _loadProject(selectedProject);
    }
  }

  void _loadProject(Project project) {
    setState(() {
      _activeProject = project;
      _sourceVideoLanguage = project.sourceVideoLanguage;
      if (project.translationConfig != null) {
        final config = project.translationConfig!;
        _llmProvider = config.providerId;
        _llmBaseUrl = config.baseUrl;
        _apiKey = config.apiKey;
        _targetLanguage = config.targetLanguage;
        _batchSize = config.batchSize;
        _availableModels = config.model != null ? [config.model!] : [];
        if (config.model != null) {
          _targetModel = config.model!;
        }
      }
    });

    // Clear translation bloc to ready it for continuation
    context.read<TranslationBloc>().add(const ResetTranslation());

    // Resume transcription bloc by feeding raw result immediately
    context.read<TranscriptionBloc>().add(
      LoadTranscriptionFromProject(
        videoPath: project.videoPath,
        fileName: project.name,
        result: project.transcription,
      ),
    );
  }
}
