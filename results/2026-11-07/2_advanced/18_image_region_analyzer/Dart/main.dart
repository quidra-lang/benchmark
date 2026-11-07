import 'dart:math' as math;
import 'pgm_reader.dart';
import 'threshold.dart';
import 'morphology.dart';
import 'labeling.dart';
import 'report.dart';

const symbols = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz';
const orientations = ['none', 'horizontal', 'vertical', 'falling', 'rising'];
const four = [Point(1, 0), Point(0, -1), Point(-1, 0), Point(0, 1)];
const eight = [Point(1, 0), Point(1, -1), Point(0, -1), Point(-1, -1), Point(-1, 0), Point(-1, 1), Point(0, 1), Point(1, 1)];
const csvHeader = 'image,label,class,flags,area,x0,y0,x1,y1,cx,cy,mean,variance,min,max,contrast,border,perimeter,chain,straight,diagonal,turns,compactness,runs,holes,hole_area,euler,parent,depth,var_x,var_y,cov_xy,hu1,orientation,anisotropy,extent,mirror_lr,mirror_tb,hull_area,solidity,feret2,width2,elongation,bays,bay_area,skeleton,endpoints,branches,neighbor,distance2,codes';

class Setting {
  final int connectivity;
  final String threshold;
  final String polarity;
  final List<String> operations;
  Setting(this.connectivity, this.threshold, this.polarity, this.operations);
  String get method => threshold == 'otsu' || threshold == 'isodata' ? threshold : 'fixed';
}

class Parameters {
  var otsuTop = 0, sweepStep = 0, bayMin = 0;
  var isotropy = Rational(0);
  final elements = <String, List<Point>>{};
  final settings = <String, Setting>{};
}

Rational parseRational(String text) {
  final parts = text.split('/');
  return Rational(int.parse(parts.first), parts.length == 1 ? 1 : int.parse(parts[1]));
}

Parameters readParameters(String path) {
  final result = Parameters();
  for (final line in readText(path).split('\n')) {
    if (line.isEmpty) {
      continue;
    }
    final words = line.split(' ');
    switch (words.first) {
      case 'otsu_top':
        result.otsuTop = int.parse(words[1]);
      case 'sweep':
        result.sweepStep = int.parse(words[1]);
      case 'isotropy':
        result.isotropy = parseRational(words[1]);
      case 'bay_min':
        result.bayMin = int.parse(words[1]);
      case 'element':
        final ox = int.parse(words[4]), oy = int.parse(words[5]);
        final offsets = <Point>[];
        for (var y = 0; y < words.length - 6; y++) {
          for (var x = 0; x < words[y + 6].length; x++) {
            if (words[y + 6][x] == '#') {
              offsets.add(Point(x - ox, y - oy));
            }
          }
        }
        result.elements[words[1]] = offsets;
      case 'image':
        result.settings[words[1]] = Setting(int.parse(words[2]), words[3], words[4], words.sublist(5));
    }
  }
  return result;
}

class Condition {
  final String feature;
  final String comparison;
  final String text;
  late final Rational value = feature == 'orientation' ? Rational(0) : parseRational(text);
  Condition(this.feature, this.comparison, this.text);

  bool holds(Region region) {
    final order = feature == 'orientation' ? region.orientation.compareTo(text) : region.features[feature]!.compareTo(value);
    return switch (comparison) {
      '<' => order < 0,
      '<=' => order <= 0,
      '>' => order > 0,
      '>=' => order >= 0,
      '=' => order == 0,
      '!=' => order != 0,
      _ => throw StateError('Invalid comparison'),
    };
  }
  String get words => '$feature $comparison $text';
}

class Rule {
  final String name;
  final List<Condition> conditions;
  Rule(this.name, this.conditions);
  bool matches(Region region) => conditions.every((condition) => condition.holds(region));
}

class Rules {
  final filters = <Condition>[];
  final classes = <Rule>[];
  final flags = <Rule>[];
  List<String> get classNames => {...classes.map((rule) => rule.name), 'other'}.toList();
}

