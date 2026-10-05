import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spawnalpha/src/prompter/marked_text.dart';
import 'package:spawnalpha/src/theme/theme.dart';

import '../../tool/gen_tokens.dart';

void main() {
  test('tokens.g.dart matches docs/design/tokens.json (run dart run tool/gen_tokens.dart)', () {
    final json = jsonDecode(File(tokensPath).readAsStringSync()) as Map<String, dynamic>;
    expect(
      File(outputPath).readAsStringSync(),
      generateTokens(json),
      reason: 'Generated tokens must match exactly, including LF line endings '
          '(enforced by .gitattributes on Windows).',
    );
  });

  test('the generated tokens carry the design values', () {
    expect(SaPalette.light.paper, const Color(0xFFF4F5F7));
    expect(SaPalette.dark.paper, const Color(0xFF0F1115));
    // Stage colours never change with the Studio theme.
    expect(SaPalette.light.stageStress, SaPalette.dark.stageStress);
    expect(SaPalette.light.stageGlass, const Color(0xB816171B));
    expect(SaSprings.pop.stiffness, 380);
    expect(SaScreenFx.zoomLead, const Duration(milliseconds: 300));
    expect(SaPrompter.readingLine, 0.3);
    expect(SaType.display.fontFamily, 'Anybody');
    expect(SaType.display.fontFamilyFallback, ['Reem Kufi']);
    expect(SaType.note.fontFamilyFallback, ['Aref Ruqaa']);
    expect(SaType.stageM.fontSize, 44);
  });

  test('the theme is built from the palette', () {
    for (final (brightness, palette) in [(Brightness.light, SaPalette.light), (Brightness.dark, SaPalette.dark)]) {
      final theme = buildTheme(brightness);
      expect(theme.scaffoldBackgroundColor, palette.paper);
      expect(theme.colorScheme.primary, palette.primary);
      expect(theme.colorScheme.secondary, palette.cue);
      expect(theme.extension<SaTheme>()!.palette, same(palette));
      expect(theme.textTheme.displaySmall!.fontFamily, SaFonts.display);
      expect(theme.textTheme.bodyLarge!.fontFamily, SaFonts.reading);
    }
  });

  test('atWidth keeps the weight when it sets the width', () {
    final s = atWidth(SaType.countdown, 150);
    expect(s.fontVariations, [const ui.FontVariation('wght', 900), const ui.FontVariation('wdth', 150)]);
  });

  test('cue colours: the stage set is theme independent, the Studio set follows the theme', () {
    expect(CueColors.stage.stress, SaPalette.dark.stageStress);
    expect(CueColors.studioLight.stress, SaPalette.light.cueStress);
    expect(CueColors.studioDark.stress, SaPalette.dark.cueStress);
    expect(CueColors.studioLight.tintOf(.faster), SaPalette.light.tintFaster);
  });
}
