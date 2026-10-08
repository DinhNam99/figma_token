import 'config.dart';
import 'model/raw_models.dart';
import 'naming.dart';

/// The generated-code category a token belongs to.
enum TokenCategory {
  color,
  spacing,
  radius,
  size,
  typography,
  shadow,
  string,
  boolean,
}

/// A token plus its `/`-separated name path and assigned category.
class ClassifiedToken {
  const ClassifiedToken({
    required this.variable,
    required this.category,
    required this.path,
  });

  final RawVariable variable;
  final TokenCategory category;
  final List<String> path;

  /// `['semantic', 'color', 'primary']`.
  String get pathString => path.join('/');
}

/// Assigns every Figma variable to a token category.
///
/// Matching is done on the whole `/`-separated path (normalized to
/// lowercase alphanumeric) using [CategoryKeywords.priority], so
/// `typography/heading/h1/font-size` lands in `typography` (checked before
/// `size`) and `elevation/1/blur` lands in `shadow`.
///
/// `COLOR` tokens that share a path with an existing typography group
/// (e.g. `typography/heading/h1/color`) are re-classified later by the
/// typography builder so that a plain `text/primary` color stays a color.
class TokenClassifier {
  TokenClassifier(this.keywords);

  final CategoryKeywords keywords;

  /// Splits and cleans a Figma variable name.
  static List<String> pathOf(String name) => name
      .split('/')
      .map((segment) => segment.trim())
      .where((segment) => segment.isNotEmpty)
      .toList();

  ClassifiedToken? classify(RawVariable variable) {
    if (!variable.isSupported) return null;
    final path = pathOf(variable.name);
    if (path.isEmpty) return null;

    switch (variable.resolvedType) {
      case 'COLOR':
        if (_matches(path, keywords.shadow)) {
          return _token(variable, path, TokenCategory.shadow);
        }
        return _token(variable, path, TokenCategory.color);
      case 'STRING':
        if (_matches(path, keywords.shadow)) {
          return _token(variable, path, TokenCategory.shadow);
        }
        // Strings only join a text style when they name a known property
        // (`font/family`, `typography/body/weight`, ...). Anything else stays
        // a plain string token instead of being dropped as an unknown part.
        if (_textProps.contains(_normalize(path.last))) {
          return _token(variable, path, TokenCategory.typography);
        }
        return _token(variable, path, TokenCategory.string);
      case 'BOOLEAN':
        return _token(variable, path, TokenCategory.boolean);
      case 'FLOAT':
        // Shadow -> typography -> spacing -> radius -> size (most specific
        // category wins; see CategoryKeywords.priority).
        for (final (name, list) in keywords.priority) {
          if (_matches(path, list)) {
            return _token(variable, path, switch (name) {
              'shadow' => TokenCategory.shadow,
              'typography' => TokenCategory.typography,
              'spacing' => TokenCategory.spacing,
              'radius' => TokenCategory.radius,
              _ => TokenCategory.size,
            });
          }
        }
        return _token(variable, path, TokenCategory.size);
      default:
        return null;
    }
  }

  ClassifiedToken _token(
    RawVariable variable,
    List<String> path,
    TokenCategory category,
  ) => ClassifiedToken(variable: variable, category: category, path: path);

  static String _normalize(String input) =>
      toSnakeCase(input).replaceAll('_', '');

  /// Leaf segments that make a `STRING` variable part of a text style
  /// (kept in sync with `_textProp` in the builder).
  static const Set<String> _textProps = {
    'family',
    'fontfamily',
    'font',
    'typeface',
    'style',
    'fontstyle',
    'decoration',
    'textdecoration',
    'weight',
    'fontweight',
  };

  static bool _matches(List<String> path, List<String> keywords) {
    final normalizedPath = path.map(_normalize).toList();
    for (final keyword in keywords) {
      final needle = _normalize(keyword);
      if (needle.isEmpty) continue;
      for (final segment in normalizedPath) {
        if (segment.contains(needle)) return true;
      }
    }
    return false;
  }
}
