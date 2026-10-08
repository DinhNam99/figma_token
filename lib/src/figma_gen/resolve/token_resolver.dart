import '../classify.dart';
import '../model/raw_models.dart';
import '../model/resolved_value.dart';
import 'alias_resolver.dart';

/// A classified token whose per-mode values were resolved to concrete values.
class ResolvedToken {
  const ResolvedToken({
    required this.classified,
    required this.collectionName,
    required this.modeNames,
    required this.defaultModeName,
    required this.valuesByMode,
  });

  final ClassifiedToken classified;
  final String collectionName;

  /// Mode names of the token's own collection, in Figma order.
  final List<String> modeNames;
  final String defaultModeName;

  /// `modeName -> concrete value`. Tokens that come from a single-mode
  /// collection only have one entry.
  final Map<String, ResolvedValue> valuesByMode;

  bool get isMultiMode => modeNames.length > 1;

  RawVariable get variable => classified.variable;
  List<String> get path => classified.path;
  String get pathString => classified.pathString;
  TokenCategory get category => classified.category;

  ResolvedValue? valueFor(String mode) => valuesByMode[mode] ?? defaultValue;

  ResolvedValue? get defaultValue =>
      valuesByMode[defaultModeName] ??
      (valuesByMode.isEmpty ? null : valuesByMode.values.first);
}

/// Runs [AliasResolver] over every classified token, collecting warnings
/// instead of failing the whole run.
///
/// Tokens for which *no* mode resolves are dropped; tokens with a partially
/// resolved set of modes are kept and fall back to their default mode when a
/// requested mode is missing.
class TokenResolver {
  TokenResolver(this.document, this.aliasResolver);

  final RawVariablesDocument document;
  final AliasResolver aliasResolver;

  final List<String> warnings = [];

  List<ResolvedToken> resolveAll(List<ClassifiedToken> tokens) {
    final result = <ResolvedToken>[];
    for (final token in tokens) {
      final resolved = resolve(token);
      if (resolved != null) result.add(resolved);
    }
    return result;
  }

  ResolvedToken? resolve(ClassifiedToken token) {
    final variable = token.variable;
    final collection = document.collections[variable.variableCollectionId];
    if (collection == null) {
      warnings.add(
        'Skipped "${variable.name}": unknown collection '
        '"${variable.variableCollectionId}".',
      );
      return null;
    }

    final modeNames = collection.modes.map((m) => m.name).toList();
    final values = <String, ResolvedValue>{};
    for (final mode in collection.modes) {
      try {
        final value = aliasResolver.resolve(variable.id, mode.modeId);
        values[mode.name] = value;
      } on AliasResolutionException catch (error) {
        warnings.add(
          'Mode "${mode.name}" of "${variable.name}": ${error.message}',
        );
      }
    }

    if (values.isEmpty) {
      warnings.add('Skipped "${variable.name}": no mode could be resolved.');
      return null;
    }

    return ResolvedToken(
      classified: token,
      collectionName: collection.name,
      modeNames: modeNames,
      defaultModeName: collection.modeNameOf(collection.defaultModeId),
      valuesByMode: values,
    );
  }
}
