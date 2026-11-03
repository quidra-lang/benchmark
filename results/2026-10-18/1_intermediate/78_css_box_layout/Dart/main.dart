import 'dart:io';
import 'dart:math' as math;

typedef Declaration = (String, String);
final initial = <String, String>{
  'display': 'block', 'position': 'static', 'box-sizing': 'content-box', 'width': 'auto', 'height': 'auto',
  'min-width': '0', 'min-height': '0', 'max-width': 'none', 'max-height': 'none',
  'top': 'auto', 'right': 'auto', 'bottom': 'auto', 'left': 'auto', 'flex-direction': 'row', 'flex-wrap': 'nowrap',
  'justify-content': 'start', 'align-items': 'stretch', 'align-self': 'auto', 'row-gap': '0', 'column-gap': '0',
  'order': '0', 'flex-grow': '0', 'flex-shrink': '1', 'flex-basis': 'auto',
  'grid-template-columns': 'none', 'grid-template-rows': 'none', 'grid-column': 'auto', 'grid-row': 'auto',
  for (final prefix in ['margin', 'padding', 'border'])
    for (final side in ['top', 'right', 'bottom', 'left']) '$prefix-$side': '0'
};
final sides = ['top', 'right', 'bottom', 'left'];
final known = {...initial.keys, 'margin', 'padding', 'border', 'gap'};
final enumerations = <String, List<String>>{
  'display': ['block', 'flex', 'grid', 'none'], 'position': ['static', 'relative', 'absolute'],
  'box-sizing': ['content-box', 'border-box'], 'flex-direction': ['row', 'row-reverse', 'column', 'column-reverse'],
  'flex-wrap': ['nowrap', 'wrap'], 'justify-content': ['start', 'end', 'center', 'space-between', 'space-around', 'space-evenly'],
  'align-items': ['stretch', 'start', 'end', 'center'], 'align-self': ['auto', 'stretch', 'start', 'end', 'center']
};
bool uint(String text) => text.isNotEmpty && text.length <= 3 && !RegExp(r'[^0-9]').hasMatch(text);
bool positive(String text) => uint(text) && int.parse(text) > 0;
bool signed(String text) => uint(text.startsWith('-') ? text.substring(1) : text);
bool percentage(String text) => text.endsWith('%') && uint(text.substring(0, text.length - 1));
bool fraction(String text) => text.endsWith('fr') && positive(text.substring(0, text.length - 2));
bool gridValue(String value) {
  final words = value.split(' ');
  return value == 'auto' || words.length == 1 && positive(words[0]) ||
      words.length == 2 && words[0] == 'span' && positive(words[1]) ||
      words.length == 3 && positive(words[0]) && words[1] == '/' && positive(words[2]) && int.parse(words[0]) < int.parse(words[2]) ||
      words.length == 4 && positive(words[0]) && words[1] == '/' && words[2] == 'span' && positive(words[3]);
}
List<Declaration>? declarations(String property, String value) {
  if (!known.contains(property)) return null;
  final words = value.split(' ');
  if (['margin', 'padding', 'border'].contains(property)) {
    if (words.isEmpty || words.length > 4 || !words.every((word) => property == 'border' ? word == '0' || word == '1' : uint(word))) return null;
    final values = words.length == 1 ? [words[0], words[0], words[0], words[0]]
        : words.length == 2 ? [words[0], words[1], words[0], words[1]]
        : words.length == 3 ? [words[0], words[1], words[2], words[1]] : words;
    return [for (var i = 0; i < 4; i++) ('$property-${sides[i]}', values[i])];
  }
  if (property == 'gap') return words.length <= 2 && words.every(uint)
      ? [('row-gap', words[0]), ('column-gap', words.length == 1 ? words[0] : words[1])] : null;
  bool valid;
  if (property.startsWith('grid-template-')) { valid = value == 'none' || words.every((word) => uint(word) || fraction(word) || word == 'auto'); }
  else if (property == 'grid-column' || property == 'grid-row') { valid = gridValue(value); }
  else if (words.length != 1) { valid = false; }
  else if (enumerations.containsKey(property)) { valid = enumerations[property]!.contains(value); }
  else if (property == 'width' || property == 'height' || property == 'flex-basis') { valid = value == 'auto' || uint(value) || percentage(value); }
  else if (property.startsWith('min-')) { valid = uint(value) || percentage(value); }
  else if (property.startsWith('max-')) { valid = value == 'none' || uint(value) || percentage(value); }
  else if (property.startsWith('border-')) { valid = value == '0' || value == '1'; }
  else if (sides.contains(property)) { valid = value == 'auto' || signed(value); }
  else if (property == 'order') { valid = signed(value); }
  else { valid = uint(value); }
  return valid ? [(property, value)] : null;
}
int sum(Iterable<int> values) => values.fold<int>(0, (a, b) => a + b);
int maximumValue(Iterable<int> values) => values.fold<int>(0, math.max);
List<int> distribute(int total, List<int> weights) {
  final denominator = sum(weights);
  if (denominator == 0) return List<int>.filled(weights.length, 0);
  final result = weights.map((weight) => total * weight ~/ denominator).toList();
  var remainder = total - sum(result);
  for (var i = 0; i < weights.length && remainder > 0; i++) {
    if (weights[i] > 0) { result[i]++; remainder--; }
  }
  return result;
}
class StyleRule {
  final List<String> selectors;
  final List<Declaration> declarations;
  StyleRule(this.selectors, this.declarations);
}
class Rect {
  final int x, y, w, h;
  Rect(this.x, this.y, this.w, this.h);
  String get text => '$x $y $w $h';
}
class Boxes {
  final Rect margin, border, padding, content;
  Boxes(this.margin, this.border, this.padding, this.content);
  Map<String, Rect> get entries => {'margin': margin, 'border': border, 'padding': padding, 'content': content};
}
class Element {
  final String type, id;
  final List<String> classes;
  final String? text;
  final int depth, index;
  final Element? parent;
  final children = <Element>[];
  final overrides = <String, String>{};
  Map<String, String> style = {};
  bool shown = false;
  int cw = 0, ch = 0, rx = 0, ry = 0, x = 0, y = 0;
  List<String> lines = [];
  Element? containing;
  Element(this.type, this.id, this.classes, this.text, this.depth, this.parent, this.index);
  String value(String property) => style[property]!;
  int number(String property) => int.parse(value(property));
  int side(String prefix, String side) => number('$prefix-$side');
  int frame(bool horizontal) => horizontal
      ? side('padding', 'left') + side('padding', 'right') + side('border', 'left') + side('border', 'right')
      : side('padding', 'top') + side('padding', 'bottom') + side('border', 'top') + side('border', 'bottom');
  int margin(bool horizontal) => horizontal ? side('margin', 'left') + side('margin', 'right') : side('margin', 'top') + side('margin', 'bottom');
  int borderWidth() => cw + frame(true);
  int borderHeight() => ch + frame(false);
  List<Element> flow() => children.where((child) => child.shown && child.value('position') != 'absolute').toList();
  List<Element> items() => flow()..sort((a, b) {
    final order = a.number('order').compareTo(b.number('order'));
    return order == 0 ? a.index.compareTo(b.index) : order;
  });
  int? resolve(String property, int? reference, bool horizontal) {
    final word = value(property);
    if (word == 'auto' || word == 'none' || word.endsWith('%') && reference == null) return null;
    final size = word.endsWith('%') ? reference! * int.parse(word.substring(0, word.length - 1)) ~/ 100 : int.parse(word);
    return value('box-sizing') == 'border-box' ? math.max(0, size - frame(horizontal)) : size;
  }
  int clamp(int value, bool horizontal, int? reference) {
    final suffix = horizontal ? 'width' : 'height';
    final lower = resolve('min-$suffix', reference, horizontal) ?? 0, upper = resolve('max-$suffix', reference, horizontal);
    return math.max(lower, upper == null ? value : math.min(value, upper));
  }
  void place(Element child, int x, int y) {
    child.rx = x + side('border', 'left') + side('padding', 'left');
    child.ry = y + side('border', 'top') + side('padding', 'top');
  }
}
class GridItem {
  final Element node;
  int? column, row;
  final int cs, rs;
  int contribution = 0, aw = 0, ax = 0, gw = 0;
  GridItem(this.node, this.column, this.row, this.cs, this.rs);
}
class Grid {
  final List<String> columns, rows;
  final List<GridItem> items;
  final int nc, nr;
  Grid(this.columns, this.rows, this.items, this.nc, this.nr);
}
class FlexItem {
  final Element node;
  final String alignment;
  final int base, hypothetical, outer;
  int cross, target, weight = 0;
  bool frozen = false;
  FlexItem(this.node, this.alignment, this.cross, this.base, this.hypothetical, this.outer) : target = hypothetical;
}
final elements = <Element>[], byId = <String, Element>{}, rules = <StyleRule>[], output = <String>[];
var width = 0, height = 0;
final maximumCache = <Element, int>{};
String align(Element parent, Element child) => child.value('align-self') == 'auto' ? parent.value('align-items') : child.value('align-self');
int contribution(Element element) => element.clamp(element.resolve('width', null, true) ?? maximum(element), true, null) + element.frame(true) + element.margin(true);
Grid placement(Element element) {
  final columns = element.value('grid-template-columns') == 'none' ? ['auto'] : element.value('grid-template-columns').split(' ');
  final rows = element.value('grid-template-rows') == 'none' ? <String>[] : element.value('grid-template-rows').split(' ');
  (int?, int) axis(String value) {
    final words = value.split(' ');
    if (value == 'auto') return (null, 1);
    if (words[0] == 'span') return (null, int.parse(words[1]));
    return (int.parse(words[0]), words.length == 1 ? 1 : words.length == 3 ? int.parse(words[2]) - int.parse(words[0]) : int.parse(words[3]));
  }
  final items = element.items().map((node) {
    final (column, cs) = axis(node.value('grid-column'));
    final (row, rs) = axis(node.value('grid-row'));
    return GridItem(node, column, row, cs, rs);
  }).toList();
  final nc = math.max(columns.length, maximumValue(items.map((item) => item.column == null ? item.cs : item.column! + item.cs - 1)));
  final occupied = <(int, int)>{};
  bool overlaps(GridItem item, int r, int c) {
    for (var y = r; y < r + item.rs; y++) {
      for (var x = c; x < c + item.cs; x++) { if (occupied.contains((y, x))) return true; }
    }
    return false;
  }
  void put(GridItem item, int r, int c) {
    item.row = r;
    item.column = c;
    for (var y = r; y < r + item.rs; y++) {
      for (var x = c; x < c + item.cs; x++) { occupied.add((y, x)); }
    }
  }
  final pending = items.where((item) => item.row == null || item.column == null).toList();
  for (final item in items) { if (item.row != null && item.column != null) put(item, item.row!, item.column!); }
  var cr = 1, cc = 1;
  for (final item in pending) {
    if (item.row != null) {
      var column = 1;
      while (column <= nc - item.cs + 1 && overlaps(item, item.row!, column)) { column++; }
      put(item, item.row!, column <= nc - item.cs + 1 ? column : 1);
    } else if (item.column != null) {
      if (item.column! < cc) cr++;
      var row = cr;
      while (overlaps(item, row, item.column!)) { row++; }
      put(item, row, item.column!);
      cr = row;
      cc = item.column! + item.cs;
    } else {
      var row = cr, column = cc;
      while (true) {
        if (column + item.cs - 1 > nc) { row++; column = 1; }
        else if (overlaps(item, row, column)) { column++; }
        else { break; }
      }
      put(item, row, column);
      cr = row;
      cc = column + item.cs;
    }
  }
  return Grid(columns, rows, items, nc, math.max(rows.length, maximumValue(items.map((item) => item.row! + item.rs - 1))));
}
List<int> trackSizes(List<String> explicit, int count, int? available, int gap, List<GridItem> items, bool horizontal, List<int> contributions) {
  final tracks = [...explicit, ...List<String>.filled(math.max(0, count - explicit.length), 'auto')];
  final sizes = <int>[];
  for (var i = 0; i < tracks.length; i++) {
    final track = tracks[i];
    if (uint(track)) { sizes.add(int.parse(track)); }
    else if (fraction(track) && available != null) { sizes.add(0); }
    else {
      var size = 0;
      for (var j = 0; j < items.length; j++) {
        final item = items[j];
        if ((horizontal ? item.column : item.row) == i + 1 && (horizontal ? item.cs : item.rs) == 1) size = math.max(size, contributions[j]);
      }
      sizes.add(size);
    }
  }
  if (available != null) {
    final remaining = available - sum(sizes) - gap * math.max(0, count - 1), hasFr = tracks.any(fraction);
    if (remaining > 0) {
      final weights = tracks.map((track) => hasFr ? fraction(track) ? int.parse(track.substring(0, track.length - 2)) : 0 : track == 'auto' ? 1 : 0).toList();
      final shares = distribute(remaining, weights);
      for (var i = 0; i < sizes.length; i++) { sizes[i] += shares[i]; }
    }
  }
  return sizes;
}
int maximum(Element element) {
  final cached = maximumCache[element];
  if (cached != null) return cached;
  int result;
  if (element.text != null) { result = element.text!.length; }
  else if (element.value('display') == 'grid') {
    final grid = placement(element), gap = element.number('column-gap');
    result = sum(trackSizes(grid.columns, grid.nc, null, gap, grid.items, true, grid.items.map((item) => contribution(item.node)).toList())) + gap * (grid.nc - 1);
  } else {
    final children = element.flow();
    result = element.value('display') == 'flex' && element.value('flex-direction').startsWith('row')
        ? sum(children.map(contribution)) + element.number('column-gap') * math.max(0, children.length - 1)
        : maximumValue(children.map(contribution));
  }
  maximumCache[element] = result;
  return result;
}
int layout(Element element, int widthReference, int? heightReference, [int? forcedWidth, int? forcedHeight]) {
  element.cw = forcedWidth ?? element.clamp(element.resolve('width', widthReference, true) ?? math.max(0, widthReference - element.margin(true) - element.frame(true)), true, widthReference);
  var fixed = forcedHeight;
  if (fixed == null) {
    final resolved = element.resolve('height', heightReference, false);
    if (resolved != null) fixed = element.clamp(resolved, false, heightReference);
  }
  var content = 0;
  element.lines = [];
  if (element.text != null) {
    for (final word in element.text!.split(' ')) {
      if (element.lines.isEmpty || element.lines.last.length + 1 + word.length > element.cw) { element.lines.add(word); }
      else { element.lines[element.lines.length - 1] += ' $word'; }
    }
    content = element.lines.length;
  } else if (element.value('display') == 'flex') { content = flex(element, fixed, heightReference); }
  else if (element.value('display') == 'grid') { content = gridLayout(element, fixed); }
  else {
    var bottom = 0, previousMargin = 0;
    for (final child in element.flow()) {
      layout(child, element.cw, fixed);
      final top = bottom + math.max(previousMargin, child.side('margin', 'top'));
      element.place(child, child.side('margin', 'left'), top);
      bottom = top + child.borderHeight();
      previousMargin = child.side('margin', 'bottom');
    }
    content = bottom + previousMargin;
  }
  element.ch = fixed ?? element.clamp(content, false, heightReference);
  return content;
}
int flex(Element element, int? k, int? heightReference) {
  final horizontal = element.value('flex-direction').startsWith('row'), reverse = element.value('flex-direction').endsWith('reverse');
  final reference = horizontal ? element.cw : k, gap = element.number(horizontal ? 'column-gap' : 'row-gap'), lineGap = element.number('row-gap');
  final items = <FlexItem>[];
  for (final node in element.items()) {
    final alignment = align(element, node);
    var cross = 0;
    if (!horizontal) {
      final available = math.max(0, element.cw - node.margin(true) - node.frame(true));
      cross = node.clamp(node.value('width') != 'auto' ? node.resolve('width', element.cw, true)!
          : alignment == 'stretch' ? available : math.min(maximum(node), available), true, element.cw);
    }
    final base = node.resolve('flex-basis', reference, horizontal) ?? node.resolve(horizontal ? 'width' : 'height', reference, horizontal)
        ?? (horizontal ? maximum(node) : layout(node, element.cw, k, cross));
    final hypothetical = node.clamp(base, horizontal, reference), outer = node.frame(horizontal) + node.margin(horizontal);
    items.add(FlexItem(node, alignment, cross, base, hypothetical, outer));
  }
  final main = horizontal ? element.cw : k ?? element.clamp(sum(items.map((item) => item.hypothetical + item.outer)) + gap * math.max(0, items.length - 1), false, heightReference);
  final lines = <List<FlexItem>>[];
  for (final item in items) {
    if (lines.isEmpty || horizontal && element.value('flex-wrap') == 'wrap' &&
        sum(lines.last.map((other) => other.hypothetical + other.outer)) + gap * lines.last.length + item.hypothetical + item.outer > main) {
      lines.add([item]);
    } else { lines.last.add(item); }
  }
  var crossStart = 0;
  for (final line in lines) {
    final growing = sum(line.map((item) => item.hypothetical + item.outer)) + gap * (line.length - 1) < main;
    for (final item in line) {
      item.weight = growing ? item.node.number('flex-grow') : item.node.number('flex-shrink') * item.base;
      item.frozen = item.weight == 0 || (growing ? item.base > item.hypothetical : item.base < item.hypothetical);
    }
    while (line.any((item) => !item.frozen)) {
      final free = main - gap * (line.length - 1) - sum(line.map((item) => (item.frozen ? item.target : item.base) + item.outer));
      final shares = distribute(math.max(0, growing ? free : -free), line.map((item) => item.frozen ? 0 : item.weight).toList());
      final violations = List<int>.filled(line.length, 0);
      for (var i = 0; i < line.length; i++) {
        final item = line[i];
        if (item.frozen) continue;
        final tentative = item.base + (growing ? shares[i] : -shares[i]);
        item.target = item.node.clamp(tentative, horizontal, reference);
        violations[i] = item.target - tentative;
      }
      final total = sum(violations);
      for (var i = 0; i < line.length; i++) {
        if (total == 0 || (total > 0 ? violations[i] > 0 : violations[i] < 0)) line[i].frozen = true;
      }
    }
    if (horizontal) {
      for (final item in line) { layout(item.node, element.cw, k, item.target); item.cross = item.node.ch; }
    }
    final outerCross = maximumValue(line.map((item) => item.cross + item.node.frame(!horizontal) + item.node.margin(!horizontal)));
    final lineCross = horizontal ? lines.length == 1 ? k ?? element.clamp(outerCross, false, heightReference) : outerCross : element.cw;
    final remaining = main - sum(line.map((item) => item.target + item.outer)) - gap * (line.length - 1);
    final spaces = List<int>.filled(line.length, 0), justification = element.value('justify-content');
    if (remaining > 0) {
      if (justification == 'end') { spaces[0] = remaining; }
      else if (justification == 'center') { spaces[0] = remaining ~/ 2; }
      else if (justification.startsWith('space-')) {
        final weights = List<int>.generate(line.length + 1, (i) => justification == 'space-evenly' ? 1
            : i == 0 || i == line.length ? justification == 'space-between' ? 0 : 1 : justification == 'space-between' ? 1 : 2);
        final shares = distribute(remaining, weights);
        for (var i = 0; i < spaces.length; i++) { spaces[i] = shares[i]; }
      }
    }
    var cursor = 0;
    for (var i = 0; i < line.length; i++) {
      final item = line[i], node = line[i].node;
      if (horizontal && item.alignment == 'stretch' && node.value('height') == 'auto') {
        item.cross = node.clamp(math.max(0, lineCross - node.margin(false) - node.frame(false)), false, k);
        layout(node, element.cw, k, item.target, item.cross);
      } else if (horizontal) { layout(node, element.cw, k, item.target); item.cross = node.ch; }
      else { layout(node, element.cw, k, item.cross, item.target); }
      final spare = lineCross - item.cross - node.frame(!horizontal) - node.margin(!horizontal);
      final offset = spare > 0 ? item.alignment == 'end' ? spare : item.alignment == 'center' ? spare ~/ 2 : 0 : 0;
      cursor += spaces[i];
      final startMargin = node.side('margin', horizontal ? reverse ? 'right' : 'left' : reverse ? 'bottom' : 'top');
      final mainPosition = reverse ? main - cursor - startMargin - (horizontal ? node.borderWidth() : node.borderHeight()) : cursor + startMargin;
      final crossPosition = crossStart + offset + node.side('margin', horizontal ? 'top' : 'left');
      element.place(node, horizontal ? mainPosition : crossPosition, horizontal ? crossPosition : mainPosition);
      cursor += item.target + item.outer + gap;
    }
    crossStart += lineCross + lineGap;
  }
  return horizontal ? lines.isEmpty ? 0 : crossStart - lineGap : main;
}
(int, int) area(List<int> sizes, int start, int span, int gap) =>
    (sum(sizes.skip(start - 1).take(span)) + gap * (span - 1), sum(sizes.take(start - 1)) + gap * (start - 1));
