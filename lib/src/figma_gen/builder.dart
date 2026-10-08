import 'classify.dart';
import 'config.dart';
import 'ir/class_spec.dart';
import 'model/resolved_value.dart';
import 'naming.dart';
import 'resolve/token_resolver.dart';

/// Result of turning resolved tokens into class-level IR.
class ClassBuildResult {
  const ClassBuildResult({required this.classes, required this.warnings});

  final List<ClassSpec> classes;
  final List<String> warnings;
}

/// Builds `ClassSpec`s (and the `FieldSpec`s inside them) from resolved
/// tokens: simple scalar categories, grouped `TextStyle`s and grouped
/// `BoxShadow`s.
class TokenClassBuilder {
  TokenClassBuilder(this.config);

  final FigmaGenConfig config;

  List<String> _warnings = [];

  static const List<(TokenCategory, String, String)> _simpleCategories = [
    (TokenCategory.spacing, 'AppSpacing', 'app_spacing.g.dart'),
    (TokenCategory.radius, 'AppRadius', 'app_radius.g.dart'),
    (TokenCategory.size, 'AppSizes', 'app_sizes.g.dart'),
    (TokenCategory.string, 'AppStrings', 'app_strings.g.dart'),
    (TokenCategory.boolean, 'AppBooleans', 'app_booleans.g.dart'),
  ];

  ClassBuildResult build(List<ResolvedToken> tokens) {
    _warnings = [];
    final sorted = [...tokens]
      ..sort(
        (a, b) =>
            a.pathString.toLowerCase().compareTo(b.pathString.toLowerCase()),
      );

    final typographyGroups = _groupTypography(
      sorted.where((t) => t.category == TokenCategory.typography).toList(),
    );

    final colorTokens = <ResolvedToken>[];
    for (final token in sorted.where(
      (t) => t.category == TokenCategory.color,
    )) {
      if (_absorbColor(typographyGroups, token)) continue;
      colorTokens.add(token);
    }

    final classes = <ClassSpec>[];

    final paletteTokens = colorTokens.where((t) => !t.isMultiMode).toList();
    if (paletteTokens.isNotEmpty) {
      _add(
        classes,
        _simpleClass(
          className: 'AppPalette',
          fileName: 'app_palette.g.dart',
          category: TokenCategory.color,
          tokens: paletteTokens,
          themeExtension: false,
          doc: const [
            'Primitive colors: one constant per Figma token.',
            '',
            'These values are mode independent, so they are safe to reference',
            'from const contexts.',
          ],
        ),
      );
    }

    final semanticTokens = colorTokens.where((t) => t.isMultiMode).toList();
    if (semanticTokens.isNotEmpty) {
      _add(
        classes,
        _simpleClass(
          className: 'AppColors',
          fileName: 'app_colors.g.dart',
          category: TokenCategory.color,
          tokens: semanticTokens,
          themeExtension: true,
          doc: const [
            'Mode dependent colors, one instance per Figma mode.',
            '',
            'Never read these from a static field: resolve them through',
            '`Theme.of(context).extension<AppColors>()` (or the generated',
            '`context.appColors`) so Light/Dark switching works.',
          ],
        ),
      );
    }

    for (final (category, className, fileName) in _simpleCategories) {
      final categoryTokens = sorted
          .where((t) => t.category == category)
          .toList();
      if (categoryTokens.isEmpty) continue;
      _add(
        classes,
        _simpleClass(
          className: className,
          fileName: fileName,
          category: category,
          tokens: categoryTokens,
          themeExtension: modeUnion(categoryTokens).isNotEmpty,
          doc: [
            'Design tokens generated from Figma '
                '(${category.name} category).',
            if (modeUnion(categoryTokens).isNotEmpty) ...[
              '',
              'Mode dependent: read via `Theme.of(context)`.',
            ],
          ],
        ),
      );
    }

    _add(classes, _typographyClass(typographyGroups));

    final shadowTokens = sorted
        .where((t) => t.category == TokenCategory.shadow)
        .toList();
    _add(classes, _shadowClass(shadowTokens));

    return ClassBuildResult(classes: classes, warnings: [..._warnings]);
  }

  void _add(List<ClassSpec> classes, ClassSpec? spec) {
    if (spec != null) classes.add(spec);
  }

  // ---------------------------------------------------------------------------
  // Mode handling
  // ---------------------------------------------------------------------------

