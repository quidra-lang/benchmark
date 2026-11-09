import 'dart:io';
import 'dart:math';
import 'canvas.dart';
import 'primitives.dart';
import 'clipping.dart';
import 'fill.dart';
import 'ppm_writer.dart';

const penCommands = ['LINE', 'RECT', 'CIRCLE', 'ELLIPSE', 'POLYLINE', 'POLYGON', 'PATH'];
const brushCommands = ['FILLRECT', 'FILLCIRCLE', 'FILLELLIPSE', 'FILLPOLYGON', 'FILLPATH', 'FLOOD', 'TEXT'];
const stateCommands = ['TRANSLATE', 'SCALE', 'ROTATE', 'SAVE', 'RESTORE', 'CLIP', 'NOCLIP', 'USE'];
const errorNames = ['unknown_command', 'bad_arguments', 'unknown_style', 'unknown_symbol', 'unknown_glyph', 'bad_value', 'stack_empty'];
const pathArity = {'M': 2, 'm': 2, 'L': 2, 'l': 2, 'H': 1, 'h': 1, 'V': 1, 'v': 1, 'Q': 4, 'q': 4, 'C': 6, 'c': 6, 'Z': 0, 'z': 0};

class Pen { final int width, on, off; final String color; Pen(this.width, this.color, this.on, this.off); }
class Brush { final List<String> colors; final String? axis; final String rule; Brush(this.colors, this.axis, this.rule); }
class Styles { final colors = <String, Color>{}, pens = <String, Pen>{}, brushes = <String, Brush>{}; }
class Font { final int width, height; final glyphs = <String, List<Point>>{}; Font(this.width, this.height); }
sealed class DrawingItem {}
class Command extends DrawingItem { final int line; final String keyword; final List<String> arguments; Command(this.line, this.keyword, this.arguments); }
class Repetition extends DrawingItem { final int count, dx, dy; final List<DrawingItem> body; Repetition(this.count, this.dx, this.dy, this.body); }
class SceneBlock {
  final String name, mode;
  final List<DrawingItem> body;
  final int endLine, opacity;
  SceneBlock(this.name, this.body, this.endLine, [this.opacity = 255, this.mode = 'normal']);
}
class Scene { int width = 0, height = 0; String background = ''; final layers = <SceneBlock>[], symbols = <String, SceneBlock>{}; }
class PathCommand { final String letter; final List<int> values; PathCommand(this.letter, this.values); }
class Subpath { final List<Point> points; bool closed = false; Subpath(this.points); }
class Execution {
  final int sequence, layer;
  final Command command;
  String kind = '', error = '';
  int pixels = 0;
  Rect? box;
  Execution(this.sequence, this.layer, this.command);
}

List<String> readLines(String name) => File('input/$name').readAsLinesSync();
bool isInteger(String word) => RegExp(r'^-?[0-9]+$').hasMatch(word);
bool allIntegers(Iterable<String> words) => words.every(isInteger);
List<int> integers(Iterable<String> words) => words.map(int.parse).toList();
Rect intersectRect(Rect a, Rect b) => (max(a.$1, b.$1), max(a.$2, b.$2), min(a.$3, b.$3), min(a.$4, b.$4));
bool emptyRect(Rect r) => r.$1 > r.$3 || r.$2 > r.$4;
bool containsPoint(Rect r, Point p) => r.$1 <= p.$1 && p.$1 <= r.$3 && r.$2 <= p.$2 && p.$2 <= r.$4;
Set<Point> rectPixels(Rect r) => {for (var y = r.$2; y <= r.$4; y++) for (var x = r.$1; x <= r.$3; x++) (x, y)};
Rect? boundingBox(Set<Point> points) {
  if (points.isEmpty) return null; var x0 = points.first.$1, y0 = points.first.$2, x1 = x0, y1 = y0; for (final (x, y) in points) { x0 = min(x0, x); y0 = min(y0, y); x1 = max(x1, x); y1 = max(y1, y); } return (x0, y0, x1, y1);
}
String boxText(Rect? box) => box == null ? 'none' : '${box.$1} ${box.$2} ${box.$3} ${box.$4}';
List<(Point, Point)> segments(List<Point> points, bool closed) => [for (var i = 1; i < points.length; i++) (points[i - 1], points[i]), if (closed) (points.last, points.first)];

