# figma_token

Design-token pipeline for Flutter: fetches **Figma Variables** over the REST
API and generates type-safe Dart/Flutter code — colors, spacing, radius, sizes,
typography, shadows, and a `ThemeExtension`-based theme with Light/Dark mode
support.

> Full guide: **[docs/figma_codegen.md](docs/figma_codegen.md)**
> (pipeline, API setup, config reference, sample JSON, CI/CD).

## Features

- **Live fetch or offline fixture** — `GET /v1/files/:key/variables/local`
  (`file_variables:read` scope) or `--source <cached.json>`.
- **Alias-aware** — resolves reference chains across collections and modes;
  circular references and runaway depths are detected, never looped on.
- **Mode-safe codegen** — single-mode collections become `abstract final
  class` constants; multi-mode collections become `ThemeExtension`s with a
  `static const` instance per Figma mode. No mode-dependent value is ever
  hardcoded in widget code: read colors through `context.appColors` /
  `Theme.of(context)` and Light/Dark switching just works.
- **Type safe & deterministic** — `Color`/`double`/`String`/`bool`/`TextStyle`/
  `BoxShadow` are preserved; identifiers are sanitized (snake/camel, keyword
  escaping, collision-free); same input ⇒ byte-identical output.
- **Formatted output** — every run finishes with `dart format`.

## Getting started

```sh
flutter pub get

# Offline (checked-in sample fixture — no token needed):
dart run bin/figma_gen.dart --source tool/fixtures/variables.sample.json

# Live (put FIGMA_TOKEN + FILE_KEY in .env first):
dart run bin/figma_gen.dart
```

Options: `--check` (CI drift gate, exit 2), `--clean` (remove stale files),
`--out <dir>`, `--config <path>`, `--no-format`, `--verbose`, `--help`.

## Usage

```dart
import 'package:figma_token/generated/app_tokens.dart';

MaterialApp(
  theme: AppThemeData.light(),
  darkTheme: AppThemeData.dark(),
  themeMode: ThemeMode.system,
);

// Mode-independent tokens are plain constants:
Padding(padding: EdgeInsets.all(AppSpacing.spacing16))

// Mode-dependent tokens come from the context (never a static field):
Container(color: context.appColors.background)
```

## Configuration

`figma_config.yaml` controls output dir, excluded/included collections, alias
depth, theme mode names, category keywords, and more — see the
[config reference](docs/figma_codegen.md#configuration).

## CI/CD

- **GitHub Actions**: [`.github/workflows/figma-tokens.yml`](.github/workflows/figma-tokens.yml)
  runs the generator with `--check` (fails on drift), plus analyze/test/format.
- **Pre-commit hook**: `git config core.hooksPath tool/hooks && chmod +x tool/hooks/pre-commit`
  blocks commits with stale generated files.

## Development

```sh
dart analyze   # lint gate
dart format .  # formatter
flutter test   # alias resolver, naming, generator tests
```

## Additional information

- Pipeline docs: [docs/figma_codegen.md](docs/figma_codegen.md)
- Generator source: `lib/src/figma_gen/`, CLI: `bin/figma_gen.dart`
- Generated output: `lib/generated/` (`app_tokens.dart` is the barrel import)
- Never commit `.env` or print token values.
