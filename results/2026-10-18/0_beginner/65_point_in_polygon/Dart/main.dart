void main() {
  const vertices = [
    (1, 1),
    (11, 2),
    (13, 9),
    (9, 7),
    (7, 12),
    (5, 6),
    (2, 10),
    (3, 5),
  ];
  for (final p in [(4, 8), (6, 4), (10, 8), (7, 11), (14, 3), (12, 8)]) {
    var inside = false;
    for (var i = 0; i < vertices.length; i++) {
      final a = vertices[i], b = vertices[(i + 1) % vertices.length];
      if ((a.$2 > p.$2) != (b.$2 > p.$2)) {
        final x = a.$1 + (b.$1 - a.$1) * (p.$2 - a.$2) / (b.$2 - a.$2);
        if (x > p.$1) inside = !inside;
      }
    }
    print('(${p.$1}, ${p.$2}): ${inside ? 'inside' : 'outside'}');
  }
}