Rules readRules(String path) {
  final result = Rules();
  for (final line in readText(path).split('\n')) {
    if (line.isEmpty) {
      continue;
    }
    final words = line.split(' ');
    if (words.first == 'filter') {
      result.filters.add(Condition(words[1], words[2], words[3]));
    } else {
      final conditions = <Condition>[];
      for (var i = 2; i < words.length; i += 3) {
        conditions.add(Condition(words[i], words[i + 1], words[i + 2]));
      }
      final rule = Rule(words[1], conditions);
      (words.first == 'class' ? result.classes : result.flags).add(rule);
    }
  }
  return result;
}

class Hole {
  final int number;
  final List<Point> pixels;
  final int owner;
  Hole(this.number, this.pixels, this.owner);
}

class Region {
  final int number;
  final List<Point> pixels;
  final features = <String, Rational>{};
  var orientation = 'none';
  var codes = <int>[];
  var skeleton = <Point>{};
  var hullDoubled = 0;
  var parent = 0, depth = 0;
  final children = <int>[];
  var kept = false;
  var droppedBy = -1;
  var className = 'other';
  var flags = <String>[];
  var neighbor = 0, distance = 0;
  Region(this.number, this.pixels);
  int integer(String name) => features[name]!.p ~/ features[name]!.q;
  void setInt(String name, int value) => features[name] = Rational(value);
}

List<Point> directions(int connectivity) => connectivity == 4 ? four : eight;
int countForeground(Mask mask) => mask.fold(0, (sum, row) => sum + row.where((value) => value).length);

List<List<Point>> groupPixels(List<List<int>> labels, int count) {
  final groups = List.generate(count + 1, (_) => <Point>[]);
  for (var y = 0; y < labels.length; y++) {
    for (var x = 0; x < labels.first.length; x++) {
      groups[labels[y][x]].add(Point(x, y));
    }
  }
  return groups;
}

List<List<Point>> enclosedComponents(Mask mask, int connectivity) {
  final background = [for (final row in mask) [for (final value in row) !value]];
  final result = labelComponents(background, connectivity);
  return groupPixels(result.labels, result.count).skip(1).where((pixels) =>
      !pixels.any((point) => point.x == 0 || point.y == 0 || point.x == mask.first.length - 1 || point.y == mask.length - 1)).toList();
}

Mask fillHoles(Mask mask, int connectivity) {
  final result = [for (final row in mask) [...row]];
  for (final pixels in enclosedComponents(mask, connectivity)) {
    for (final point in pixels) {
      result[point.y][point.x] = true;
    }
  }
  return result;
}

int cross(Point a, Point b, Point point) => (b.x - a.x) * (point.y - a.y) - (b.y - a.y) * (point.x - a.x);
int squaredDistance(Point a, Point b) {
  final dx = a.x - b.x, dy = a.y - b.y;
  return dx * dx + dy * dy;
}

List<Point> halfHull(Iterable<Point> points) {
  final chain = <Point>[];
  for (final point in points) {
    while (chain.length >= 2 && cross(chain[chain.length - 2], chain.last, point) <= 0) {
      chain.removeLast();
    }
    chain.add(point);
  }
  return chain;
}

List<Point> convexHull(List<Point> pixels) {
  final corners = <Point>{};
  for (final point in pixels) {
    for (var dy = 0; dy <= 1; dy++) {
      for (var dx = 0; dx <= 1; dx++) {
        corners.add(Point(point.x + dx, point.y + dy));
      }
    }
  }
  final ordered = corners.toList()..sort((a, b) => a.x == b.x ? a.y.compareTo(b.y) : a.x.compareTo(b.x));
  final lower = halfHull(ordered), upper = halfHull(ordered.reversed);
  return [...lower.take(lower.length - 1), ...upper.take(upper.length - 1)];
}

