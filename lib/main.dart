import 'dart:io';

import 'package:caption_trans/converter/ffmpeg_macos.dart';
import 'package:caption_trans/converter/ffmpeg_windows.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'blocs/transcription/transcription_bloc.dart';
import 'blocs/translation/translation_bloc.dart';
import 'blocs/project/project_bloc.dart';
import 'blocs/project/project_event.dart';
import 'package:caption_trans/l10n/app_localizations.dart';
import 'services/settings_service.dart';
import 'ui/home_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settingsService = await SettingsService.init();

  // Register FFmpeg converter for automatic video/audio format conversion.
  // This uses the ffmpeg_kit library internally (no subprocess),
  // so it works within the macOS sandbox.
  if (Platform.isMacOS) {
    FFmpegMacOsConverter.register();
  } else if (Platform.isWindows) {
    FFmpegWindowsConverter.register();
  }

  runApp(CaptionTransApp(settingsService: settingsService));
}

class CaptionTransApp extends StatefulWidget {
  final SettingsService settingsService;

  const CaptionTransApp({super.key, required this.settingsService});

  @override
  State<CaptionTransApp> createState() => _CaptionTransAppState();
}

class _CaptionTransAppState extends State<CaptionTransApp> {
  Locale _locale = const Locale('zh');

  void _setLocale(Locale locale) {
    setState(() => _locale = locale);
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(create: (_) => ProjectBloc()..add(const LoadProjects())),
        BlocProvider(create: (_) => TranscriptionBloc()),
        BlocProvider(create: (_) => TranslationBloc()),
      ],
      child: MaterialApp(
        title: 'Caption Trans',
        debugShowCheckedModeBanner: false,
        locale: _locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: _buildDarkTheme(),
        home: HomePage(
          onLocaleChanged: _setLocale,
          settingsService: widget.settingsService,
        ),
      ),
    );
  }

  ThemeData _buildDarkTheme() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF6C63FF),
      brightness: Brightness.dark,
      surface: const Color(0xFF1A1A2E),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: const Color(0xFF0F0F1A),
      cardTheme: CardThemeData(
        color: const Color(0xFF1A1A2E),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.05),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colorScheme.primary),
        ),
      ),
    );
  }
}
