import '../model/raw_models.dart';
import '../model/resolved_value.dart';

/// Thrown when a variable reference chain cannot be resolved to a concrete
/// value: unknown ids, malformed payloads, cycles, or depth overruns.
class AliasResolutionException implements Exception {
  const AliasResolutionException(this.message);

  final String message;

  @override
  String toString() => 'AliasResolutionException: $message';
}

/// Resolves Figma variable references (`VARIABLE_ALIAS`) to concrete values.
///
/// A token such as `semantic.color.primary` typically points at
/// `primitive.color.blue500`; the resolver follows the chain until it reaches
/// a literal RGBA/number/string/bool.
///
/// Safety guarantees:
///  * **Cycle safe** — a visited set stops `a -> b -> a` loops.
///  * **Depth limited** — chains longer than [maxDepth] fail fast.
///  * **Mode aware** — when a chain crosses collections, the requested mode is
///    used if the target collection defines it, otherwise the target
///    collection's default mode is used (which is how Figma resolves aliases
///    across collections that do not share modes).
class AliasResolver {
  AliasResolver(this.document, {this.maxDepth = 32})
    : assert(maxDepth > 0, 'maxDepth must be positive');

  final RawVariablesDocument document;
  final int maxDepth;

  /// Resolves [variableId] for [requestedModeId].
  ///
  /// [chain] is the (internal) list of visited variable names used to build
  /// helpful error messages.
  ResolvedValue resolve(
    String variableId,
    String requestedModeId, {
    Set<String> visited = const {},
    List<String> chain = const [],
    int depth = 0,
  }) {
    if (depth > maxDepth) {
      throw AliasResolutionException(
        'Alias chain deeper than $maxDepth: ${_describe(chain, variableId)}',
      );
    }
    if (visited.contains(variableId)) {
      throw AliasResolutionException(
        'Circular reference: ${_describe(chain, variableId)}',
      );
    }

    final variable = document.variables[variableId];
    if (variable == null) {
      throw AliasResolutionException(
        'Unknown variable id "$variableId" referenced by '
        '${chain.isEmpty ? '<root>' : chain.last}.',
      );
    }

    final collection = document.collections[variable.variableCollectionId];
    final modeId = _effectiveModeId(collection, requestedModeId);

    final raw =
        variable.valuesByMode[modeId] ??
        variable.valuesByMode[collection?.defaultModeId];
    if (raw == null) {
      throw AliasResolutionException(
        'Variable "${variable.name}" has no value for mode "$modeId".',
      );
    }

    if (raw is Map) {
      final map = raw.cast<String, dynamic>();
      if (map['type'] == 'VARIABLE_ALIAS') {
        final target = map['id'] as String?;
        if (target == null) {
          throw AliasResolutionException(
            'Malformed alias in "${variable.name}" (missing "id").',
          );
        }
        return resolve(
          target,
          modeId,
          visited: {...visited, variableId},
          chain: [...chain, variable.name],
          depth: depth + 1,
        );
      }
      if (map.containsKey('r') ||
          map.containsKey('g') ||
          map.containsKey('b')) {
        return ColorValue(
          r: (map['r'] as num? ?? 0).toDouble(),
          g: (map['g'] as num? ?? 0).toDouble(),
          b: (map['b'] as num? ?? 0).toDouble(),
          a: (map['a'] as num? ?? 1).toDouble(),
        );
      }
      throw AliasResolutionException(
        'Unsupported object value for "${variable.name}": '
        '${map.keys.join(', ')}.',
      );
    }
    if (raw is num) return NumberValue(raw.toDouble());
    if (raw is String) return StringValue(raw);
    if (raw is bool) return BoolValue(raw);

    throw AliasResolutionException(
      'Unsupported value of type ${raw.runtimeType} for "${variable.name}".',
    );
  }

  /// Mode of the target collection to read: the requested one when the target
  /// collection declares it, otherwise its default mode.
  String _effectiveModeId(RawCollection? collection, String requestedModeId) {
    if (collection == null) return requestedModeId;
    if (requestedModeId.isNotEmpty &&
        collection.modeById(requestedModeId) != null) {
      return requestedModeId;
    }
    return collection.defaultModeId;
  }

  String _describe(List<String> chain, String lastId) {
    final names = [...chain];
    final variable = document.variables[lastId];
    names.add(variable?.name ?? lastId);
    return names.join(' -> ');
  }
}
