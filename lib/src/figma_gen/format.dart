import 'dart:io';

/// Result of running `dart format` over generated files.
class FormatResult {
  const FormatResult({required this.succeeded, this.stderr = ''});

  final bool succeeded;
  final String stderr;
}

/// Runs `dart format` on [paths] (the last pipeline step).
///
/// A failure is reported, not fatal: the written files remain on disk so the
/// syntax error can be inspected and fixed.
Future<FormatResult> formatDartFiles(
  List<String> paths, {
  bool enabled = true,
}) async {
  if (!enabled || paths.isEmpty) return const FormatResult(succeeded: true);
  final result = await Process.run('dart', ['format', ...paths]);
  if (result.exitCode == 0) return const FormatResult(succeeded: true);
  final stderr = (result.stderr as String).trim();
  return FormatResult(
    succeeded: false,
    stderr: stderr.isEmpty ? 'dart format failed' : stderr,
  );
}
