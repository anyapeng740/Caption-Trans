import 'dart:async';
import 'dart:math' as math;
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'alist_audio_convert_service.dart';
import 'alist_service.dart';

enum AListAudioBatchStatus { queued, running, completed, canceled, failed }

enum AListAudioTaskStatus { queued, running, completed, canceled, failed }

class AListAudioTaskItem {
  AListAudioTaskItem({required this.id, required this.remotePath});

  final String id;
  final String remotePath;
  AListAudioTaskStatus status = AListAudioTaskStatus.queued;
  String? message;
  String? outputPath;
  double? progress;
  Duration? currentPosition;
  Duration? mediaDuration;
  DateTime? startedAt;
  DateTime? finishedAt;

  Duration? get elapsed {
    final DateTime? start = startedAt;
    if (start == null) return null;
    final DateTime end = finishedAt ?? DateTime.now();
    return end.difference(start);
  }

  Duration? get eta {
    if (status != AListAudioTaskStatus.running) return null;
    final Duration? elapsedValue = elapsed;
    final double? progressValue = progress;
    if (elapsedValue == null ||
        progressValue == null ||
        !progressValue.isFinite ||
        progressValue <= 0.01 ||
        progressValue >= 0.999) {
      return null;
    }
    final double remainingMs =
        elapsedValue.inMilliseconds * ((1 / progressValue) - 1);
    if (!remainingMs.isFinite || remainingMs < 0) {
      return null;
    }
    return Duration(milliseconds: remainingMs.round());
  }
}

class AListAudioBatchTask {
  AListAudioBatchTask({
    required this.id,
    required this.baseUrl,
    required this.username,
    required this.password,
    required this.outputDir,
    required this.format,
    required this.concurrency,
    required this.items,
  });

  final String id;
  final String baseUrl;
  final String username;
  final String password;
  final String outputDir;
  final AListAudioFormat format;
  final int concurrency;
  final List<AListAudioTaskItem> items;
  final DateTime createdAt = DateTime.now();
  AListAudioBatchStatus status = AListAudioBatchStatus.queued;
  bool cancelRequested = false;
  DateTime? startedAt;
  DateTime? finishedAt;

  int get completedCount => items
      .where((item) => item.status == AListAudioTaskStatus.completed)
      .length;

  int get failedCount =>
      items.where((item) => item.status == AListAudioTaskStatus.failed).length;

  int get canceledCount => items
      .where((item) => item.status == AListAudioTaskStatus.canceled)
      .length;

  int get runningCount =>
      items.where((item) => item.status == AListAudioTaskStatus.running).length;

  int get queuedCount =>
      items.where((item) => item.status == AListAudioTaskStatus.queued).length;

  double get progress {
    if (items.isEmpty) return 0;
    double total = 0;
    for (final AListAudioTaskItem item in items) {
      switch (item.status) {
        case AListAudioTaskStatus.queued:
          break;
        case AListAudioTaskStatus.running:
          total += item.progress ?? 0;
          break;
        case AListAudioTaskStatus.completed:
        case AListAudioTaskStatus.canceled:
        case AListAudioTaskStatus.failed:
          total += 1;
          break;
      }
    }
    return total / items.length;
  }

  Duration? get elapsed {
    final DateTime? start = startedAt;
    if (start == null) return null;
    final DateTime end = finishedAt ?? DateTime.now();
    return end.difference(start);
  }
}

class AListAudioTaskManager extends ChangeNotifier {
  AListAudioTaskManager._();

  static final AListAudioTaskManager instance = AListAudioTaskManager._();

  final AListService _alist = AListService();
  final AListAudioConvertService _converter = AListAudioConvertService();
  final List<AListAudioBatchTask> _batches = <AListAudioBatchTask>[];
  final Map<String, AListAudioConversionHandle> _activeHandles =
      <String, AListAudioConversionHandle>{};

  bool _queueRunning = false;
  int _nextBatchId = 1;
  int _nextItemId = 1;