int gridLayout(Element element, int? k) {
  final grid = placement(element), columnGap = element.number('column-gap'), rowGap = element.number('row-gap');
  final columns = trackSizes(grid.columns, grid.nc, element.cw, columnGap, grid.items, true, grid.items.map((item) => contribution(item.node)).toList());
  for (final item in grid.items) {
    final node = item.node;
    final (aw, ax) = area(columns, item.column!, item.cs, columnGap);
    item.aw = aw;
    item.ax = ax;
    item.gw = node.clamp(node.resolve('width', aw, true) ?? math.max(0, aw - node.margin(true) - node.frame(true)), true, aw);
    layout(node, aw, null, item.gw);
    item.contribution = node.borderHeight() + node.margin(false);
  }
  final rows = trackSizes(grid.rows, grid.nr, k, rowGap, grid.items, false, grid.items.map((item) => item.contribution).toList());
  for (final item in grid.items) {
    final node = item.node, alignment = align(element, item.node);
    final (ah, ay) = area(rows, item.row!, item.rs, rowGap);
    if (alignment == 'stretch' && node.value('height') == 'auto') {
      layout(node, item.aw, ah, item.gw, node.clamp(math.max(0, ah - node.margin(false) - node.frame(false)), false, ah));
    } else { layout(node, item.aw, ah, item.gw); }
    final spare = ah - node.borderHeight() - node.margin(false);
    final offset = spare > 0 ? alignment == 'end' ? spare : alignment == 'center' ? spare ~/ 2 : 0 : 0;
    element.place(node, item.ax + node.side('margin', 'left'), ay + offset + node.side('margin', 'top'));
  }
  return sum(rows) + rowGap * math.max(0, grid.nr - 1);
}
void relayout() {
  maximumCache.clear();
  for (final node in elements) {
    node.style = Map.of(initial);
    final ranks = <String, int>{};
    for (final rule in rules) {
      final matching = rule.selectors.where((selector) => selector[0] == '#' ? selector.substring(1) == node.id
          : selector[0] == '.' ? node.classes.contains(selector.substring(1)) : selector == node.type).toList();
      if (matching.isEmpty) continue;
      final rank = maximumValue(matching.map((selector) => selector[0] == '#' ? 2 : selector[0] == '.' ? 1 : 0));
      for (final (property, value) in rule.declarations) {
        if (!ranks.containsKey(property) || rank >= ranks[property]!) { node.style[property] = value; ranks[property] = rank; }
      }
    }
    node.style.addAll(node.overrides);
    node.shown = node.value('display') != 'none' && (node.parent?.shown ?? true);
    node.containing = null;
  }
  final root = elements.first;
  if (root.shown && root.value('position') != 'absolute') {
    layout(root, width, height);
    root.rx = root.side('margin', 'left');
    root.ry = root.side('margin', 'top');
  }
  for (final node in elements) {
    if (!node.shown || node.value('position') != 'absolute') continue;
    var containing = node.parent;
    while (containing != null && containing.value('position') == 'static') { containing = containing.parent; }
    node.containing = containing;
    final cbw = containing == null ? width : containing.cw + containing.side('padding', 'left') + containing.side('padding', 'right');
    final cbh = containing == null ? height : containing.ch + containing.side('padding', 'top') + containing.side('padding', 'bottom');
    final left = node.value('left') == 'auto' ? null : node.number('left'), right = node.value('right') == 'auto' ? null : node.number('right');
    final top = node.value('top') == 'auto' ? null : node.number('top'), bottom = node.value('bottom') == 'auto' ? null : node.number('bottom');
    final available = math.max(0, cbw - (left ?? 0) - (right ?? 0) - node.margin(true) - node.frame(true));
    final fw = node.clamp(node.value('width') != 'auto' ? node.resolve('width', cbw, true)!
        : left != null && right != null ? available : math.min(maximum(node), available), true, cbw);
    final fh = node.value('height') == 'auto' && top != null && bottom != null
        ? node.clamp(math.max(0, cbh - top - bottom - node.margin(false) - node.frame(false)), false, cbh) : null;
    layout(node, cbw, cbh, fw, fh);
    node.rx = left != null ? left + node.side('margin', 'left') : right != null ? cbw - right - node.side('margin', 'right') - node.borderWidth() : node.side('margin', 'left');
    node.ry = top != null ? top + node.side('margin', 'top') : bottom != null ? cbh - bottom - node.side('margin', 'bottom') - node.borderHeight() : node.side('margin', 'top');
  }
  for (final node in elements) {
    if (!node.shown) continue;
    final absolute = node.value('position') == 'absolute', reference = node.value('position') == 'absolute' ? node.containing : node.parent;
    node.x = (reference == null ? 0 : reference.x + (absolute ? reference.side('border', 'left') : 0)) + node.rx;
    node.y = (reference == null ? 0 : reference.y + (absolute ? reference.side('border', 'top') : 0)) + node.ry;
    if (node.value('position') == 'relative') {
      node.x += node.value('left') != 'auto' ? node.number('left') : node.value('right') != 'auto' ? -node.number('right') : 0;
      node.y += node.value('top') != 'auto' ? node.number('top') : node.value('bottom') != 'auto' ? -node.number('bottom') : 0;
    }
  }
}
Boxes boxes(Element node) {
  final border = Rect(node.x, node.y, node.borderWidth(), node.borderHeight());
  final margin = Rect(node.x - node.side('margin', 'left'), node.y - node.side('margin', 'top'), border.w + node.margin(true), border.h + node.margin(false));
  final padding = Rect(node.x + node.side('border', 'left'), node.y + node.side('border', 'top'),
      border.w - node.side('border', 'left') - node.side('border', 'right'), border.h - node.side('border', 'top') - node.side('border', 'bottom'));
  return Boxes(margin, border, padding, Rect(padding.x + node.side('padding', 'left'), padding.y + node.side('padding', 'top'), node.cw, node.ch));
}
List<String> snapshot() => elements.map((node) => node.shown ? boxes(node).border.text : 'none').toList();
String changed(List<String> before) {
  final names = <String>[];
  for (var i = 0; i < elements.length; i++) {
    final node = elements[i];
    if (before[i] != (node.shown ? boxes(node).border.text : 'none')) names.add(node.id);
  }
  return names.isEmpty ? 'no change' : names.join(' ');
}
void render() {
  final screen = List.generate(height, (_) => List<String>.filled(width, '.'));
  void paint(int x, int y, String c) { if (x >= 0 && x < width && y >= 0 && y < height) screen[y][x] = c; }
  for (final node in elements) {
    if (!node.shown) continue;
    final bw = node.borderWidth(), bh = node.borderHeight();
    for (var y = math.max(0, node.y); y < math.min(height, node.y + bh); y++) {
      for (var x = math.max(0, node.x); x < math.min(width, node.x + bw); x++) {
        final horizontal = node.side('border', 'top') == 1 && y == node.y || node.side('border', 'bottom') == 1 && y == node.y + bh - 1;
        final vertical = node.side('border', 'left') == 1 && x == node.x || node.side('border', 'right') == 1 && x == node.x + bw - 1;
        screen[y][x] = horizontal ? vertical ? '+' : '-' : vertical ? '|' : ' ';
      }
    }
    if (node.text != null) {
      final content = boxes(node).content;
      for (var i = 0; i < node.lines.length; i++) {
        final line = node.lines[i];
        for (var j = 0; j < line.length; j++) { paint(content.x + j, content.y + i, line[j]); }
      }
    }
  }
  final edge = ''.padRight(width + 2, '#');
  output.addAll(['render ${width}x$height', edge, ...screen.map((row) => '#${row.join()}#'), edge]);
}
void execute(String line) {
  final words = line.split(' ');
  final command = words.first, args = words.skip(1).toList();
  final id = args.isEmpty ? '' : args[0];
  if (command == 'LAYOUT') {
    output.add('layout ${width}x$height');
    for (final node in elements) { output.add('${''.padRight(node.depth * 2)}${node.id} ${node.shown ? boxes(node).border.text : 'none'}'); }
  } else if (command == 'BOX') {
    final node = byId[id];
    if (node == null) { output.add('error: unknown element $id'); return; }
    if (!node.shown) { output.add('box $id: none'); }
    else {
      output.add('box $id');
      for (final entry in boxes(node).entries.entries) { output.add('${entry.key} ${entry.value.text}'); }
    }
  } else if (command == 'RENDER') { render(); }
  else if (command == 'HIT') {
    final x = int.parse(args[0]), y = int.parse(args[1]);
    if (x >= width || y >= height) { output.add('error: point $x $y outside viewport'); return; }
    Element? selected;
    for (final node in elements) {
      if (node.shown && x >= node.x && y >= node.y && x < node.x + node.borderWidth() && y < node.y + node.borderHeight()) selected = node;
    }
    final path = <String>[];
    for (var current = selected; current != null; current = current.parent) { path.add(current.id); }
    output.add('hit $x $y: ${path.isEmpty ? 'none' : path.reversed.join(' > ')}');
  } else if (command == 'SET') {
    final node = byId[id], property = args[1], value = args.skip(2).join(' ');
    if (node == null) { output.add('error: unknown element $id'); return; }
    if (!known.contains(property)) { output.add('error: unknown property $property'); return; }
    final expanded = declarations(property, value);
    if (expanded == null) { output.add('error: invalid value for $property: $value'); return; }
    final before = snapshot();
    for (final (key, item) in expanded) { node.overrides[key] = item; }
    relayout();
    output.add('set $id $property $value: ${changed(before)}');
  } else if (command == 'VIEWPORT') {
    final w = int.parse(args[0]), h = int.parse(args[1]);
    if (w < 1 || w > 80 || h < 1 || h > 40) { output.add('error: invalid viewport $w $h'); return; }
    final before = snapshot();
    width = w;
    height = h;
    relayout();
    output.add('viewport $w $h: ${changed(before)}');
  } else if (command == 'OVERFLOW') {
    final overflowing = <String>[];
    for (final node in elements) {
      if (!node.shown) continue;
      bool overflow;
      if (node.text != null) { overflow = maximumValue(node.lines.map((line) => line.length)) > node.cw || node.lines.length > node.ch; }
      else {
        final content = boxes(node).content;
        overflow = node.flow().any((child) {
          final margin = boxes(child).margin;
          return margin.x < content.x || margin.y < content.y || margin.x + margin.w > content.x + content.w || margin.y + margin.h > content.y + content.h;
        });
      }
      if (overflow) overflowing.add(node.id);
    }
    output.add('overflow: ${overflowing.isEmpty ? 'none' : overflowing.join(' ')}');
  } else { output.add('error: unknown command $command'); }
}
void main() {
  final dimensions = stdin.readLineSync()!.split(' ').map(int.parse).toList();
  width = dimensions[0];
  height = dimensions[1];
  String line;
  while ((line = stdin.readLineSync()!) != '---') {
    final split = line.indexOf(' { '), expanded = <Declaration>[];
    for (final item in line.substring(split + 3, line.length - 2).split('; ')) {
      final colon = item.indexOf(': ');
      expanded.addAll(declarations(item.substring(0, colon), item.substring(colon + 2)) ?? []);
    }
    rules.add(StyleRule(line.substring(0, split).split(', '), expanded));
  }
  final stack = <Element>[];
  while ((line = stdin.readLineSync()!) != '===') {
    var spaces = 0;
    while (spaces < line.length && line[spaces] == ' ') { spaces++; }
    final depth = spaces ~/ 2, text = line.substring(spaces), space = line.substring(spaces).indexOf(' ');
    final head = space < 0 ? text : text.substring(0, space), hash = (space < 0 ? text : text.substring(0, space)).indexOf('#');
    final parts = head.substring(hash + 1).split('.'), parent = depth == 0 ? null : stack[depth - 1];
    final node = Element(head.substring(0, hash), parts[0], parts.skip(1).toList(), space < 0 ? null : text.substring(space + 2, text.length - 1), depth, parent, elements.length);
    parent?.children.add(node);
    elements.add(node);
    byId[node.id] = node;
    stack.length = depth;
    stack.add(node);
  }
  relayout();
  while ((line = stdin.readLineSync()!) != 'END') { execute(line); }
  if (output.isNotEmpty) stdout.write('${output.join('\n')}\n');
}