  /// Union of mode names of every *multi-mode* collection contributing to
  /// [tokens]. Single-mode collections are constants and therefore do not
  /// introduce modes. Empty means "emit a plain constant class".
  List<String> modeUnion(List<ResolvedToken> tokens) {
    final sorted = [...tokens]
      ..sort((a, b) => a.collectionName.compareTo(b.collectionName));
    final union = <String>[];
    for (final token in sorted) {
      if (!token.isMultiMode) continue;
      for (final mode in token.modeNames) {
        if (!union.contains(mode)) union.add(mode);
      }
    }
    return union;
  }

  // ---------------------------------------------------------------------------
  // Simple (one field per token) categories
  // ---------------------------------------------------------------------------

  ClassSpec? _simpleClass({
    required String className,
    required String fileName,
    required TokenCategory category,
    required List<ResolvedToken> tokens,
    required bool themeExtension,
    required List<String> doc,
  }) {
    final modes = themeExtension ? modeUnion(tokens) : const <String>[];
    final dartType = _dartTypeFor(category);
    final used = <String>{className, 'fromMode', 'copyWith', 'lerp'};
    final fields = <FieldSpec>[];

    for (final token in tokens) {
      final exprs = <String, String>{};
      for (final entry in token.valuesByMode.entries) {
        final expr = _renderValue(category, entry.value, token);
        if (expr == null) continue;
        exprs[entry.key] = expr;
      }
      if (exprs.isEmpty) continue;
      fields.add(
        FieldSpec(
          name: fieldNameFor(token.path, category, used),
          dartType: dartType,
          doc: docFor(token),
          exprByMode: exprs,
        ),
      );
    }

    if (fields.isEmpty) return null;
    return ClassSpec(
      className: className,
      fileName: fileName,
      doc: doc,
      fields: fields,
      modeNames: modes,
      themeExtension: themeExtension,
      usesFlutter:
          category == TokenCategory.color ||
          category == TokenCategory.typography ||
          category == TokenCategory.shadow ||
          themeExtension,
    );
  }

  String? _renderValue(
    TokenCategory category,
    ResolvedValue value,
    ResolvedToken token,
  ) {
    final expected = _dartTypeFor(category);
    final expr = switch (category) {
      TokenCategory.color => switch (value) {
        ColorValue() => 'Color(${value.hexLiteral})',
        _ => null,
      },
      TokenCategory.spacing ||
      TokenCategory.radius ||
      TokenCategory.size => switch (value) {
        NumberValue() => value.literal,
        _ => null,
      },
      TokenCategory.string => switch (value) {
        StringValue() => dartStringLiteral(value.value),
        _ => null,
      },
      TokenCategory.boolean => switch (value) {
        BoolValue() => '${value.value}',
        _ => null,
      },
      _ => null,
    };
    if (expr == null) {
      _warnings.add(
        'Skipped "${token.pathString}": expected $expected but Figma '
        'returned ${value.runtimeType}.',
      );
    }
    return expr;
  }

  static String _dartTypeFor(TokenCategory category) => switch (category) {
    TokenCategory.color => 'Color',
    TokenCategory.spacing ||
    TokenCategory.radius ||
    TokenCategory.size => 'double',
    TokenCategory.string => 'String',
    TokenCategory.boolean => 'bool',
    TokenCategory.typography => 'TextStyle',
    TokenCategory.shadow => 'BoxShadow',
  };

  // ---------------------------------------------------------------------------
  // Typography
  // ---------------------------------------------------------------------------

  static const Set<String> _colorProps = {
    'color',
    'foreground',
    'fg',
    'tint',
    'oncolor',
  };

  Map<String, _TypographyGroup> _groupTypography(List<ResolvedToken> tokens) {
    final groups = <String, _TypographyGroup>{};
    for (final token in tokens) {
      final prop = _textProp(token.path.last);
      final parent = token.path.sublist(0, token.path.length - 1);
      final key = parent.join('/');
      if (prop == null) {
        _warnings.add(
          'Ignored "${token.pathString}": unknown typography property.',
        );
        continue;
      }
      final group = groups.putIfAbsent(key, () => _TypographyGroup(parent));
      if (group.parts.containsKey(prop)) {
        _warnings.add(
          'Duplicate "$prop" for text style "${group.pathString}": '
          'keeping "${group.parts[prop]!.variable.name}".',
        );
        continue;
      }
      group.parts[prop] = token;
      group.tokens.add(token);
    }
    groups.removeWhere((_, group) => group.parts.isEmpty);
    return groups;
  }

