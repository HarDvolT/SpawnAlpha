import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:spawnalpha/src/model/script_document.dart';
import 'package:spawnalpha/src/recording/activity_trace.dart';
import 'package:spawnalpha/src/recording/recording_inspector.dart';
import 'package:spawnalpha/src/recording/screen_recording.dart';
import 'package:spawnalpha/src/storage/script_store.dart';
import 'package:spawnalpha/src/storage/screen_take_store.dart';

Future<void> runGeneratedRecovery(String path) async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(home: SizedBox.shrink()));
  try {
    if (await WindowsScreenRecordings.channel.invokeMethod<bool>(
          'activityFixture',
          const {},
        ) !=
        true) {
      throw StateError('Generated recovery requires the fixture binary');
    }
    final root = await Directory('build/screen-ui-fixtures')
        .resolveSymbolicLinks();
    final directory = Directory(path);
    final resolved = await directory.resolveSymbolicLinks();
    final expected =
        '$root${Platform.pathSeparator}${directory.uri.pathSegments.where((s) => s.isNotEmpty).last}';
    if (resolved.toLowerCase() != expected.toLowerCase() ||
        !RegExp(r'^[0-9]+$').hasMatch(
          directory.uri.pathSegments.where((s) => s.isNotEmpty).last,
        )) {
      throw StateError('Recovery must stay in the generated fixture folder');
    }
    final manifests = await directory
        .list(followLinks: false)
        .where((f) => f is File && f.path.endsWith('.json'))
        .toList();
    if (manifests.length != 1) throw StateError('Generated manifest missing');
    final metadata =
        jsonDecode(await File(manifests.single.path).readAsString()) as Map;
    if (metadata['state'] != 'pending' || metadata['recordActivity'] != true) {
      throw StateError('No interrupted opted-in fixture take');
    }
    final script = ScriptDocument.fromJson(
      Map<String, Object?>.from(metadata['script'] as Map),
    );
    final library = ScriptLibrary(MemoryScriptStore());
    await library.save(script);
    final store = ScreenTakeStore(
      directory,
      library,
      const WindowsRecordingInspector(),
    );
    if (await store.recover() != 1) throw StateError('Video recovery failed');
    final take = library.scripts.single.takes.single;
    final activity = await inspectActivity(
      File(take.activityPath!),
      limit: take.duration,
    );
    if (!take.recovered ||
        take.duration.inSeconds < 2 ||
        activity.complete ||
        activity.events < 120 ||
        activity.durationUs > take.duration.inMicroseconds ||
        await store.recover() != 0 ||
        library.scripts.single.takes.length != 1) {
      throw StateError('Partial activity recovery mismatch');
    }
    library.dispose();
    debugPrint(
      'Native abrupt-exit recovery check passed: real fragmented video and flushed timing-only activity recovered once, no overwrite.',
    );
  } on Object {
    debugPrint('Native abrupt-exit recovery check failed.');
  }
  await SystemNavigator.pop();
}
