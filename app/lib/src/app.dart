import 'dart:io';

import 'package:flutter/material.dart';

import 'recording/audio_input.dart';
import 'recording/screen_source.dart';
import 'storage/script_store.dart';
import 'theme/theme.dart';
import 'storage/settings.dart';
import 'ui/home_screen.dart';

/// The app's shared services, available to every screen through
/// [AppScope.of].
class AppServices {
  AppServices({required this.library, required this.settings, required this.recordingsDir, AudioInputs? audio, ScreenSources? screens})
      : audio = audio ?? AudioInputs.platform(), screens = screens ?? ScreenSources.platform();

  final ScriptLibrary library;
  final Settings settings;

  /// Microphones: listing, choosing and levels (Windows for now).
  final AudioInputs audio;

  final ScreenSources screens;

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
