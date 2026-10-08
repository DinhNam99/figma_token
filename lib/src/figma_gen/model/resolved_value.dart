/// Concrete values a Figma variable alias chain can resolve to.
///
/// Figma stores `COLOR` variables as RGBA floats, `FLOAT` as numbers,
/// `STRING`/`BOOLEAN` literally, and any `VARIABLE_ALIAS` reference as
/// `{"type": "VARIABLE_ALIAS", "id": "<variable id>"}`.
sealed class ResolvedValue {
  const ResolvedValue();
}

/// An RGBA color with channels in the `0.0 - 1.0` range, as Figma stores them.
final class ColorValue extends ResolvedValue {
  const ColorValue({
    required this.r,
    required this.g,
    required this.b,
    this.a = 1.0,
  });

  final double r;
  final double g;
  final double b;
  final double a;

  static int _channel(double channel) {
    final value = (channel * 255).round();
    if (value < 0) return 0;
    if (value > 255) return 255;
    return value;
  }

  /// The color as a `0xAARRGGBB` literal, e.g. `0xFF1A73E8`.
  String get hexLiteral {
    final packed =
        (_channel(a) << 24) |
        (_channel(r) << 16) |
        (_channel(g) << 8) |
        _channel(b);
    return '0x${packed.toRadixString(16).toUpperCase().padLeft(8, '0')}';
  }

  @override
  bool operator ==(Object other) =>
      other is ColorValue &&
      other.r == r &&
      other.g == g &&
      other.b == b &&
      other.a == a;

  @override
  int get hashCode => Object.hash(r, g, b, a);

  @override
  String toString() => 'ColorValue($hexLiteral)';
}

/// A `FLOAT` token, always normalized to a Dart `double`.
final class NumberValue extends ResolvedValue {
  const NumberValue(this.value);

  final double value;

  /// Renders `8` as `8.0`, `-0.5` as `-0.5` — always a valid Dart `double`.
  String get literal {
    if (!value.isFinite) {
      throw ArgumentError.value(value, 'value', 'Not a finite number');
    }
    if (value == value.roundToDouble() && value.abs() < 1e15) {
      return '${value.toStringAsFixed(0)}.0';
    }
    // Trim floating point noise (e.g. 0.30000000000000004 -> 0.3).
    var text = value.toString();
    if (text.contains('e') || text.contains('E')) {
      text = value.toStringAsFixed(6);
      if (text.contains('.')) {
        text = text.replaceFirst(RegExp(r'0+$'), '');
        text = text.replaceFirst(RegExp(r'\.$'), '');
      }
    }
    return text.contains('.') || text.contains('-') ? text : '$text.0';
  }

  @override
  bool operator ==(Object other) =>
      other is NumberValue && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'NumberValue($value)';
}

/// A `STRING` token.
final class StringValue extends ResolvedValue {
  const StringValue(this.value);

  final String value;

  @override
  bool operator ==(Object other) =>
      other is StringValue && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'StringValue($value)';
}

/// A `BOOLEAN` token.
final class BoolValue extends ResolvedValue {
  const BoolValue(this.value);

  final bool value;

  @override
  bool operator ==(Object other) => other is BoolValue && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'BoolValue($value)';
}
