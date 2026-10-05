import 'package:flutter_test/flutter_test.dart';
import 'package:spawnalpha/src/recording/screen_source.dart';
import 'package:spawnalpha/src/recording/source_selection.dart';

const display = ScreenSource(id: 'display:main', name: 'Display 1', kind: ScreenSourceKind.display,
  width: 1920, height: 1080, primary: true);
const window = ScreenSource(id: 'window:20:123', name: 'My presentation', kind: ScreenSourceKind.window,
  width: 1280, height: 720);

class FakeScreenSources implements ScreenSources {
  List<ScreenSource> items = [display, window];
  bool fail = false;
  @override
  bool get supported => true;
  @override
  Future<List<ScreenSource>> list() async {
    if (fail) throw StateError('Private window title must not reach the UI');
    return items;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Windows messages preserve Unicode names and reject invalid entries', () async {
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(WindowsScreenSources.channel, (call) async {
      expect(call.method, 'list');
      return [
        for (final (id, name, kind) in [('d', 'Display 1', 'display'), ('f', 'Présentation française', 'window'),
          ('a', 'عرض تقديمي', 'window')])
          {'id': id, 'name': name, 'kind': kind, 'width': 1920, 'height': 1080, 'primary': id == 'd'},
        {'id': 'd', 'name': 'duplicate', 'kind': 'display', 'width': 1920, 'height': 1080},
        {'id': 'bad', 'name': 'closed', 'kind': 'window', 'width': 0, 'height': 0},
        {'id': 'bad', 'name': 'unknown', 'kind': 'other', 'width': 1, 'height': 1},
        null,
      ];
    });
    addTearDown(() => messenger.setMockMethodCallHandler(WindowsScreenSources.channel, null));
    final sources = await const WindowsScreenSources().list();
    expect(sources.map((s) => s.name), ['Display 1', 'Présentation française', 'عرض تقديمي']);
    expect(sources.first.primary, isTrue);
    expect(sources.last.kind, ScreenSourceKind.window);
    expect(() => sources.add(window), throwsUnsupportedError);
  });

  test('selection follows the same window when its title or size changes', () async {
    final backend = FakeScreenSources();
    final selection = SourceSelection(backend);
    addTearDown(selection.dispose);
    await selection.refresh();
    selection.choose(window.id);
    backend.items = [const ScreenSource(id: 'window:20:123', name: 'Renamed', kind: ScreenSourceKind.window,
      width: 900, height: 600)];
    final confirmed = await selection.confirm();
    expect(confirmed!.name, 'Renamed');
    expect(confirmed.width, 900);
  });

  test('a window closed before confirmation cannot be accepted', () async {
    final backend = FakeScreenSources();
    final selection = SourceSelection(backend);
    addTearDown(selection.dispose);
    await selection.refresh();
    selection.choose(window.id);
    backend.items = [display];
    expect(await selection.confirm(), isNull);
    expect(selection.selected, isNull);
    expect(selection.problem, contains('no longer available'));
    selection.choose(display.id);
    expect(await selection.confirm(), display);
  });

  test('errors clear selection, hide private details and allow a retry', () async {
    final backend = FakeScreenSources();
    final selection = SourceSelection(backend);
    addTearDown(selection.dispose);
    await selection.refresh();
    selection.choose(display.id);
    backend.fail = true;
    expect(await selection.confirm(), isNull);
    expect(selection.sources, isEmpty);
    expect(selection.problem, isNot(contains('Private')));
    backend.fail = false;
    await selection.refresh();
    expect(selection.problem, isNull);
    expect(selection.sources, hasLength(2));
  });

  test('no source is picked automatically or carried across picker sessions', () async {
    final selection = SourceSelection(FakeScreenSources());
    addTearDown(selection.dispose);
    await selection.refresh();
    expect(await selection.confirm(), isNull);
    selection.choose('missing');
    expect(selection.selected, isNull);
  });

  test('a refresh finishing after disposal is harmless', () async {
    final selection = SourceSelection(FakeScreenSources());
    final pending = selection.refresh();
    selection.dispose();
    await pending;
  });

  test('other platforms do not offer screen selection yet', () async {
    const backend = UnsupportedScreenSources();
    expect(backend.supported, isFalse);
    expect(await backend.list(), isEmpty);
  });
}