bool containsCenter(List<Point> hull, int x, int y) {
  final center = Point(2 * x + 1, 2 * y + 1);
  for (var i = 0; i < hull.length; i++) {
    final a = hull[i], b = hull[(i + 1) % hull.length];
    if (cross(Point(2 * a.x, 2 * a.y), Point(2 * b.x, 2 * b.y), center) < 0) {
      return false;
    }
  }
  return true;
}

(int, int, int, int) boxBounds(List<Point> pixels) {
  var x0 = pixels.first.x, x1 = x0;
  var y0 = pixels.first.y, y1 = y0;
  for (final point in pixels) {
    x0 = math.min(x0, point.x);
    x1 = math.max(x1, point.x);
    y0 = math.min(y0, point.y);
    y1 = math.max(y1, point.y);
  }
  return (x0, y0, x1, y1);
}

int boxDistance(Region first, Region second) {
  final dx = first.integer('x0') + first.integer('x1') - second.integer('x0') - second.integer('x1');
  final dy = first.integer('y0') + first.integer('y1') - second.integer('y0') - second.integer('y1');
  return dx * dx + dy * dy;
}

String meanText(int total, int count) => count == 0 ? '-' : decimal(Rational(total, count), 2);
String orientationLine(List<Region> regions) => ['orientations', for (final name in orientations) '$name ${regions.where((region) => region.orientation == name).length}'].join(' ');

class ImageAnalysis {
  final Image image;
  final Setting setting;
  late final Histogram histogram;
  late final OtsuResult otsuResult;
  late final int isodataCutoff;
  late final int isodataIterations;
  late final int cutoff;
  late final Mask initial;
  late Mask finalMask;
  final morphCounts = <int>[];
  final sweep = <(int, int, int)>[];
  late final List<List<int>> labels;
  late final int provisional;
  final regions = <Region>[];
  late final int fourComponents;
  late final int eightComponents;
  late final int bitQuad;
  final holes = <Hole>[];
  late final List<List<int>> holeOf;

  ImageAnalysis(this.image, this.setting, Parameters parameters) {
    histogram = Histogram(image);
    otsuResult = otsu(histogram);
    final (isoCutoff, isoIterations) = isodata(histogram);
    isodataCutoff = isoCutoff;
    isodataIterations = isoIterations;
    cutoff = switch (setting.threshold) {
      'otsu' => otsuResult.cutoff,
      'isodata' => isoCutoff,
      _ => int.parse(setting.threshold),
    };
    initial = binarize(cutoff);
    finalMask = initial;
    for (final operation in setting.operations) {
      if (operation == 'fill') {
        finalMask = fillHoles(finalMask, 12 - setting.connectivity);
      } else {
        final parts = operation.split(':');
        final offsets = parameters.elements[parts[1]]!;
        finalMask = switch (parts.first) {
          'erode' => erode(finalMask, offsets),
          'dilate' => dilate(finalMask, offsets),
          'open' => opening(finalMask, offsets),
          'close' => closing(finalMask, offsets),
          _ => throw StateError('Invalid operation'),
        };
      }
      morphCounts.add(countForeground(finalMask));
    }
    for (var t = parameters.sweepStep; t < image.maxval; t += parameters.sweepStep) {
      final mask = binarize(t);
      sweep.add((t, countForeground(mask), labelComponents(mask, setting.connectivity).count));
    }
    final result = labelComponents(finalMask, setting.connectivity);
    labels = result.labels;
    provisional = result.provisional;
    final groups = groupPixels(labels, result.count);
    for (var number = 1; number <= result.count; number++) {
      regions.add(Region(number, groups[number]));
    }
    fourComponents = labelComponents(finalMask, 4).count;
    eightComponents = labelComponents(finalMask, 8).count;
    bitQuad = bitQuadEuler(finalMask, setting.connectivity);
    holeOf = List.generate(image.height, (_) => List.filled(image.width, 0));
    for (final pixels in enclosedComponents(finalMask, 12 - setting.connectivity)) {
      final first = pixels.first;
      final number = holes.length + 1;
      final owner = labels[first.y - 1][first.x];
      for (final point in pixels) {
        holeOf[point.y][point.x] = number;
      }
      holes.add(Hole(number, pixels, owner));
    }
    for (final region in regions) {
      final first = region.pixels.first;
      if (first.y >= 1 && holeOf[first.y - 1][first.x] > 0) {
        final owner = holes[holeOf[first.y - 1][first.x] - 1].owner;
        region.parent = owner;
        region.depth = regions[owner - 1].depth + 1;
        regions[owner - 1].children.add(region.number);
      }
      measure(region, parameters);
    }
  }

