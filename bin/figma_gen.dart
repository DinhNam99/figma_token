// Figma Variables -> Dart/Flutter design tokens generator.
//
// Pipeline:
//   Figma REST API -> raw JSON -> parser -> alias resolver -> IR -> code
//   emitter -> `dart format` -> .dart files under `output_dir`.
//
// Run with: dart run bin/figma_gen.dart --help
import 'dart:convert';
import 'dart:io';

import 'package:figma_token/src/figma_gen/api/figma_variables_api.dart';
import 'package:figma_token/src/figma_gen/config.dart';
import 'package:figma_token/src/figma_gen/env.dart';
import 'package:figma_token/src/figma_gen/format.dart';
import 'package:figma_token/src/figma_gen/generator.dart';
import 'package:figma_token/src/figma_gen/model/raw_models.dart';

const String _usage = '''
Figma design token generator

Usage: dart run bin/figma_gen.dart [options]

Options:
  -c, --config <path>   Config file (default: figma_config.yaml)
  -o, --out <dir>       Override output_dir from the config
  -s, --source <path>   Read a cached raw API JSON response (offline mode)
      --check           Do not write: exit 2 if generated output differs
      --clean           Delete stale *.g.dart files in the output dir
      --no-format       Skip the final `dart format` step
  -v, --verbose         Verbose logging
  -h, --help            Show this help

Token resolution order (never printed):
  1. FIGMA_TOKEN / FILE_KEY environment variables
  2. the `env_file` from the config (default: .env)

Exit codes: 0 success, 1 error, 2 --check drift, 64 usage error.
''';

Future<void> main(List<String> arguments) async {
  final options = _Options.parse(arguments);
  if (options == null) {
    stderr.writeln(_usage);
    exit(64);
  }
  if (options.help) {
    stdout.writeln(_usage);
    exit(0);
  }

  try {
    exit(await _run(options));
  } on ConfigException catch (error) {
    stderr.writeln('error: ${error.message}');
    exit(1);
  } on FigmaApiException catch (error) {
    stderr.writeln('error: $error');
    exit(1);
  } on FormatException catch (error) {
    stderr.writeln('error: invalid JSON: ${error.message}');
    exit(1);
  } catch (error) {
    stderr.writeln('error: $error');
    exit(1);
  }
}

Future<int> _run(_Options options) async {
  final configPath = options.configPath ?? FigmaGenConfig.defaultFilePath;
  final configFile = File(configPath);
  if (!configFile.existsSync() && options.sourcePath == null) {
    throw ConfigException(
      'Config file not found: $configPath. Create it (see '
      'figma_config.yaml) or pass --config <path>.',
    );
  }
  var config = configFile.existsSync()
      ? FigmaGenConfig.load(configPath)
      : const FigmaGenConfig();
  config = config.copyWith(
    fileKey: options.fileKey,
    outputDir: options.outputDir,
    sourceFile: options.sourcePath,
    runFormat: options.format ? null : false,
  );

  // ---- 1. Fetch or load raw JSON -----------------------------------------
  final RawVariablesDocument document;
  if (options.sourcePath != null) {
    final file = File(options.sourcePath!);
    if (!file.existsSync()) {
      throw ConfigException('Source file not found: ${options.sourcePath}');
    }
    document = RawVariablesDocument.fromJson(
      jsonDecode(file.readAsStringSync()) as Map<String, dynamic>,
    );
    _log(
      'Loaded ${document.variables.length} variables / '
      '${document.collections.length} collections from ${options.sourcePath}',
      verbose: options.verbose,
    );
  } else {
    final fileKey =
        config.fileKey ??
        readSecret('FILE_KEY', envFilePath: config.envFile ?? '.env');
    if (fileKey == null || fileKey.isEmpty) {
      throw ConfigException(
        'No file key. Set `file_key` in $configPath or FILE_KEY in .env.',
      );
    }
    final token = readSecret(
      'FIGMA_TOKEN',
      envFilePath: config.envFile ?? '.env',
    );
    if (token == null || token.isEmpty) {
      throw const ConfigException(
        'No Figma token. Set FIGMA_TOKEN in the environment or in .env '
        '(`file_variables:read` scope required).',
      );
    }
    final api = FigmaVariablesApi(token: token);
    document = await api.fetchLocalVariables(fileKey);
    _log(
      'Fetched ${document.variables.length} variables / '
      '${document.collections.length} collections '
      '(token: ****${token.length})',
      verbose: options.verbose,
    );
  }

  // ---- 2. Resolve aliases and generate -----------------------------------
  final result = const TokenGenerator().generate(document, config);
  for (final warning in result.warnings) {
    stderr.writeln('warning: $warning');
  }
  if (result.files.isEmpty) {
    stderr.writeln('error: nothing to generate.');
    return 1;
  }

  // ---- 3. Materialize: generate -> temp dir -> `dart format` --------------
  // Formatting in a temp dir first means both `--check` and the normal run
  // compare *formatted* content against disk, so `dart format` never shows up
  // as false drift and unchanged files are not rewritten.
  final materialized = await _materialize(result, config);

  // ---- 4. Write (or compare) ---------------------------------------------
  final outputDir = Directory(config.outputDir);
  final stale = _findStaleFiles(outputDir, result, options.clean);

  if (options.check) {
    return _check(result, materialized, outputDir, stale);
  }

  final written = <String>[];
  for (final file in result.files) {
    final path = '${outputDir.path}/${file.relativePath}';
    final existing = File(path);
    final current = existing.existsSync() ? existing.readAsStringSync() : null;
    if (current == materialized[file.relativePath]) {
      _log('unchanged: $path', verbose: options.verbose);
      continue;
    }
    if (!existing.existsSync()) {
      existing.parent.createSync(recursive: true);
    }
    existing.writeAsStringSync(materialized[file.relativePath]!);
    written.add(path);
  }

  for (final path in stale) {
    File(path).deleteSync();
    _log('deleted: $path', verbose: options.verbose);
  }

  stdout.writeln(
    '${result.files.length} file(s) in ${config.outputDir} '
    '(${written.length} written, ${stale.length} deleted).',
  );
  return 0;
}

