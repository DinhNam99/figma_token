import '../ir/class_spec.dart';
import 'code_writer.dart';

/// Emits the barrel file (`app_tokens.dart`) exporting every generated file.
String emitBarrel({
  required List<ClassSpec> classes,
  required String header,
  required String themeFileName,
  required bool includeTheme,
}) {
  final writer = CodeWriter();
  writer.lines(header.split('\n'));
  writer.line();
  writer.line('/// Design tokens generated from Figma Variables.');
  writer.line('library;');
  writer.line();
  for (final spec in classes) {
    writer.line("export '${spec.fileName}';");
  }
  if (includeTheme) writer.line("export '$themeFileName';");
  return writer.toString();
}