  Mask binarize(int threshold) => [for (final row in image.pixels) [for (final value in row) setting.polarity == 'bright' ? value > threshold : value <= threshold]];
  int labelAt(int x, int y) => x >= 0 && x < image.width && y >= 0 && y < image.height ? labels[y][x] : -1;

  List<int> chainCode(Region region) {
    final steps = directions(setting.connectivity);
    final visited = [region.pixels.first];
    final codes = <int>[];
    var heading = steps.length - 1;
    while (true) {
      final point = visited.last;
      final start = steps.length == 4 ? (heading + 3) % 4 : (heading + (heading.isEven ? 7 : 6)) % 8;
      var chosen = -1;
      for (var offset = 0; offset < steps.length; offset++) {
        final direction = (start + offset) % steps.length;
        final step = steps[direction];
        if (labelAt(point.x + step.x, point.y + step.y) == region.number) {
          chosen = direction;
          break;
        }
      }
      if (chosen < 0) {
        return [];
      }
      final step = steps[chosen];
      visited.add(Point(point.x + step.x, point.y + step.y));
      codes.add(chosen);
      heading = chosen;
      final moves = codes.length;
      if (moves >= 2 && visited[moves] == visited[1] && visited[moves - 1] == visited.first) {
        return codes.sublist(0, moves - 1);
      }
    }
  }

