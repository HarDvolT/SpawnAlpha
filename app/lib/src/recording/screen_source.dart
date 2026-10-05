import 'dart:io';

import 'package:flutter/services.dart';

enum ScreenSourceKind { display, window }

/// A local capture candidate. IDs are opaque: the Windows backend resolves
/// them again before capture. Window titles stay in memory and are never logged.
class ScreenSource {
  const ScreenSource({
    required this.id,
    required this.name,
    required this.kind,
    required this.width,
    required this.height,
    this.primary = false,
  });

  final String id;
  final String name;
  final ScreenSourceKind kind;
  final int width;
  final int height;
  final bool primary;

  static ScreenSource? fromMessage(Object? value) {
    if (value is! Map) return null;
    final id = value['id'];
    final name = value['name'];
    final kind = value['kind'];
    final width = value['width'];
    final height = value['height'];
    if (id is! String ||
        id.isEmpty ||
        name is! String ||
        name.trim().isEmpty ||
        width is! int ||
        height is! int ||
        width <= 0 ||
        height <= 0 ||
        (kind != 'display' && kind != 'window')) {
      return null;
    }
    return ScreenSource(
      id: id,
      name: name,
      kind: kind == 'display' ? ScreenSourceKind.display : ScreenSourceKind.window,
      width: width,
      height: height,
      primary: value['primary'] == true,
    );
  }
}

/// Listing reads names and dimensions only; it does not start capture.
abstract class ScreenSources {
  factory ScreenSources.platform() =>
      Platform.isWindows ? const WindowsScreenSources() : const UnsupportedScreenSources();

  bool get supported;
  Future<List<ScreenSource>> list();
}

class WindowsScreenSources implements ScreenSources {
  const WindowsScreenSources();
  static const channel = MethodChannel('spawnalpha/screen_sources');

  @override
  bool get supported => true;

  @override
  Future<List<ScreenSource>> list() async {
    final rows = await channel.invokeListMethod<Object?>('list') ?? [];
    final sources = rows.map(ScreenSource.fromMessage).whereType<ScreenSource>();
    final seen = <String>{};
    return List.unmodifiable(sources.where((source) => seen.add(source.id)));
  }
}

class UnsupportedScreenSources implements ScreenSources {
  const UnsupportedScreenSources();
  @override
  bool get supported => false;
  @override
  Future<List<ScreenSource>> list() async => const [];
}