/// Writes the generated files into a temp dir, runs `dart format` on them
/// (unless disabled), and returns `relativePath -> formatted content`.
Future<Map<String, String>> _materialize(
  GenerationResult result,
  FigmaGenConfig config,
) async {
  final tempDir = Directory.systemTemp.createTempSync('figma_gen_build_');
  try {
    final tempPaths = <String>[];
    for (final file in result.files) {
      final path = '${tempDir.path}/${file.relativePath}';
      File(path)
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(file.content);
      tempPaths.add(path);
    }
    if (config.runFormat && tempPaths.isNotEmpty) {
      final formatted = await formatDartFiles(tempPaths);
      if (!formatted.succeeded) {
        stderr.writeln('warning: ${formatted.stderr}');
        stderr.writeln('warning: generated output was left unformatted.');
      }
    }
    return {
      for (final file in result.files)
        file.relativePath: File(
          '${tempDir.path}/${file.relativePath}',
        ).readAsStringSync(),
    };
  } finally {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  }
}

/// `--check`: compare the freshly materialized (formatted) output with what is
/// on disk (so `dart format` differences are not reported as drift).
int _check(
  GenerationResult result,
  Map<String, String> materialized,
  Directory outputDir,
  List<String> stale,
) {
  var drift = false;
  for (final file in result.files) {
    final path = '${outputDir.path}/${file.relativePath}';
    final disk = File(path);
    final current = disk.existsSync() ? disk.readAsStringSync() : null;
    if (current != materialized[file.relativePath]) {
      stderr.writeln('drift: $path differs from the generated output.');
      drift = true;
    }
  }
  for (final path in stale) {
    stderr.writeln('drift: stale file $path would be deleted.');
    drift = true;
  }

  if (drift) {
    stderr.writeln(
      'Generated tokens are out of date. Run: dart run bin/figma_gen.dart',
    );
    return 2;
  }
  stdout.writeln('Generated tokens are up to date.');
  return 0;
}

/// Files in the output dir that end in `.g.dart` but are no longer produced.
List<String> _findStaleFiles(
  Directory outputDir,
  GenerationResult result,
  bool enabled,
) {
  if (!enabled || !outputDir.existsSync()) return const [];
  final keep = {for (final file in result.files) file.relativePath};
  return [
    for (final entity in outputDir.listSync())
      if (entity is File &&
          entity.path.endsWith('.g.dart') &&
          !keep.contains(entity.uri.pathSegments.last))
        entity.path,
  ];
}

void _log(String message, {required bool verbose}) {
  if (verbose) stdout.writeln(message);
}

class _Options {
  _Options({
    this.configPath,
    this.outputDir,
    this.sourcePath,
    this.fileKey,
    this.check = false,
    this.clean = false,
    this.format = true,
    this.verbose = false,
    this.help = false,
  });

  final String? configPath;
  final String? outputDir;
  final String? sourcePath;
  final String? fileKey;
  final bool check;
  final bool clean;
  final bool format;
  final bool verbose;
  final bool help;

  /// Returns `null` on a usage error.
  static _Options? parse(List<String> args) {
    final values = <String, String?>{};
    var help = false;
    var check = false;
    var clean = false;
    var format = true;
    var verbose = false;

    for (var i = 0; i < args.length; i++) {
      var arg = args[i];
      String? inlineValue;
      final eq = arg.indexOf('=');
      if (arg.startsWith('--') && eq > 0) {
        inlineValue = arg.substring(eq + 1);
        arg = arg.substring(0, eq);
      }
      String? valueOf(String name) {
        if (inlineValue != null) return inlineValue;
        if (i + 1 >= args.length) return null;
        i++;
        return args[i];
      }

      switch (arg) {
        case '-h' || '--help':
          help = true;
        case '-c' || '--config':
          values['config'] = valueOf(arg);
          if (values['config'] == null) return null;
        case '-o' || '--out':
          values['out'] = valueOf(arg);
          if (values['out'] == null) return null;
        case '-s' || '--source':
          values['source'] = valueOf(arg);
          if (values['source'] == null) return null;
        case '--file-key':
          values['fileKey'] = valueOf(arg);
          if (values['fileKey'] == null) return null;
        case '--check':
          check = true;
        case '--clean':
          clean = true;
        case '--no-format':
          format = false;
        case '-v' || '--verbose':
          verbose = true;
        default:
          return null;
      }
    }

    return _Options(
      configPath: values['config'],
      outputDir: values['out'],
      sourcePath: values['source'],
      fileKey: values['fileKey'],
      check: check,
      clean: clean,
      format: format,
      verbose: verbose,
      help: help,
    );
  }
}