  void measure(Region region, Parameters parameters) {
    final f = region.features;
    final area = region.pixels.length;
    final (x0, y0, x1, y1) = boxBounds(region.pixels);
    final basics = {'area': area, 'x0': x0, 'y0': y0, 'x1': x1, 'y1': y1, 'width': x1 - x0 + 1, 'height': y1 - y0 + 1};
    for (final entry in basics.entries) {
      region.setInt(entry.key, entry.value);
    }
    region.setInt('border', x0 == 0 || y0 == 0 || x1 == image.width - 1 || y1 == image.height - 1 ? 1 : 0);
    var sumValues = 0, sumSquares = 0, sx = 0, sy = 0, sxx = 0, syy = 0, sxy = 0;
    var minimum = image.maxval, maximum = 0;
    final surrounding = <Point>{};
    var perimeter = 0, runs = 0, mirroredLR = 0, mirroredTB = 0;
    for (final point in region.pixels) {
      final x = point.x, y = point.y;
      final value = image.pixels[y][x];
      sumValues += value;
      sumSquares += value * value;
      sx += x;
      sy += y;
      sxx += x * x;
      syy += y * y;
      sxy += x * y;
      minimum = math.min(minimum, value);
      maximum = math.max(maximum, value);
      for (final offset in eight) {
        final neighbor = Point(x + offset.x, y + offset.y);
        if (labelAt(neighbor.x, neighbor.y) == 0) {
          surrounding.add(neighbor);
        }
      }
      if (directions(12 - setting.connectivity).any((offset) => labelAt(x + offset.x, y + offset.y) != region.number)) {
        perimeter++;
      }
      if (labelAt(x - 1, y) != region.number) {
        runs++;
      }
      if (labelAt(x0 + x1 - x, y) == region.number) {
        mirroredLR++;
      }
      if (labelAt(x, y0 + y1 - y) == region.number) {
        mirroredTB++;
      }
    }
    f['mean'] = Rational(sumValues, area);
    f['variance'] = Rational(area * sumSquares - sumValues * sumValues, area * area);
    region.setInt('min', minimum);
    region.setInt('max', maximum);
    final count = surrounding.length;
    final sumSurrounding = surrounding.fold(0, (sum, point) => sum + image.pixels[point.y][point.x]);
    f['contrast'] = count == 0 ? Rational(0) : Rational(sumValues * count - sumSurrounding * area, area * count);
    region.setInt('perimeter', perimeter);
    region.setInt('runs', runs);
    region.codes = chainCode(region);
    final straight = setting.connectivity == 4 ? region.codes.length : region.codes.where((code) => code.isEven).length;
    final diagonal = region.codes.length - straight;
    var turns = 0;
    for (var i = 0; i < region.codes.length; i++) {
      if (region.codes[i] != region.codes[(i + region.codes.length - 1) % region.codes.length]) {
        turns++;
      }
    }
    region.setInt('chain', region.codes.length);
    region.setInt('straight', straight);
    region.setInt('diagonal', diagonal);
    region.setInt('turns', turns);
    final length = 5 * straight + 7 * diagonal;
    f['compactness'] = Rational(length * length, 25 * area);
    final owned = holes.where((hole) => hole.owner == region.number).toList();
    region.setInt('holes', owned.length);
    region.setInt('hole_area', owned.fold(0, (sum, hole) => sum + hole.pixels.length));
    region.setInt('euler', 1 - owned.length);
    region.setInt('depth', region.depth);
    final m20 = area * sxx - sx * sx, m02 = area * syy - sy * sy, m11 = area * sxy - sx * sy;
    f['cx'] = Rational(sx, area);
    f['cy'] = Rational(sy, area);
    f['var_x'] = Rational(m20, area * area);
    f['var_y'] = Rational(m02, area * area);
    f['cov_xy'] = Rational(m11, area * area);
    f['hu1'] = Rational(m20 + m02, area * area * area);
    final anisotropy = m20 + m02 > 0 ? Rational((m20 - m02).abs() + 2 * m11.abs(), m20 + m02) : Rational(0);
    f['anisotropy'] = anisotropy;
    final u = m20 - m02, v = 2 * m11;
    if (anisotropy.compareTo(parameters.isotropy) <= 0) {
      region.orientation = 'none';
    } else if (v.abs() >= u.abs()) {
      region.orientation = v > 0 ? 'falling' : 'rising';
    } else {
      region.orientation = u > 0 ? 'horizontal' : 'vertical';
    }
    f['extent'] = Rational(area, (x1 - x0 + 1) * (y1 - y0 + 1));
    f['mirror_lr'] = Rational(mirroredLR, area);
    f['mirror_tb'] = Rational(mirroredTB, area);
    final hull = convexHull(region.pixels);
    var doubled = 0, feret = 0;
    var width = Rational(0);
    for (var i = 0; i < hull.length; i++) {
      final a = hull[i], b = hull[(i + 1) % hull.length];
      doubled += a.x * b.y - b.x * a.y;
      var reach = 0;
      for (final point in hull) {
        reach = math.max(reach, cross(a, b, point).abs());
        feret = math.max(feret, squaredDistance(a, point));
      }
      final candidate = Rational(reach * reach, squaredDistance(a, b));
      if (i == 0 || candidate.compareTo(width) < 0) {
        width = candidate;
      }
    }
    region.hullDoubled = doubled.abs();
    f['solidity'] = Rational(2 * area, region.hullDoubled);
    region.setInt('feret2', feret);
    f['width2'] = width;
    f['elongation'] = Rational(feret * width.q, width.p);
    final bayMask = List.generate(y1 - y0 + 1, (dy) => List.generate(x1 - x0 + 1, (dx) {
      final x = x0 + dx, y = y0 + dy;
      return labels[y][x] == 0 && holeOf[y][x] == 0 && containsCenter(hull, x, y);
    }));
    final bays = labelComponents(bayMask, 12 - setting.connectivity);
    final sizes = groupPixels(bays.labels, bays.count).skip(1).map((pixels) => pixels.length).toList();
    region.setInt('bays', sizes.where((size) => size >= parameters.bayMin).length);
    region.setInt('bay_area', sizes.fold(0, (sum, size) => sum + size));
    region.skeleton = thin(region.pixels);
    final crossings = region.skeleton.map((point) => crossingNumber(region.skeleton, point)).toList();
    region.setInt('skeleton', region.skeleton.length);
    region.setInt('endpoints', crossings.where((crossing) => crossing == 1).length);
    region.setInt('branches', crossings.where((crossing) => crossing >= 3).length);
  }

