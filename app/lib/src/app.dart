import 'dart:io';

import 'package:flutter/material.dart';

import 'recording/audio_input.dart';
import 'recording/screen_source.dart';
import 'recording/screen_preview.dart';
import 'recording/floating_prompter.dart';
import 'recording/screen_recording.dart';
import 'recording/recording_inspector.dart';
import 'storage/screen_take_store.dart';
import 'storage/script_store.dart';
import 'theme/theme.dart';
import 'storage/settings.dart';
import 'ui/home_screen.dart';

/// The app's shared services, available to every screen through
/// [AppScope.of].
class AppServices {
  AppServices({required this.library, required this.settings, required this.recordingsDir, AudioInputs? audio, ScreenSources? screens, ScreenPreviews? previews, FloatingPrompters? floating, ScreenRecordings? recorder, RecordingInspector? inspector})
      : audio = audio ?? AudioInputs.platform(), screens = screens ?? ScreenSources.platform(), previews = previews ?? ScreenPreviews.platform(),
        floating = floating ?? FloatingPrompters.platform(), recorder = recorder ?? ScreenRecordings.platform(),
        inspector = inspector ?? RecordingInspector.platform();

  final ScriptLibrary library;
  final Settings settings;

  /// Microphones: listing, choosing and levels (Windows for now).
  final AudioInputs audio;

  final ScreenSources screens;
  final ScreenPreviews previews;
  final FloatingPrompters floating;
  final ScreenRecordings recorder;
  final RecordingInspector inspector;
  late final ScreenTakeStore screenTakes = ScreenTakeStore(recordingsDir, library, inspector);

  /// Where camera takes are saved.
  final Directory recordingsDir;
}

class AppScope extends InheritedWidget {
  const AppScope({super.key, required this.services, required super.child});

  final AppServices services;

  static AppServices of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!.services;

  @override
  bool updateShouldNotify(AppScope old) => old.services != services;
}

class SpawnAlphaApp extends StatelessWidget {
  const SpawnAlphaApp({super.key, required this.services});

  final AppServices services;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      services: services,
      child: MaterialApp(
        title: 'SpawnAlpha',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        home: const HomeScreen(),
      ),
    );
  }
}