  List<AListAudioBatchTask> get batches =>
      List<AListAudioBatchTask>.unmodifiable(_batches.reversed);

  bool get hasTasks => _batches.isNotEmpty;

  int get activeBatchCount => _batches
      .where(
        (batch) =>
            batch.status == AListAudioBatchStatus.queued ||
            batch.status == AListAudioBatchStatus.running,
      )
      .length;

  int get runningItemCount => _batches
      .expand((AListAudioBatchTask batch) => batch.items)
      .where(
        (AListAudioTaskItem item) =>
            item.status == AListAudioTaskStatus.running,
      )
      .length;

  Future<String> enqueueBatch({
    required String baseUrl,
    required String username,
    required String password,
    required String outputDir,
    required AListAudioFormat format,
    required int concurrency,
    required List<String> remotePaths,
  }) async {
    final AListAudioBatchTask batch = AListAudioBatchTask(
      id: 'alist-audio-batch-${_nextBatchId++}',
      baseUrl: baseUrl.trim(),
      username: username.trim(),
      password: password,
      outputDir: outputDir.trim(),
      format: format,
      concurrency: concurrency.clamp(1, 5),
      items: remotePaths
          .map(
            (String remotePath) => AListAudioTaskItem(
              id: 'alist-audio-item-${_nextItemId++}',
              remotePath: remotePath,
            ),
          )
          .toList(),
    );
    _batches.add(batch);
    notifyListeners();
    unawaited(_pumpQueue());
    return batch.id;
  }

  Future<void> cancelBatch(String batchId) async {
    final AListAudioBatchTask? batch = _findBatch(batchId);
    if (batch == null) return;
    batch.cancelRequested = true;
    if (batch.status == AListAudioBatchStatus.queued) {
      batch.status = AListAudioBatchStatus.canceled;
      batch.finishedAt = DateTime.now();
      for (final AListAudioTaskItem item in batch.items) {
        if (item.status == AListAudioTaskStatus.queued) {
          item.status = AListAudioTaskStatus.canceled;
          item.message ??= '已取消';
          item.finishedAt = DateTime.now();
        }
      }
      notifyListeners();
      return;
    }

    for (final AListAudioTaskItem item in batch.items) {
      if (item.status == AListAudioTaskStatus.running) {
        _activeHandles[item.id]?.cancel();
      } else if (item.status == AListAudioTaskStatus.queued) {
        item.status = AListAudioTaskStatus.canceled;
        item.message ??= '已取消';
        item.finishedAt = DateTime.now();
      }
    }
    notifyListeners();
  }

  void removeBatch(String batchId) {
    _batches.removeWhere((AListAudioBatchTask batch) => batch.id == batchId);
    notifyListeners();
  }

  void clearFinished() {
    _batches.removeWhere((AListAudioBatchTask batch) {
      return batch.status == AListAudioBatchStatus.completed ||
          batch.status == AListAudioBatchStatus.canceled ||
          batch.status == AListAudioBatchStatus.failed;
    });
    notifyListeners();
  }

  AListAudioBatchTask? _findBatch(String batchId) {
    for (final AListAudioBatchTask batch in _batches) {
      if (batch.id == batchId) {
        return batch;
      }
    }
    return null;
  }

  Future<void> _pumpQueue() async {
    if (_queueRunning) return;
    _queueRunning = true;
    try {
      while (true) {
        AListAudioBatchTask? nextBatch;
        for (final AListAudioBatchTask batch in _batches) {
          if (batch.status == AListAudioBatchStatus.queued) {
            nextBatch = batch;
            break;
          }
        }
        if (nextBatch == null) {
          break;
        }
        await _runBatch(nextBatch);
      }
    } finally {
      _queueRunning = false;
      notifyListeners();
    }
  }