  void applyRules(Rules rules) {
    for (final region in regions) {
      for (var i = 0; i < rules.filters.length; i++) {
        if (!rules.filters[i].holds(region)) {
          region.droppedBy = i;
          break;
        }
      }
      if (region.droppedBy >= 0) {
        continue;
      }
      region.kept = true;
      for (final rule in rules.classes) {
        if (rule.matches(region)) {
          region.className = rule.name;
          break;
        }
      }
      region.flags = [for (final rule in rules.flags) if (rule.matches(region)) rule.name];
    }
    final kept = keptRegions;
    for (final region in kept) {
      for (final other in kept) {
        if (other.number == region.number) {
          continue;
        }
        final distance = boxDistance(region, other);
        if (region.neighbor == 0 || distance < region.distance) {
          region.neighbor = other.number;
          region.distance = distance;
        }
      }
    }
  }

  List<Region> get keptRegions => regions.where((region) => region.kept).toList();
  String treeText(int number) {
    final region = regions[number - 1];
    return region.children.isEmpty ? '$number' : '$number(${region.children.map(treeText).join(' ')})';
  }

  List<String> thresholdLines(int top) {
    final h = histogram;
    final lines = [
      'image ${image.name} size ${image.width} ${image.height} maxval ${image.maxval}',
      'histogram pixels ${h.pixels} min ${h.minimum} max ${h.maximum} mean ${meanText(h.total, h.pixels)} median ${h.median} mode ${h.mode} levels ${h.levels}',
      'bins ${[h.binWidth, ...h.bins].join(' ')}',
      'otsu threshold ${otsuResult.cutoff} upper ${otsuResult.upper} candidates ${otsuResult.candidates.length}',
    ];
    var rank = 0;
    for (final c in otsuResult.candidates.take(top)) {
      final gap = Rational(c.sumAbove * c.below - c.sumBelow * c.above, c.below * c.above);
      lines.add('rank ${++rank} t ${c.cutoff} below ${c.below} above ${c.above} mean_below ${meanText(c.sumBelow, c.below)} mean_above ${meanText(c.sumAbove, c.above)} gap ${decimal(gap, 2)}');
    }
    lines.add('isodata threshold $isodataCutoff iterations $isodataIterations');
    lines.add('threshold $cutoff ${setting.method} ${setting.polarity} foreground ${countForeground(initial)}');
    for (var i = 0; i < setting.operations.length; i++) {
      lines.add('morph ${setting.operations[i]} foreground ${morphCounts[i]}');
    }
    for (final (threshold, foreground, count) in sweep) {
      lines.add('sweep $threshold foreground $foreground regions $count');
    }
    return lines;
  }

  String regionSymbol(int x, int y, bool skeletonOnly) {
    final label = labels[y][x];
    if (label == 0) {
      return holeOf[y][x] > 0 ? ':' : '.';
    }
    final region = regions[label - 1];
    if (skeletonOnly && !region.skeleton.contains(Point(x, y))) {
      return '+';
    }
    return region.kept ? symbols[label % symbols.length] : '#';
  }

