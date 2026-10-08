import '../config.dart';
import '../ir/class_spec.dart';
import '../naming.dart';
import 'code_writer.dart';

/// `ColorScheme` parameters we can fill from generated token fields, in
/// declaration order (Flutter's `ColorScheme` roles).
const List<String> _colorSchemeRoles = [
  'primary',
  'onPrimary',
  'primaryContainer',
  'onPrimaryContainer',
  'secondary',
  'onSecondary',
  'secondaryContainer',
  'onSecondaryContainer',
  'tertiary',
  'onTertiary',
  'tertiaryContainer',
  'onTertiaryContainer',
  'error',
  'onError',
  'errorContainer',
  'onErrorContainer',
  'surface',
  'onSurface',
  'surfaceContainerLowest',
  'surfaceContainerLow',
  'surfaceContainer',
  'surfaceContainerHigh',
  'surfaceContainerHighest',
  'surfaceDim',
  'surfaceBright',
  'surfaceVariant',
  'onSurfaceVariant',
  'outline',
  'outlineVariant',
  'shadow',
  'scrim',
  'inverseSurface',
  'inversePrimary',
  'surfaceTint',
];

/// Deprecated `ColorScheme` roles mapped onto their replacements (keys are
/// lowercased token field names), so the generated code stays warning-free on
/// current Flutter versions.
const Map<String, String> _legacyRoleMapping = {
  'background': 'surface',
  'onbackground': 'onSurface',
  'surfacevariant': 'surfaceContainerHighest',
  'onsurfacevariant': 'onSurfaceContainerHighest',
};

/// Emits `app_theme.g.dart`: `ThemeData` factories for every Figma mode plus
/// `BuildContext` extensions for reading `ThemeExtension`s.
String emitTheme({
  required List<ClassSpec> classes,
  required FigmaGenConfig config,
  required String header,
}) {
  final extensions = classes.where((spec) => spec.themeExtension).toList();
  final lightMode = config.theme.lightMode;
  final darkMode = config.theme.darkMode;
  final lightArgs = _schemeArgs(classes, lightMode, isDark: false);
  final darkArgs = _schemeArgs(classes, darkMode, isDark: true);

  // Only import what the file actually references (analyzer-clean output).
  final referenced = <String>{for (final spec in extensions) spec.className};
  for (final expr in [...lightArgs.values, ...darkArgs.values]) {
    referenced.add(expr.split('.').first);
  }

  final writer = CodeWriter();
  writer.lines(header.split('\n'));
  writer.line();
  writer.line("import 'package:flutter/material.dart';");
  for (final spec in classes) {
    if (!referenced.contains(spec.className)) continue;
    writer.line("import '${spec.fileName}';");
  }
  writer.line();

  final constExtensions = extensions.every((spec) => spec.constSafe);

  writer.doc([
    'Theme factories wired to the generated design tokens.',
    '',
    '`AppThemeData.light()` / `AppThemeData.dark()` map Figma modes',
    '(`${config.theme.lightMode}` / `${config.theme.darkMode}`) onto Flutter\'s',
    'theme system. Widgets must resolve colors through',
    '`Theme.of(context)` (or the `context.appColors` style getters below)',
    'so Light/Dark switching works without rebuilding token files.',
  ]);
  writer.line('abstract final class AppThemeData {');
  writer.block(() {
    writer.line();
    writer.line(
      '/// Theme for the Figma `${_modeFor(extensions, lightMode)}` mode.',
    );
    writer.line('static ThemeData light() => _build(');
    writer.block(() {
      writer.line('Brightness.light,');
      writer.line('${constExtensions ? 'const ' : ''}[');
      writer.block(() {
        for (final spec in extensions) {
          writer.line(
            '${spec.className}.${spec.getterFor(_modeFor(extensions, lightMode, spec: spec))},',
          );
        }
      });
      writer.line('],');
    });
    writer.line(');');

    writer.line();
    writer.line(
      '/// Theme for the Figma `${_modeFor(extensions, darkMode)}` mode.',
    );
    writer.line('static ThemeData dark() => _build(');
    writer.block(() {
      writer.line('Brightness.dark,');
      writer.line('${constExtensions ? 'const ' : ''}[');
      writer.block(() {
        for (final spec in extensions) {
          writer.line(
            '${spec.className}.${spec.getterFor(_modeFor(extensions, darkMode, isDark: true, spec: spec))},',
          );
        }
      });
      writer.line('],');
    });
    writer.line(');');

    writer.line();
    writer.line('static ThemeData _build(');
    writer.block(() {
      writer.line('Brightness brightness,');
      writer.line('List<ThemeExtension<dynamic>> extensions,');
    });
    writer.line(') {');
    writer.block(() {
      final hasScheme = lightArgs.isNotEmpty || darkArgs.isNotEmpty;
      if (hasScheme) {
        writer.line('final colorScheme = brightness == Brightness.light');
        writer.line('    ? ${_schemeCtor('light', lightArgs)}');
        writer.line('    : ${_schemeCtor('dark', darkArgs)};');
        writer.line();
        writer.line('return ThemeData(');
        writer.block(() {
          writer.line('useMaterial3: true,');
          writer.line('colorScheme: colorScheme,');
          writer.line('extensions: extensions,');
        });
        writer.line(');');
      } else {
        writer.line('return ThemeData(');
        writer.block(() {
          writer.line('useMaterial3: true,');
          writer.line('brightness: brightness,');
          writer.line('extensions: extensions,');
        });
        writer.line(');');
      }
    });
    writer.line('}');
  });
  writer.line('}');
  writer.line();

  for (final spec in extensions) {
    final mode = _modeFor(extensions, lightMode, spec: spec);
    final fallback = spec.getterFor(mode);
    writer.doc(['Mode aware `${spec.className}` for the current theme.']);
    writer.line('extension ${spec.className}Context on BuildContext {');
    writer.block(() {
      writer.line('${spec.className} get ${toCamelCase(spec.className)} =>');
      writer.block(() {
        writer.line(
          'Theme.of(this).extension<${spec.className}>() ?? '
          '${spec.className}.$fallback;',
        );
      });
    });
    writer.line('}');
    writer.line();
  }

  return writer.toString();
}

