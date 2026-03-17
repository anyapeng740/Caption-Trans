import 'dart:async';
import '../../models/subtitle_segment.dart';
import '../../models/translation_config.dart';
import 'translation_provider.dart';
import 'llm_provider.dart';

/// Orchestrates the translation process with context management.
///
/// Handles batch splitting, context window sliding, glossary extraction,
/// and progress reporting.
class TranslationService {
  static final TranslationService _instance = TranslationService._internal();

  factory TranslationService() {
    return _instance;
  }

  TranslationService._internal();

  TranslationProvider? _provider;
  String? _contextSummary;
  Completer<void>? _abortCompleter;
  bool _isCancelled = false;

  /// Get the current context summary (built during translateAll).
  String? get contextSummary => _contextSummary;
  final Map<String, String> _glossary = {};

  TranslationProvider? get currentProvider => _provider;

  void _ensureAbortController() {
    if (_abortCompleter != null && !_abortCompleter!.isCompleted) {
      _abortCompleter!.complete();
    }
    _abortCompleter = Completer<void>();
    _isCancelled = false;
  }

  /// Cancel any ongoing translation.
  void cancel() {
    _isCancelled = true;
    if (_abortCompleter != null && !_abortCompleter!.isCompleted) {
      _abortCompleter!.complete();
    }
    _provider?.dispose();
  }

  /// Initialize or switch the translation provider based on config.
  void configure(TranslationConfig config) {
    _provider?.dispose();
    _provider = LlmProvider(providerId: config.providerId);
  }

  /// Translate all segments with context-aware batching.
  ///
  /// Returns a new list of [SubtitleSegment] with [translatedText] populated.
  Future<List<SubtitleSegment>> translateAll({
    required List<SubtitleSegment> segments,
    required TranslationConfig config,
    void Function(int completed, int total, List<SubtitleSegment> partials)? onProgress,
  }) async {
    if (_provider == null) {
      throw StateError('Translation provider not configured. Call configure() first.');
    }

    _ensureAbortController();

    // Validate API key first
    final isValid = await _provider!.validateApiKey(config.apiKey, model: config.model, baseUrl: config.baseUrl);
    if (!isValid) {
      throw Exception('Invalid API key for ${_provider!.name}');
    }

    final allTexts = segments.map((s) => s.text).toList();
    final totalSegments = segments.length;

    // Step 1: Build context summary for global understanding
    onProgress?.call(0, totalSegments, segments);
    if (_isCancelled) {
      throw const TranslationAbortedException();
    }
    try {
      _contextSummary = await _provider!.buildContextSummary(
        allTexts: allTexts,
        sourceLanguage: config.sourceLanguage,
        targetLanguage: config.targetLanguage,
        model: config.model,
        abortTrigger: _abortCompleter?.future,
      );
    } catch (e) {
      if (_isCancelled) {
        throw const TranslationAbortedException();
      }
      rethrow;
    }

    // Step 2: Translate in batches with sliding context window
    final translatedTexts = segments.map((s) => s.translatedText ?? '').toList();
    var completedCount = translatedTexts.where((t) => t.isNotEmpty).length;

    for (var batchStart = 0;
        batchStart < totalSegments;
        batchStart += config.batchSize) {
      final batchEnd = (batchStart + config.batchSize).clamp(0, totalSegments);
      final batchTexts = allTexts.sublist(batchStart, batchEnd);

      // Check if this batch is already translated
      bool needsTranslation = false;
      for (var i = batchStart; i < batchEnd; i++) {
        if (translatedTexts[i].isEmpty) {
          needsTranslation = true;
          break;
        }
      }

      if (!needsTranslation) {
        continue; // Skip this batch, it's already translated
      }

      // Context before: last N translated lines from previous batch
      final contextBeforeStart =
          (batchStart - config.contextOverlap).clamp(0, totalSegments);
      final contextBefore = batchStart > 0
          ? translatedTexts.sublist(contextBeforeStart, batchStart)
          : <String>[];

      // Context after: next N original lines after this batch
      final contextAfterEnd =
          (batchEnd + config.contextOverlap).clamp(0, totalSegments);
      final contextAfter = batchEnd < totalSegments
          ? allTexts.sublist(batchEnd, contextAfterEnd)
          : <String>[];

      if (_isCancelled) {
        throw const TranslationAbortedException();
      }

      late final List<String> batchResults;
      try {
        batchResults = await _provider!.translateBatch(
          texts: batchTexts,
          sourceLanguage: config.sourceLanguage,
          targetLanguage: config.targetLanguage,
          model: config.model,
          contextBefore: contextBefore,
          contextAfter: contextAfter,
          glossary: _glossary,
          abortTrigger: _abortCompleter?.future,
        );
      } catch (e) {
        if (_isCancelled) {
          throw const TranslationAbortedException();
        }
        rethrow;
      }

      // Store results
      int newlyCompleted = 0;
      for (var i = 0; i < batchResults.length; i++) {
        if (translatedTexts[batchStart + i].isEmpty && batchResults[i].isNotEmpty) {
          newlyCompleted++;
        }
        translatedTexts[batchStart + i] = batchResults[i];
      }

      completedCount += newlyCompleted;
      
      final partialSegments = segments
          .asMap()
          .entries
          .map((e) => e.value.copyWith(
                translatedText: translatedTexts[e.key].isEmpty ? null : translatedTexts[e.key],
              ))
          .toList();

      onProgress?.call(completedCount, totalSegments, partialSegments);

      // Extract key terms from first batch for glossary
      if (batchStart == 0) {
        _extractGlossary(batchTexts, batchResults);
      }
    }

    // Step 3: Build result segments with translations
    return segments
        .asMap()
        .entries
        .map((e) => e.value.copyWith(
              translatedText: translatedTexts[e.key].isEmpty ? null : translatedTexts[e.key],
            ))
        .toList();
  }

  /// Simple glossary extraction from first batch translations.
  void _extractGlossary(List<String> sourceTexts, List<String> translatedTexts) {
    // The glossary will be built up over time as we encounter consistent
    // translations. For now, we keep it manual-ready for future enhancement.
    // A more sophisticated implementation could use the LLM to extract
    // key term pairs from the first batch.
    _glossary.clear();
  }

  /// Clear accumulated context and glossary.
  void reset() {
    _contextSummary = null;
    _glossary.clear();
    _abortCompleter = null;
    _isCancelled = false;
  }

  void dispose() {
    _provider?.dispose();
    _provider = null;
    reset();
  }

  /// List available models from the provider.
  Future<List<String>> listModels(TranslationConfig config) async {
    if (_provider == null || (_provider is LlmProvider && (_provider as LlmProvider).providerId != config.providerId)) {
      configure(config);
    }
    return _provider!.listModels(config.apiKey, baseUrl: config.baseUrl);
  }
}