  /// Moves `.../color` color tokens into a matching text style group.
  bool _absorbColor(Map<String, _TypographyGroup> groups, ResolvedToken token) {
    if (token.path.isEmpty) return false;
    final last = _normalizeProp(token.path.last);
    if (!_colorProps.contains(last)) return false;
    final parent = token.path.sublist(0, token.path.length - 1).join('/');
    final group = groups[parent];
    if (group == null) return false;
    group.color = token;
    group.tokens.add(token);
    return true;
  }

  ClassSpec? _typographyClass(Map<String, _TypographyGroup> groups) {
    if (groups.isEmpty) return null;
    final ordered = groups.entries.toList()
      ..sort((a, b) => a.key.toLowerCase().compareTo(b.key.toLowerCase()));

    final allTokens = [for (final entry in ordered) ...entry.value.tokens];
    final modes = modeUnion(allTokens);
    final used = <String>{'AppTypography', 'fromMode', 'copyWith', 'lerp'};
    final fields = <FieldSpec>[];
    var constSafe = true;

    for (final entry in ordered) {
      final group = entry.value;
      final exprs = <String, String>{};
      for (final mode in modes.isEmpty ? const <String>[''] : modes) {
        final expr = _textStyle(group, mode);
        if (expr == null) continue;
        if (expr.contains('GoogleFonts.')) constSafe = false;
        exprs[mode] = expr;
      }
      if (exprs.isEmpty) continue;
      fields.add(
        FieldSpec(
          name: fieldNameFor(group.path, TokenCategory.typography, used),
          dartType: 'TextStyle',
          doc: group.doc,
          exprByMode: exprs,
        ),
      );
    }

    if (fields.isEmpty) return null;
    return ClassSpec(
      className: 'AppTypography',
      fileName: 'app_typography.g.dart',
      doc: [
        'Text styles composed from Figma typography tokens.',
        if (modes.isNotEmpty) ...[
          '',
          'Mode dependent: read via `Theme.of(context).extension<AppTypography>()`.',
        ],
        if (config.googleFonts) ...[
          '',
          'Uses `package:google_fonts` — add it to pubspec.yaml '
              '(`flutter pub add google_fonts`).',
        ],
      ],
      fields: fields,
      modeNames: modes,
      themeExtension: modes.isNotEmpty,
      usesFlutter: true,
      constSafe: constSafe,
    );
  }

  String? _textStyle(_TypographyGroup group, String mode) {
    final family = _stringOf(group, 'family', mode) ?? config.defaultFontFamily;
    final size = _numOf(group, 'fontSize', mode);
    final lineHeight = _numOf(group, 'lineHeight', mode);
    final letterSpacing = _lengthOf(group, 'letterSpacing', mode, size);
    final weight = _fontWeightOf(group, mode);
    final italic = _italic(group, mode);
    final decoration = _decorationOf(group, mode);
    final color = _colorOf(group, mode);

    final props = <String>[];
    if (weight != null) props.add('fontWeight: $weight');
    if (italic) props.add('fontStyle: FontStyle.italic');
    if (size != null && !size.percent) {
      props.add('fontSize: ${NumberValue(size.value).literal}');
    }
    final height = _heightOf(lineHeight, size);
    if (height != null) props.add('height: $height');
    if (letterSpacing != null) {
      props.add('letterSpacing: ${NumberValue(letterSpacing.value).literal}');
    }
    if (decoration != null) props.add('decoration: $decoration');
    if (color != null) props.add('color: Color(${color.hexLiteral})');

    if (family != null && config.googleFonts) {
      final literal = dartStringLiteral(family);
      return props.isEmpty
          ? 'GoogleFonts.getFont($literal)'
          : 'GoogleFonts.getFont($literal, ${props.join(', ')})';
    }
    if (family != null) {
      props.insert(0, 'fontFamily: ${dartStringLiteral(family)}');
    }
    if (props.isEmpty) return null;
    return 'TextStyle(${props.join(', ')})';
  }

  /// `height` (line-height / font-size) as a Dart double literal.
  String? _heightOf(_Length? lineHeight, _Length? fontSize) {
    if (lineHeight == null) return null;
    if (lineHeight.percent) {
      return NumberValue(lineHeight.value / 100).literal;
    }
    if (fontSize == null || fontSize.percent || fontSize.value <= 0) {
      _warnings.add(
        'Line height ignored: a matching font size is required to compute '
        'the `height` ratio.',
      );
      return null;
    }
    return NumberValue(lineHeight.value / fontSize.value).literal;
  }

