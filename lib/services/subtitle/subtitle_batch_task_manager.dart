import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import '../../core/utils/srt_parser.dart';
import '../../models/subtitle_segment.dart';
import '../../models/translation_config.dart';
import '../../models/transcription_result.dart';
import '../settings_service.dart';
import '../translation/llm_provider.dart';
import '../translation/translation_failure.dart';
import '../translation/translation_service.dart';
import '../whisper/whisper_service.dart';
import 'subtitle_batch_path_planner.dart';

enum SubtitleBatchStatus { queued, running, completed, canceled, failed }

enum SubtitleTaskPhase {
  queued,
  preparingRuntime,
  transcoding,
  transcribing,
  translating,
  exporting,
  completed,
  canceled,
  failed,
}

class SubtitleBatchSourceFile {
  const SubtitleBatchSourceFile({
    required this.path,
    required this.relativePath,
    required this.sizeBytes,
  });

  final String path;
  final String relativePath;
  final int sizeBytes;
}

class SubtitleBatchTaskItem {
  SubtitleBatchTaskItem({required this.id, required this.source});

  final String id;
  final SubtitleBatchSourceFile source;
  SubtitleTaskPhase phase = SubtitleTaskPhase.queued;
  String? message;
  double progress = 0;
  DateTime? startedAt;
  DateTime? finishedAt;
  final List<String> logs = <String>[];
  final List<String> outputPaths = <String>[];
  TranscriptionResult? transcriptionResult;

  String get filePath => source.path;
  String get relativePath => source.relativePath;
  int get sizeBytes => source.sizeBytes;

  bool get isTerminal =>
      phase == SubtitleTaskPhase.completed ||
      phase == SubtitleTaskPhase.canceled ||
      phase == SubtitleTaskPhase.failed;

  Duration? get elapsed {
    final DateTime? start = startedAt;
    if (start == null) return null;
    return (finishedAt ?? DateTime.now()).difference(start);
  }

  Duration? get eta {
    final Duration? elapsedValue = elapsed;
    if (elapsedValue == null || progress <= 0.01 || progress >= 0.999) {
      return null;
    }
    final double remainingMs =
        elapsedValue.inMilliseconds * ((1 / progress) - 1);
    if (!remainingMs.isFinite || remainingMs < 0) {
      return null;
    }
    return Duration(milliseconds: remainingMs.round());
  }

  void appendLog(String line) {
    final String trimmed = line.trim();
    if (trimmed.isEmpty) return;
    if (logs.isNotEmpty && logs.last == trimmed) return;
    logs.add(trimmed);
    if (logs.length > 40) {
      logs.removeRange(0, logs.length - 40);
    }
  }
}

class SubtitleBatchTask {
  SubtitleBatchTask({
    required this.id,
    required this.settingsService,
    required this.inputRoot,
    required this.outputRoot,
    required this.modelName,
    required this.sourceLanguage,
    required this.enableTranslation,
    required this.bilingual,
    required this.translationConfig,
    required this.items,
  });

  final String id;
  final SettingsService settingsService;
  final String inputRoot;
  final String outputRoot;
  final String modelName;
  final String sourceLanguage;
  final bool enableTranslation;
  final bool bilingual;
  final TranslationConfig? translationConfig;
  final List<SubtitleBatchTaskItem> items;
  final DateTime createdAt = DateTime.now();
  SubtitleBatchStatus status = SubtitleBatchStatus.queued;
  bool cancelRequested = false;
  DateTime? startedAt;
  DateTime? finishedAt;

  int get completedCount => items
      .where(
        (SubtitleBatchTaskItem item) =>
            item.phase == SubtitleTaskPhase.completed,
      )
      .length;

  int get failedCount => items
      .where(
        (SubtitleBatchTaskItem item) => item.phase == SubtitleTaskPhase.failed,
      )
      .length;

  int get canceledCount => items
      .where(
        (SubtitleBatchTaskItem item) =>
            item.phase == SubtitleTaskPhase.canceled,
      )
      .length;

