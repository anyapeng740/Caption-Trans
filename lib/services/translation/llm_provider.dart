import 'package:openai_dart/openai_dart.dart';
import 'translation_provider.dart';

/// LLM implementation of [TranslationProvider] using openai_dart.
class LlmProvider implements TranslationProvider {
  final String providerId;
  String? _apiKey;
  String? _baseUrl;
  OpenAIClient? _client;

  LlmProvider({required this.providerId});

  @override
  String get name => providerId;

  void _ensureModel(String apiKey, String? baseUrl) {
    if (_apiKey != apiKey || _baseUrl != baseUrl || _client == null) {
      _apiKey = apiKey;
      _baseUrl = baseUrl;
      _client?.close();
      _client = OpenAIClient.withApiKey(
        apiKey,
        baseUrl: (baseUrl != null && baseUrl.isNotEmpty) ? baseUrl : null,
      );
    }
  }

  @override
  Future<List<String>> translateBatch({
    required List<String> texts,
    required String sourceLanguage,
    required String targetLanguage,
    String? model,
    List<String> contextBefore = const [],
    List<String> contextAfter = const [],
    Map<String, String> glossary = const {},
    void Function(int completed, int total)? onProgress,
    Future<void>? abortTrigger,
  }) async {
    if (_apiKey == null) {
      throw StateError('API key not configured. Call validateApiKey first.');
    }
    _ensureModel(_apiKey!, _baseUrl);

    final prompt = _buildTranslationPrompt(
      texts: texts,
      sourceLanguage: sourceLanguage,
      targetLanguage: targetLanguage,
      contextBefore: contextBefore,
      contextAfter: contextAfter,
      glossary: glossary,
    );

    onProgress?.call(0, texts.length);

    final responseFuture = _client!.chat.completions.create(
      ChatCompletionCreateRequest(
        model: model ?? 'gpt-4o',
        messages: [ChatMessage.user(prompt)],
      ),
    );
    final response = await _awaitWithAbort(responseFuture, abortTrigger);

    final responseText = response.text ?? '';

    onProgress?.call(texts.length, texts.length);

    final finishMessage = response.firstChoice?.finishReason;

    return _parseTranslationResponse(responseText, texts.length, finishMessage);
  }

  @override
  Future<String> buildContextSummary({
    required List<String> allTexts,
    required String sourceLanguage,
    required String targetLanguage,
    String? model,
    Future<void>? abortTrigger,
  }) async {
    if (_apiKey == null) {
      throw StateError('API key not configured. Call validateApiKey first.');
    }
    _ensureModel(_apiKey!, _baseUrl);

    final sampleSize = allTexts.length > 50 ? 50 : allTexts.length;
    final step = allTexts.length ~/ sampleSize;
    if (step == 0) return '';

    final sample = <String>[];
    for (
      var i = 0;
      i < allTexts.length && sample.length < sampleSize;
      i += step
    ) {
      sample.add(allTexts[i]);
    }

    final prompt =
        '''
You are analyzing a video transcript for translation preparation.

Source language: $sourceLanguage
Target language: $targetLanguage

Here is a sample of the transcript:
${sample.asMap().entries.map((e) => '${e.key + 1}. ${e.value}').join('\n')}

Please provide:
1. A brief summary of the content topic
2. Key terms and proper nouns that should be translated consistently
3. The overall tone (formal/informal/technical)

Keep your response concise (under 200 words).
''';

    final responseFuture = _client!.chat.completions.create(
      ChatCompletionCreateRequest(
        model: model ?? 'gpt-4o',
        messages: [ChatMessage.user(prompt)],
      ),
    );
    final response = await _awaitWithAbort(responseFuture, abortTrigger);
    return response.text ?? '';
  }

  @override
  Future<bool> validateApiKey(
    String apiKey, {
    String? model,
    String? baseUrl,
  }) async {
    try {
      _ensureModel(apiKey, baseUrl);
      final response = await _client!.chat.completions.create(
        ChatCompletionCreateRequest(
          model: model ?? 'gpt-4o',
          messages: [ChatMessage.user('Reply with a single word: OK')],
        ),
      );
      final text = response.text ?? '';
      return text.toLowerCase().contains('ok');
    } catch (e) {
      return false;
    }
  }

