import 'package:equatable/equatable.dart';
import '../../models/translation_config.dart';
import '../../models/subtitle_segment.dart';

/// Events for the TranslationBloc.
abstract class TranslationEvent extends Equatable {
  const TranslationEvent();

  @override
  List<Object?> get props => [];
}

/// Start translation with the given config and segments.
class StartTranslation extends TranslationEvent {
  final List<SubtitleSegment> segments;
  final TranslationConfig config;

  const StartTranslation({
    required this.segments,
    required this.config,
  });

  @override
  List<Object?> get props => [segments, config];
}

/// Cancel an ongoing translation.
class CancelTranslation extends TranslationEvent {
  const CancelTranslation();
}

/// Reset translation state.
class ResetTranslation extends TranslationEvent {
  const ResetTranslation();
}

/// Update translation configuration.
class UpdateTranslationConfig extends TranslationEvent {
  final TranslationConfig config;
  const UpdateTranslationConfig(this.config);

  @override
  List<Object?> get props => [config];
}