  int get runningCount => items
      .where(
        (SubtitleBatchTaskItem item) =>
            item.phase == SubtitleTaskPhase.preparingRuntime ||
            item.phase == SubtitleTaskPhase.transcoding ||
            item.phase == SubtitleTaskPhase.transcribing ||
            item.phase == SubtitleTaskPhase.translating ||
            item.phase == SubtitleTaskPhase.exporting,
      )
      .length;

  int get queuedCount => items
      .where(
        (SubtitleBatchTaskItem item) => item.phase == SubtitleTaskPhase.queued,
      )
      .length;

  double get progress {
    if (items.isEmpty) return 0;
    double total = 0;
    for (final SubtitleBatchTaskItem item in items) {
      switch (item.phase) {
        case SubtitleTaskPhase.queued:
          break;
        case SubtitleTaskPhase.preparingRuntime:
        case SubtitleTaskPhase.transcoding:
        case SubtitleTaskPhase.transcribing:
        case SubtitleTaskPhase.translating:
        case SubtitleTaskPhase.exporting:
          total += item.progress;
          break;
        case SubtitleTaskPhase.completed:
        case SubtitleTaskPhase.canceled:
        case SubtitleTaskPhase.failed:
          total += 1;
          break;
      }
    }
    return total / items.length;
  }

  Duration? get elapsed {
    final DateTime? start = startedAt;
    if (start == null) return null;
    return (finishedAt ?? DateTime.now()).difference(start);
  }
}

class _SubtitleTaskExecution {
  _SubtitleTaskExecution({
    required this.whisperService,
    required this.translationService,
  });

  final WhisperService whisperService;
  final TranslationService translationService;
  bool cancelRequested = false;

  Future<void> cancel() async {
    cancelRequested = true;
    translationService.cancel();
    await whisperService.dispose();
  }
}

class _QueuedSubtitleItem {
  const _QueuedSubtitleItem({required this.batch, required this.item});

  final SubtitleBatchTask batch;
  final SubtitleBatchTaskItem item;
}

class SubtitleBatchTaskManager extends ChangeNotifier {
  SubtitleBatchTaskManager._();

  static final SubtitleBatchTaskManager instance = SubtitleBatchTaskManager._();

  final List<SubtitleBatchTask> _batches = <SubtitleBatchTask>[];
  final Map<String, _SubtitleTaskExecution> _activeExecutions =
      <String, _SubtitleTaskExecution>{};
  final Set<String> _warmedModels = <String>{};

  bool _queueScheduled = false;
  int _nextBatchId = 1;
  int _nextItemId = 1;
  int _concurrency = 1;

  List<SubtitleBatchTask> get batches =>
      List<SubtitleBatchTask>.unmodifiable(_batches.reversed);

  bool get hasTasks => _batches.isNotEmpty;

  int get concurrency => _concurrency;

  int get activeBatchCount => _batches
      .where(
        (SubtitleBatchTask batch) =>
            batch.status == SubtitleBatchStatus.queued ||
            batch.status == SubtitleBatchStatus.running,
      )
      .length;

  int get runningItemCount => _batches
      .expand((SubtitleBatchTask batch) => batch.items)
      .where(
        (SubtitleBatchTaskItem item) =>
            item.phase == SubtitleTaskPhase.preparingRuntime ||
            item.phase == SubtitleTaskPhase.transcoding ||
            item.phase == SubtitleTaskPhase.transcribing ||
            item.phase == SubtitleTaskPhase.translating ||
            item.phase == SubtitleTaskPhase.exporting,
      )
      .length;

  double get activeProgress {
    final List<SubtitleBatchTask> activeBatches = _batches
        .where(
          (SubtitleBatchTask batch) =>
              batch.status == SubtitleBatchStatus.queued ||
              batch.status == SubtitleBatchStatus.running,
        )
        .toList();
    if (activeBatches.isEmpty) {
      return 1;
    }
    return activeBatches
            .map((SubtitleBatchTask batch) => batch.progress)
            .reduce((double a, double b) => a + b) /
        activeBatches.length;
  }

  void setConcurrency(int value) {
    final int next = value.clamp(1, 4);
    if (next == _concurrency) return;
    _concurrency = next;
    notifyListeners();
    _schedulePump();
  }

