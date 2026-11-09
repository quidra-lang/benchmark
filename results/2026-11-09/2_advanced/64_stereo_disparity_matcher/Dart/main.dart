import 'dart:io';
import 'dart:math';
part 'pgm_io.dart';
part 'costs.dart';
part 'aggregation.dart';
part 'refinement.dart';
part 'evaluation.dart';

const methodNames = [
      'sad',
      'ssd',
      'census',
      'sgm',
      'fusion',
      'wta_final',
      'sgm_final',
    ],
    sourceNames = ['kept', 'median', 'background', 'interpolated', 'none'];

class Selection {
  final List<int> image, reasons, margins;
  final lr = List.filled(4, 0);
  int bounds = 0;
  final int window;
  Selection(int n, this.window)
    : image = List.filled(n, 0),
      reasons = List.filled(n, 0),
      margins = List.filled(n, 0);
}

class Post {
  late List<int> image;
  final List<int> source;
  int components = 0,
      pixels = 0,
      median = 0,
      background = 0,
      interpolated = 0,
      none = 0;
  Post(int n) : source = List.filled(n, 4);
}

class Method {
  final String name;
  final List<int> image;
  final Selection? selection;
  final Post? post;
  Method(this.name, this.image, {this.selection, this.post});
}

class StereoObject {
  final List<int> pixels;
  int x0,
      y0,
      x1 = -1,
      y1 = -1,
      min = 0,
      max = 0,
      median = 0,
      truth = 0,
      truthCount = 0,
      sum = 0;
  final int first;
  StereoObject(this.pixels, int w, int h)
    : x0 = w,
      y0 = h,
      first = pixels.first;
}

int countTrue(List<bool> v) => v.where((b) => b).length;
int validCount(List<int> v) => v.where((d) => d != 0).length;
int lowerMedian(List<int> v) {
  final a = List<int>.of(v)..sort();
  return a[(a.length - 1) ~/ 2];
}

List<List<int>> components(List<int> image, int w, int h, int span) {
  final visited = List.filled(image.length, false), out = <List<int>>[];
  const neighbors = [(1, 0), (-1, 0), (0, 1), (0, -1)];
  for (var root = 0; root < image.length; root++) {
    if (image[root] == 0 || visited[root]) continue;
    visited[root] = true;
    final queue = [root];
    for (var head = 0; head < queue.length; head++) {
      final p = queue[head], x = p % w, y = p ~/ w;
      for (final (dx, dy) in neighbors) {
        final xx = x + dx, yy = y + dy;
        if (xx < 0 || xx >= w || yy < 0 || yy >= h) continue;
        final q = yy * w + xx;
        if (image[q] != 0 &&
            !visited[q] &&
            (image[p] - image[q]).abs() <= span) {
          visited[q] = true;
          queue.add(q);
        }
      }
    }
    out.add(queue);
  }
  return out;
}

