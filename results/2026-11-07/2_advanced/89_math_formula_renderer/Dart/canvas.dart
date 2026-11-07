part of 'main.dart';

List<String> drawCanvas(List<Placement> roots, int width, int height) {
  final grid = List.generate(height, (_) => List.filled(width, ' '));
  void draw(Box box, int x, int y) {
    for (final d in box.drawn) {
      for (var i = 0; i < d.text.length; i++) {
        if (d.text[i] != ' ') grid[y + d.y][x + d.x + i] = d.text[i];
      }
    }
    for (final child in box.children) {
      draw(child.box, x + child.x, y + child.y);
    }
  }

  for (final root in roots) {
    draw(root.box, root.x, root.y);
  }
  return grid.map((row) => row.join().trimRight()).toList();
}

(List<String>, int, Map<String, int>) describeBoxes(List<Placement> roots) {
  final out = <String>[], kinds = <String, int>{};
  var depth = 0;
  void walk(Placement p, int parentX, int parentY, int level) {
    final x = parentX + p.x, y = parentY + p.y, b = p.box;
    out.add(
      '${repeated(' ', 2 * level)}${p.role}${b.description} x=$x y=$y w=${b.width} h=${b.height} b=${b.baseline}',
    );
    depth = max(depth, level + 1);
    final kind = b.description.split(' ').first;
    kinds[kind] = (kinds[kind] ?? 0) + 1;
    for (final child in b.children) {
      walk(child, x, y, level + 1);
    }
  }

  for (final root in roots) {
    walk(root, 0, 0, 0);
  }
  return (out, depth, kinds);
}