  Future<String> enqueueBatch({
    required SettingsService settingsService,
    required String inputRoot,
    required String outputRoot,
    required String modelName,
    required String sourceLanguage,
    required bool enableTranslation,
    required bool bilingual,
    required TranslationConfig? translationConfig,
    required List<SubtitleBatchSourceFile> files,
  }) async {
    final SubtitleBatchTask batch = SubtitleBatchTask(
      id: 'subtitle-batch-${_nextBatchId++}',
      settingsService: settingsService,
      inputRoot: inputRoot,
      outputRoot: outputRoot,
      modelName: modelName,
      sourceLanguage: sourceLanguage,
      enableTranslation: enableTranslation,
      bilingual: bilingual,
      translationConfig: translationConfig,
      items: files
          .map(
            (SubtitleBatchSourceFile file) => SubtitleBatchTaskItem(
              id: 'subtitle-task-${_nextItemId++}',
              source: file,
            ),
          )
          .toList(),
    );
    _batches.add(batch);
    notifyListeners();
    _schedulePump();
    return batch.id;
  }

  Future<void> cancelBatch(String batchId) async {
    final SubtitleBatchTask? batch = _findBatch(batchId);
    if (batch == null) return;
    batch.cancelRequested = true;
    final DateTime now = DateTime.now();
    for (final SubtitleBatchTaskItem item in batch.items) {
      if (item.phase == SubtitleTaskPhase.queued) {
        item.phase = SubtitleTaskPhase.canceled;
        item.message = '已取消';
        item.finishedAt = now;
      } else if (!item.isTerminal) {
        item.message = '正在停止当前任务...';
        item.appendLog('收到取消请求，正在停止当前任务...');
      }
    }
    final Iterable<_SubtitleTaskExecution> executions = batch.items
        .where(
          (SubtitleBatchTaskItem item) =>
              _activeExecutions.containsKey(item.id),
        )
        .map((SubtitleBatchTaskItem item) => _activeExecutions[item.id]!);
    await Future.wait(executions.map((_SubtitleTaskExecution e) => e.cancel()));
    _refreshBatchStatus(batch);
    notifyListeners();
    _schedulePump();
  }

  void removeBatch(String batchId) {
    _batches.removeWhere((SubtitleBatchTask batch) => batch.id == batchId);
    notifyListeners();
  }

  void clearFinished() {
    _batches.removeWhere(
      (SubtitleBatchTask batch) =>
          batch.status == SubtitleBatchStatus.completed ||
          batch.status == SubtitleBatchStatus.canceled ||
          batch.status == SubtitleBatchStatus.failed,
    );
    notifyListeners();
  }

  SubtitleBatchTask? _findBatch(String batchId) {
    for (final SubtitleBatchTask batch in _batches) {
      if (batch.id == batchId) {
        return batch;
      }
    }
    return null;
  }

  void _schedulePump() {
    if (_queueScheduled) return;
    _queueScheduled = true;
    scheduleMicrotask(() async {
      _queueScheduled = false;
      await _pumpQueue();
    });
  }

  Future<void> _pumpQueue() async {
    while (_activeExecutions.length < _concurrency) {
      final _QueuedSubtitleItem? next = _findNextQueuedItem();
      if (next == null) {
        return;
      }
      _startItem(next.batch, next.item);
    }
  }

  _QueuedSubtitleItem? _findNextQueuedItem() {
    for (final SubtitleBatchTask batch in _batches) {
      if (batch.cancelRequested ||
          (batch.status != SubtitleBatchStatus.queued &&
              batch.status != SubtitleBatchStatus.running)) {
        continue;
      }
      final bool modelWarmed = _warmedModels.contains(batch.modelName);
      final bool hasRunningForModel = _batches
          .expand((SubtitleBatchTask value) => value.items)
          .any((SubtitleBatchTaskItem item) {
            if (item.phase != SubtitleTaskPhase.preparingRuntime &&
                item.phase != SubtitleTaskPhase.transcoding &&
                item.phase != SubtitleTaskPhase.transcribing &&
                item.phase != SubtitleTaskPhase.translating &&
                item.phase != SubtitleTaskPhase.exporting) {
              return false;
            }
            final SubtitleBatchTask? owner = _ownerBatchForItem(item.id);
            return owner?.modelName == batch.modelName;
          });
      if (!modelWarmed && hasRunningForModel) {
        continue;
      }
      for (final SubtitleBatchTaskItem item in batch.items) {
        if (item.phase == SubtitleTaskPhase.queued) {
          return _QueuedSubtitleItem(batch: batch, item: item);
        }
      }
    }
    return null;
  }

