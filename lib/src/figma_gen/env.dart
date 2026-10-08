import 'dart:io';

/// Minimal `.env` reader: `KEY = value`, quoted values, `#` comments.
///
/// Values are **never** logged by this tool; treat them as secrets.
Map<String, String> parseEnvFile(String content) {
  final result = <String, String>{};
  for (final line in content.split(RegExp(r'\r?\n'))) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
    final index = trimmed.indexOf('=');
    if (index <= 0) continue;
    final key = trimmed.substring(0, index).trim().toUpperCase();
    var value = trimmed.substring(index + 1).trim();
    if (value.length >= 2 &&
        ((value.startsWith('"') && value.endsWith('"')) ||
            (value.startsWith("'") && value.endsWith("'")))) {
      value = value.substring(1, value.length - 1).trim();
    }
    if (value.isNotEmpty) result[key] = value;
  }
  return result;
}

/// Resolves a secret from the process environment first, then [envFilePath].
///
/// Returns `null` when the key is absent; callers must never print the value.
String? readSecret(String key, {String envFilePath = '.env'}) {
  final fromEnv = Platform.environment[key];
  if (fromEnv != null && fromEnv.trim().isNotEmpty) {
    return fromEnv.trim();
  }
  final file = File(envFilePath);
  if (!file.existsSync()) return null;
  final value = parseEnvFile(file.readAsStringSync())[key.toUpperCase()];
  return (value == null || value.trim().isEmpty) ? null : value.trim();
}
