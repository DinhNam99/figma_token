import '../ir/class_spec.dart';
import '../naming.dart';
import 'code_writer.dart';

/// Emits the full source of one generated class file.
String emitClass(ClassSpec spec, {required String header}) {
  final writer = CodeWriter();
  writer.lines(header.split('\n'));
  writer.line();
  if (spec.usesFlutter) {
    writer.line("import 'package:flutter/material.dart';");
    writer.line();
  }
  writer.doc(spec.doc);
  if (spec.themeExtension) {
    writer.line('@immutable');
    writer.line(
      'class ${spec.className} extends ThemeExtension<${spec.className}> {',
    );
  } else {
    writer.line('abstract final class ${spec.className} {');
  }

  writer.block(() {
    if (spec.themeExtension) {
      _constructor(writer, spec);
      for (final field in spec.fields) {
        writer.line();
        writer.doc(field.doc);
        writer.line('final ${field.dartType} ${field.name};');
      }
      _modeGetters(writer, spec);
      _fromMode(writer, spec);
      _copyWith(writer, spec);
      _lerp(writer, spec);
    } else {
      var first = true;
      for (final field in spec.fields) {
        if (!first) writer.line();
        first = false;
        writer.doc(field.doc);
        final keyword = spec.constSafe ? 'const' : 'final';
        writer.line(
          'static $keyword ${field.dartType} ${field.name} = '
          '${field.exprByMode.values.first};',
        );
      }
    }
  });

  writer.line('}');
  writer.line();
  return writer.toString();
}

void _constructor(CodeWriter writer, ClassSpec spec) {
  writer.line();
  final params = spec.fields
      .map((field) => 'required this.${field.name}')
      .join(', ');
  writer.line('const ${spec.className}({$params});');
}

void _modeGetters(CodeWriter writer, ClassSpec spec) {
  if (spec.modeNames.isEmpty) return;
  final keyword = spec.constSafe ? 'const' : 'final';
  for (var index = 0; index < spec.modeNames.length; index++) {
    final mode = spec.modeNames[index];
    final getter = spec.getterNames[index];
    writer.line();
    writer.line('/// Values of the Figma mode `$mode`.');
    writer.line(
      'static $keyword ${spec.className} $getter = ${spec.className}(',
    );
    writer.block(() {
      for (final field in spec.fields) {
        writer.line('${field.name}: ${field.exprFor(mode)},');
      }
    });
    writer.line(');');
  }
}

void _fromMode(CodeWriter writer, ClassSpec spec) {
  if (spec.modeNames.isEmpty) return;
  writer.line();
  writer.line('/// Resolves this extension for a Figma [mode] name.');
  writer.line('static ${spec.className} fromMode(String mode) =>');
  writer.line('    switch (mode.trim().toLowerCase()) {');
  final seen = <String>{};
  for (var index = 0; index < spec.modeNames.length; index++) {
    final key = spec.modeNames[index].trim().toLowerCase();
    if (!seen.add(key)) continue;
    writer.line(
      "      ${dartStringLiteral(key)} => ${spec.getterNames[index]},",
    );
  }
  final available = spec.modeNames.join(', ');
  writer.line(
    "      _ => throw ArgumentError.value(mode, 'mode', "
    "'Unknown ${spec.className} mode (available: $available)')",
  );
  writer.line('    };');
}

void _copyWith(CodeWriter writer, ClassSpec spec) {
  writer.line();
  writer.line('@override');
  final params = spec.fields
      .map((field) => '${field.dartType}? ${field.name}')
      .join(', ');
  final args = spec.fields
      .map((field) => '${field.name}: ${field.name} ?? this.${field.name}')
      .join(', ');
  writer.line(
    '${spec.className} copyWith({$params}) => '
    '${spec.className}($args);',
  );
}

void _lerp(CodeWriter writer, ClassSpec spec) {
  writer.line();
  writer.line('@override');
  writer.line('${spec.className} lerp(${spec.className}? other, double t) {');
  writer.block(() {
    writer.line('if (other == null) return this;');
    writer.line('return ${spec.className}(');
    writer.block(() {
      for (final field in spec.fields) {
        writer.line('${field.name}: ${_lerpExpr(field)},');
      }
    });
    writer.line(');');
  });
  writer.line('}');
}

String _lerpExpr(FieldSpec field) {
  final name = field.name;
  final other = 'other.$name';
  return switch (field.dartType) {
    'Color' => 'Color.lerp($name, $other, t) ?? $name',
    'TextStyle' => 'TextStyle.lerp($name, $other, t) ?? $name',
    'BoxShadow' => 'BoxShadow.lerp($name, $other, t) ?? $name',
    'double' => '$name + ($other - $name) * t',
    _ => 't < 0.5 ? $name : $other',
  };
}