  SubtitleBatchTask? _ownerBatchForItem(String itemId) {
    for (final SubtitleBatchTask batch in _batches) {
      for (final SubtitleBatchTaskItem item in batch.items) {
        if (item.id == itemId) {
          return batch;
        }
      }
    }
    return null;
  }

  void _startItem(SubtitleBatchTask batch, SubtitleBatchTaskItem item) {
    batch.status = SubtitleBatchStatus.running;
    batch.startedAt ??= DateTime.now();
    item.phase = SubtitleTaskPhase.preparingRuntime;
    item.progress = 0.02;
    item.message = '准备 Whisper 运行时';
    item.startedAt = DateTime.now();

    final _SubtitleTaskExecution execution = _SubtitleTaskExecution(
      whisperService: WhisperService(settingsService: batch.settingsService),
      translationService: TranslationService(
        providerFactory: (TranslationConfig config) =>
            LlmProvider(providerId: config.providerId),
      ),
    );
    _activeExecutions[item.id] = execution;
    notifyListeners();

    unawaited(
      _runItem(batch, item, execution).whenComplete(() async {
        _activeExecutions.remove(item.id);
        if (execution.cancelRequested && !item.isTerminal) {
          item.phase = SubtitleTaskPhase.canceled;
          item.message = '已取消';
          item.finishedAt = DateTime.now();
        }
        await execution.whisperService.dispose();
        execution.translationService.dispose();
        _refreshBatchStatus(batch);
        notifyListeners();
        _schedulePump();
      }),
    );
  }

