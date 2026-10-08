# Figma Variables → Dart/Flutter codegen

A design-token pipeline that reads [Figma Variables](https://help.figma.com/hc/en-us/articles/15339657135383-Guide-to-variables-in-Figma)
over the REST API and emits type-safe Dart: constants for mode-independent
tokens, `ThemeExtension`s for mode-dependent ones, and a `ThemeData` factory
wired to Light/Dark modes.

## Pipeline

```
┌──────────────────────────┐
│ Figma REST API           │  GET /v1/files/:key/variables/local
│ (or --source raw JSON)   │  auth: X-Figma-Token (file_variables:read)
└────────────┬─────────────┘
             │ raw JSON
             ▼
┌──────────────────────────┐
│ Tolerant parser          │  lib/src/figma_gen/model/raw_models.dart
│ RawCollections/Variables │  unknown keys ignored, fixtures == API response
└────────────┬─────────────┘
             │
             ▼
┌──────────────────────────┐
│ Alias resolver           │  lib/src/figma_gen/resolve/alias_resolver.dart
│ chains / cycles / depth  │  visited-set + max_alias_depth, per-mode values
└────────────┬─────────────┘
             │ ResolvedValue (literal per mode)
             ▼
┌──────────────────────────┐
│ Token resolver +         │  resolve/token_resolver.dart, classify.dart
│ classifier               │  category by path keywords: shadow → typography
│                          │  → spacing → radius → size; COLOR → color
└────────────┬─────────────┘
             │ tokens grouped by category & mode
             ▼
┌──────────────────────────┐
│ IR + emitters            │  ir/class_spec.dart, builder.dart, emit/*
│ ClassSpec / FieldSpec    │  single-mode → `abstract final class` consts
│                          │  multi-mode → ThemeExtension + per-mode getters
└────────────┬─────────────┘
             │ raw Dart source
             ▼
┌──────────────────────────┐
│ `dart format` (temp dir) │  format.dart — compared, never rewrites blindly
└────────────┬─────────────┘
             │
             ▼
      *.g.dart files  +  app_tokens.dart barrel
      under output_dir (default: lib/generated/)
```

CLI entrypoint: `bin/figma_gen.dart`. Library code: `lib/src/figma_gen/`.

## Getting an API token

1. In Figma: **Settings → Security → Personal access tokens → Generate new
   token**.
2. Grant the **`file_variables:read`** scope. Without it the endpoint returns
   `403 … This endpoint requires the file_variables:read scope`.
3. The Variables endpoint is available to **full members of Enterprise
   organisations**; on other plans use offline mode (below).
4. Put the token and file key in `.env` at the project root (gitignored):

   ```sh
   FIGMA_TOKEN = "figd_xxxxxxxxxxxx"
   FILE_KEY    = "AbCdEfGh123456"
   ```

   Values may be double-quoted; quotes are stripped by the parser. **Never
   commit `.env` or print the token** — the tool only ever logs `****<length>`.

5. Run:

   ```sh
   dart run bin/figma_gen.dart
   ```

### Offline mode (fixtures / no token)

Cache a raw API response and feed it back with `--source`:

```sh
dart run bin/figma_gen.dart --source tool/fixtures/variables.sample.json
```

`tool/fixtures/variables.sample.json` is a checked-in sample response
(3 collections, 43 variables, Light/Dark modes, a 2-hop alias chain) used by
tests and CI.

## Configuration

All settings live in `figma_config.yaml`:

```yaml
file_key: ""                  # optional if FILE_KEY is set in .env
output_dir: lib/generated
excluded_collections: []      # exact names, case insensitive
included_collections: []      # non-empty = allowlist mode
max_alias_depth: 32           # deeper chains / cycles → warning, skipped
format: true                  # run `dart format` as the last step
google_fonts: false           # emit GoogleFonts.getFont(...) instead of fontFamily
default_font_family: null     # fallback for text styles without a family
source: null                  # default offline source (same as --source)
env_file: .env                # where FIGMA_TOKEN / FILE_KEY are read from
theme:
  light_mode: "Light"         # Figma mode name mapped to ThemeData.light()
  dark_mode: "Dark"           # Figma mode name mapped to ThemeData.dark()
categories:                   # path keywords per category (priority order
  spacing: [...]              # is: shadow → typography → spacing → radius
  radius: [...]               # → size; COLOR-typed tokens always land in
  size: [...]                 # `color` unless a keyword says otherwise)
  typography: [...]
  shadow: [...]
```

CLI flags override the config:

| Flag | Meaning |
| --- | --- |
| `-c, --config <path>` | Config file (default `figma_config.yaml`) |
| `-o, --out <dir>` | Override `output_dir` |
| `-s, --source <path>` | Offline mode: read a cached raw API JSON |
| `--file-key <key>` | Override `file_key` |
| `--check` | Don't write; exit `2` if output on disk differs |
| `--clean` | Delete stale `*.g.dart` files no longer produced |
| `--no-format` | Skip the `dart format` step |
| `-v, --verbose` | Verbose logging (never prints secrets) |
| `-h, --help` | Usage |

Exit codes: `0` success · `1` error · `2` `--check` drift · `64` usage error.

## Sample API response (excerpt)

`GET /v1/files/:key/variables/local` returns collections + variables keyed by
id — this is the shape the parser accepts (see
`tool/fixtures/variables.sample.json` for the full fixture):

```jsonc
{
  "status": 200,
  "error": false,
  "meta": {
    "variableCollections": {
      "10:0": {
        "id": "10:0",
        "name": "Primitives",
        "defaultModeId": "10:2",
        "modes": [
          { "modeId": "10:2", "name": "Mode 1" }
        ],
        "variableIds": ["10:100", "10:101"]
      },
      "20:0": {
        "id": "20:0",
        "name": "Semantic",
        "defaultModeId": "20:2",
        "modes": [
          { "modeId": "20:2", "name": "Light" },
          { "modeId": "20:3", "name": "Dark" }
        ],
        "variableIds": ["20:200"]
      }
    },
    "variables": {
      "10:100": {
        "id": "10:100",
        "name": "color/blue/500",
        "variableCollectionId": "10:0",
        "resolvedType": "COLOR",
        "valuesByMode": {
          "10:2": { "r": 0.184, "g": 0.435, "b": 0.929, "a": 1 }
        },
        "description": "Primary brand blue"
      },
      "20:200": {
        "id": "20:200",
        "name": "color/primary",
        "variableCollectionId": "20:0",
        "resolvedType": "COLOR",
        "valuesByMode": {
          // alias reference (Figma's `{type, id}` value form)
          "20:2": { "type": "VARIABLE_ALIAS", "id": "10:100" },
          "20:3": { "type": "VARIABLE_ALIAS", "id": "10:102" }
        },
        "description": "Primary action color"
      }
    }
  }
}
```

## Alias resolution

A Figma alias value is `{ "type": "VARIABLE_ALIAS", "id": "<variableId>" }`.
The resolver walks these recursively:

```dart
resolve(id, modeId, visited: {}, depth: 0):
  if depth > max_alias_depth  → AliasResolutionException("chain deeper than N")
  if id in visited            → AliasResolutionException("Circular reference: a → b → a")
  variable = document.variables[id]           // unknown id → exception
  effectiveMode = collection.modeById(modeId) // unknown mode → collection default
  value = variable.valuesByMode[effectiveMode]
  if value is alias → resolve(value.id, effectiveMode,
                              visited + {id}, chain + {name}, depth + 1)
  else             → ResolvedValue(literal)
```

Key properties:

- **Cross-collection chains** work: each hop uses the *aliased variable's own*
  collection to pick the mode, so a `Semantic` Light token pointing at a
  `Primitives` token resolves correctly even though the mode ids differ.
- **Cycles** are caught by the visited set and reported with the full chain
  (`a → b → a`) instead of looping forever.
- **Depth** is bounded by `max_alias_depth` (default 32) as a second safety net.
- **Failures are non-fatal**: an unresolvable token is skipped with a
  `warning:` line on stderr; the rest still generates.

## Classification

A token's `/`-separated path is lowercased and matched against the
`categories` keywords. The first matching category in priority order wins:

```
shadow → typography → spacing → radius → size
```

`COLOR`-typed variables default to the **color** category; `FLOAT` defaults to
**size**; `BOOLEAN` → **booleans**; `STRING` only joins **typography** when its
leaf matches a known text-style property (`font`, `weight`, `line-height`, …),
otherwise it is a plain **strings** token.

Tokens are grouped by (category, Figma variable group). Whether a group becomes
constants or a `ThemeExtension` depends on its modes:

- **Single mode** → `abstract final class` with `static const` fields.
- **Multiple modes** (e.g. Light/Dark) → `ThemeExtension` subclass with a
  `static const` instance per mode and a `fromMode()` constructor.

## Generated output

`dart run bin/figma_gen.dart` produces (from the sample fixture):

```
lib/generated/
├── app_tokens.dart        # barrel: exports everything below
├── app_palette.g.dart     # primitive colors (single mode → consts)
├── app_colors.g.dart      # semantic colors (Light/Dark → ThemeExtension)
├── app_spacing.g.dart     # doubles
├── app_radius.g.dart      # doubles
├── app_sizes.g.dart       # doubles
├── app_strings.g.dart     # strings (multi-mode → ThemeExtension)
├── app_booleans.g.dart    # bools (multi-mode → ThemeExtension)
├── app_typography.g.dart  # TextStyle constants / groups
├── app_shadows.g.dart     # BoxShadow constants
└── app_theme.g.dart       # AppThemeData + BuildContext extensions
```

### Mode-independent token → constants

```dart
/// Design tokens generated from Figma (spacing category).
abstract final class AppSpacing {
  /// `spacing/16` — collection `Primitives`.
  static const double spacing16 = 16.0;
}
```

### Mode-dependent token → `ThemeExtension` (never hardcoded values)

```dart
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.primary,
    /* … */
  });

  /// `color/primary` — collection `Semantic`.
  final Color primary;

  /// Values of the Figma mode `Light`.
  static const AppColors light = AppColors(primary: Color(0xFF2F6FED) /* … */);

  /// Values of the Figma mode `Dark`.
  static const AppColors dark = AppColors(primary: Color(0xFF7CA3F8) /* … */);

  /// Resolves this extension for a Figma [mode] name.
  static AppColors fromMode(String mode) => switch (mode.trim().toLowerCase()) {
    'light' => light,
    'dark' => dark,
    _ => throw ArgumentError.value(
      mode,
      'mode',
      'Unknown AppColors mode (available: Light, Dark)',
    ),
  };

  @override
  AppColors copyWith({Color? primary /* … */}) => /* … */;

  @override
  AppColors lerp(AppColors? other, double t) => /* per-field Color.lerp */;
}
```

### Theme wiring + `BuildContext` accessors

```dart
abstract final class AppThemeData {
  static ThemeData light() => _build(Brightness.light, const [AppColors.light, /* … */]);
  static ThemeData dark()  => _build(Brightness.dark,  const [AppColors.dark,  /* … */]);
}

extension AppColorsContext on BuildContext {
  AppColors get appColors =>
      Theme.of(this).extension<AppColors>() ?? AppColors.light;
}
```

Usage in the app — **no mode-dependent values in widget code**:

```dart
MaterialApp(
  theme: AppThemeData.light(),
  darkTheme: AppThemeData.dark(),
  themeMode: ThemeMode.system,
);

// Somewhere in a widget:
Container(
  color: context.appColors.background,
  padding: EdgeInsets.all(AppSpacing.spacing16),
);
```

Light/Dark switching works purely through `Theme.of(context)`; the token files
never need regenerating when the user changes mode.

## Type safety & naming

- **Types are preserved**: `COLOR` → `Color`, `FLOAT` → `double`, `STRING` →
  `String`, `BOOLEAN` → `bool`; text styles → `TextStyle`; shadows →
  `BoxShadow`.
- **Identifiers are sanitized**: any path becomes a valid Dart name
  (`color/on-background` → `onBackground`, `spacing/16` → `spacing16`),
  Dart keywords are escaped, and collisions get deterministic suffixes
  (`uniqueIdentifier`). Output is deterministic — same input, byte-identical
  files (covered by tests).
- Every generated file starts with
  `// GENERATED CODE - DO NOT MODIFY BY HAND.` and documents the source
  variable + collection in doc comments.
- `dart format` always runs as the last step (in a temp dir first, so
  `--check` compares *formatted* content and never reports format noise as
  drift).

## CI/CD

### GitHub Actions

`.github/workflows/figma-tokens.yml` gates PRs on token drift using the
checked-in fixture (no secrets needed):

```yaml
name: figma-tokens
on:
  pull_request:
    paths: ["lib/generated/**", "tool/**", "lib/src/figma_gen/**", "bin/**"]
  push:
    branches: [main]

jobs:
  check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          channel: stable
      - run: flutter pub get
      # Drift gate: fails (exit 2) if lib/generated is out of date.
      - run: dart run bin/figma_gen.dart --source tool/fixtures/variables.sample.json --check
      - run: dart analyze
      - run: flutter test
```

To generate from the **real** Figma file instead of the fixture, add secrets
(`FIGMA_TOKEN`, `FILE_KEY`), export them into the step's env, and drop
`--source …`. The token needs the `file_variables:read` scope.

### Pre-commit hook

```sh
# one-time setup
git config core.hooksPath tool/hooks
chmod +x tool/hooks/pre-commit
```

The hook runs `--check` against the configured source and blocks the commit
when generated files are stale; `--no-verify` bypasses it.

## Development

```sh
flutter pub get
dart analyze          # lint gate
dart format .         # formatter
flutter test          # alias resolver, naming, generator (33 tests)
```

Adding a category or renaming files: see
`lib/src/figma_gen/classify.dart` (keywords), `builder.dart` (file
grouping), `emit/theme_emitter.dart` (theme wiring).
