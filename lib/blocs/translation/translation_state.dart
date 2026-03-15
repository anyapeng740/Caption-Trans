import 'package:equatable/equatable.dart';
import '../../models/subtitle_segment.dart';
import '../../models/translation_config.dart';

/// States for the TranslationBloc.
abstract class TranslationState extends Equatable {
  const TranslationState();

  @override
  List<Object?> get props => [];
}

/// Initial state — no translation started.
class TranslationInitial extends TranslationState {
  const TranslationInitial();
}

/// Translation is in progress.
class TranslationInProgress extends TranslationState {
  final int completed;
  final int total;
  final String statusMessage;
  final List<SubtitleSegment>? partialSegments;

  const TranslationInProgress({
    required this.completed,
    required this.total,
    this.statusMessage = 'Translating...',
    this.partialSegments,
  });

  double get progress => total > 0 ? completed / total : 0;

  @override
  List<Object?> get props => [completed, total, statusMessage, partialSegments];
}

/// Translation completed successfully.
class TranslationComplete extends TranslationState {
  final List<SubtitleSegment> translatedSegments;
  final TranslationConfig config;

  const TranslationComplete({
    required this.translatedSegments,
    required this.config,
  });

  @override
  List<Object?> get props => [translatedSegments, config];
}

/// Translation failed.
class TranslationError extends TranslationState {
  final String message;

  const TranslationError({required this.message});

  @override
  List<Object?> get props => [message];
}