/// Picks the Figma mode name closest to [configured] for [spec].
String _modeFor(
  List<ClassSpec> extensions,
  String configured, {
  bool isDark = false,
  ClassSpec? spec,
}) {
  final modes =
      spec?.modeNames ??
      (extensions.isEmpty ? const <String>[] : extensions.first.modeNames);
  if (modes.isEmpty) return configured;
  final lower = configured.trim().toLowerCase();
  for (final mode in modes) {
    if (mode.trim().toLowerCase() == lower) return mode;
  }
  if (isDark && modes.length > 1) return modes.last;
  return modes.first;
}

/// Token expressions per `ColorScheme` role for one brightness.
Map<String, String> _schemeArgs(
  List<ClassSpec> classes,
  String configuredMode, {
  required bool isDark,
}) {
  final byRole = <String, String>{};
  final legacyByRole = <String, String>{};

  void collect(ClassSpec spec, String? qualifier) {
    for (final field in spec.fields) {
      if (field.dartType != 'Color') continue;
      final base = qualifier == null
          ? '${spec.className}.${field.name}'
          : '$qualifier.${field.name}';
      final exact = _exactRoleOf(field.name);
      if (exact != null) {
        byRole.putIfAbsent(exact, () => base);
        continue;
      }
      final legacy = _legacyRoleMapping[field.name.toLowerCase()];
      if (legacy != null) {
        legacyByRole.putIfAbsent(legacy, () => base);
      }
    }
  }

  // Semantic (mode dependent) tokens win over primitives.
  for (final spec in classes.where((s) => s.themeExtension)) {
    final getter = spec.getterFor(
      _modeFor(classes, configuredMode, isDark: isDark, spec: spec),
    );
    collect(spec, '${spec.className}.$getter');
  }
  // Then plain constant color classes such as `AppPalette`.
  for (final spec in classes.where((s) => !s.themeExtension)) {
    collect(spec, null);
  }

  final result = <String, String>{};
  for (final role in _colorSchemeRoles) {
    final value = byRole[role] ?? legacyByRole[role];
    if (value != null) result[role] = value;
  }
  return result;
}

String? _exactRoleOf(String fieldName) {
  final lower = fieldName.toLowerCase();
  for (final role in _colorSchemeRoles) {
    if (role.toLowerCase() == lower) return role;
  }
  return null;
}

String _schemeCtor(String kind, Map<String, String> args) {
  if (args.isEmpty) {
    return 'ColorScheme.$kind()';
  }
  final entries = [
    for (final entry in args.entries) '${entry.key}: ${entry.value},',
  ].join(' ');
  // Not `const`: tokens are read through static getters
  // (`AppColors.light.primary`), which are not constant expressions.
  return 'ColorScheme.$kind($entries)';
}