Styles readStyles(List<String> lines) {
  final styles = Styles(); for (final line in lines) { if (line.isEmpty || line.startsWith('#')) continue; final words = line.split(' '), name = words[1], v = words.sublist(2);
    switch (words.first) {
      case 'color': final c = integers(v); styles.colors[name] = (c[0], c[1], c[2], c[3]);
      case 'pen': styles.pens[name] = Pen(int.parse(v[0]), v[1], int.parse(v[2]), int.parse(v[3]));
      case 'brush': styles.brushes[name] = Brush([v[0]], null, v[1]);
      case 'gradient': styles.brushes[name] = Brush([v[0], v[1]], v[2], v[3]);
    }
  } return styles;
}
Font readFont(List<String> lines) {
  final header = lines.first.split(' '), font = Font(int.parse(header[1]), int.parse(header[2]));
  for (var i = 1; i < lines.length; i += 1 + font.height) { final character = lines[i].split(' ')[1]; font.glyphs[character] = [for (var r = 0; r < font.height; r++) for (var c = 0; c < font.width; c++) if (lines[i + 1 + r][c] == '#') (c, r)]; } return font;
}
class SceneParser {
  final instructions = <(int, List<String>)>[];
  int index = 0;
  SceneParser(List<String> lines) { for (var i = 0; i < lines.length; i++) { final line = lines[i].trimLeft(); if (line.isNotEmpty && !line.startsWith('#')) instructions.add((i + 1, line.split(RegExp(' +')))); } }
  (List<DrawingItem>, int) body(String end) {
    final items = <DrawingItem>[];
    while (index < instructions.length) { final (line, words) = instructions[index++]; if (words.first == end) return (items, line); if (words.first == 'REPEAT') { final (nested, _) = body('ENDREPEAT'); items.add(Repetition(int.parse(words[1]), int.parse(words[2]), int.parse(words[3]), nested)); } else { items.add(Command(line, words.first, words.sublist(1))); } } return (items, 0);
  }
  Scene parse() {
    final scene = Scene(); while (index < instructions.length) { final (_, words) = instructions[index++]; if (words.first == 'CANVAS') { scene.width = int.parse(words[1]); scene.height = int.parse(words[2]); scene.background = words[3]; continue; } final (items, end) = body('END'); final block = words.first == 'LAYER' ? SceneBlock(words[1], items, end, int.parse(words[2]), words[3]) : SceneBlock(words[1], items, end); if (words.first == 'LAYER') { scene.layers.add(block); } else { scene.symbols[block.name] = block; } } return scene;
  }
}
List<PathCommand>? parsePath(List<String> words) {
  final commands = <PathCommand>[]; var index = 0;
  while (index < words.length) { final letter = words[index], arity = pathArity[letter]; if (arity == null || index + 1 + arity > words.length) return null; final values = words.sublist(index + 1, index + 1 + arity); if (!allIntegers(values)) return null; if ((commands.isEmpty || ['Z', 'z'].contains(commands.last.letter)) && !['M', 'm'].contains(letter)) return null; commands.add(PathCommand(letter, integers(values))); index += 1 + arity; } return commands.isEmpty ? null : commands;
}
bool validForm(String keyword, List<String> a) {
  const fixed = {'LINE': (5, 1), 'RECT': (5, 1), 'FILLRECT': (5, 1), 'CIRCLE': (4, 1), 'FILLCIRCLE': (4, 1), 'ELLIPSE': (5, 1), 'FILLELLIPSE': (5, 1), 'FLOOD': (3, 1), 'ERASE': (4, 0), 'TRANSLATE': (2, 0), 'SCALE': (2, 0), 'ROTATE': (1, 0), 'SAVE': (0, 0), 'RESTORE': (0, 0), 'NOCLIP': (0, 0), 'CLIP': (4, 0), 'USE': (3, 1)};
  final form = fixed[keyword]; if (form != null) return a.length == form.$1 && allIntegers(a.skip(form.$2));
  if (keyword == 'TEXT') return a.length == 5 && allIntegers(a.sublist(1, 3));
  if (['POLYLINE', 'POLYGON', 'FILLPOLYGON'].contains(keyword)) return a.length >= 2 && allIntegers(a.skip(1)) && a.length == 2 + 2 * int.parse(a[1]);
  return a.length >= 2 && isInteger(a[1]) && parsePath(a.sublist(2)) != null;
}

