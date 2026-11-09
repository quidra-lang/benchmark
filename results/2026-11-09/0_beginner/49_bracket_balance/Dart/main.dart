void main() {
  for (final s in [
    '(a + b) * [c - d]',
    '{x = [1, 2, (3 + 4)]}',
    'f(a[i] + g(b)}',
    '(1 + 2)) * 3',
    'if (a < b) { c = d[0]; }',
    '((a + b] * c',
    '[{(x * y) - z}',
  ]) {
    final stack = <String>[];
    int? error;
    for (var i = 0; i < s.length; i++) {
      final c = s[i];
      if ('([{'.contains(c)) {
        stack.add(c);
      } else if (')]}'.contains(c)) {
        final expected = '([{'[')]}'.indexOf(c)];
        if (stack.isEmpty || stack.last != expected) {
          error = i;
          break;
        }
        stack.removeLast();
      }
    }
    if (error == null && stack.isNotEmpty) error = s.length;
    print('$s -> ${error == null ? 'balanced' : 'error at index $error'}');
  }
}
