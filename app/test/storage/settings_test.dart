import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:spawnalpha/src/markup/claude_markup_engine.dart';
import 'package:spawnalpha/src/markup/local_markup_engine.dart';
import 'package:spawnalpha/src/markup/openai_compatible_engine.dart';
import 'package:spawnalpha/src/markup/providers.dart';
import 'package:spawnalpha/src/prompter/guide.dart';
import 'package:spawnalpha/src/storage/settings.dart';

void main() {
  late Directory dir;
  setUp(() async => dir = await Directory.systemTemp.createTemp('settings_test'));
  tearDown(() => dir.delete(recursive: true));

  File file() => File('${dir.path}/settings.json');

  test('keeps a key per provider and round-trips the configuration', () async {
    final secrets = MemorySecretStore();
    final settings = Settings(file: file(), secrets: secrets);
    await settings.update((s) => s.provider = MarkupProvider.ollama);
    await settings.setConfig(MarkupProvider.ollama, const ProviderConfig(baseUrl: 'http://192.168.1.20:11434/v1', model: 'qwen3:8b'));
    await settings.setApiKey(MarkupProvider.openAi, ' sk-openai ');
    await settings.setApiKey(MarkupProvider.mistral, 'mistral-key');
    await settings.setApiKey(MarkupProvider.mistral, '');

    expect(secrets.values, {'api_key_openAi': 'sk-openai'});
    expect(file().readAsStringSync(), isNot(contains('sk-openai')), reason: 'keys never go in the file');

    final reloaded = Settings(file: file(), secrets: secrets);
    await reloaded.load();
    expect(reloaded.provider, MarkupProvider.ollama);
    expect(reloaded.configOf(MarkupProvider.ollama).model, 'qwen3:8b');
    expect(reloaded.configOf(MarkupProvider.lmStudio).baseUrl, 'http://localhost:1234/v1');
    expect(reloaded.apiKeyOf(MarkupProvider.openAi), 'sk-openai');
    expect(reloaded.hasApiKey(MarkupProvider.mistral), isFalse);
  });

  test('keeps the prompter preferences, with kinetic text on by default', () async {
    final settings = Settings(file: file(), secrets: MemorySecretStore());
    expect(settings.kinetic, isTrue);
    await settings.update((s) => s
      ..kinetic = false
      ..mirror = true);
    final reloaded = Settings(file: file(), secrets: MemorySecretStore());
    await reloaded.load();
    expect(reloaded.kinetic, isFalse);
    expect(reloaded.mirror, isTrue);
  });

  test('starts with the agreed dot, One phrase and center, preserving saved choices', () async {
    final settings = Settings(file: file(), secrets: MemorySecretStore());
    expect(settings.guide, PrompterGuide.dot);
    expect(settings.motion, PrompterMotion.phrase);
    expect(settings.alignment, PrompterAlignment.center);
    await settings.update((s) => s
      ..guide = PrompterGuide.spotlight
      ..motion = PrompterMotion.smooth);
    final reloaded = Settings(file: file(), secrets: MemorySecretStore());
    await reloaded.load();
    expect(reloaded.guide, PrompterGuide.spotlight);
    expect(reloaded.motion, PrompterMotion.smooth);
  });

  test('reads settings from before providers existed', () async {
    file().writeAsStringSync(jsonEncode({'markupSource': 'claude', 'claudeModel': 'claude-sonnet-5-5'}));
    final secrets = MemorySecretStore()..values['anthropic_api_key'] = 'sk-ant';
    final settings = Settings(file: file(), secrets: secrets);
    await settings.load();
    expect(settings.provider, MarkupProvider.claude);
    expect(settings.configOf(MarkupProvider.claude).model, 'claude-sonnet-5-5');
    expect(settings.apiKeyOf(MarkupProvider.claude), 'sk-ant');
  });

  for (final alignment in PrompterAlignment.values) {
    test('remembers ${alignment.name} text alignment after reopening', () async {
      final settings = Settings(file: file(), secrets: MemorySecretStore());
      await settings.update((s) => s.alignment = alignment);
      final reloaded = Settings(file: file(), secrets: MemorySecretStore());
      await reloaded.load();
      expect(reloaded.alignment, alignment);
    });
  }

  test('old settings get agreed defaults when choices have never been saved', () async {
    await file().writeAsString('{}');
    final settings = Settings(file: file(), secrets: MemorySecretStore());
    await settings.load();
    expect(settings.motion, PrompterMotion.phrase);
    expect(settings.alignment, PrompterAlignment.center);
  });

  test('automatic or unknown alignment retains language-aware layout', () async {
    for (final data in [{'alignment': null, 'motion': 'lineStep'}, {'alignment': 'unknown', 'motion': 'lineStep'}]) {
      await file().writeAsString(jsonEncode(data));
      final settings = Settings(file: file(), secrets: MemorySecretStore());
      await settings.load();
      expect(settings.alignment, isNull);
      expect(PrompterAlignment.resolve(settings.alignment, rtl: false, motion: settings.motion), PrompterAlignment.left);
      expect(PrompterAlignment.resolve(settings.alignment, rtl: true, motion: settings.motion), PrompterAlignment.right);
      expect(PrompterAlignment.resolve(settings.alignment, rtl: true, motion: PrompterMotion.phrase), PrompterAlignment.center);
    }
  });

  test('builds the chosen engine, or the on-device one until it is set up', () async {
    final settings = Settings(secrets: MemorySecretStore());
    await settings.update((s) => s.provider = MarkupProvider.claude);
    expect(settings.setupProblemForProvider, contains('API key'));
    expect(settings.engine(), isA<LocalMarkupEngine>());

    await settings.setApiKey(MarkupProvider.claude, 'sk-ant');
    expect(settings.setupProblemForProvider, isNull);
    expect(settings.engine(), isA<ClaudeMarkupEngine>());

    await settings.update((s) => s.provider = MarkupProvider.lmStudio);
    expect(settings.setupProblemForProvider, contains('model'));
    expect(settings.remoteEngine(MarkupProvider.lmStudio), isA<OpenAiCompatibleEngine>(),
        reason: 'models can be listed before one is chosen');
    await settings.setConfig(MarkupProvider.lmStudio, settings.configOf(MarkupProvider.lmStudio).copyWith(model: 'gemma'));
    final engine = settings.engine();
    expect(engine, isA<OpenAiCompatibleEngine>());
    expect((engine as OpenAiCompatibleEngine).isLocal, isTrue);
  });

  group('setupProblem', () {
    test('needs an address, a key where required, and a model', () {
      expect(setupProblem(MarkupProvider.onDevice, ProviderConfig.defaults(MarkupProvider.onDevice), null), isNull);
      expect(setupProblem(MarkupProvider.custom, ProviderConfig.defaults(MarkupProvider.custom), null),
          contains('server address'));
      expect(setupProblem(MarkupProvider.custom, const ProviderConfig(baseUrl: 'not a url', model: 'm'), null),
          contains('server address'));
      expect(setupProblem(MarkupProvider.custom, const ProviderConfig(baseUrl: 'https://openrouter.ai/api/v1', model: 'm'), null),
          isNull, reason: 'a key is optional for custom servers');
      expect(setupProblem(MarkupProvider.gemini, const ProviderConfig(baseUrl: 'https://x.y/v1', model: 'm'), ''),
          contains('API key'));
    });

    test('names a custom server by its host and treats LAN addresses as local', () {
      final engine = buildEngine(
        MarkupProvider.custom,
        const ProviderConfig(baseUrl: 'http://192.168.1.20:8080/v1', model: 'm'),
        null,
      ) as OpenAiCompatibleEngine;
      expect(engine.name, '192.168.1.20');
      expect(engine.isLocal, isTrue);
    });
  });
}
