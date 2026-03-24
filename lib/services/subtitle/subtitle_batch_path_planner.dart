import 'package:path/path.dart' as p;

class SubtitleBatchOutputPlan {
  const SubtitleBatchOutputPlan({
    required this.outputDir,
    required this.originalSrtPath,
    required this.translatedSrtPath,
    required this.relativeMediaPath,
  });

  final String outputDir;
  final String originalSrtPath;
  final String? translatedSrtPath;
  final String relativeMediaPath;

  String get primaryOutputPath => translatedSrtPath ?? originalSrtPath;

  List<String> get outputPaths => <String>[
    originalSrtPath,
    if (translatedSrtPath != null) translatedSrtPath!,
  ];
}

SubtitleBatchOutputPlan buildSubtitleBatchOutputPlan({
  required String inputRoot,
  required String mediaPath,
  required String outputRoot,
  required bool enableTranslation,
  required bool bilingual,
}) {
  final String normalizedInputRoot = p.normalize(inputRoot);
  final String normalizedMediaPath = p.normalize(mediaPath);
  final String relativeMediaPath = p.relative(
    normalizedMediaPath,
    from: normalizedInputRoot,
  );
  final String relativeDir = p.dirname(relativeMediaPath);
  final String outputDir = relativeDir == '.'
      ? outputRoot
      : p.join(outputRoot, relativeDir);
  final String baseName = p.basenameWithoutExtension(normalizedMediaPath);
  return SubtitleBatchOutputPlan(
    outputDir: outputDir,
    originalSrtPath: p.join(outputDir, '$baseName.srt'),
    translatedSrtPath: enableTranslation
        ? p.join(
            outputDir,
            bilingual ? '$baseName.bilingual.srt' : '$baseName.translated.srt',
          )
        : null,
    relativeMediaPath: relativeMediaPath,
  );
}
