/// Raw, tolerant models for the Figma `GET /v1/files/:key/variables/local`
/// response. Parsing is intentionally lenient: unknown JSON keys are ignored
/// and map keys are preferred over embedded ids so that both the official
/// response and cached fixtures parse identically.
library;

/// A mode (e.g. `Light`, `Dark`, `Brand B`) inside a variable collection.
class RawMode {
  const RawMode({required this.modeId, required this.name});

  final String modeId;
  final String name;

  factory RawMode.fromJson(Map<String, dynamic> json) => RawMode(
    modeId: json['modeId'] as String? ?? '',
    name: json['name'] as String? ?? 'Mode',
  );
}

/// A Figma variable collection: a group of tokens sharing the same modes.
class RawCollection {
  const RawCollection({
    required this.id,
    required this.name,
    required this.modes,
    required this.defaultModeId,
    required this.variableIds,
  });

  final String id;
  final String name;
  final List<RawMode> modes;
  final String defaultModeId;
  final List<String> variableIds;

  bool get isMultiMode => modes.length > 1;

  RawMode? modeById(String modeId) {
    for (final mode in modes) {
      if (mode.modeId == modeId) return mode;
    }
    return null;
  }

  String modeNameOf(String modeId) =>
      modeById(modeId)?.name ?? modes.first.name;

  factory RawCollection.fromJson(String id, Map<String, dynamic> json) {
    final modes = (json['modes'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(RawMode.fromJson)
        .toList();
    return RawCollection(
      id: json['id'] as String? ?? id,
      name: json['name'] as String? ?? 'Collection',
      modes: modes.isEmpty
          ? const [RawMode(modeId: '', name: 'Default')]
          : modes,
      defaultModeId:
          json['defaultModeId'] as String? ??
          (modes.isEmpty ? '' : modes.first.modeId),
      variableIds: (json['variableIds'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toList(),
    );
  }
}

/// A single design token (Figma variable).
class RawVariable {
  const RawVariable({
    required this.id,
    required this.name,
    required this.variableCollectionId,
    required this.resolvedType,
    required this.valuesByMode,
    required this.description,
  });

  static const Set<String> supportedTypes = {
    'COLOR',
    'FLOAT',
    'STRING',
    'BOOLEAN',
  };

  final String id;
  final String name;
  final String variableCollectionId;

  /// One of `COLOR`, `FLOAT`, `STRING`, `BOOLEAN`.
  final String resolvedType;

  /// `modeId -> value`, where value is a literal or a
  /// `{"type": "VARIABLE_ALIAS", "id": ...}` reference.
  final Map<String, dynamic> valuesByMode;

  final String description;

  bool get isSupported => supportedTypes.contains(resolvedType);

  factory RawVariable.fromJson(String id, Map<String, dynamic> json) =>
      RawVariable(
        id: json['id'] as String? ?? id,
        name: json['name'] as String? ?? 'variable',
        variableCollectionId: json['variableCollectionId'] as String? ?? '',
        resolvedType: json['resolvedType'] as String? ?? 'STRING',
        valuesByMode:
            (json['valuesByMode'] as Map<String, dynamic>? ??
                    const <String, dynamic>{})
                .cast<String, dynamic>(),
        description: json['description'] as String? ?? '',
      );
}

/// The decoded `local variables` document.
class RawVariablesDocument {
  const RawVariablesDocument({
    required this.collections,
    required this.variables,
    this.fileKey,
  });

  final Map<String, RawCollection> collections;
  final Map<String, RawVariable> variables;

  /// Set when the document came from a live API call (used in file headers).
  final String? fileKey;

  /// Accepts the official body (`{"status":..., "meta": {...}}`), the bare
  /// `meta` object, and fixtures that wrap everything under `meta`.
  factory RawVariablesDocument.fromJson(Map<String, dynamic> json) {
    final meta = (json['meta'] as Map<String, dynamic>?) ?? json;

    final collectionsJson =
        (meta['variableCollections'] as Map<String, dynamic>? ??
        meta['collections'] as Map<String, dynamic>? ??
        const <String, dynamic>{});
    final variablesJson =
        (meta['variables'] as Map<String, dynamic>? ??
        const <String, dynamic>{});

    return RawVariablesDocument(
      collections: {
        for (final entry in collectionsJson.entries)
          if (entry.value is Map<String, dynamic>)
            entry.key: RawCollection.fromJson(
              entry.key,
              entry.value as Map<String, dynamic>,
            ),
      },
      variables: {
        for (final entry in variablesJson.entries)
          if (entry.value is Map<String, dynamic>)
            entry.key: RawVariable.fromJson(
              entry.key,
              entry.value as Map<String, dynamic>,
            ),
      },
      fileKey: json['fileKey'] as String?,
    );
  }
}
