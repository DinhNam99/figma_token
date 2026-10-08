/// Identifier sanitization for generated Dart code.
///
/// Figma token names look like `semantic/color/primary`,
/// `Spacing / Medium`, `blue/500`, `H1`, `font-size` — this library turns
/// them into collision-free `lowerCamelCase` / `PascalCase` identifiers and
/// guarantees the results are valid, non-keyword Dart.
library;

/// Words that cannot be used as a Dart identifier (reserved words plus a
/// few contextual ones we avoid to be conservative).
const Set<String> _reserved = {
  'abstract',
  'as',
  'assert',
  'async',
  'await',
  'break',
  'case',
  'catch',
  'class',
  'const',
  'continue',
  'default',
  'deferred',
  'do',
  'dynamic',
  'else',
  'enum',
  'export',
  'extends',
  'extension',
  'external',
  'factory',
  'false',
  'final',
  'finally',
  'for',
  'Function',
  'get',
  'hide',
  'if',
  'implements',
  'import',
  'in',
  'interface',
  'is',
  'late',
  'library',
  'mixin',
  'new',
  'null',
  'on',
  'operator',
  'part',
  'required',
  'rethrow',
  'return',
  'sealed',
  'set',
  'show',
  'static',
  'super',
  'switch',
  'sync',
  'this',
  'throw',
  'true',
  'try',
  'typedef',
  'var',
  'void',
  'when',
  'while',
  'with',
  'yield',
};

/// Splits arbitrary text into lowercase word parts.
///
/// Handles `/`, `-`, `_`, `.`, whitespace, and existing camelCase/PascalCase
/// boundaries: `semantic ColorPrimary` -> `[semantic, color, primary]`.
List<String> wordParts(String input) {
  final parts = <String>[];
  final buffer = StringBuffer();
  var previousWasLowerOrDigit = false;

  for (final rune in input.runes) {
    final char = String.fromCharCode(rune);
    final isSeparator = !RegExp(r'[A-Za-z0-9]').hasMatch(char);
    if (isSeparator) {
      if (buffer.isNotEmpty) {
        parts.add(buffer.toString().toLowerCase());
        buffer.clear();
      }
      previousWasLowerOrDigit = false;
      continue;
    }
    final isUpper = char.toUpperCase() == char && char.toLowerCase() != char;
    if (isUpper && previousWasLowerOrDigit && buffer.isNotEmpty) {
      parts.add(buffer.toString().toLowerCase());
      buffer.clear();
    }
    buffer.write(char);
    previousWasLowerOrDigit = !isUpper;
  }
  if (buffer.isNotEmpty) parts.add(buffer.toString().toLowerCase());
  return parts;
}

/// `blue/500` -> `blue500` (used for names, never for identifiers directly).
String toSnakeCase(String input) => wordParts(input).join('_');

/// `semantic color primary` -> `semanticColorPrimary`.
String toCamelCase(String input) {
  final parts = wordParts(input);
  if (parts.isEmpty) return '';
  return parts.first + parts.skip(1).map(_capitalize).join();
}

/// `semantic color primary` -> `SemanticColorPrimary`.
String toPascalCase(String input) => wordParts(input).map(_capitalize).join();

String _capitalize(String word) =>
    word.isEmpty ? word : word[0].toUpperCase() + word.substring(1);

/// Makes [input] a valid Dart identifier.
///
/// * non-alphanumerics are stripped as word boundaries,
/// * a leading digit gets a `_` prefix,
/// * reserved words get a `_` suffix (`switch` -> `switch_`),
/// * empty input falls back to [fallback].
String safeIdentifier(String input, {String fallback = 'token'}) {
  final camel = toCamelCase(input);
  var result = camel.isEmpty ? fallback : camel;
  if (RegExp(r'^[0-9]').hasMatch(result)) result = '_$result';
  if (_reserved.contains(result) || _reserved.contains(toPascalCase(input))) {
    result = '${result}_';
  }
  return result;
}

/// Returns [candidate] or a variant of it that is not present in [used],
/// adding it to [used] on success.
///
/// Strategy: exact match, then `parentCandidate` (prefixed with [parent]),
/// then numbered suffixes — this keeps `primary` -> `primary` but resolves
/// `color/primary` + `text/primary` -> `primary` + `textPrimary`.
String uniqueIdentifier(
  String candidate, {
  required Set<String> used,
  String? parent,
  String fallback = 'token',
}) {
  var name = candidate.isEmpty ? fallback : candidate;
  if (!used.contains(name)) {
    used.add(name);
    return name;
  }
  if (parent != null && parent.isNotEmpty) {
    final prefixed = safeIdentifier('$parent${toPascalCase(candidate)}');
    if (!used.contains(prefixed)) {
      used.add(prefixed);
      return prefixed;
    }
  }
  var suffix = 2;
  while (used.contains('$name$suffix')) {
    suffix++;
  }
  final unique = '$name$suffix';
  used.add(unique);
  return unique;
}

/// Escapes a value for a single-quoted Dart string literal.
String dartStringLiteral(String value) =>
    "'"
    "${value.replaceAll(r'\', r'\\').replaceAll("'", r"\'").replaceAll(r'$', r'\$')}"
    "'";
