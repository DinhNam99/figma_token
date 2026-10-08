import 'dart:convert';
import 'dart:io';

import 'package:figma_token/src/figma_gen/classify.dart';
import 'package:figma_token/src/figma_gen/config.dart';
import 'package:figma_token/src/figma_gen/generator.dart';
import 'package:figma_token/src/figma_gen/model/raw_models.dart';
import 'package:flutter_test/flutter_test.dart';

const String _fixturePath = 'tool/fixtures/variables.sample.json';

RawVariablesDocument _loadFixture() => RawVariablesDocument.fromJson(
  jsonDecode(File(_fixturePath).readAsStringSync()) as Map<String, dynamic>,
);

void main() {
  group('TokenClassifier', () {
    late TokenClassifier classifier;

    setUp(() {
      classifier = TokenClassifier(const CategoryKeywords());
    });

    ClassifiedToken classify(String name, String type) => classifier.classify(
      RawVariable(
        id: 'id',
        name: name,
        variableCollectionId: 'c',
        resolvedType: type,
        valuesByMode: const {},
        description: '',
      ),
    )!;

    test('assigns categories by path keyword priority', () {
      expect(classify('color/primary', 'COLOR').category, TokenCategory.color);
      expect(classify('spacing/8', 'FLOAT').category, TokenCategory.spacing);
      expect(classify('radius/sm', 'FLOAT').category, TokenCategory.radius);
      expect(classify('size/icon/sm', 'FLOAT').category, TokenCategory.size);
      expect(
        classify('typography/heading/h1/font-size', 'FLOAT').category,
        TokenCategory.typography,
      );
      expect(classify('shadow/1/blur', 'FLOAT').category, TokenCategory.shadow);
      expect(
        classify('string/app-name', 'STRING').category,
        TokenCategory.string,
      );
      expect(
        classify('feature/enable-beta', 'BOOLEAN').category,
        TokenCategory.boolean,
      );
    });

    test('shadow beats size, typography beats size', () {
      expect(
        classify('elevation/card/blur', 'FLOAT').category,
        TokenCategory.shadow,
      );
      // `font-size` contains "size" but typography is checked first.
      expect(
        classify('typography/body/font-size', 'FLOAT').category,
        TokenCategory.typography,
      );
    });

    test('only known leaves make a STRING part of a text style', () {
      expect(
        classify('typography/body/regular/family', 'STRING').category,
        TokenCategory.typography,
      );
      expect(
        classify('string/app-name', 'STRING').category,
        TokenCategory.string,
      );
    });

    test('keeps the path segments', () {
      expect(classify('color/on-background', 'COLOR').path, [
        'color',
        'on-background',
      ]);
    });
  });

  group('TokenGenerator (end to end on the sample fixture)', () {
    late RawVariablesDocument fixture;
    late GenerationResult result;

    setUpAll(() {
      fixture = _loadFixture();
      result = const TokenGenerator().generate(fixture, const FigmaGenConfig());
    });

    String file(String name) =>
        result.files.firstWhere((f) => f.relativePath == name).content;

    test('produces the expected file set', () {
      expect(result.warnings, isEmpty);
      expect(result.files.map((f) => f.relativePath), [
        'app_palette.g.dart',
        'app_colors.g.dart',
        'app_spacing.g.dart',
        'app_radius.g.dart',
        'app_sizes.g.dart',
        'app_strings.g.dart',
        'app_booleans.g.dart',
        'app_typography.g.dart',
        'app_shadows.g.dart',
        'app_theme.g.dart',
        'app_tokens.dart',
      ]);
    });

    test('primitives become const colors', () {
      final palette = file('app_palette.g.dart');
      expect(palette, contains('abstract final class AppPalette'));
      expect(
        palette,
        contains('static const Color blue500 = Color(0xFF2F6FED);'),
      );
      expect(
        palette,
        contains('static const Color gray950 = Color(0xFF0B1220);'),
      );
    });

    test('mode dependent colors become a ThemeExtension with one instance '
        'per Figma mode', () {
      final colors = file('app_colors.g.dart');
      expect(
        colors,
        contains('class AppColors extends ThemeExtension<AppColors>'),
      );
      expect(colors, contains('static const AppColors light = AppColors('));
      expect(colors, contains('static const AppColors dark = AppColors('));
      expect(colors, contains('primary: Color(0xFF2F6FED),')); // Light
      expect(colors, contains('primary: Color(0xFF4F8CFF),')); // Dark
      expect(colors, contains('background: Color(0xFF0B1220),')); // Dark bg
      expect(colors, contains('static AppColors fromMode(String mode)'));
      expect(colors, contains('AppColors copyWith({'));
      expect(colors, contains('AppColors lerp(AppColors? other, double t)'));
      expect(colors, contains('Color.lerp(primary, other.primary, t)'));
    });

    test('dimension tokens are typed doubles', () {
      final spacing = file('app_spacing.g.dart');
      expect(spacing, contains('static const double spacing4 = 4.0;'));
      expect(spacing, contains('static const double spacing16 = 16.0;'));

      final radius = file('app_radius.g.dart');
      expect(radius, contains('static const double sm = 4.0;'));
      expect(radius, contains('static const double full = 999.0;'));

      final sizes = file('app_sizes.g.dart');
      expect(sizes, contains('static const double iconSm = 16.0;'));
      expect(sizes, contains('static const double iconMd = 24.0;'));
    });

    test('typography is composed from its parts', () {
      final typography = file('app_typography.g.dart');
      expect(typography, contains('static const TextStyle headingH1'));
      expect(typography, contains("fontFamily: 'Inter'"));
      expect(typography, contains('fontWeight: FontWeight.w700'));
      expect(typography, contains('fontSize: 32.0'));
      expect(typography, contains('height: 1.25')); // 40 / 32
      expect(typography, contains('letterSpacing: -0.5'));
      expect(typography, contains('color: Color(0xFF2F6FED)'));
      expect(typography, contains('fontWeight: FontWeight.w400')); // "Regular"
      expect(typography, contains('height: 1.5')); // 24 / 16
    });

    test('shadows are composed into BoxShadow constants', () {
      final shadows = file('app_shadows.g.dart');
      expect(shadows, contains('static const BoxShadow'));
      expect(shadows, contains('offset: Offset(0.0, 2.0)'));
      expect(shadows, contains('blurRadius: 8.0'));
      expect(shadows, contains('color: Color(0x26000000)')); // 15% black
    });

    test('strings and booleans keep their literal types', () {
      expect(file('app_strings.g.dart'), contains("appName: 'Figma Tokens'"));
      expect(file('app_booleans.g.dart'), contains('featureEnableBeta: true'));
    });

    test('the theme file wires modes and BuildContext accessors', () {
      final theme = file('app_theme.g.dart');
      expect(theme, contains('abstract final class AppThemeData'));
      expect(theme, contains('static ThemeData light()'));
      expect(theme, contains('static ThemeData dark()'));
      expect(theme, contains('ColorScheme.light('));
      expect(theme, contains('ColorScheme.dark('));
      expect(theme, contains('extension AppColorsContext on BuildContext'));
      expect(theme, contains('Theme.of(this).extension<AppColors>()'));
    });

    test('the barrel exports every generated file', () {
      final barrel = file('app_tokens.dart');
      for (final generated in result.files) {
        if (generated.relativePath == barrelFileName) continue;
        expect(barrel, contains("export '${generated.relativePath}';"));
      }
    });

    test('never emits unresolved values', () {
      for (final generated in result.files) {
        expect(generated.content, isNot(contains('Instance of')));
        expect(generated.content, isNot(contains(': null')));
        expect(generated.content, isNot(contains('TODO')));
      }
    });

    test('excluded collections are not generated', () {
      final config = FigmaGenConfig.parse('''
excluded_collections:
  - Semantic
''');
      final filtered = const TokenGenerator().generate(fixture, config);
      expect(
        filtered.files.map((f) => f.relativePath),
        isNot(contains('app_colors.g.dart')),
      );
      expect(
        filtered.warnings,
        contains(contains('Skipped collection "Semantic"')),
      );
      // Primitives (colors, spacing, ...) are still generated.
      expect(
        filtered.files.map((f) => f.relativePath),
        contains('app_palette.g.dart'),
      );
    });

    test('generation is deterministic', () {
      final again = const TokenGenerator().generate(
        fixture,
        const FigmaGenConfig(),
      );
      expect(
        again.files.map((f) => f.content).join(),
        result.files.map((f) => f.content).join(),
      );
    });
  });
}