  String? _fontWeightOf(_TypographyGroup group, String mode) {
    final value = group.parts['weight']?.valueFor(mode);
    if (value is NumberValue) return _weightLiteral(value.value);
    if (value is StringValue) {
      final text = value.value.trim().toLowerCase().replaceAll(' ', '');
      const named = <String, int>{
        'thin': 100,
        'hairline': 100,
        'extralight': 200,
        'ultralight': 200,
        'light': 300,
        'regular': 400,
        'normal': 400,
        'book': 400,
        'medium': 500,
        'semibold': 600,
        'demibold': 600,
        'bold': 700,
        'extrabold': 800,
        'ultrabold': 800,
        'black': 900,
        'heavy': 900,
      };
      final namedWeight = named[text];
      if (namedWeight != null) return _weightLiteral(namedWeight.toDouble());
      final numeric = double.tryParse(text);
      if (numeric != null) return _weightLiteral(numeric);
      _warnings.add(
        'Unknown font weight "${value.value}" in "${group.pathString}"; '
        'ignored.',
      );
    }
    return null;
  }

  static String _weightLiteral(double weight) {
    var normalized = weight;
    if (normalized >= 1 && normalized <= 11) normalized *= 100;
    final hundreds = (normalized / 100).round() * 100;
    final clamped = hundreds.clamp(100, 900);
    return 'FontWeight.w$clamped';
  }

  bool _italic(_TypographyGroup group, String mode) {
    final value = group.parts['style']?.valueFor(mode);
    if (value is! StringValue) return false;
    final text = value.value.trim().toLowerCase();
    return text == 'italic' || text == 'oblique';
  }

  String? _decorationOf(_TypographyGroup group, String mode) {
    final value = group.parts['decoration']?.valueFor(mode);
    if (value is! StringValue) return null;
    return switch (value.value.trim().toLowerCase()) {
      'underline' => 'TextDecoration.underline',
      'overline' => 'TextDecoration.overline',
      'line-through' || 'strikethrough' => 'TextDecoration.lineThrough',
      'none' || '' => null,
      _ => null,
    };
  }

  String? _stringOf(_TypographyGroup group, String prop, String mode) {
    final value = group.parts[prop]?.valueFor(mode);
    if (value is StringValue && value.value.trim().isNotEmpty) {
      return value.value.trim();
    }
    return null;
  }

  _Length? _numOf(_TypographyGroup group, String prop, String mode) =>
      _length(group.parts[prop]?.valueFor(mode));

  _Length? _lengthOf(
    _TypographyGroup group,
    String prop,
    String mode,
    _Length? relativeTo,
  ) {
    final raw = _length(group.parts[prop]?.valueFor(mode));
    if (raw == null) return null;
    if (!raw.percent) return raw;
    if (relativeTo == null || relativeTo.percent) {
      _warnings.add(
        'Percentage "$prop" in "${group.pathString}" ignored: no font size.',
      );
      return null;
    }
    return _Length(relativeTo.value * raw.value / 100, false);
  }

  ColorValue? _colorOf(_TypographyGroup group, String mode) {
    final token = group.color;
    if (token == null) return null;
    final value = token.valueFor(mode);
    if (value is ColorValue) return value;
    _warnings.add('Text color "${token.pathString}" is not a color; ignored.');
    return null;
  }

  static _Length? _length(ResolvedValue? value) {
    if (value is NumberValue) return _Length(value.value, false);
    if (value is StringValue) {
      final text = value.value.trim().toLowerCase();
      if (text.endsWith('%')) {
        final parsed = double.tryParse(
          text.substring(0, text.length - 1).trim(),
        );
        return parsed == null ? null : _Length(parsed, true);
      }
      final parsed = double.tryParse(text.replaceAll('px', '').trim());
      return parsed == null ? null : _Length(parsed, false);
    }
    return null;
  }

  /// `font-size` / `line-height` / `letter-spacing` aliases.
  static String? _textProp(String segment) {
    final normalized = _normalizeProp(segment);
    return switch (normalized) {
      'fontsize' || 'size' || 'pixels' => 'fontSize',
      'lineheight' ||
      'leading' ||
      'linespacing' ||
      'linespacingpx' => 'lineHeight',
      'letterspacing' || 'tracking' || 'letterspace' => 'letterSpacing',
      'weight' || 'fontweight' => 'weight',
      'family' || 'fontfamily' || 'typeface' || 'font' => 'family',
      'style' || 'fontstyle' => 'style',
      'decoration' || 'textdecoration' => 'decoration',
      'color' => 'color',
      _ => null,
    };
  }

