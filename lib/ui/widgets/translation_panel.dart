import 'package:flutter/material.dart';
import '../../blocs/transcription/transcription_state.dart';
import '../../blocs/translation/translation_state.dart';
import '../../core/constants.dart';
import 'package:caption_trans/l10n/app_localizations.dart';

const Map<String, String> defaultLlmBaseUrls = {
  // --- 国内核心梯队 (网络直连极速) ---
  'DeepSeek (深度求索)': 'https://api.deepseek.com/v1',
  '通义千问 (阿里云)': 'https://dashscope.aliyuncs.com/compatible-mode/v1',
  '月之暗面 (Kimi)': 'https://api.moonshot.cn/v1',
  '智谱清言 (GLM)': 'https://open.bigmodel.cn/api/paas/v4',
  '豆包 (火山引擎)': 'https://ark.cn-beijing.volces.com/api/v3',
  '零一万物 (01.AI)': 'https://api.lingyiwanwu.com/v1',
  '百川智能 (Baichuan)': 'https://api.baichuan-ai.com/v1',
  '文心一言 (百度千帆)': 'https://qianfan.baidubce.com/v2',

  // --- 国际标杆厂商 ---
  'OpenAI': 'https://api.openai.com/v1',
  'Gemini (Google)': 'https://generativelanguage.googleapis.com/v1beta/openai',

  // --- 本地部署与极客选项 ---
  'Ollama (本地默认)': 'http://localhost:11434/v1',
  'SiliconFlow (硅基流动)': 'https://api.siliconflow.cn/v1',
};

/// Panel for configuring and starting translation.
class TranslationPanel extends StatelessWidget {
  final TranscriptionState transcriptionState;
  final TranslationState translationState;
  final String targetLanguage;
  final String llmProvider;
  final String llmBaseUrl;
  final String apiKey;
  final String targetModel;
  final int batchSize;
  final List<String> availableModels;
  final bool isLoadingModels;
  final ValueChanged<String> onLlmProviderChanged;
  final ValueChanged<String> onLlmBaseUrlChanged;
  final ValueChanged<String> onTargetLanguageChanged;
  final ValueChanged<String> onApiKeyChanged;
  final ValueChanged<String> onTargetModelChanged;
  final ValueChanged<int> onBatchSizeChanged;
  final VoidCallback onCheckModels;
  final VoidCallback onStartTranslation;

