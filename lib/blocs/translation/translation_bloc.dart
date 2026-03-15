import 'package:flutter_bloc/flutter_bloc.dart';
import '../../services/translation/translation_service.dart';
import 'translation_event.dart';
import 'translation_state.dart';

/// BLoC managing the subtitle translation workflow.
class TranslationBloc extends Bloc<TranslationEvent, TranslationState> {
  final TranslationService _translationService;

  TranslationBloc({
    TranslationService? translationService,
  })  : _translationService = translationService ?? TranslationService(),
        super(const TranslationInitial()) {
    on<StartTranslation>(_onStartTranslation);
    on<ResetTranslation>(_onReset);
  }

  Future<void> _onStartTranslation(
    StartTranslation event,
    Emitter<TranslationState> emit,
  ) async {
    try {
      emit(TranslationInProgress(
        completed: 0,
        total: event.segments.length,
        statusMessage: 'Initializing translation...',
      ));

      // Configure the provider
      _translationService.configure(event.config);

      // Run translation with progress updates
      final translatedSegments = await _translationService.translateAll(
        segments: event.segments,
        config: event.config,
        onProgress: (completed, total, partials) {
          if (!emit.isDone) {
            emit(TranslationInProgress(
              completed: completed,
              total: total,
              partialSegments: partials,
              statusMessage:
                  'Translating subtitles ($completed/$total)...',
            ));
          }
        },
      );

      emit(TranslationComplete(
        translatedSegments: translatedSegments,
        config: event.config,
      ));
    } catch (e) {
      emit(TranslationError(message: e.toString()));
    }
  }

  void _onReset(
    ResetTranslation event,
    Emitter<TranslationState> emit,
  ) {
    _translationService.reset();
    emit(const TranslationInitial());
  }

  @override
  Future<void> close() {
    _translationService.dispose();
    return super.close();
  }
}