  // ---------------------------------------------------------------------------
  // Shadows
  // ---------------------------------------------------------------------------

  ClassSpec? _shadowClass(List<ResolvedToken> tokens) {
    if (tokens.isEmpty) return null;
    final groups = <String, _ShadowGroup>{};
    for (final token in tokens) {
      final prop = _shadowProp(token.path.last);
      final parent = token.path.sublist(0, token.path.length - 1);
      final key = parent.join('/');
      final group = groups.putIfAbsent(key, () => _ShadowGroup(parent));
      group.tokens.add(token);
      if (prop == null) {
        group.fallback ??= token;
        continue;
      }
      if (group.parts.containsKey(prop)) continue;
      group.parts[prop] = token;
    }
    groups.removeWhere(
      (_, group) => group.parts.isEmpty && group.fallback == null,
    );
    if (groups.isEmpty) return null;

    final ordered = groups.entries.toList()
      ..sort((a, b) => a.key.toLowerCase().compareTo(b.key.toLowerCase()));
    final allTokens = [for (final entry in ordered) ...entry.value.tokens];
    final modes = modeUnion(allTokens);
    final used = <String>{'AppShadows', 'fromMode', 'copyWith', 'lerp'};
    final fields = <FieldSpec>[];

    for (final entry in ordered) {
      final group = entry.value;
      final exprs = <String, String>{};
      for (final mode in modes.isEmpty ? const <String>[''] : modes) {
        final expr = _boxShadow(group, mode);
        if (expr != null) exprs[mode] = expr;
      }
      if (exprs.isEmpty) continue;
      fields.add(
        FieldSpec(
          name: fieldNameFor(group.path, TokenCategory.shadow, used),
          dartType: 'BoxShadow',
          doc: group.doc,
          exprByMode: exprs,
        ),
      );
    }

    if (fields.isEmpty) return null;
    return ClassSpec(
      className: 'AppShadows',
      fileName: 'app_shadows.g.dart',
      doc: [
        'Elevation/shadow tokens as `BoxShadow` constants.',
        if (modes.isNotEmpty) ...[
          '',
          'Mode dependent: read via `Theme.of(context).extension<AppShadows>()`.',
        ],
      ],
      fields: fields,
      modeNames: modes,
      themeExtension: modes.isNotEmpty,
      usesFlutter: true,
    );
  }

  static String? _shadowProp(String segment) {
    final normalized = _normalizeProp(segment);
    return switch (normalized) {
      'x' || 'offsetx' || 'xoffset' => 'offsetX',
      'y' || 'offsety' || 'yoffset' => 'offsetY',
      'blur' || 'blurradius' || 'radius' => 'blur',
      'spread' || 'spreadradius' => 'spread',
      'color' => 'color',
      'opacity' => 'opacity',
      _ => null,
    };
  }

  String? _boxShadow(_ShadowGroup group, String mode) {
    if (group.parts.isEmpty) {
      // A lone number (e.g. `elevation/1 = 4`) is treated as the blur radius.
      final value = group.fallback?.valueFor(mode);
      if (value is NumberValue) {
        return 'BoxShadow(color: Color(0xFF000000), '
            'offset: const Offset(0.0, 0.0), '
            'blurRadius: ${value.literal}, '
            'spreadRadius: 0.0)';
      }
      if (group.fallback != null) {
        _warnings.add(
          'Shadow "${group.pathString}" has no usable properties; skipped.',
        );
      }
      return null;
    }

    var color = _colorPart(group, mode) ?? const ColorValue(r: 0, g: 0, b: 0);
    final opacity = group.parts['opacity']?.valueFor(mode);
    if (opacity is NumberValue && opacity.value >= 0 && opacity.value <= 1) {
      color = ColorValue(
        r: color.r,
        g: color.g,
        b: color.b,
        a: color.a * opacity.value,
      );
    }
    final x = _numberPart(group, 'offsetX', mode) ?? 0.0;
    final y = _numberPart(group, 'offsetY', mode) ?? 0.0;
    final blur = _numberPart(group, 'blur', mode) ?? 0.0;
    final spread = _numberPart(group, 'spread', mode) ?? 0.0;

    return 'BoxShadow(color: Color(${color.hexLiteral}), '
        'offset: Offset(${NumberValue(x).literal}, '
        '${NumberValue(y).literal}), '
        'blurRadius: ${NumberValue(blur).literal}, '
        'spreadRadius: ${NumberValue(spread).literal})';
  }

