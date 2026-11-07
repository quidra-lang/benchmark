typedef Color = (int, int, int, int);
typedef Rgb = (int, int, int);
typedef Image = List<List<Rgb>>;

int floorRatio(int n, int d) => n ~/ d - (n < 0 && n.remainder(d) != 0 ? 1 : 0);
int roundRatio(int n, int d) { if (d < 0) { n = -n; d = -d; } return floorRatio(2 * n + d, 2 * d); }
int effectiveAlpha(int alpha, int opacity) => roundRatio(alpha * opacity, 255);

class Layer {
  final int width, height, opacity;
  final String mode;
  late final List<List<Color?>> colors;
  late final List<List<int>> lines;
  Layer(this.width, this.height, this.opacity, this.mode) { colors = List.generate(height, (_) => List.filled(width, null)); lines = List.generate(height, (_) => List.filled(width, 0)); }
  void paint(int x, int y, Color color, int line) { colors[y][x] = color; lines[y][x] = line; }
  bool erase(int x, int y) { final painted = colors[y][x] != null; colors[y][x] = null; return painted; }
  int alphaAt(int x, int y) { final color = colors[y][x]; return color == null ? 0 : effectiveAlpha(color.$4, opacity); }
  Rgb blend(int x, int y, Rgb current) {
    final color = colors[y][x]; if (color == null) return current; final alpha = effectiveAlpha(color.$4, opacity);
    int channel(int s, int v) { final source = switch (mode) { 'multiply' => roundRatio(s * v, 255), 'screen' => 255 - roundRatio((255 - s) * (255 - v), 255), _ => s }; return roundRatio(alpha * source + (255 - alpha) * v, 255); }
    return (channel(color.$1, current.$1), channel(color.$2, current.$2), channel(color.$3, current.$3));
  }
}
Image composite(List<Layer> layers, Color background, int width, int height) => [for (var y = 0; y < height; y++) [for (var x = 0; x < width; x++) layers.fold<Rgb>((background.$1, background.$2, background.$3), (color, layer) => layer.blend(x, y, color))]];