  List<String> mapLines() {
    final size = '${image.name} ${image.width} ${image.height}';
    final lines = ['morphology $size'];
    for (var y = 0; y < image.height; y++) {
      final row = StringBuffer();
      for (var x = 0; x < image.width; x++) {
        row.write(initial[y][x] ? (finalMask[y][x] ? '#' : '-') : (finalMask[y][x] ? '+' : '.'));
      }
      lines.add(row.toString());
    }
    for (final heading in ['labels', 'skeleton']) {
      lines.add('$heading $size');
      for (var y = 0; y < image.height; y++) {
        lines.add([for (var x = 0; x < image.width; x++) regionSymbol(x, y, heading == 'skeleton')].join());
      }
    }
    return lines;
  }

  String csvRow(Region region) {
    final fields = [image.name, '${region.number}', region.className, region.flags.isEmpty ? '-' : region.flags.join('+')];
    void appendInt(String name) => fields.add('${region.integer(name)}');
    void appendDecimal(String name, int digits) => fields.add(decimal(region.features[name]!, digits));
    for (final name in ['area', 'x0', 'y0', 'x1', 'y1']) {
      appendInt(name);
    }
    for (final name in ['cx', 'cy']) {
      appendDecimal(name, 3);
    }
    for (final name in ['mean', 'variance']) {
      appendDecimal(name, 2);
    }
    appendInt('min');
    appendInt('max');
    appendDecimal('contrast', 2);
    for (final name in ['border', 'perimeter', 'chain', 'straight', 'diagonal', 'turns']) {
      appendInt(name);
    }
    appendDecimal('compactness', 3);
    for (final name in ['runs', 'holes', 'hole_area', 'euler']) {
      appendInt(name);
    }
    fields.add(region.parent == 0 ? '-' : '${region.parent}');
    fields.add('${region.depth}');
    for (final name in ['var_x', 'var_y', 'cov_xy']) {
      appendDecimal(name, 3);
    }
    appendDecimal('hu1', 4);
    fields.add(region.orientation);
    for (final name in ['anisotropy', 'extent', 'mirror_lr', 'mirror_tb']) {
      appendDecimal(name, 3);
    }
    fields.add(hullAreaText(region.hullDoubled));
    appendDecimal('solidity', 3);
    appendInt('feret2');
    appendDecimal('width2', 3);
    appendDecimal('elongation', 3);
    for (final name in ['bays', 'bay_area', 'skeleton', 'endpoints', 'branches']) {
      appendInt(name);
    }
    fields.add(region.neighbor == 0 ? '-' : '${region.neighbor}');
    fields.add(region.neighbor == 0 ? '-' : decimal(Rational(region.distance, 4), 2));
    fields.add(region.codes.isEmpty ? '-' : region.codes.join());
    return fields.join(',');
  }

  String intensityText(bool foreground) {
    var sum = 0, count = 0;
    for (var y = 0; y < image.height; y++) {
      for (var x = 0; x < image.width; x++) {
        if (finalMask[y][x] == foreground) {
          sum += image.pixels[y][x];
          count++;
        }
      }
    }
    return meanText(sum, count);
  }

  String areaLine() {
    final kept = keptRegions;
    if (kept.isEmpty) {
      return 'area total 0 mean - largest - smallest -';
    }
    var total = 0;
    var largest = kept.first, smallest = kept.first;
    for (final region in kept) {
      final area = region.integer('area');
      total += area;
      if (area > largest.integer('area')) {
        largest = region;
      }
      if (area < smallest.integer('area')) {
        smallest = region;
      }
    }
    return 'area total $total mean ${meanText(total, kept.length)} largest ${largest.number} ${largest.integer('area')} smallest ${smallest.number} ${smallest.integer('area')}';
  }