class Application {
  final Image left, right, truth;
  final Params params;
  late Regions regions;
  late List<int> textureValues, censusLeft, censusRight;
  final methods = <Method>[], report = <String>[];
  late Volume aggregateValues;
  Application(this.left, this.right, this.truth, this.params);
  Selection selectDisparity(Volume v, int window) {
    final p = params,
        w = left.w,
        h = left.h,
        n = w * h,
        rightDisparity = List.filled(w * h, 0);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        var best = 0;
        for (var d = p.min; d <= p.max && x + d < w; d++) {
          final cost = v[y * w + x + d][d - p.min];
          if (rightDisparity[y * w + x] == 0 || cost < best) {
            best = cost;
            rightDisparity[y * w + x] = d;
          }
        }
      }
    }
    final out = Selection(n, window);
    for (var index = 0; index < v.length; index++) {
      final row = v[index], x = index % w;
      var di = 0;
      for (var j = 1; j < row.length; j++) {
        if (row[j] < row[di]) di = j;
      }
      final d1 = p.min + di, c1 = row[di];
      var c2 = 1 << 62;
      for (var j = 0; j < row.length; j++) {
        if ((j - di).abs() >= 2) c2 = min(c2, row[j]);
      }
      if (d1 == p.min || d1 == p.max) out.bounds++;
      bool consistent(int d) =>
          x - d >= 0 && (d - rightDisparity[index - d]).abs() <= p.lr;
      var reason = 0;
      if (textureValues[index] < p.textureThreshold) {
        reason = 50;
      } else if (100 * c2 <= (100 + p.uniqueness) * c1) {
        reason = 100;
      } else if (x - d1 < 0) {
        reason = 150;
      } else if (!consistent(d1)) {
        reason = 255;
        for (var d = p.min; d <= p.max; d++) {
          if (consistent(d)) {
            reason = 200;
            break;
          }
        }
      }
      out.reasons[index] = reason;
      if (reason == 0) {
        out.image[index] = d1;
        out.margins[index] = c2 - c1;
      }
      if (reason == 0 || reason == 200 || reason == 255) {
        final diff = (d1 - rightDisparity[index - d1]).abs();
        out.lr[min(3, diff)]++;
      }
    }
    return out;
  }

  Post postprocess(Selection selection) {
    final p = params,
        w = left.w,
        h = left.h,
        a0 = selection.image,
        a1 = List<int>.of(a0),
        out = Post(a0.length);
    for (final component in components(a0, w, h, p.speckleRange)) {
      if (component.length < p.speckleSize) {
        out.components++;
        out.pixels += component.length;
        for (final i in component) {
          a1[i] = 0;
        }
      }
    }
    final a2 = List.filled(a0.length, 0);
    for (var i = 0; i < a1.length; i++) {
      if (a1[i] == 0) continue;
      final x = i % w, y = i ~/ w, values = <int>[];
      for (var yy = max(0, y - 1); yy <= min(h - 1, y + 1); yy++) {
        for (var xx = max(0, x - 1); xx <= min(w - 1, x + 1); xx++) {
          final value = a1[yy * w + xx];
          if (value != 0) values.add(value);
        }
      }
      a2[i] = lowerMedian(values);
      if (a2[i] != a1[i]) out.median++;
    }
    out.image = List.of(a2);
    for (var i = 0; i < a2.length; i++) {
      final d = a2[i];
      if (d != 0) {
        out.source[i] = d == a0[i] ? 0 : 1;
        continue;
      }
      final x = i % w,
          y = i ~/ w,
          values = <int>[],
          background =
              selection.reasons[i] == 150 || selection.reasons[i] == 255;
      if (background) {
        for (var xx = x - 1; xx >= 0; xx--) {
          final v = a2[y * w + xx];
          if (v != 0) {
            values.add(v);
            break;
          }
        }
        for (var xx = x + 1; xx < w; xx++) {
          final v = a2[y * w + xx];
          if (v != 0) {
            values.add(v);
            break;
          }
        }
        if (values.isNotEmpty) {
          out.image[i] = values.reduce(min);
          out.source[i] = 2;
          out.background++;
        }
      } else {
        for (final (rx, ry) in directions) {
          for (
            var xx = x + rx, yy = y + ry;
            xx >= 0 && xx < w && yy >= 0 && yy < h;
            xx += rx, yy += ry
          ) {
            final v = a2[yy * w + xx];
            if (v != 0) {
              values.add(v);
              break;
            }
          }
        }
        if (values.isNotEmpty) {
          out.image[i] = lowerMedian(values);
          out.source[i] = 3;
          out.interpolated++;
        }
      }
      if (out.image[i] == 0) out.none++;
    }
    return out;
  }

  void prepare() {
    final p = params;
    regions = truthRegions(truth);
    textureValues = texture(left, p.textureWindow);
    censusLeft = census(left);
    censusRight = census(right);
    final chosen = <String, Selection>{}, sweep = <String>[];
    for (final kind in methodNames.take(3)) {
      Metrics? best;
      for (final window in p.windows[kind]!) {
        final cost = costVolume(
              left,
              right,
              censusLeft,
              censusRight,
              kind,
              window,
              p,
            ),
            selection = selectDisparity(cost, window),
            metrics = evaluate(selection.image, truth.pixels, regions.nonocc);
        sweep.add(
          'sweep $kind window $window valid ${validCount(selection.image)} bad1 ${ratio(metrics.bad1, metrics.pixels)} bad2 ${ratio(metrics.bad2, metrics.pixels)}',
        );
        if (best == null ||
            metrics.bad1 < best.bad1 ||
            (metrics.bad1 == best.bad1 && metrics.bad2 < best.bad2)) {
          chosen[kind] = selection;
          best = metrics;
        }
      }
    }
    final base = costVolume(
          left,
          right,
          censusLeft,
          censusRight,
          p.sgmCost,
          p.sgmWindow,
          p,
        ),
        paths = <String>[];
    aggregateValues = aggregate(base, left, p, (i, summed) {
      final selection = selectDisparity(summed, p.sgmWindow),
          metrics = evaluate(selection.image, truth.pixels, regions.nonocc);
      chosen['sgm'] = selection;
      paths.add(
        'paths $i valid ${validCount(selection.image)} bad1 ${ratio(metrics.bad1, metrics.pixels)} bad2 ${ratio(metrics.bad2, metrics.pixels)}',
      );
    });
    for (final kind in methodNames.take(4)) {
      methods.add(Method(kind, chosen[kind]!.image, selection: chosen[kind]));
    }
    final fusion = List.filled(left.pixels.length, 0);
    for (var i = 0; i < fusion.length; i++) {
      final values = [
        for (final kind in methodNames.take(4))
          if (chosen[kind]!.image[i] != 0) chosen[kind]!.image[i],
      ];
      if (values.isNotEmpty) {
        final median = lowerMedian(values),
            votes = values.where((d) => (d - median).abs() <= 1).length;
        if (votes >= p.fusionVotes) fusion[i] = median;
      }
    }
    methods.add(Method('fusion', fusion));
    final wtaPost = postprocess(chosen[p.wtaCost]!),
        sgmPost = postprocess(chosen['sgm']!);
    methods.addAll([
      Method('wta_final', wtaPost.image, post: wtaPost),
      Method('sgm_final', sgmPost.image, post: sgmPost),
    ]);
    report.addAll(sweep);
    report.addAll(paths);
  }

  void imagesAndDepth() {
    final p = params, w = left.w, h = left.h;
    for (final (index, name) in [
      (5, 'disparity_wta.pgm'),
      (6, 'disparity_sgm.pgm'),
    ]) {
      writePGM(name, w, h, methods[index].image.map((d) => 8 * d).toList());
    }
    writePGM('occlusion.pgm', w, h, methods[3].selection!.reasons);
    final errors = List.filled(w * h, 0);
    for (var i = 0; i < errors.length; i++) {
      final g = truth.pixels[i];
      if (g == 0) continue;
      final d = methods[6].image[i];
      errors[i] = d == 0 ? 255 : 50 * (1 + min(3, (d - g).abs()));
    }
    writePGM('error_sgm.pgm', w, h, errors);
    final out = [
      'x,y,sad,ssd,census,sgm,disparity,source,subpixel,depth,truth,truth_depth',
    ];
    for (final (x, y) in p.samples) {
      final index = y * w + x, row = ['$x', '$y'];
      for (final method in methods.take(4)) {
        final d = method.image[index];
        row.add(d == 0 ? '-' : '$d');
      }
      final d = methods[6].image[index];
      if (d == 0) {
        row.addAll(['-', 'none', '-', '-']);
      } else {
        final (sub, depth) = subpixel(aggregateValues[index], d, p);
        row.addAll([
          '$d',
          sourceNames[methods[6].post!.source[index]],
          sub,
          depth,
        ]);
      }
      final g = truth.pixels[index];
      row.addAll(
        g == 0 ? ['-', '-'] : ['$g', decimal2(p.focal * p.baseline, g)],
      );
      out.add(row.join(','));
    }
    writeLines('depth.csv', out);
  }

  void objects() {
    final p = params,
        w = left.w,
        h = left.h,
        image = methods[6].image,
        objects = <StereoObject>[];
    var small = 0, pixels = 0;
    for (final component in components(image, w, h, p.objectRange)) {
      if (component.length < p.objectSize) {
        small++;
        continue;
      }
      final o = StereoObject(component, w, h),
          values = <int>[],
          counts = <int, int>{};
      for (final index in component) {
        final x = index % w,
            y = index ~/ w,
            d = image[index],
            g = truth.pixels[index];
        o.x0 = min(o.x0, x);
        o.y0 = min(o.y0, y);
        o.x1 = max(o.x1, x);
        o.y1 = max(o.y1, y);
        o.sum += d;
        values.add(d);
        if (g != 0) counts[g] = (counts[g] ?? 0) + 1;
      }
      values.sort();
      o.min = values.first;
      o.max = values.last;
      o.median = values[(values.length - 1) ~/ 2];
      for (final g in regions.layers) {
        final count = counts[g] ?? 0;
        if (count > o.truthCount) {
          o.truth = g;
          o.truthCount = count;
        }
      }
      objects.add(o);
      pixels += component.length;
    }
    objects.sort((x, y) {
      var c = y.median.compareTo(x.median);
      if (c != 0) return c;
      c = y.pixels.length.compareTo(x.pixels.length);
      return c != 0 ? c : x.first.compareTo(y.first);
    });
    final out = ['objects ${objects.length} small $small pixels $pixels'],
        detected = <int>{};
    for (var rank = 0; rank < objects.length; rank++) {
      final o = objects[rank], n = o.pixels.length;
      var truth = 'truth - iou -';
      if (o.truth != 0) {
        final union = n + regions.layerCounts[o.truth]! - o.truthCount;
        truth = 'truth ${o.truth} iou ${ratio(o.truthCount, union)}';
        if (2 * o.truthCount > union) detected.add(o.truth);
      }
      out.add(
        'object ${rank + 1} pixels $n box ${o.x0} ${o.y0} ${o.x1} ${o.y1} disparity ${o.min} ${o.max} median ${o.median} mean ${decimal2(o.sum, n)} depth ${decimal2(p.focal * p.baseline * n, o.sum)} size ${decimal2((o.x1 - o.x0 + 1) * p.baseline, o.median)} ${decimal2((o.y1 - o.y0 + 1) * p.baseline, o.median)} $truth',
      );
    }
    final missed = regions.layers.where((g) => !detected.contains(g)).toList();
    out.add(
      'layers ${regions.layers.length} detected ${detected.length} missed ${missed.isEmpty ? '-' : missed.join(' ')}',
    );
    writeLines('objects.txt', out);
  }

  void evaluationReport() {
    final p = params, w = left.w, h = left.h, n = w * h;
    var textureSum = 0, textureless = 0;
    for (final t in textureValues) {
      textureSum += t;
      if (t < p.textureThreshold) textureless++;
    }
    final known = countTrue(regions.known),
        nonocc = countTrue(regions.nonocc),
        occluded = countTrue(regions.occluded),
        disc = countTrue(regions.disc);
    var difference = 0, absoluteDifference = 0;
    for (var index = 0; index < n; index++) {
      if (regions.nonocc[index]) {
        final g = truth.pixels[index],
            delta = right.pixels[index - g] - left.pixels[index];
        difference += delta;
        absoluteDifference += delta.abs();
      }
    }
    var bias = decimal2(difference.abs(), nonocc);
    if (difference < 0 && bias != '0.00') bias = '-$bias';
    final out = [
          'image $w $h',
          'disparities ${p.min} ${p.max}',
          'left ${imageSummary(left)}',
          'right ${imageSummary(right)}',
          'texture mean ${decimal2(textureSum, n)} textureless $textureless',
          'ground_truth known $known nonocc $nonocc occluded $occluded disc $disc unknown ${n - known}',
          'photometric pixels $nonocc mean_abs ${decimal2(absoluteDifference, nonocc)} bias $bias',
          ...report,
        ],
        masks = [regions.nonocc, regions.known, regions.disc],
        regionNames = ['nonocc', 'all', 'disc'],
        metrics = List.generate(methods.length, (_) => <Metrics>[]);
    for (var mi = 0; mi < methods.length; mi++) {
      final method = methods[mi], valid = validCount(method.image);
      out.add('method ${method.name} valid $valid invalid ${n - valid}');
      final values = <int>[], distinct = <int>{};
      var horizontal = 0, vertical = 0;
      for (var index = 0; index < n; index++) {
        final d = method.image[index];
        if (d == 0) continue;
        values.add(d);
        distinct.add(d);
        final x = index % w, y = index ~/ w;
        if (x + 1 < w &&
            method.image[index + 1] != 0 &&
            (d - method.image[index + 1]).abs() >= 2)
          horizontal++;
        if (y + 1 < h &&
            method.image[index + w] != 0 &&
            (d - method.image[index + w]).abs() >= 2)
          vertical++;
      }
      if (values.isEmpty) {
        out.add('disparity min - max - median - distinct 0');
      } else {
        values.sort();
        out.add(
          'disparity min ${values.first} max ${values.last} median ${values[(values.length - 1) ~/ 2]} distinct ${distinct.length}',
        );
      }
      out.add('jumps horizontal $horizontal vertical $vertical');
      final selection = method.selection;
      if (selection != null) {
        final counts = <int, int>{};
        for (final reason in selection.reasons) {
          counts[reason] = (counts[reason] ?? 0) + 1;
        }
        out.addAll([
          'window ${selection.window} bounds ${selection.bounds}',
          'reasons textureless ${counts[50] ?? 0} nonunique ${counts[100] ?? 0} outside ${counts[150] ?? 0} mismatch ${counts[200] ?? 0} occluded ${counts[255] ?? 0}',
          'lr 0 ${selection.lr[0]} 1 ${selection.lr[1]} 2 ${selection.lr[2]} 3+ ${selection.lr[3]}',
        ]);
      } else if (method.name == 'fusion') {
        final counts = List.filled(5, 0);
        for (var index = 0; index < n; index++) {
          final count = methods
              .take(4)
              .where((m) => m.image[index] != 0)
              .length;
          counts[count]++;
        }
        out.add(
          'votes 0 ${counts[0]} 1 ${counts[1]} 2 ${counts[2]} 3 ${counts[3]} 4 ${counts[4]}',
        );
      } else {
        final post = method.post!;
        out.add(
          'postprocess speckles ${post.components} ${post.pixels} median ${post.median} background ${post.background} interpolated ${post.interpolated} unfilled ${post.none}',
        );
        for (var source = 0; source < sourceNames.length; source++) {
          final mask = List.generate(
                n,
                (i) => regions.known[i] && post.source[i] == source,
              ),
              m = evaluate(method.image, truth.pixels, mask);
          out.add(
            'source ${sourceNames[source]} pixels ${m.pixels} bad1 ${ratio(m.bad1, m.pixels)}',
          );
        }
      }
      for (var region = 0; region < masks.length; region++) {
        final m = evaluate(method.image, truth.pixels, masks[region]);
        metrics[mi].add(m);
        final mae = m.valid > 0 ? decimal2(m.error, m.valid) : '-';
        out.add(
          'region ${regionNames[region]} pixels ${m.pixels} valid ${m.valid} bad1 ${ratio(m.bad1, m.pixels)} bad2 ${ratio(m.bad2, m.pixels)} mae $mae exact ${m.exact}',
        );
      }
      var depthCount = 0, depthSum = 0, depthMax = 0;
      for (var i = 0; i < n; i++) {
        if (regions.nonocc[i] && method.image[i] != 0) {
          final error =
              (depthHundred(method.image[i], p) -
                      depthHundred(truth.pixels[i], p))
                  .abs();
          depthCount++;
          depthSum += error;
          depthMax = max(depthMax, error);
        }
      }
      if (depthCount == 0) {
        out.add('depth_error pixels 0 mean - max -');
      } else {
        out.add(
          'depth_error pixels $depthCount mean ${decimal2(depthSum, 100 * depthCount)} max ${decimal2(depthMax, 100)}',
        );
      }
      final errors = List.filled(5, 0);
      var invalid = 0;
      for (var i = 0; i < n; i++) {
        if (!regions.known[i]) continue;
        final d = method.image[i];
        if (d == 0) {
          invalid++;
        } else {
          errors[min(4, (d - truth.pixels[i]).abs())]++;
        }
      }
      out.add(
        'errors 0 ${errors[0]} 1 ${errors[1]} 2 ${errors[2]} 3 ${errors[3]} 4+ ${errors[4]} invalid $invalid',
      );
    }
    for (var region = 0; region < regionNames.length; region++) {
      final order = List.generate(7, (i) => i)
        ..sort((i, j) {
          final a = metrics[i][region], b = metrics[j][region];
          var c = a.bad1.compareTo(b.bad1);
          if (c != 0) return c;
          c = a.bad2.compareTo(b.bad2);
          if (c != 0) return c;
          if (a.valid == 0 || b.valid == 0) {
            if (a.valid == 0 && b.valid > 0) return 1;
            if (a.valid > 0 && b.valid == 0) return -1;
          } else {
            c = (a.error * b.valid).compareTo(b.error * a.valid);
            if (c != 0) return c;
          }
          return i.compareTo(j);
        });
      out.add(
        'ranking ${regionNames[region]} ${order.map((i) => methods[i].name).join(' ')}',
      );
    }
    for (final method in methods.take(4)) {
      var tp = 0, fp = 0, fn = 0;
      for (var i = 0; i < n; i++) {
        final reason = method.selection!.reasons[i],
            detected = reason == 150 || reason == 255;
        if (regions.occluded[i]) {
          if (detected) {
            tp++;
          } else {
            fn++;
          }
        } else if (regions.nonocc[i] && detected) {
          fp++;
        }
      }
      out.add(
        'occlusion ${method.name} tp $tp fp $fp fn $fn precision ${ratio(tp, tp + fp)} recall ${ratio(tp, tp + fn)}',
      );
    }
    for (final method in methods.take(4)) {
      final indices =
          [
            for (var i = 0; i < n; i++)
              if (regions.nonocc[i] && method.image[i] != 0) i,
          ]..sort((i, j) {
            final c = method.selection!.margins[j].compareTo(
              method.selection!.margins[i],
            );
            return c != 0 ? c : i.compareTo(j);
          });
      for (final percent in [25, 50, 75, 100]) {
        final count = (indices.length * percent + 99) ~/ 100,
            bad = indices
                .take(count)
                .where((i) => (method.image[i] - truth.pixels[i]).abs() > 1)
                .length,
            margin = count > 0
                ? '${method.selection!.margins[indices[count - 1]]}'
                : '-';
        out.add(
          'confidence ${method.name} $percent pixels $count margin $margin bad1 ${ratio(bad, count)}',
        );
      }
    }
    for (final g in regions.layers) {
      final mask = List.generate(
            n,
            (i) => truth.pixels[i] == g && regions.nonocc[i],
          ),
          line = [
            'layer $g pixels ${regions.layerCounts[g]} nonocc ${countTrue(mask)} bad1',
          ];
      for (final method in methods) {
        line.add('${evaluate(method.image, truth.pixels, mask).bad1}');
      }
      out.add(line.join(' '));
    }
    final hist = <int, int>{};
    for (final d in methods[6].image) {
      if (d != 0) hist[d] = (hist[d] ?? 0) + 1;
    }
    for (var d = p.min; d <= p.max; d++) {
      out.add('histogram $d ${hist[d] ?? 0}');
    }
    writeLines('evaluation.txt', out);
  }
}

String imageSummary(Image img) {
  var total = 0, lo = img.pixels.first, hi = img.pixels.first;
  for (final v in img.pixels) {
    total += v;
    lo = min(lo, v);
    hi = max(hi, v);
  }
  return 'mean ${decimal2(total, img.pixels.length)} min $lo max $hi';
}

void main() {
  final a = Application(
    readPGM('input/left.pgm'),
    readPGM('input/right.pgm'),
    readPGM('input/ground_truth.pgm'),
    readParams(),
  );
  a.prepare();
  a.imagesAndDepth();
  a.evaluationReport();
  a.objects();
}