  Future<void> _runItem(
    SubtitleBatchTask batch,
    SubtitleBatchTaskItem item,
    _SubtitleTaskExecution execution,
  ) async {
    String wavPath = item.filePath;
    try {
      void updatePhase(
        SubtitleTaskPhase phase, {
        double? progress,
        String? message,
        String? logLine,
      }) {
        if (execution.cancelRequested) {
          throw _SubtitleTaskCanceled();
        }
        item.phase = phase;
        if (progress != null) {
          item.progress = progress.clamp(0, 0.999999);
        }
        if (message != null && message.trim().isNotEmpty) {
          item.message = message.trim();
        }
        if (logLine != null && logLine.trim().isNotEmpty) {
          item.appendLog(logLine);
        }
        if (phase.index >= SubtitleTaskPhase.transcribing.index) {
          _warmedModels.add(batch.modelName);
        }
        notifyListeners();
      }

      updatePhase(
        SubtitleTaskPhase.preparingRuntime,
        progress: 0.02,
        message: '准备 Whisper 运行时',
      );
      await execution.whisperService.downloadModel(
        batch.modelName,
        onPreparationState: (String phase, double? progress) {
          final double normalized = switch (phase) {
            'downloading_runtime' => 0.03 + ((progress ?? 0) * 0.12),
            'extracting_runtime' => 0.16,
            'creating_environment' => 0.18,
            'installing_dependencies' => 0.2,
            'starting_sidecar' => 0.22,
            _ => 0.03,
          };
          updatePhase(
            SubtitleTaskPhase.preparingRuntime,
            progress: normalized,
            message: _runtimeStatusLabel(phase),
          );
        },
        onPreparationLog: (String line) {
          updatePhase(
            SubtitleTaskPhase.preparingRuntime,
            message: '准备 Whisper 运行时',
            logLine: line,
          );
        },
      );
      if (execution.cancelRequested) throw _SubtitleTaskCanceled();

      await execution.whisperService.loadModel(batch.modelName);
      updatePhase(
        SubtitleTaskPhase.transcoding,
        progress: 0.24,
        message: '转为 Whisper 可识别音频',
      );
      wavPath = await execution.whisperService.transcodeToWav(item.filePath);
      if (execution.cancelRequested) throw _SubtitleTaskCanceled();

      updatePhase(
        SubtitleTaskPhase.transcribing,
        progress: 0.28,
        message: '开始识别字幕',
      );
      final TranscriptionResult result = await execution.whisperService
          .transcribeWav(
            wavPath,
            language: batch.sourceLanguage,
            onStatus: (String status, String? detail) {
              updatePhase(
                SubtitleTaskPhase.transcribing,
                progress: _transcribingProgress(status),
                message: _transcribingStatusLabel(status, detail),
                logLine: detail,
              );
            },
            onLog: (String line) {
              updatePhase(
                SubtitleTaskPhase.transcribing,
                message: item.message,
                logLine: line,
              );
            },
          );
      item.transcriptionResult = result;
      if (execution.cancelRequested) throw _SubtitleTaskCanceled();

      final SubtitleBatchOutputPlan outputPlan = buildSubtitleBatchOutputPlan(
        inputRoot: batch.inputRoot,
        mediaPath: item.filePath,
        outputRoot: batch.outputRoot,
        enableTranslation: batch.enableTranslation,
        bilingual: batch.bilingual,
      );
      await Directory(outputPlan.outputDir).create(recursive: true);

      updatePhase(
        SubtitleTaskPhase.exporting,
        progress: batch.enableTranslation ? 0.9 : 0.97,
        message: '导出原文字幕',
      );
      await File(
        outputPlan.originalSrtPath,
      ).writeAsString(SrtParser.generate(result.segments));
      item.outputPaths
        ..clear()
        ..add(outputPlan.originalSrtPath);

      if (!batch.enableTranslation || batch.translationConfig == null) {
        item.phase = SubtitleTaskPhase.completed;
        item.progress = 1;
        item.finishedAt = DateTime.now();
        item.message = '已导出到 ${outputPlan.originalSrtPath}';
        notifyListeners();
        return;
      }

      final TranslationConfig translationConfig = batch.translationConfig!
          .copyWith(
            sourceLanguage: result.language == 'unknown'
                ? batch.sourceLanguage
                : result.language,
          );
      updatePhase(
        SubtitleTaskPhase.translating,
        progress: 0.92,
        message: '翻译字幕中',
      );
      final List<SubtitleSegment>
      translatedSegments = await execution.translationService.translateAll(
        segments: result.segments,
        config: translationConfig,
        onProgress: (int completed, int total, List<SubtitleSegment> partials) {
          final double translationProgress = total == 0 ? 0 : completed / total;
          updatePhase(
            SubtitleTaskPhase.translating,
            progress: 0.92 + (translationProgress * 0.06),
            message: '翻译字幕中 $completed/$total',
          );
        },
      );
      if (execution.cancelRequested) throw _SubtitleTaskCanceled();

      final String translatedContent = SrtParser.generate(
        translatedSegments,
        useTranslation: !batch.bilingual,
        bilingual: batch.bilingual,
      );
      final String translatedPath = outputPlan.translatedSrtPath!;
      updatePhase(
        SubtitleTaskPhase.exporting,
        progress: 0.99,
        message: batch.bilingual ? '导出双语字幕' : '导出译文字幕',
      );
      await File(translatedPath).writeAsString(translatedContent);
      item.outputPaths
        ..clear()
        ..addAll(outputPlan.outputPaths);

      final int failedSegments = translatedSegments
          .where(
            (SubtitleSegment segment) =>
                isTranslationErrorText(segment.translatedText),
          )
          .length;
      item.phase = SubtitleTaskPhase.completed;
      item.progress = 1;
      item.finishedAt = DateTime.now();
      item.message = failedSegments > 0
          ? '已导出，$failedSegments 个片段翻译失败'
          : '已导出到 ${outputPlan.primaryOutputPath}';
      notifyListeners();
    } on _SubtitleTaskCanceled {
      item.phase = SubtitleTaskPhase.canceled;
      item.progress = item.progress.clamp(0, 0.999999);
      item.finishedAt = DateTime.now();
      item.message = '已取消';
      notifyListeners();
    } catch (error) {
      item.phase = execution.cancelRequested
          ? SubtitleTaskPhase.canceled
          : SubtitleTaskPhase.failed;
      item.finishedAt = DateTime.now();
      item.message = execution.cancelRequested ? '已取消' : error.toString();
      item.appendLog(error.toString());
      notifyListeners();
    } finally {
      await execution.whisperService.cleanupTempWav(
        wavPath,
        originalMediaPath: item.filePath,
      );
    }
  }