typedef Matrix = (int, int, int, int, int, int);
class DrawingState {
  final Rect screen;
  Matrix matrix = (1, 0, 0, 1, 0, 0);
  late Rect clip;
  List<(Matrix, Rect)> stack = [];
  DrawingState(this.screen) { clip = screen; }
  DrawingState.copy(DrawingState other) : screen = other.screen, matrix = other.matrix, clip = other.clip, stack = [...other.stack];
  Point transform(int x, int y) { final (a, b, c, d, e, f) = matrix; return (a * x + b * y + e, c * x + d * y + f); }
  Rect deviceRect(int x0, int y0, int x1, int y1) { final p = transform(x0, y0), q = transform(x1, y1); return (min(p.$1, q.$1), min(p.$2, q.$2), max(p.$1, q.$1), max(p.$2, q.$2)); }
  Point radii(int rx, int ry) => (matrix.$1.abs() * rx + matrix.$2.abs() * ry, matrix.$3.abs() * rx + matrix.$4.abs() * ry);
  void translate(int dx, int dy) { final (a, b, c, d, e, f) = matrix; matrix = (a, b, c, d, e + a * dx + b * dy, f + c * dx + d * dy); }
  void scale(int sx, int sy) { final (a, b, c, d, e, f) = matrix; matrix = (a * sx, b * sy, c * sx, d * sy, e, f); }
  void rotate(int k) { for (var i = 0; i < k % 4; i++) { final (a, b, c, d, e, f) = matrix; matrix = (b, -a, d, -c, e, f); } }
}