  double? _numberPart(_ShadowGroup group, String prop, String mode) {
    final value = group.parts[prop]?.valueFor(mode);
    if (value is NumberValue) return value.value;
    if (value is StringValue) {
      final parsed = double.tryParse(value.value.trim().replaceAll('px', ''));
      if (parsed != null) return parsed;
    }
    if (value != null) {
      _warnings.add('Shadow "$prop" must be a number; ignored.');
    }
    return null;
  }

  ColorValue? _colorPart(_ShadowGroup group, String mode) {
    final value = group.parts['color']?.valueFor(mode);
    if (value is ColorValue) return value;
    if (value != null) {
      _warnings.add('Shadow color must be a color; ignored.');
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // Shared helpers
  // ---------------------------------------------------------------------------

  /// Leading path segments that are pure grouping noise
  /// (`semantic/color/primary` -> `primary`).
  static const List<String> _stripWords = [
    'primitive',
    'primitives',
    'semantic',
    'semantics',
    'token',
    'tokens',
    'color',
    'colors',
    'palette',
    'value',
    'values',
    'string',
    'strings',
    'boolean',
    'booleans',
  ];

  String fieldNameFor(
    List<String> path,
    TokenCategory category,
    Set<String> used,
  ) {
    final keywords = switch (category) {
      TokenCategory.spacing => config.categoryKeywords.spacing,
      TokenCategory.radius => config.categoryKeywords.radius,
      TokenCategory.size => config.categoryKeywords.size,
      TokenCategory.typography => config.categoryKeywords.typography,
      TokenCategory.shadow => config.categoryKeywords.shadow,
      _ => const <String>[],
    };
    final keywordSet = {
      for (final keyword in keywords) _normalizeProp(keyword),
    };
    final segments = [...path];
    // Drop grouping noise: `semantic/color/primary` -> `primary`.
    while (segments.length > 1 &&
        _stripWords.contains(_normalizeProp(segments.first))) {
      segments.removeAt(0);
    }
    // Then drop exactly one category word: `size/icon/sm` -> `iconSm`,
    // `typography/heading/h1` -> `headingH1`.
    if (segments.length > 1 &&
        keywordSet.contains(_normalizeProp(segments.first))) {
      segments.removeAt(0);
    }

    var candidate = safeIdentifier(segments.join(' '), fallback: 'token');
    if (RegExp(r'^_?[0-9]').hasMatch(candidate) &&
        segments.length != path.length) {
      // `spacing/16` -> `spacing16`, not `_16`.
      candidate = safeIdentifier(path.join(' '), fallback: 'token');
    }
    final parent = segments.length > 1
        ? safeIdentifier(segments.sublist(0, segments.length - 1).join(' '))
        : null;
    return uniqueIdentifier(candidate, used: used, parent: parent);
  }

  List<String> docFor(ResolvedToken token) {
    final description = token.variable.description.trim();
    return [
      '`${token.pathString}` — collection `${token.collectionName}`.',
      if (description.isNotEmpty) ...['', description],
    ];
  }

  static String _normalizeProp(String input) =>
      toSnakeCase(input).replaceAll('_', '');
}

class _TypographyGroup {
  _TypographyGroup(this.path);

  final List<String> path;
  final List<ResolvedToken> tokens = [];
  final Map<String, ResolvedToken> parts = {};
  ResolvedToken? color;

  String get pathString => path.isEmpty ? '(root)' : path.join('/');

  List<String> get doc {
    final description = color?.variable.description.trim() ?? '';
    return [
      'Text style `$pathString`.',
      if (description.isNotEmpty) ...['', description],
    ];
  }
}

class _ShadowGroup {
  _ShadowGroup(this.path);

  final List<String> path;
  final List<ResolvedToken> tokens = [];
  final Map<String, ResolvedToken> parts = {};
  ResolvedToken? fallback;

  String get pathString => path.isEmpty ? '(root)' : path.join('/');

  List<String> get doc => [
    'Shadow `$pathString`.',
    if (fallback?.variable.description.trim().isNotEmpty ?? false) ...[
      '',
      fallback!.variable.description.trim(),
    ],
  ];
}

class _Length {
  const _Length(this.value, this.percent);

  final double value;
  final bool percent;
}
