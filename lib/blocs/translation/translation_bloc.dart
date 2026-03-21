import 'package:flutter_bloc/flutter_bloc.dart';
import '../../services/translation/translation_provider.dart';
import '../../services/translation/translation_service.dart';
import 'translation_event.dart';
import 'translation_state.dart';

/// BLoC managing the subtitle translation workflow.
class TranslationBloc extends Bloc<TranslationEvent, TranslationState> {
  final TranslationService _translationService;

  TranslationBloc({TranslationService? translationService})
    : _translationService = translationService ?? TranslationService(),
      super(const TranslationInitial()) {
    on<StartTranslation>(_onStartTranslation);
    on<CancelTranslation>(_onCancelTranslation);
    on<ResetTranslation>(_onReset);
  }

  Future<void> _onStartTranslation(
    StartTranslation event,
    Emitter<TranslationState> emit,
  ) async {
    var latestPartials = event.segments;

    try {
      emit(
        TranslationInProgress(
          completed: 0,
          total: event.segments.length,
          partialSegments: latestPartials,
          statusMessage: 'Initializing translation...',
        ),
      );

      // Configure the provider
      _translationService.configure(event.config);

      // Run translation with progress updates
      final translatedSegments = await _translationService.translateAll(
        segments: event.segments,
        config: event.config,
        onProgress: (completed, total, partials) {
          latestPartials = partials;
          if (!emit.isDone) {
            emit(
              TranslationInProgress(
                completed: completed,
                total: total,
                partialSegments: partials,
                statusMessage: 'Translating subtitles ($completed/$total)...',
              ),
            );
          }
        },
      );

      emit(
        TranslationComplete(
          translatedSegments: translatedSegments,
          config: event.config,
        ),
      );
    } on TranslationAbortedException catch (e) {
      if (!emit.isDone) {
        emit(
          TranslationCancelled(
            message: e.message,
            partialSegments: latestPartials,
            config: event.config,
          ),
        );
      }
    } catch (e) {
      if (!emit.isDone) {
        emit(
          TranslationError(
            message: e.toString(),
            partialSegments: latestPartials,
            config: event.config,
          ),
        );
      }
    }
  }

  void _onCancelTranslation(
    CancelTranslation event,
    Emitter<TranslationState> emit,
  ) {
    if (state is TranslationInProgress) {
      _translationService.cancel();
    }
  }

  void _onReset(ResetTranslation event, Emitter<TranslationState> emit) {
    _translationService.reset();
    emit(const TranslationInitial());
  }

  @override
  Future<void> close() {
    _translationService.dispose();
    return super.close();
  }
}