class Renderer {
  final Scene scene;
  final Styles styles;
  final Font font;
  late final Rect screen;
  final layers = <Layer>[], executions = <Execution>[];
  late DrawingState state;
  late Layer layer;
  Renderer(this.scene, this.styles, this.font) { screen = (0, 0, scene.width - 1, scene.height - 1); }
  void run() { for (final block in scene.layers) { layer = Layer(scene.width, scene.height, block.opacity, block.mode); layers.add(layer); state = DrawingState(screen); executeBody(block.body); } }
  void executeBody(List<DrawingItem> body) {
    for (final item in body) { if (item is Repetition) { final saved = DrawingState.copy(state); for (var k = 0; k < item.count; k++) { state = DrawingState.copy(saved); state.translate(k * item.dx, k * item.dy); executeBody(item.body); } state = DrawingState.copy(saved); } else { executeCommand(item as Command); } }
  }
  void executeCommand(Command command) {
    final execution = Execution(executions.length + 1, layers.length, command); executions.add(execution); final error = check(command);
    if (error != null) { execution.kind = 'error'; execution.error = error; return; }
    if (stateCommands.contains(command.keyword)) { execution.kind = 'state'; applyState(command); return; }
    final pixels = draw(command); execution.kind = 'drawing'; execution.pixels = pixels.length; execution.box = boundingBox(pixels);
  }
  String? check(Command command) {
    final k = command.keyword, a = command.arguments;
    if (![...penCommands, ...brushCommands, 'ERASE', ...stateCommands].contains(k)) return 'unknown_command';
    if (!validForm(k, a)) return 'bad_arguments';
    if (penCommands.contains(k) && !styles.pens.containsKey(a[0]) || brushCommands.contains(k) && !styles.brushes.containsKey(a[0])) return 'unknown_style';
    if (k == 'USE') { final symbol = scene.symbols[a[0]]; if (symbol == null || symbol.endLine >= command.line) return 'unknown_symbol'; }
    if (k == 'TEXT' && a[4].split('').any((c) => c != '_' && !font.glyphs.containsKey(c))) return 'unknown_glyph';
    if (k == 'RESTORE' && state.stack.isEmpty) return 'stack_empty';
    final valid = switch (k) {
      'CIRCLE' || 'FILLCIRCLE' => int.parse(a[3]) >= 1,
      'ELLIPSE' || 'FILLELLIPSE' => int.parse(a[3]) >= 1 && int.parse(a[4]) >= 1,
      'POLYLINE' => int.parse(a[1]) >= 2,
      'POLYGON' || 'FILLPOLYGON' => int.parse(a[1]) >= 3,
      'PATH' || 'FILLPATH' => int.parse(a[1]) >= 1 && int.parse(a[1]) <= 32,
      'FLOOD' => containsPoint(state.clip, state.transform(int.parse(a[1]), int.parse(a[2]))),
      'TEXT' => ['left', 'center', 'right'].contains(a[3]),
      'SCALE' => int.parse(a[0]) != 0 && int.parse(a[1]) != 0,
      'CLIP' => !emptyRect(intersectRect(state.deviceRect(int.parse(a[0]), int.parse(a[1]), int.parse(a[2]), int.parse(a[3])), state.clip)),
      _ => true,
    }; return valid ? null : 'bad_value';
  }
  void applyState(Command command) {
    final a = command.arguments;
    switch (command.keyword) {
      case 'TRANSLATE': state.translate(int.parse(a[0]), int.parse(a[1]));
      case 'SCALE': state.scale(int.parse(a[0]), int.parse(a[1]));
      case 'ROTATE': state.rotate(int.parse(a[0]));
      case 'SAVE': state.stack.add((state.matrix, state.clip));
      case 'RESTORE': final pair = state.stack.removeLast(); state.matrix = pair.$1; state.clip = pair.$2;
      case 'CLIP': state.clip = intersectRect(state.deviceRect(int.parse(a[0]), int.parse(a[1]), int.parse(a[2]), int.parse(a[3])), state.clip);
      case 'NOCLIP': state.clip = screen;
      case 'USE': final snapshot = DrawingState.copy(state); state.translate(int.parse(a[1]), int.parse(a[2])); executeBody(scene.symbols[a[0]]!.body); state = snapshot;
    }
  }
  Rect rectangle(List<int> values) => state.deviceRect(values[0], values[1], values[2], values[3]);
  Set<Point> draw(Command command) {
    final k = command.keyword, a = command.arguments;
    if (k == 'ERASE') { final pixels = rectPixels(intersectRect(rectangle(integers(a)), state.clip)); return {for (final (x, y) in pixels) if (layer.erase(x, y)) (x, y)}; }
    if (penCommands.contains(k)) { final pen = styles.pens[a[0]]!, pixels = penCoverage(k, pen, a.sublist(1)), color = styles.colors[pen.color]!; for (final (x, y) in pixels) { layer.paint(x, y, color, command.line); } return pixels; }
    final brush = styles.brushes[a[0]]!, pixels = brushCoverage(k, brush, a.sublist(1)), first = styles.colors[brush.colors.first]!;
    if (pixels.isEmpty) return pixels; final box = boundingBox(pixels)!;
    for (final (x, y) in pixels) { var color = first; if (brush.axis != null) { final second = styles.colors[brush.colors[1]]!, offset = brush.axis == 'x' ? x - box.$1 : y - box.$2, length = brush.axis == 'x' ? box.$3 - box.$1 : box.$4 - box.$2; if (length > 0) { int channel(int v1, int v2) => v1 + roundRatio((v2 - v1) * offset, length); color = (channel(first.$1, second.$1), channel(first.$2, second.$2), channel(first.$3, second.$3), channel(first.$4, second.$4)); } } layer.paint(x, y, color, command.line); } return pixels;
  }
  List<Point> vertices(List<String> arguments) { final v = integers(arguments.skip(1)); return [for (var i = 0; i < v.length; i += 2) state.transform(v[i], v[i + 1])]; }
  (Point, Set<Point>) shape(String keyword, List<int> v) {
    final center = state.transform(v[0], v[1]); late int rx, ry;
    if (['CIRCLE', 'FILLCIRCLE'].contains(keyword)) { final radii = state.radii(v[2], v[2]); rx = radii.$1; ry = radii.$2; if (rx == ry) return (center, circlePoints(rx)); }
    else { final radii = state.radii(v[2], v[3]); rx = radii.$1; ry = radii.$2; } return (center, ellipsePoints(rx, ry));
  }
  Set<Point> penCoverage(String keyword, Pen pen, List<String> a) {
    if (['CIRCLE', 'ELLIPSE'].contains(keyword)) { final (center, points) = shape(keyword, integers(a)); return expand(points.map((p) => (center.$1 + p.$1, center.$2 + p.$2)), pen.width); }
    late List<(Point, Point)> lines;
    if (keyword == 'LINE') { final v = integers(a); lines = [(state.transform(v[0], v[1]), state.transform(v[2], v[3]))]; }
    else if (keyword == 'RECT') { final (x0, y0, x1, y1) = rectangle(integers(a)); lines = segments([(x0, y0), (x1, y0), (x1, y1), (x0, y1)], true); }
    else if (['POLYLINE', 'POLYGON'].contains(keyword)) { lines = segments(vertices(a), keyword == 'POLYGON'); }
    else { lines = [for (final path in buildSubpaths(parsePath(a.sublist(1))!, int.parse(a[0]))) ...segments(path.points, path.closed)]; }
    final points = <Point>[];
    for (final (start, end) in lines) { final clipped = clipSegment(start, end, state.clip); if (clipped != null) points.addAll(bresenham(clipped.$1, clipped.$2)); }
    return expand([for (var i = 0; i < points.length; i++) if (pen.off == 0 || i % (pen.on + pen.off) < pen.on) points[i]], pen.width);
  }
  Set<Point> expand(Iterable<Point> points, int width) => {for (final (x, y) in points) for (final p in expandSquare(x, y, width)) if (containsPoint(state.clip, p)) p};
  Set<Point> brushCoverage(String keyword, Brush brush, List<String> a) {
    if (keyword == 'FILLRECT') return rectPixels(intersectRect(rectangle(integers(a)), state.clip));
    if (['FILLCIRCLE', 'FILLELLIPSE'].contains(keyword)) { final (center, points) = shape(keyword, integers(a)); return fillShape(center, points, state.clip); }
    if (keyword == 'FILLPOLYGON') return fillPolygons([clipPolygon(vertices(a), state.clip)], brush.rule, state.clip);
    if (keyword == 'FILLPATH') return fillPolygons([for (final path in buildSubpaths(parsePath(a.sublist(1))!, int.parse(a[0]))) clipPolygon(path.points, state.clip)], brush.rule, state.clip);
    if (keyword == 'FLOOD') return floodFill(layer, state.transform(int.parse(a[0]), int.parse(a[1])), state.clip);
    return textCoverage(int.parse(a[0]), int.parse(a[1]), a[2], a[3]);
  }
  Set<Point> textCoverage(int x, int y, String alignment, String text) {
    final advance = font.width + 1, extent = text.length * advance - 1, left = switch (alignment) { 'left' => x, 'center' => x - extent ~/ 2, _ => x - extent + 1 }; final pixels = <Point>{};
    for (var i = 0; i < text.length; i++) { final character = text[i]; if (character == '_') continue; final origin = left + i * advance; for (final (column, row) in font.glyphs[character]!) { final r = state.deviceRect(origin + column, y + row, origin + column + 1, y + row + 1); pixels.addAll(rectPixels(intersectRect((r.$1, r.$2, r.$3 - 1, r.$4 - 1), state.clip))); } } return pixels;
  }
  List<Subpath> buildSubpaths(List<PathCommand> commands, int count) {
    final paths = <Subpath>[]; Point current = (0, 0), start = (0, 0);
    for (final command in commands) { final letter = command.letter, kind = letter.toUpperCase(), v = command.values; if (kind == 'Z') { paths.last.closed = true; current = start; continue; } final (ox, oy) = letter == letter.toLowerCase() ? current : (0, 0); late List<Point> points;
      if (kind == 'H') { points = [(v[0] + ox, current.$2)]; } else if (kind == 'V') { points = [(current.$1, v[0] + oy)]; } else { points = [for (var i = 0; i < v.length; i += 2) (v[i] + ox, v[i + 1] + oy)]; }
      final device = points.map((p) => state.transform(p.$1, p.$2)).toList();
      if (kind == 'M') { paths.add(Subpath([device.first])); start = points.first; }
      else if (['L', 'H', 'V'].contains(kind)) { paths.last.points.add(device.first); }
      else { paths.last.points.addAll(bezierPoints([paths.last.points.last, ...device], count).skip(1)); }
      current = points.last;
    } return paths;
  }
}