  @override
  Future<List<String>> listModels(String apiKey, {String? baseUrl}) async {
    try {
      _ensureModel(apiKey, baseUrl);
      final modelsList = await _client!.models.list();

      final models = modelsList.data
          .map((m) => m.id)
          .where((id) => id.isNotEmpty)
          .toList();

      models.sort((a, b) {
        if (a.contains('flash') && !b.contains('flash')) return -1;
        if (!a.contains('flash') && b.contains('flash')) return 1;
        return a.compareTo(b);
      });

      return models;
    } catch (e) {
      // Fallback
      return ['Get models failed. Please check your API key and baseURL.'];
    }
  }

  @override
  void dispose() {
    _client?.close();
    _client = null;
    _apiKey = null;
    _baseUrl = null;
  }

  String _buildTranslationPrompt({
    required List<String> texts,
    required String sourceLanguage,
    required String targetLanguage,
    List<String> contextBefore = const [],
    List<String> contextAfter = const [],
    Map<String, String> glossary = const {},
  }) {
    final buffer = StringBuffer();
    buffer.writeln('You are a professional subtitle translator.');
    buffer.writeln(
      'Translate the following subtitle lines from $sourceLanguage to $targetLanguage.',
    );
    buffer.writeln();
    buffer.writeln('RULES:');
    buffer.writeln('1. Keep translations natural and conversational');
    buffer.writeln('2. Maintain consistent terminology throughout');
    buffer.writeln('3. Return EXACTLY ${texts.length} translated lines');
    buffer.writeln(
      '4. Each translated line should correspond to the same numbered input line',
    );
    buffer.writeln(
      '5. Output ONLY the translations, one per line, numbered like: 1. translated text',
    );
    buffer.writeln(
      '6. Do NOT translate proper nouns unless there is a widely used translation',
    );
    buffer.writeln();

    if (glossary.isNotEmpty) {
      buffer.writeln('GLOSSARY (use these translations consistently):');
      glossary.forEach((source, target) {
        buffer.writeln('  "$source" → "$target"');
      });
      buffer.writeln();
    }

    if (contextBefore.isNotEmpty) {
      buffer.writeln(
        'PRECEDING CONTEXT (already translated, for reference only):',
      );
      for (final line in contextBefore) {
        buffer.writeln('  - $line');
      }
      buffer.writeln();
    }

    buffer.writeln('LINES TO TRANSLATE:');
    for (var i = 0; i < texts.length; i++) {
      buffer.writeln('${i + 1}. ${texts[i]}');
    }

    if (contextAfter.isNotEmpty) {
      buffer.writeln();
      buffer.writeln(
        'FOLLOWING CONTEXT (for reference only, do NOT translate):',
      );
      for (final line in contextAfter) {
        buffer.writeln('  - $line');
      }
    }

    return buffer.toString();
  }

  List<String> _parseTranslationResponse(
    String response,
    int expectedCount,
    FinishReason? finishMessage,
  ) {
    if (response.isEmpty) {
      if (finishMessage != null) {
        return List.filled(expectedCount, finishMessage.toString());
      }
      return List.filled(
        expectedCount,
        '[Translation error: The output may contain sensitive terms. Please try switching to a different model. 翻译错误，可能包含敏感词，请尝试更换模型]',
      );
    }

    final lines = response
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    final results = <String>[];
    for (final line in lines) {
      final match = RegExp(r'^\d+[.:]\s*(.+)$').firstMatch(line);
      if (match != null) {
        results.add(match.group(1)!.trim());
      }
    }

    if (results.length != expectedCount && lines.length == expectedCount) {
      return lines;
    }

    while (results.length < expectedCount) {
      results.add('[Translation Error]');
    }

    return results.length > expectedCount
        ? results.sublist(0, expectedCount)
        : results;
  }

  Future<T> _awaitWithAbort<T>(
    Future<T> future,
    Future<void>? abortTrigger,
  ) async {
    if (abortTrigger == null) return await future;

    final abortFuture = abortTrigger.then<T>((_) {
      throw const TranslationAbortedException();
    });

    return await Future.any([future, abortFuture]);
  }
}