  Future<void> _runBatch(AListAudioBatchTask batch) async {
    batch.status = AListAudioBatchStatus.running;
    batch.startedAt = DateTime.now();
    batch.finishedAt = null;
    notifyListeners();
    try {
      await Directory(batch.outputDir).create(recursive: true);

      int cursor = 0;
      final int workerCount = math.min(
        batch.concurrency.clamp(1, 5),
        batch.items.length,
      );

      Future<void> worker() async {
        while (true) {
          if (batch.cancelRequested) return;
          if (cursor >= batch.items.length) return;
          final int currentIndex = cursor;
          cursor++;
          final AListAudioTaskItem item = batch.items[currentIndex];
          await _runItem(batch, item);
        }
      }

      await Future.wait(
        List<Future<void>>.generate(workerCount, (_) => worker()),
      );
    } catch (error) {
      batch.status = AListAudioBatchStatus.failed;
      batch.finishedAt = DateTime.now();
      for (final AListAudioTaskItem item in batch.items) {
        if (item.status == AListAudioTaskStatus.queued) {
          item.status = AListAudioTaskStatus.failed;
          item.message = error.toString();
          item.finishedAt = DateTime.now();
        }
      }
      notifyListeners();
      return;
    }

    batch.finishedAt = DateTime.now();
    if (batch.cancelRequested) {
      batch.status = AListAudioBatchStatus.canceled;
      for (final AListAudioTaskItem item in batch.items) {
        if (item.status == AListAudioTaskStatus.queued) {
          item.status = AListAudioTaskStatus.canceled;
          item.message ??= '已取消';
          item.finishedAt ??= DateTime.now();
        }
      }
    } else if (batch.items.any(
      (AListAudioTaskItem item) => item.status == AListAudioTaskStatus.failed,
    )) {
      batch.status = AListAudioBatchStatus.failed;
    } else {
      batch.status = AListAudioBatchStatus.completed;
    }
    notifyListeners();
  }

  Future<void> _runItem(
    AListAudioBatchTask batch,
    AListAudioTaskItem item,
  ) async {
    if (batch.cancelRequested) {
      item.status = AListAudioTaskStatus.canceled;
      item.message ??= '已取消';
      item.finishedAt = DateTime.now();
      notifyListeners();
      return;
    }

    item.status = AListAudioTaskStatus.running;
    item.startedAt ??= DateTime.now();
    item.finishedAt = null;
    item.progress ??= 0;
    item.currentPosition ??= Duration.zero;
    notifyListeners();

    try {
      final AListLink input = _alist.buildWebDavInput(
        baseUrl: batch.baseUrl,
        username: batch.username,
        password: batch.password,
        remotePath: item.remotePath,
      );
      item.outputPath = _converter.buildOutputPath(
        outputDir: batch.outputDir,
        remotePath: item.remotePath,
        format: batch.format,
      );

      final AListAudioConversionHandle handle = _converter.startConversion(
        inputUrl: input.url,
        headers: input.headers,
        outputPath: item.outputPath!,
        format: batch.format,
        onProgress: (AListAudioProgress progress) {
          item.progress = progress.progress;
          item.currentPosition = progress.current;
          item.mediaDuration = progress.total ?? item.mediaDuration;
          notifyListeners();
        },
      );
      _activeHandles[item.id] = handle;
      await handle.done;
      if (batch.cancelRequested) {
        item.status = AListAudioTaskStatus.canceled;
        item.message = '已取消';
      } else {
        item.status = AListAudioTaskStatus.completed;
        item.progress = 1;
        item.currentPosition = item.mediaDuration ?? item.currentPosition;
        item.message = null;
      }
      item.finishedAt = DateTime.now();
      notifyListeners();
    } catch (error) {
      if (error is AListAudioCancelledError || batch.cancelRequested) {
        item.status = AListAudioTaskStatus.canceled;
        item.message = '已取消';
      } else {
        item.status = AListAudioTaskStatus.failed;
        item.message = error.toString();
      }
      item.finishedAt = DateTime.now();
      notifyListeners();
    } finally {
      _activeHandles.remove(item.id);
    }
  }
}