  const TranslationPanel({
    super.key,
    required this.transcriptionState,
    required this.translationState,
    required this.targetLanguage,
    required this.llmProvider,
    required this.llmBaseUrl,
    required this.apiKey,
    required this.targetModel,
    required this.batchSize,
    required this.availableModels,
    required this.isLoadingModels,
    required this.onLlmProviderChanged,
    required this.onLlmBaseUrlChanged,
    required this.onTargetLanguageChanged,
    required this.onApiKeyChanged,
    required this.onTargetModelChanged,
    required this.onBatchSizeChanged,
    required this.onCheckModels,
    required this.onStartTranslation,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;

    // Ensure the current llmProvider acts correctly if not in map
    final currentProviderValue = defaultLlmBaseUrls.containsKey(llmProvider)
        ? llmProvider
        : (defaultLlmBaseUrls.keys.contains('Gemini (Google)')
              ? 'Gemini (Google)'
              : defaultLlmBaseUrls.keys.first);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.aiProvider,
              style: theme.textTheme.bodySmall?.copyWith(
                color: Colors.white.withValues(alpha: 0.6),
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: currentProviderValue,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.cloud_rounded, size: 18),
                isDense: true,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
              ),
              items: defaultLlmBaseUrls.keys.map((p) {
                return DropdownMenuItem(
                  value: p,
                  child: Text(
                    p,
                    style: const TextStyle(fontSize: 14),
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              }).toList(),
              onChanged: _isTranslating
                  ? null
                  : (v) {
                      if (v != null) {
                        onLlmProviderChanged(v);
                        onLlmBaseUrlChanged(defaultLlmBaseUrls[v]!);
                      }
                    },
            ),
            const SizedBox(height: 20),
            Text(
              'Base URL',
              style: theme.textTheme.bodySmall?.copyWith(
                color: Colors.white.withValues(alpha: 0.6),
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              decoration: const InputDecoration(
                hintText: 'e.g. https://api.openai.com/v1',
                isDense: true,
                prefixIcon: Icon(Icons.link_rounded, size: 18),
              ),
              onChanged: onLlmBaseUrlChanged,
              controller: TextEditingController(
                text: llmBaseUrl,
              )..selection = TextSelection.collapsed(offset: llmBaseUrl.length),
            ),
            const SizedBox(height: 20),
            Text(
              l10n.geminiApiKey,
              style: theme.textTheme.bodySmall?.copyWith(
                color: Colors.white.withValues(alpha: 0.6),
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    obscureText: true,
                    decoration: InputDecoration(
                      hintText: l10n.enterApiKey,
                      isDense: true,
                      prefixIcon: const Icon(Icons.key_rounded, size: 18),
                    ),
                    onChanged: onApiKeyChanged,
                    controller: TextEditingController(text: apiKey)
                      ..selection = TextSelection.collapsed(
                        offset: apiKey.length,
                      ),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: _isTranslating || apiKey.isEmpty
                      ? null
                      : onCheckModels,
                  icon: const Icon(Icons.fact_check_rounded, size: 18),
                  label: const Text('检测'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              l10n.geminiModel,
              style: theme.textTheme.bodySmall?.copyWith(
                color: Colors.white.withValues(alpha: 0.6),
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            isLoadingModels
                ? const LinearProgressIndicator()
                : availableModels.isEmpty
                ? Text(
                    'Please click "检测" to fetch available models',
                    style: TextStyle(
                      color: theme.colorScheme.error,
                      fontSize: 13,
                    ),
                  )
                : DropdownButtonFormField<String>(
                    initialValue: availableModels.contains(targetModel)
                        ? targetModel
                        : availableModels.first,
                    decoration: InputDecoration(
                      hintText: l10n.enterGeminiModel,
                      isDense: true,
                      prefixIcon: const Icon(
                        Icons.psychology_rounded,
                        size: 18,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                    ),
                    items: availableModels.toSet().map((m) {
                      return DropdownMenuItem(
                        value: m,
                        child: Text(m, style: const TextStyle(fontSize: 14)),
                      );
                    }).toList(),
                    onChanged: _isTranslating
                        ? null
                        : (v) {
                            if (v != null) onTargetModelChanged(v);
                          },
                  ),
            const SizedBox(height: 20),
            Text(
              l10n.batchSizeLabel(batchSize),
              style: theme.textTheme.bodySmall?.copyWith(
                color: Colors.white.withValues(alpha: 0.6),
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 4,
                      thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 6,
                      ),
                      overlayShape: const RoundSliderOverlayShape(
                        overlayRadius: 14,
                      ),
                    ),
                    child: Slider(
                      value: batchSize.toDouble(),
                      min: 1,
                      max: 100,
                      divisions: 99,
                      onChanged: _isTranslating
                          ? null
                          : (v) => onBatchSizeChanged(v.round()),
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    batchSize.toString(),
                    style: TextStyle(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            Text(
              l10n.batchSizeHint,
              style: theme.textTheme.labelSmall?.copyWith(
                color: Colors.white.withValues(alpha: 0.4),
                fontSize: 11,
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.targetLanguage,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.white.withValues(alpha: 0.6),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        initialValue: targetLanguage,
                        decoration: const InputDecoration(
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                        ),
                        items: AppConstants.supportedLanguages.entries
                            .map(
                              (e) => DropdownMenuItem(
                                value: e.key,
                                child: Text(
                                  '${e.value} (${e.key})',
                                  style: const TextStyle(fontSize: 14),
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: _isTranslating
                            ? null
                            : (v) {
                                if (v != null) onTargetLanguageChanged(v);
                              },
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                _buildStartButton(context, l10n),
              ],
            ),
            if (_isTranslating ||
                translationState is TranslationComplete ||
                translationState is TranslationError)
              Padding(
                padding: const EdgeInsets.only(top: 20),
                child: _buildStatusWidget(context, l10n),
              ),
          ],
        ),
      ),
    );
  }

  bool get _isTranslating => translationState is TranslationInProgress;

  bool get _canStart =>
      transcriptionState is TranscriptionComplete &&
      apiKey.isNotEmpty &&
      availableModels.isNotEmpty &&
      translationState is! TranslationInProgress;

  Widget _buildStartButton(BuildContext context, AppLocalizations l10n) {
    if (_isTranslating) {
      return const SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }

    return ElevatedButton.icon(
      onPressed: _canStart ? onStartTranslation : null,
      icon: const Icon(Icons.translate_rounded, size: 20),
      label: Text(l10n.translate),
      style: ElevatedButton.styleFrom(
        backgroundColor: Theme.of(context).colorScheme.tertiary,
        foregroundColor: Colors.white,
      ),
    );
  }

  Widget _buildStatusWidget(BuildContext context, AppLocalizations l10n) {
    final theme = Theme.of(context);

    if (translationState is TranslationInProgress) {
      final s = translationState as TranslationInProgress;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.translate_rounded,
                size: 16,
                color: Colors.tealAccent,
              ),
              const SizedBox(width: 8),
              Text(
                l10n.translatingProgress(s.completed, s.total),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.white.withValues(alpha: 0.8),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: s.progress,
              backgroundColor: Colors.white.withValues(alpha: 0.08),
              valueColor: const AlwaysStoppedAnimation(Colors.tealAccent),
              minHeight: 4,
            ),
          ),
        ],
      );
    }

    if (translationState is TranslationComplete) {
      final s = translationState as TranslationComplete;
      final langName =
          AppConstants.supportedLanguages[s.config.targetLanguage] ??
          s.config.targetLanguage;
      return Row(
        children: [
          const Icon(
            Icons.check_circle_rounded,
            color: Colors.greenAccent,
            size: 18,
          ),
          const SizedBox(width: 8),
          Text(
            l10n.segmentsTranslated(s.translatedSegments.length, langName),
            style: theme.textTheme.bodySmall?.copyWith(
              color: Colors.greenAccent,
            ),
          ),
        ],
      );
    }

    if (translationState is TranslationError) {
      final s = translationState as TranslationError;
      return Row(
        children: [
          const Icon(Icons.error_rounded, color: Colors.redAccent, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              s.message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: Colors.redAccent,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      );
    }

    return const SizedBox.shrink();
  }
}
