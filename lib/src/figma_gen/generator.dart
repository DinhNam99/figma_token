import 'builder.dart';
import 'classify.dart';
import 'config.dart';
import 'emit/barrel_emitter.dart';
import 'emit/class_emitter.dart';
import 'emit/theme_emitter.dart';
import 'ir/class_spec.dart';
import 'model/raw_models.dart';
import 'resolve/alias_resolver.dart';
import 'resolve/token_resolver.dart';

/// File names produced by the generator.
const String themeFileName = 'app_theme.g.dart';
const String barrelFileName = 'app_tokens.dart';

/// Everything one generation run produces, plus human readable warnings.
class GenerationResult {
  const GenerationResult({required this.files, required this.warnings});

  final List<GeneratedFile> files;
  final List<String> warnings;
}

/// `Raw JSON -> Parser -> Alias Resolver -> IR -> Dart source`.
///
/// The generator itself performs no I/O: it takes a decoded
/// [RawVariablesDocument] and returns file contents, which keeps it trivially
/// testable (and lets CI run it against a cached fixture).
class TokenGenerator {
  const TokenGenerator();

  GenerationResult generate(
    RawVariablesDocument document,
    FigmaGenConfig config,
  ) {
    final warnings = <String>[];

    // 1. Collection filtering (excluded_collections / included_collections).
    final includedCollectionIds = <String>{};
    for (final collection in document.collections.values) {
      if (config.isCollectionIncluded(collection.name)) {
        includedCollectionIds.add(collection.id);
      } else {
        warnings.add('Skipped collection "${collection.name}" (filtered out).');
      }
    }

    // 2. Classification.
    final classifier = TokenClassifier(config.categoryKeywords);
    final classified = <ClassifiedToken>[];
    for (final variable in document.variables.values) {
      if (!includedCollectionIds.contains(variable.variableCollectionId)) {
        continue;
      }
      final token = classifier.classify(variable);
      if (token == null) {
        warnings.add(
          'Skipped "${variable.name}": unsupported type '
          '${variable.resolvedType}.',
        );
        continue;
      }
      classified.add(token);
    }

    // 3. Alias resolution (cycle + depth safe).
    final resolver = TokenResolver(
      document,
      AliasResolver(document, maxDepth: config.maxAliasDepth),
    );
    final resolved = resolver.resolveAll(classified);
    warnings.addAll(resolver.warnings);

    // 4. IR construction.
    final built = TokenClassBuilder(config).build(resolved);
    warnings.addAll(built.warnings);

    if (built.classes.isEmpty) {
      warnings.add(
        'No tokens were generated — check excluded_collections and the '
        'variable names in your Figma file.',
      );
      return GenerationResult(files: const [], warnings: warnings);
    }

    // 5. Code emission.
    final header = _header(config, document);
    final files = <GeneratedFile>[
      for (final spec in built.classes)
        GeneratedFile(
          relativePath: spec.fileName,
          content: emitClass(spec, header: header),
        ),
      GeneratedFile(
        relativePath: themeFileName,
        content: emitTheme(
          classes: built.classes,
          config: config,
          header: header,
        ),
      ),
      GeneratedFile(
        relativePath: barrelFileName,
        content: emitBarrel(
          classes: built.classes,
          header: header,
          themeFileName: themeFileName,
          includeTheme: true,
        ),
      ),
    ];

    return GenerationResult(files: files, warnings: warnings);
  }

  static String _header(FigmaGenConfig config, RawVariablesDocument document) {
    final source = document.fileKey ?? config.fileKey;
    return '${config.effectiveHeader}'
        '${source == null ? '' : '\n// Source: Figma file `$source`.'}';
  }
}