  List<String> summaryLines(Rules rules) {
    final kept = keptRegions;
    final holePixels = holes.fold(0, (sum, hole) => sum + hole.pixels.length);
    final lines = [
      'image ${image.name}',
      'threshold $cutoff ${setting.method} ${setting.polarity} conn ${setting.connectivity}',
      'foreground ${countForeground(initial)} ${countForeground(finalMask)}',
      'regions ${regions.length} provisional $provisional kept ${kept.length} dropped ${regions.length - kept.length}',
      'connectivity four $fourComponents eight $eightComponents',
      'holes ${holes.length} hole_pixels $holePixels euler ${regions.length - holes.length} bitquad $bitQuad',
    ];
    for (final hole in holes) {
      final (x0, y0, x1, y1) = boxBounds(hole.pixels);
      lines.add('hole ${hole.number} owner ${hole.owner} area ${hole.pixels.length} box $x0 $y0 $x1 $y1');
    }
    var depthMax = 0;
    final trees = ['tree'];
    for (final region in regions) {
      depthMax = math.max(depthMax, region.depth);
      if (region.parent == 0) {
        trees.add(treeText(region.number));
      }
    }
    lines.add('depth_max $depthMax');
    lines.add(trees.join(' '));
    lines.add('intensity foreground ${intensityText(true)} background ${intensityText(false)}');
    lines.add(areaLine());
    lines.add(['classes', for (final name in rules.classNames) '$name ${kept.where((region) => region.className == name).length}'].join(' '));
    lines.add(orientationLine(kept));
    lines.add(['flags', for (final rule in rules.flags) '${rule.name} ${kept.where((region) => region.flags.contains(rule.name)).length}'].join(' '));
    return lines;
  }
}

List<String> overallLines(List<ImageAnalysis> analyses, Rules rules) {
  final regions = [for (final analysis in analyses) ...analysis.regions];
  final kept = regions.where((region) => region.kept).toList();
  final holes = analyses.fold(0, (sum, analysis) => sum + analysis.holes.length);
  final lines = ['overall', 'images ${analyses.length}', 'regions ${regions.length} kept ${kept.length} dropped ${regions.length - kept.length}', 'holes $holes euler ${regions.length - holes}'];
  for (var i = 0; i < rules.filters.length; i++) {
    lines.add('filter ${i + 1} ${rules.filters[i].words} dropped ${regions.where((region) => region.droppedBy == i).length}');
  }
  for (final name in rules.classNames) {
    final members = kept.where((region) => region.className == name).toList();
    final area = members.fold(0, (sum, region) => sum + region.integer('area'));
    lines.add('class $name count ${members.length} area $area mean ${meanText(area, members.length)}');
  }
  for (final rule in rules.flags) {
    lines.add('flag ${rule.name} count ${kept.where((region) => region.flags.contains(rule.name)).length}');
  }
  lines.add(orientationLine(kept));
  Region? largest;
  var largestName = '';
  for (final analysis in analyses) {
    for (final region in analysis.keptRegions) {
      if (largest == null || region.integer('area') > largest.integer('area')) {
        largest = region;
        largestName = analysis.image.name;
      }
    }
  }
  lines.add(largest == null ? 'largest -' : 'largest $largestName ${largest.number} ${largest.integer('area')}');
  return lines;
}

void main() {
  final parameters = readParameters('input/params.txt');
  final rules = readRules('input/rules.txt');
  final analyses = <ImageAnalysis>[];
  for (final image in readImages('input/images.txt')) {
    final analysis = ImageAnalysis(image, parameters.settings[image.name]!, parameters);
    analysis.applyRules(rules);
    analyses.add(analysis);
  }
  final thresholds = <String>[], maps = <String>[], rows = [csvHeader], summary = <String>[];
  for (final analysis in analyses) {
    thresholds.addAll(analysis.thresholdLines(parameters.otsuTop));
    maps.addAll(analysis.mapLines());
    rows.addAll(analysis.keptRegions.map(analysis.csvRow));
    summary.addAll(analysis.summaryLines(rules));
  }
  summary.addAll(overallLines(analyses, rules));
  writeFiles('output', {'thresholds.txt': thresholds, 'labels.txt': maps, 'regions.csv': rows, 'summary.txt': summary});
}
