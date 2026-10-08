import 'package:figma_token/src/figma_gen/model/raw_models.dart';
import 'package:figma_token/src/figma_gen/model/resolved_value.dart';
import 'package:figma_token/src/figma_gen/resolve/alias_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

/// Builds a two-collection document:
///   * `Primitives` (single mode `Value`): `blue/500`
///   * `Semantic` (modes `Light`, `Dark`): `primary` -> `blue/500`
RawVariablesDocument _document({
  Map<String, dynamic>? semanticValues,
  bool withCycle = false,
  bool withDeepChain = false,
}) {
  final variables = <String, dynamic>{
    '10:100': {
      'id': '10:100',
      'name': 'blue/500',
      'variableCollectionId': '10:0',
      'resolvedType': 'COLOR',
      'valuesByMode': {
        '10:2': {'r': 0.25, 'g': 0.5, 'b': 0.75, 'a': 1},
      },
    },
    '10:200': {
      'id': '10:200',
      'name': 'primary',
      'variableCollectionId': '10:1',
      'resolvedType': 'COLOR',
      'valuesByMode':
          semanticValues ??
          {
            '10:3': {'type': 'VARIABLE_ALIAS', 'id': '10:100'},
            '10:4': {'type': 'VARIABLE_ALIAS', 'id': '10:100'},
          },
    },
  };

  if (withCycle) {
    variables['10:300'] = {
      'id': '10:300',
      'name': 'a',
      'variableCollectionId': '10:1',
      'resolvedType': 'COLOR',
      'valuesByMode': {
        '10:3': {'type': 'VARIABLE_ALIAS', 'id': '10:301'},
      },
    };
    variables['10:301'] = {
      'id': '10:301',
      'name': 'b',
      'variableCollectionId': '10:1',
      'resolvedType': 'COLOR',
      'valuesByMode': {
        '10:3': {'type': 'VARIABLE_ALIAS', 'id': '10:300'},
      },
    };
  }

  if (withDeepChain) {
    // a0 -> a1 -> ... -> a5 (6 hops).
    for (var i = 0; i < 6; i++) {
      variables['10:4$i'] = {
        'id': '10:4$i',
        'name': 'chain$i',
        'variableCollectionId': '10:1',
        'resolvedType': 'FLOAT',
        'valuesByMode': {
          '10:3': {
            'type': 'VARIABLE_ALIAS',
            'id': i == 5 ? '10:100' : '10:4${i + 1}',
          },
        },
      };
    }
  }

  return RawVariablesDocument.fromJson({
    'meta': {
      'variableCollections': {
        '10:0': {
          'id': '10:0',
          'name': 'Primitives',
          'modes': [
            {'modeId': '10:2', 'name': 'Value'},
          ],
          'defaultModeId': '10:2',
          'variableIds': ['10:100'],
        },
        '10:1': {
          'id': '10:1',
          'name': 'Semantic',
          'modes': [
            {'modeId': '10:3', 'name': 'Light'},
            {'modeId': '10:4', 'name': 'Dark'},
          ],
          'defaultModeId': '10:3',
          'variableIds': ['10:200'],
        },
      },
      'variables': variables,
    },
  });
}

void main() {
  group('AliasResolver', () {
    test('resolves a direct literal value', () {
      final resolver = AliasResolver(_document());
      final value = resolver.resolve('10:100', '10:2');
      expect(value, isA<ColorValue>());
      expect((value as ColorValue).hexLiteral, '0xFF4080BF');
    });

    test('resolves a cross-collection alias chain', () {
      final resolver = AliasResolver(_document());
      // Light mode of `primary` -> primitive blue/500 (single-mode target).
      expect(
        (resolver.resolve('10:200', '10:3') as ColorValue).hexLiteral,
        '0xFF4080BF',
      );
      // Dark mode: the alias lives in the dark mode slot, the target falls
      // back to the primitive collection's default mode.
      expect(
        (resolver.resolve('10:200', '10:4') as ColorValue).hexLiteral,
        '0xFF4080BF',
      );
    });

    test('uses the collection default mode when a mode id is unknown', () {
      final resolver = AliasResolver(_document());
      expect(
        (resolver.resolve('10:100', 'nonexistent-mode') as ColorValue).r,
        closeTo(0.25, 1e-9),
      );
    });

    test('throws on circular references instead of looping forever', () {
      final resolver = AliasResolver(_document(withCycle: true));
      expect(
        () => resolver.resolve('10:300', '10:3'),
        throwsA(
          isA<AliasResolutionException>().having(
            (e) => e.message,
            'message',
            contains('Circular'),
          ),
        ),
      );
    });

    test('respects the max depth limit', () {
      final deep = _document(withDeepChain: true);
      final shallow = AliasResolver(deep, maxDepth: 3);
      expect(
        () => shallow.resolve('10:40', '10:3'),
        throwsA(
          isA<AliasResolutionException>().having(
            (e) => e.message,
            'message',
            contains('deeper than 3'),
          ),
        ),
        reason: 'a 6 hop chain must fail with maxDepth: 3',
      );

      final generous = AliasResolver(deep, maxDepth: 32);
      expect(
        () => generous.resolve('10:40', '10:3'),
        returnsNormally,
        reason: 'the same chain resolves with the default depth limit',
      );
    });

    test('throws for unknown variable ids', () {
      final resolver = AliasResolver(_document());
      expect(
        () => resolver.resolve('nope', '10:2'),
        throwsA(isA<AliasResolutionException>()),
      );
    });

    test('parses FLOAT, STRING and BOOLEAN values', () {
      final document = RawVariablesDocument.fromJson({
        'meta': {
          'variableCollections': {
            '1:0': {
              'id': '1:0',
              'name': 'Scalars',
              'modes': [
                {'modeId': '1:1', 'name': 'Value'},
              ],
              'defaultModeId': '1:1',
              'variableIds': ['a', 'b', 'c'],
            },
          },
          'variables': {
            'a': {
              'id': 'a',
              'name': 'space',
              'variableCollectionId': '1:0',
              'resolvedType': 'FLOAT',
              'valuesByMode': {'1:1': 8},
            },
            'b': {
              'id': 'b',
              'name': 'family',
              'variableCollectionId': '1:0',
              'resolvedType': 'STRING',
              'valuesByMode': {'1:1': 'Inter'},
            },
            'c': {
              'id': 'c',
              'name': 'enabled',
              'variableCollectionId': '1:0',
              'resolvedType': 'BOOLEAN',
              'valuesByMode': {'1:1': true},
            },
          },
        },
      });
      final resolver = AliasResolver(document);
      expect((resolver.resolve('a', '1:1') as NumberValue).literal, '8.0');
      expect((resolver.resolve('b', '1:1') as StringValue).value, 'Inter');
      expect((resolver.resolve('c', '1:1') as BoolValue).value, isTrue);
    });
  });

  group('NumberValue.literal', () {
    test('always renders a Dart double', () {
      expect(const NumberValue(8).literal, '8.0');
      expect(const NumberValue(-0.5).literal, '-0.5');
      expect(const NumberValue(999).literal, '999.0');
      expect(const NumberValue(1.25).literal, '1.25');
    });
  });
}
