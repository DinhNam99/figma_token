/// Intermediate representation of a generated Dart class: a set of fields,
/// each with an expression per Figma mode.
library;

/// One generated member (a color, a `double`, a `TextStyle`, ...).
class FieldSpec {
  const FieldSpec({
    required this.name,
    required this.dartType,
    required this.doc,
    required this.exprByMode,
  });

  /// Dart identifier, already sanitized and de-duplicated.
  final String name;

  /// `Color`, `double`, `TextStyle`, `BoxShadow`, `String`, `bool`.
  final String dartType;

  /// Doc comment lines (without the `///` prefix).
  final List<String> doc;

  /// `Figma mode name -> Dart expression`.
  final Map<String, String> exprByMode;

  /// The expression for [mode], falling back to the token's own value when
  /// it comes from a single-mode collection merged into a multi-mode class.
  String exprFor(String mode) {
    final direct = exprByMode[mode];
    if (direct != null) return direct;
    if (exprByMode.isEmpty) {
      return "throw StateError('no value generated for ${r'$'}name')";
    }
    return exprByMode.values.first;
  }
}

/// One generated file-level class.
class ClassSpec {
  ClassSpec({
    required this.className,
    required this.fileName,
    required this.doc,
    required this.fields,
    required this.modeNames,
    required this.themeExtension,
    required this.usesFlutter,
    this.constSafe = true,
  });

  final String className;

  /// e.g. `app_colors.g.dart` (relative to the output directory).
  final String fileName;

  /// Doc comment lines for the class itself.
  final List<String> doc;

  final List<FieldSpec> fields;

  /// Figma mode names this class is emitted for (empty for plain constant
  /// classes).
  final List<String> modeNames;

  /// `true` when the class extends `ThemeExtension<T>`.
  final bool themeExtension;

  /// `true` when the emitted file must import `package:flutter/material.dart`.
  final bool usesFlutter;

  /// `false` when at least one expression is not a compile-time constant
  /// (e.g. `GoogleFonts.getFont(...)`), forcing `static final` members.
  final bool constSafe;

  /// A light/default mode getter name, used as fallback in context
  /// extensions. `null` for constant classes.
  String? get defaultGetter => getterNames.isEmpty ? null : getterNames.first;

  List<String>? _getterNamesCache;

  List<String> get getterNames => _getterNamesCache ??= _buildGetterNames();

  /// Static getter exposing the values of Figma [mode].
  String getterFor(String mode) {
    final index = modeNames.indexOf(mode);
    if (index >= 0 && index < getterNames.length) return getterNames[index];
    return defaultGetter ?? '';
  }

  List<String> _buildGetterNames() {
    final used = <String>{className, 'fromMode', 'copyWith', 'lerp'};
    for (final field in fields) {
      used.add(field.name);
    }
    return [for (final mode in modeNames) _unique(mode, used)];
  }

  static String _unique(String mode, Set<String> used) {
    var candidate = _camel(mode);
    if (candidate.isEmpty) candidate = 'mode';
    if (RegExp(r'^[0-9]').hasMatch(candidate)) candidate = '_$candidate';
    var result = candidate;
    var suffix = 2;
    while (used.contains(result)) {
      result = '$candidate$suffix';
      suffix++;
    }
    used.add(result);
    return result;
  }

  static String _camel(String input) {
    final words = input
        .split(RegExp(r'[^A-Za-z0-9]+'))
        .where((word) => word.isNotEmpty)
        .toList();
    if (words.isEmpty) return '';
    final first = words.first.toLowerCase();
    final rest = words.skip(1).map((word) {
      final lower = word.toLowerCase();
      return lower[0].toUpperCase() + lower.substring(1);
    }).join();
    return first + rest;
  }
}

/// Everything one generation run produces.
class GeneratedFile {
  const GeneratedFile({required this.relativePath, required this.content});

  /// Path relative to the configured output directory.
  final String relativePath;
  final String content;
}
