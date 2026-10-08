/// Minimal indentation-aware code writer for the emitters.
class CodeWriter {
  final StringBuffer _buffer = StringBuffer();
  int _depth = 0;

  /// Writes one line (or a blank line when [text] is empty).
  void line([String text = '']) {
    if (text.isEmpty) {
      _buffer.writeln();
      return;
    }
    _buffer.write('  ' * _depth);
    _buffer.writeln(text);
  }

  /// Writes every line of [text].
  void lines(Iterable<String> lines) {
    for (final text in lines) {
      line(text);
    }
  }

  /// Writes [lines] as a `///` doc comment.
  void doc(Iterable<String> lines) {
    for (final text in lines) {
      line(text.isEmpty ? '///' : '/// $text');
    }
  }

  /// Runs [body] indented by one level.
  void block(void Function() body) {
    _depth++;
    body();
    _depth--;
  }

  @override
  String toString() => _buffer.toString();
}
