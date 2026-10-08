import 'package:figma_token/src/figma_gen/naming.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('case conversion', () {
    test('splits Figma style paths', () {
      expect(wordParts('semantic/color/primary'), [
        'semantic',
        'color',
        'primary',
      ]);
      expect(toSnakeCase('Font Size'), 'font_size');
      expect(toCamelCase('on-background'), 'onBackground');
      expect(toPascalCase('blue/500'), 'Blue500');
    });

    test('handles camelCase boundaries', () {
      expect(toCamelCase('fontFamily'), 'fontFamily');
      expect(toSnakeCase('letterSpacing'), 'letter_spacing');
    });
  });

  group('safeIdentifier', () {
    test('produces valid identifiers', () {
      expect(safeIdentifier('blue/500'), 'blue500');
      expect(safeIdentifier('on-background'), 'onBackground');
      expect(safeIdentifier('16'), '_16');
      expect(safeIdentifier('my key'), 'myKey');
      expect(safeIdentifier(''), 'token');
    });

    test('escapes Dart keywords', () {
      expect(safeIdentifier('class'), 'class_');
      expect(safeIdentifier('switch'), 'switch_');
      expect(safeIdentifier('default'), 'default_');
      // Not a keyword: kept as is.
      expect(safeIdentifier('surface'), 'surface');
    });
  });

  group('uniqueIdentifier', () {
    late Set<String> used;

    setUp(() => used = {'AppColors', 'copyWith', 'lerp'});

    test('keeps the first occurrence unchanged', () {
      expect(uniqueIdentifier('primary', used: used), 'primary');
    });

    test('prefixes with the parent on collision', () {
      expect(uniqueIdentifier('primary', used: used), 'primary');
      expect(
        uniqueIdentifier('primary', used: used, parent: 'text'),
        'textPrimary',
      );
    });

    test('falls back to a numeric suffix', () {
      expect(uniqueIdentifier('primary', used: used), 'primary');
      expect(
        uniqueIdentifier('primary', used: used, parent: 'text'),
        'textPrimary',
      );
      expect(
        uniqueIdentifier('primary', used: used, parent: 'text'),
        'primary2',
      );
    });

    test('is deterministic', () {
      final first = uniqueIdentifier('onSurface', used: used);
      final second = uniqueIdentifier('onSurface', used: used);
      expect(first, 'onSurface');
      expect(second, 'onSurface2');
    });
  });

  group('dartStringLiteral', () {
    test('escapes quotes, backslashes and dollar signs', () {
      expect(dartStringLiteral('Inter'), "'Inter'");
      expect(dartStringLiteral(r"a'b"), r"'a\'b'");
      expect(dartStringLiteral(r'a\b'), r"'a\\b'");
      expect(dartStringLiteral(r'a$b'), r"'a\$b'");
    });
  });
}