String rgbText(Rgb color) => '${color.$1} ${color.$2} ${color.$3}';
String colorText(Color color) => '${color.$1} ${color.$2} ${color.$3} ${color.$4}';
int compareValues(List<int> a, List<int> b) { for (var i = 0; i < a.length; i++) { final c = a[i].compareTo(b[i]); if (c != 0) return c; } return 0; }
int compareRgb(Rgb a, Rgb b) => compareValues([a.$1, a.$2, a.$3], [b.$1, b.$2, b.$3]);
int compareColor(Color a, Color b) => compareValues([a.$1, a.$2, a.$3, a.$4], [b.$1, b.$2, b.$3, b.$4]);
List<MapEntry<T, int>> ranked<T>(Map<T, int> counts, int Function(T, T) compare) => counts.entries.toList()..sort((a, b) { final c = b.value.compareTo(a.value); return c != 0 ? c : compare(a.key, b.key); });
List<String> commandLines(List<Execution> executions) => [for (final e in executions) 'cmd ${e.sequence} line ${e.command.line} ${e.command.keyword} ${switch (e.kind) { 'error' => 'error ${e.error}', 'drawing' => 'pixels ${e.pixels} box ${boxText(e.box)}', _ => 'ok' }}'];
List<int> visibleCounts(List<Layer> layers, int width, int height) {
  final counts = List.filled(layers.length, 0); for (var y = 0; y < height; y++) { for (var x = 0; x < width; x++) { var covered = false; for (var i = layers.length - 1; i >= 0; i--) { final alpha = layers[i].alphaAt(x, y); if (alpha > 0 && !covered) counts[i]++; if (alpha == 255) covered = true; } } } return counts;
}
List<String> layerLines(Scene scene, List<Layer> layers, List<Execution> executions) {
  final visible = visibleCounts(layers, scene.width, scene.height), lines = ['layers ${layers.length}'];
  for (var i = 0; i < layers.length; i++) { final layer = layers[i], block = scene.layers[i], own = executions.where((e) => e.layer == i + 1).toList(), counts = <Color, int>{}, pixels = <Point>{};
    for (var y = 0; y < layer.height; y++) { for (var x = 0; x < layer.width; x++) { final color = layer.colors[y][x]; if (color != null) { pixels.add((x, y)); counts[color] = (counts[color] ?? 0) + 1; } } }
    lines.add('layer ${i + 1} ${block.name} opacity ${block.opacity} mode ${block.mode} commands ${own.length} errors ${own.where((e) => e.kind == 'error').length} pixels ${pixels.length} box ${boxText(boundingBox(pixels))} visible ${visible[i]} colors ${counts.length}');
    for (final entry in ranked(counts, compareColor).take(5)) { lines.add('color ${colorText(entry.key)} pixels ${entry.value}'); }
  } return lines;
}
Map<String, int> symbolUses(Scene scene, List<Execution> executions) {
  final uses = {for (final name in scene.symbols.keys) name: 0}; for (final e in executions) { if (e.kind == 'state' && e.command.keyword == 'USE') { final name = e.command.arguments.first; uses[name] = uses[name]! + 1; } } return uses;
}
List<(String, String)> unusedItems(Scene scene, Styles styles, List<Execution> executions) {
  final pens = <String>{}, brushes = <String>{}; for (final e in executions) { if (e.kind != 'drawing') continue; if (penCommands.contains(e.command.keyword)) { pens.add(e.command.arguments.first); } else if (brushCommands.contains(e.command.keyword)) { brushes.add(e.command.arguments.first); } }
  final colors = {scene.background, for (final name in pens) styles.pens[name]!.color, for (final name in brushes) ...styles.brushes[name]!.colors}, uses = symbolUses(scene, executions), unused = <(String, String)>[];
  void collect(String kind, Iterable<String> all, Set<String> used) { final names = all.toList()..sort(); for (final name in names) { if (!used.contains(name)) unused.add((kind, name)); } }
  collect('color', styles.colors.keys, colors); collect('pen', styles.pens.keys, pens); collect('brush', styles.brushes.keys, brushes); collect('symbol', scene.symbols.keys, {for (final entry in uses.entries) if (entry.value > 0) entry.key}); return unused;
}
List<String> summaryLines(Scene scene, Styles styles, List<Execution> executions, Image image) {
  final background = styles.colors[scene.background]!, kinds = {'drawing': 0, 'state': 0, 'error': 0}, errors = {for (final name in errorNames) name: 0}, keywords = <String, List<int>>{}; var painted = 0, erased = 0;
  for (final e in executions) { kinds[e.kind] = kinds[e.kind]! + 1; final k = e.command.keyword, tally = keywords.putIfAbsent(k, () => [0, 0, 0]); tally[0]++; if (e.kind == 'error') { errors[e.error] = errors[e.error]! + 1; tally[1]++; } else if (e.kind == 'drawing') { tally[2] += e.pixels; if (k == 'ERASE') { erased += e.pixels; } else { painted += e.pixels; } } }
  final lines = ['canvas ${scene.width} ${scene.height}', 'background ${background.$1} ${background.$2} ${background.$3}', 'layers ${scene.layers.length}', 'symbols ${scene.symbols.length}', 'commands ${executions.length}', 'drawing ${kinds['drawing']}', 'state ${kinds['state']}', 'errors ${kinds['error']}', for (final name in errorNames) 'error $name ${errors[name]}', 'painted $painted', 'erased $erased'];
  final counts = <Rgb, int>{}; for (final row in image) { for (final color in row) { counts[color] = (counts[color] ?? 0) + 1; } } lines.add('colors ${counts.length}'); final top = ranked(counts, compareRgb).take(8).toList(); for (var i = 0; i < top.length; i++) { lines.add('top ${i + 1} ${rgbText(top[i].key)} pixels ${top[i].value}'); }
  final uses = symbolUses(scene, executions), names = scene.symbols.keys.toList()..sort(); for (final name in names) { lines.add('symbol $name uses ${uses[name]}'); } final ordered = keywords.keys.toList()..sort(); for (final k in ordered) { final t = keywords[k]!; lines.add('keyword $k executed ${t[0]} errors ${t[1]} pixels ${t[2]}'); }
  final unused = unusedItems(scene, styles, executions); lines.add('unused ${unused.length}'); for (final (kind, name) in unused) { lines.add('unused $kind $name'); } return lines;
}
List<String> probeLines(List<String> probes, Image image, List<Layer> layers) {
  final lines = <String>[]; for (var i = 1; i <= int.parse(probes.first); i++) { final words = probes[i].split(' '), values = integers(words.skip(1));
    if (words.first == 'point') { final x = values[0], y = values[1], stack = [for (var j = 0; j < layers.length; j++) if (layers[j].alphaAt(x, y) > 0) '${j + 1}:${layers[j].lines[y][x]}']; lines.add('point $i $x $y rgb ${rgbText(image[y][x])} layers ${stack.length} stack ${stack.isEmpty ? 'none' : stack.join(' ')}'); }
    else { final x0 = values[0], y0 = values[1], x1 = values[2], y1 = values[3], totals = [0, 0, 0], colors = <Rgb>{}, cover = List.filled(layers.length, 0); for (var y = y0; y <= y1; y++) { for (var x = x0; x <= x1; x++) { final color = image[y][x]; colors.add(color); totals[0] += color.$1; totals[1] += color.$2; totals[2] += color.$3; for (var j = 0; j < layers.length; j++) { if (layers[j].alphaAt(x, y) > 0) cover[j]++; } } } final count = (x1 - x0 + 1) * (y1 - y0 + 1); lines.add('area $i $x0 $y0 $x1 $y1 pixels $count mean ${totals.map((total) => total ~/ count).join(' ')} colors ${colors.length} cover ${cover.join(' ')}'); }
  } return lines;
}

void main() {
  final styles = readStyles(readLines('styles.txt')), font = readFont(readLines('font.txt')), scene = SceneParser(readLines('scene.txt')).parse(), probes = readLines('probes.txt'), renderer = Renderer(scene, styles, font); renderer.run();
  final image = composite(renderer.layers, styles.colors[scene.background]!, scene.width, scene.height); Directory('output').createSync(recursive: true);
  writePpm(image); writePreview(image); writeText('commands.txt', commandLines(renderer.executions)); writeText('layers.txt', layerLines(scene, renderer.layers, renderer.executions)); writeText('summary.txt', summaryLines(scene, styles, renderer.executions, image)); writeText('probes.txt', probeLines(probes, image, renderer.layers));
}