  void _refreshBatchStatus(SubtitleBatchTask batch) {
    final bool allTerminal = batch.items.every(
      (SubtitleBatchTaskItem item) => item.isTerminal,
    );
    if (!allTerminal) {
      batch.status = batch.runningCount > 0
          ? SubtitleBatchStatus.running
          : SubtitleBatchStatus.queued;
      return;
    }

    batch.finishedAt ??= DateTime.now();
    if (batch.items.every(
      (SubtitleBatchTaskItem item) => item.phase == SubtitleTaskPhase.canceled,
    )) {
      batch.status = SubtitleBatchStatus.canceled;
      return;
    }
    if (batch.items.any(
      (SubtitleBatchTaskItem item) => item.phase == SubtitleTaskPhase.failed,
    )) {
      batch.status = SubtitleBatchStatus.failed;
      return;
    }
    if (batch.items.any(
      (SubtitleBatchTaskItem item) => item.phase == SubtitleTaskPhase.canceled,
    )) {
      batch.status = SubtitleBatchStatus.canceled;
      return;
    }
    batch.status = SubtitleBatchStatus.completed;
  }
}

class _SubtitleTaskCanceled implements Exception {}

String subtitleTaskPhaseLabel(SubtitleTaskPhase phase) {
  return switch (phase) {
    SubtitleTaskPhase.queued => '排队中',
    SubtitleTaskPhase.preparingRuntime => '准备运行时',
    SubtitleTaskPhase.transcoding => '转音频中',
    SubtitleTaskPhase.transcribing => '识别字幕中',
    SubtitleTaskPhase.translating => '翻译中',
    SubtitleTaskPhase.exporting => '导出中',
    SubtitleTaskPhase.completed => '已完成',
    SubtitleTaskPhase.canceled => '已取消',
    SubtitleTaskPhase.failed => '失败',
  };
}

String subtitleBatchStatusLabel(SubtitleBatchStatus status) {
  return switch (status) {
    SubtitleBatchStatus.queued => '排队中',
    SubtitleBatchStatus.running => '执行中',
    SubtitleBatchStatus.completed => '已完成',
    SubtitleBatchStatus.canceled => '已取消',
    SubtitleBatchStatus.failed => '有失败',
  };
}

String _runtimeStatusLabel(String phase) {
  return switch (phase) {
    'checking_runtime' => '检查 Whisper 运行时',
    'downloading_runtime' => '下载 Whisper 运行时',
    'extracting_runtime' => '解压 Whisper 运行时',
    'creating_environment' => '创建 Python 环境',
    'installing_dependencies' => '安装 Whisper 依赖',
    'starting_sidecar' => '启动 Whisper Sidecar',
    _ => '准备 Whisper 运行时',
  };
}

double _transcribingProgress(String status) {
  return switch (status) {
    'loading_audio' => 0.34,
    'preparing_model' => 0.4,
    'transcribing' => 0.62,
    'aligning' => 0.78,
    'finalizing' => 0.88,
    _ => 0.32,
  };
}

String _transcribingStatusLabel(String status, String? detail) {
  final String base = switch (status) {
    'loading_audio' => '读取音频',
    'preparing_model' => '准备模型',
    'transcribing' => '识别字幕',
    'aligning' => '时间轴对齐',
    'finalizing' => '整理结果',
    _ => '识别字幕中',
  };
  final String trimmed = (detail ?? '').trim();
  if (trimmed.isEmpty) {
    return base;
  }
  return '$base · $trimmed';
}
