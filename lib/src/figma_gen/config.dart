import 'dart:io';

import 'package:yaml/yaml.dart';

/// Thrown when `figma_config.yaml` (or CLI overrides) are invalid.
class ConfigException implements Exception {
  const ConfigException(this.message);

  final String message;

  @override
  String toString() => 'ConfigException: $message';
}

/// Category keyword sets: a token belongs to the first category (checked in
/// [CategoryKeywords.priority] order) whose keywords appear anywhere in its
/// `/`-separated path.
class CategoryKeywords {
  const CategoryKeywords({
    this.spacing = const [
      'spacing',
      'space',
      'gap',
      'gutter',
      'inset',
      'padding',
      'margin',
    ],
    this.radius = const ['radius', 'corner', 'rounded'],
    this.size = const [
      'size',
      'dimension',
      'width',
      'height',
      'icon',
      'stroke',
      'breathing',
    ],
    this.typography = const [
      'typography',
      'font',
      'font-size',
      'fontsize',
      'line-height',
      'lineheight',
      'letter-spacing',
      'letterspacing',
      'tracking',
      'weight',
      'family',
      'leading',
      'text-style',
      'textstyle',
    ],
    this.shadow = const [
      'shadow',
      'elevation',
      'blur',
      'drop-shadow',
      'dropshadow',
    ],
  });

  final List<String> spacing;
  final List<String> radius;
  final List<String> size;
  final List<String> typography;
  final List<String> shadow;

  /// Most specific category first: `typography/font-size` must not be
  /// swallowed by `size`, `elevation/1/blur` must not become a size.
  List<(String, List<String>)> get priority => [
    ('shadow', shadow),
    ('typography', typography),
    ('spacing', spacing),
    ('radius', radius),
    ('size', size),
  ];

  factory CategoryKeywords.fromYaml(YamlMap? node) {
    if (node == null) return const CategoryKeywords();
    List<String> read(String key, List<String> fallback) {
      final value = node[key];
      if (value is! YamlList) return fallback;
      final items = value
          .map((e) => e.toString().trim().toLowerCase())
          .where((e) => e.isNotEmpty)
          .toList();
      return items.isEmpty ? fallback : items;
    }

    const defaults = CategoryKeywords();
    return CategoryKeywords(
      spacing: read('spacing', defaults.spacing),
      radius: read('radius', defaults.radius),
      size: read('size', defaults.size),
      typography: read('typography', defaults.typography),
      shadow: read('shadow', defaults.shadow),
    );
  }
}

/// Theme brightness <-> Figma mode name mapping used by the generated
/// `AppThemeData`.
class ThemeConfig {
  const ThemeConfig({this.lightMode = 'Light', this.darkMode = 'Dark'});

  final String lightMode;
  final String darkMode;

  factory ThemeConfig.fromYaml(YamlMap? node) {
    if (node == null) return const ThemeConfig();
    return ThemeConfig(
      lightMode: (node['light_mode'] as String?) ?? 'Light',
      darkMode: (node['dark_mode'] as String?) ?? 'Dark',
    );
  }
}

/// Parsed `figma_config.yaml`.
class FigmaGenConfig {
  const FigmaGenConfig({
    this.fileKey,
    this.outputDir = 'lib/generated',
    this.excludedCollections = const [],
    this.includedCollections = const [],
    this.maxAliasDepth = 32,
    this.runFormat = true,
    this.googleFonts = false,
    this.envFile = '.env',
    this.header,
    this.sourceFile,
    this.defaultFontFamily,
    this.categoryKeywords = const CategoryKeywords(),
    this.theme = const ThemeConfig(),
  });

  final String? fileKey;
  final String outputDir;
  final List<String> excludedCollections;

  /// Empty means "all collections".
  final List<String> includedCollections;
  final int maxAliasDepth;
  final bool runFormat;
  final bool googleFonts;
  final String? envFile;
  final String? header;

  /// Optional path to a cached raw API response for offline runs.
  final String? sourceFile;

  /// Fallback `fontFamily` for text styles that do not define one.
  final String? defaultFontFamily;

  final CategoryKeywords categoryKeywords;
  final ThemeConfig theme;

  static const String defaultFilePath = 'figma_config.yaml';

  static const String defaultHeader =
      '// GENERATED CODE - DO NOT MODIFY BY HAND.\n'
      '// Design tokens synced from Figma Variables.';

  String get effectiveHeader => header ?? defaultHeader;

  bool isCollectionIncluded(String name) {
    final normalized = name.trim().toLowerCase();
    if (excludedCollections.any((c) => c.trim().toLowerCase() == normalized)) {
      return false;
    }
    if (includedCollections.isEmpty) return true;
    return includedCollections.any((c) => c.trim().toLowerCase() == normalized);
  }

  /// Loads [path]; a missing file is only an error when [required].
  factory FigmaGenConfig.load(String path, {bool required = true}) {
    final file = File(path);
    if (!file.existsSync()) {
      if (required) {
        throw ConfigException(
          'Config file not found: $path (create it or pass --config <path>).',
        );
      }
      return const FigmaGenConfig();
    }
    return FigmaGenConfig.parse(file.readAsStringSync(), source: path);
  }

  factory FigmaGenConfig.parse(String yaml, {String source = 'memory'}) {
    final document = loadYaml(yaml);
    if (document == null) return const FigmaGenConfig();
    if (document is! YamlMap) {
      throw ConfigException('$source must contain a YAML mapping.');
    }

    List<String> stringList(String key) {
      final value = document[key];
      if (value is! YamlList) return const [];
      return value.map((e) => e.toString()).toList();
    }

    String? optionalString(String key) {
      final value = document[key];
      if (value == null) return null;
      final text = value.toString().trim();
      return text.isEmpty ? null : text;
    }

    final maxDepth = document['max_alias_depth'];
    final runFormat = document['format'];
    final googleFonts = document['google_fonts'];

    return FigmaGenConfig(
      fileKey: optionalString('file_key'),
      outputDir: optionalString('output_dir') ?? 'lib/generated',
      excludedCollections: stringList('excluded_collections'),
      includedCollections: stringList('included_collections'),
      maxAliasDepth: maxDepth is num ? maxDepth.toInt() : 32,
      runFormat: runFormat is bool ? runFormat : true,
      googleFonts: googleFonts is bool ? googleFonts : false,
      envFile: optionalString('env_file') ?? '.env',
      header: optionalString('header'),
      sourceFile: optionalString('source'),
      defaultFontFamily: optionalString('default_font_family'),
      categoryKeywords: CategoryKeywords.fromYaml(
        document['categories'] as YamlMap?,
      ),
      theme: ThemeConfig.fromYaml(document['theme'] as YamlMap?),
    );
  }

  /// Returns a copy with CLI overrides applied.
  FigmaGenConfig copyWith({
    String? fileKey,
    String? outputDir,
    String? sourceFile,
    bool? runFormat,
  }) {
    return FigmaGenConfig(
      fileKey: fileKey ?? this.fileKey,
      outputDir: outputDir ?? this.outputDir,
      excludedCollections: excludedCollections,
      includedCollections: includedCollections,
      maxAliasDepth: maxAliasDepth,
      runFormat: runFormat ?? this.runFormat,
      googleFonts: googleFonts,
      envFile: envFile,
      header: header,
      sourceFile: sourceFile ?? this.sourceFile,
      defaultFontFamily: defaultFontFamily,
      categoryKeywords: categoryKeywords,
      theme: theme,
    );
  }
}
