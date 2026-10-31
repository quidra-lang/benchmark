import 'dart:io';
import 'dart:math';
part 'fixed_point.dart';
part 'vector3.dart';
part 'scene.dart';
part 'intersect.dart';
part 'shading.dart';

const rayKinds = ['primary', 'reflection', 'refraction', 'shadow'];

class Settings {
  final int w, h, contrast, depth, far, epsilon, pad;
  Settings(
    this.w,
    this.h,
    this.contrast,
    this.depth,
    this.far,
    this.epsilon,
    this.pad,
  );
}

Settings readSettings() {
  final v = File(
    'input/render.txt',
  ).readAsLinesSync().map((s) => integers(s.split(' ').sublist(1))).toList();
  return Settings(
    v[0][0],
    v[0][1],
    v[1][0],
    v[2][0],
    v[3][0],
    v[4][0],
    v[5][0],
  );
}

class Node {
  final Bounds box;
  final int depth;
  final objects = <SceneObject>[];
  Node? left, right;
  int visits = 0;
  Node(this.box, this.depth);
}

class Sample {
  final Vec direction;
  final int distance, intensity;
  Sample(this.direction, this.distance, this.intensity);
}

class TraceContext {
  int rays = 0, depth = 0;
}

class Result {
  Vec color, point = zero, normal = zero, base = zero;
  final Hit? hit;
  int illumination = 0;
  List<int> lit = [];
  Result(this.color, this.hit);
}

class Pixel {
  final Result center;
  Vec color;
  int samples = 1, rays, depth;
  Pixel(this.center, this.rays, this.depth) : color = center.color;
  String get label => center.hit?.object.label ?? '.';
}

Bounds union(List<SceneObject> objects) {
  var lo = objects.first.bounds.lo, hi = objects.first.bounds.hi;
  for (final o in objects.skip(1)) {
    lo = Vec.fromList(List.generate(3, (a) => min(lo[a], o.bounds.lo[a])));
    hi = Vec.fromList(List.generate(3, (a) => max(hi[a], o.bounds.hi[a])));
  }
  return Bounds(lo, hi);
}

int area(Bounds b) {
  final d = b.hi - b.lo;
  return d.x * d.y + d.y * d.z + d.z * d.x;
}

Node? build(List<SceneObject> objects, int depth) {
  if (objects.isEmpty) return null;
  final node = Node(union(objects), depth);
  if (objects.length <= 2) {
    node.objects.addAll(objects);
    node.objects.sort((a, b) => a.id.compareTo(b.id));
    for (final o in node.objects) {
      o.leafDepth = depth;
    }
    return node;
  }
  var chosen = <SceneObject>[], split = 0, cost = 1 << 62;
  for (var axis = 0; axis < 3; axis++) {
    final sorted = List<SceneObject>.of(objects)
      ..sort((a, b) {
        final ca = floorDiv(a.bounds.lo[axis] + a.bounds.hi[axis], 2),
            cb = floorDiv(b.bounds.lo[axis] + b.bounds.hi[axis], 2);
        return ca != cb ? ca.compareTo(cb) : a.id.compareTo(b.id);
      });
    for (var i = 1; i < sorted.length; i++) {
      final c =
          area(union(sorted.sublist(0, i))) * i +
          area(union(sorted.sublist(i))) * (sorted.length - i);
      if (c < cost) {
        cost = c;
        split = i;
        chosen = sorted;
      }
    }
  }
  node.left = build(chosen.sublist(0, split), depth + 1);
  node.right = build(chosen.sublist(split), depth + 1);
  return node;
}

int cone(Light l, Vec d) {
  if (l.kind != 'spot') return scaleUnit;
  final c = -d.dot(l.direction);
  if (c <= l.outer) return 0;
  if (c >= l.inner) return scaleUnit;
  return floorDiv((c - l.outer) * scaleUnit, l.inner - l.outer);
}

void writeLines(String name, List<String> lines) {
  Directory('output').createSync(recursive: true);
  File(
    'output/$name',
  ).writeAsStringSync(lines.isEmpty ? '' : '${lines.join('\n')}\n');
}

class Renderer {
  final Scene scene;
  final Settings settings;
  final Node? root;
  bool active = true;
  final rays = List.filled(4, 0),
      misses = List.filled(4, 0),
      nodeTests = List.filled(4, 0),
      objectTests = List.filled(4, 0);
  late final List<int> depths;
  int tir = 0, clamped = 0, supersampled = 0;
  final pixels = <Pixel>[];
  Renderer(this.scene, this.settings, this.root) {
    depths = List.filled(settings.depth + 1, 0);
  }
  Hit? test(SceneObject o, Ray ray, int kind) {
    if (active) objectTests[kind]++;
    return intersect(o, ray, settings.epsilon);
  }

  Slab? nodeTest(Node n, Ray ray, int kind) {
    if (active) {
      nodeTests[kind]++;
      n.visits++;
    }
    return slab(n.box, ray);
  }

  Hit? nearest(Ray ray, int kind) {
    Hit? found;
    void testObject(SceneObject o) {
      final h = test(o, ray, kind), current = found;
      if (h != null &&
          h.distance <= settings.far &&
          (current == null ||
              h.distance < current.distance ||
              (h.distance == current.distance && o.id < current.object.id)))
        found = h;
    }

    for (final o in scene.objects) {
      if (o.kind == 'plane') testObject(o);
    }
    void visit(Node? node) {
      if (node == null) return;
      final s = nodeTest(node, ray, kind), current = found;
      if (s == null ||
          s.far <= settings.epsilon ||
          s.near > settings.far ||
          (current != null && s.near > current.distance))
        return;
      if (node.left == null) {
        for (final o in node.objects) {
          testObject(o);
        }
      } else {
        visit(node.left);
        visit(node.right);
      }
    }

    visit(root);
    return found;
  }

  List<SceneObject> occluders(Ray ray, int distance) {
    final out = <SceneObject>[];
    void testObject(SceneObject o) {
      final h = test(o, ray, 3);
      if (h != null && h.distance < distance) out.add(o);
    }

    for (final o in scene.objects) {
      if (o.kind == 'plane') testObject(o);
    }
    void visit(Node? node) {
      if (node == null) return;
      final s = nodeTest(node, ray, 3);
      if (s == null || s.far <= settings.epsilon || s.near >= distance) return;
      if (node.left == null) {
        for (final o in node.objects) {
          testObject(o);
        }
      } else {
        visit(node.left);
        visit(node.right);
      }
    }

    visit(root);
    out.sort((a, b) => a.id.compareTo(b.id));
    return out;
  }

  Ray camera(int qx, int qy) {
    final u = floorDiv((qx - 2 * settings.w) * scene.hw, 2 * settings.w),
        v = floorDiv((2 * settings.h - qy) * scene.hh, 2 * settings.h);
    return Ray(
      scene.eye,
      (scene.forward + scene.right.scaled(u) + scene.up.scaled(v)).normalized,
    );
  }

  List<Sample> samples(Light l, Vec p) {
    if (l.kind == 'sun')
      return [Sample(l.direction, settings.far, l.intensity)];
    final out = <Sample>[], k = l.k;
    for (var j = 0; j < k; j++) {
      for (var i = 0; i < k; i++) {
        var q = l.p;
        if (l.kind == 'area')
          q = Vec.fromList(
            List.generate(
              3,
              (a) =>
                  l.p[a] +
                  floorDiv((2 * i + 1) * l.u[a], 2 * k) +
                  floorDiv((2 * j + 1) * l.v[a], 2 * k),
            ),
          );
        final rel = q - p;
        out.add(
          Sample(rel.normalized, rel.length, floorDiv(l.intensity, k * k)),
        );
      }
    }
    return out;
  }

  Vec local(Ray ray, Result result, TraceContext? ctx, List<String>? record) {
    final m = result.hit!.object.material;
    var ds = 0, ss = 0;
    result.lit = List.filled(scene.lights.length, 0);
    for (var index = 0; index < scene.lights.length; index++) {
      final l = scene.lights[index], lightSamples = samples(l, result.point);
      var lit = 0, dtotal = 0, stotal = 0;
      for (final sample in lightSamples) {
        if (result.normal.dot(sample.direction) <= 0) {
          if (active) l.backfacing++;
          continue;
        }
        final g = cone(l, sample.direction);
        if (g == 0) {
          if (active) l.outside++;
          continue;
        }
        if (active) {
          rays[3]++;
          l.shadow++;
        }
        if (ctx != null) ctx.rays++;
        final obscuring = occluders(
          Ray(result.point, sample.direction),
          sample.distance,
        );
        var f = g;
        for (final o in obscuring) {
          f = mul(f, o.material.kt);
          if (active) o.shadow++;
        }
        if (f == 0) {
          if (active) l.blocked++;
          continue;
        }
        if (obscuring.isNotEmpty && active) l.attenuated++;
        lit++;
        final (dif, spe) = components(
          m,
          result.normal,
          sample.direction,
          -ray.direction,
          mul(sample.intensity, f),
        );
        dtotal += dif;
        stotal += spe;
      }
      result.lit[index] = lit;
      if (lit > 0) result.illumination++;
      ds += dtotal;
      ss += stotal;
      record?.add(
        'light ${index + 1} lit $lit of ${lightSamples.length} diffuse $dtotal specular $stotal',
      );
    }
    return Vec.fromList(
      List.generate(3, (a) {
        final raw =
            floorDiv(result.base[a] * (scene.ambient + ds), scaleUnit) +
            floorDiv(255 * ss, scaleUnit);
        if (raw > 255 && active) clamped++;
        return min(raw, 255);
      }),
    );
  }

  Result trace(
    Ray ray,
    int kind,
    int depth, [
    TraceContext? ctx,
    List<String>? record,
  ]) {
    if (active) {
      rays[kind]++;
      depths[depth]++;
    }
    if (ctx != null) {
      ctx.rays++;
      ctx.depth = max(ctx.depth, depth);
    }
    record?.add(
      'ray ${rayKinds[kind]} $depth origin ${ray.origin} direction ${ray.direction}',
    );
    final h = nearest(ray, kind), result = Result(scene.background, null);
    if (h == null) {
      if (active) misses[kind]++;
      record?.addAll(['miss', 'color ${result.color}']);
      return result;
    }
    final hitResult = Result(scene.background, h);
    if (active) {
      if (kind == 0) {
        h.object.primary++;
      } else {
        h.object.secondary++;
      }
    }
    hitResult.point = ray.origin + ray.direction.scaled(h.distance);
    final n0 = outward(h, hitResult.point, ray.direction),
        front = n0.dot(ray.direction) <= 0;
    hitResult.normal = front ? n0 : -n0;
    hitResult.base = baseColor(h.object.material, hitResult.point);
    record?.add(
      'hit ${h.object.label} t ${h.distance} point ${hitResult.point} normal ${hitResult.normal} base ${hitResult.base}',
    );
    var color = local(ray, hitResult, ctx, record);
    record?.add('local $color');
    final m = h.object.material;
    if (depth < settings.depth && (m.kr > 0 || m.kt > 0)) {
      final (wr, wt, tdir, totalInternal) = refracted(
        m,
        ray.direction,
        hitResult.normal,
        front,
      );
      if (totalInternal) {
        if (active) tir++;
        record?.add('total_internal_reflection');
      }
      record?.add('weights ${scaleUnit - m.kr - m.kt} $wr $wt');
      var cr = zero, ct = zero;
      if (wr > 0)
        cr = trace(
          Ray(hitResult.point, reflected(ray.direction, hitResult.normal)),
          1,
          depth + 1,
          ctx,
          record,
        ).color;
      if (wt > 0)
        ct = trace(Ray(hitResult.point, tdir), 2, depth + 1, ctx, record).color;
      color = mix([color, cr, ct], [scaleUnit - m.kr - m.kt, wr, wt]);
    }
    final fog = scene.fog;
    if (fog != null) {
      var fg = 0;
      if (h.distance >= fog.end) {
        fg = scaleUnit;
      } else if (h.distance > fog.start) {
        fg = floorDiv(
          (h.distance - fog.start) * scaleUnit,
          fog.end - fog.start,
        );
      }
      color = mix([color, fog.color], [scaleUnit - fg, fg]);
    }
    hitResult.color = color;
    record?.add('color $color');
    return hitResult;
  }

  void render() {
    final s = settings;
    for (var y = 0; y < s.h; y++) {
      for (var x = 0; x < s.w; x++) {
        final ctx = TraceContext(),
            v = trace(camera(4 * x + 2, 4 * y + 2), 0, 0, ctx);
        pixels.add(Pixel(v, ctx.rays, ctx.depth));
      }
    }
    const offsets = [(0, -1), (0, 1), (-1, 0), (1, 0)],
        subsamples = [(1, 1), (3, 1), (1, 3), (3, 3)];
    for (var y = 0; y < s.h; y++) {
      for (var x = 0; x < s.w; x++) {
        final p = pixels[y * s.w + x];
        var adaptive = false;
        for (final (dx, dy) in offsets) {
          final xx = x + dx, yy = y + dy;
          if (xx < 0 || xx >= s.w || yy < 0 || yy >= s.h) continue;
          final q = pixels[yy * s.w + xx];
          var contrast = 0;
          for (var a = 0; a < 3; a++) {
            contrast = max(
              contrast,
              (p.center.color[a] - q.center.color[a]).abs(),
            );
          }
          if (p.label != q.label || contrast > s.contrast) adaptive = true;
        }
        if (adaptive) {
          supersampled++;
          p.samples = 4;
          var color = zero;
          final ctx = TraceContext()..depth = p.depth;
          for (final (dx, dy) in subsamples) {
            color =
                color + trace(camera(4 * x + dx, 4 * y + dy), 0, 0, ctx).color;
          }
          p.color = color.map((v) => floorDiv(v, 4));
          p.rays += ctx.rays;
          p.depth = ctx.depth;
        }
      }
    }
  }

  (int, int, int, bool) images() {
    final s = settings;
    var tmin = 1 << 62, tmax = 0, cmax = 0, hasHit = false;
    for (final p in pixels) {
      cmax = max(cmax, p.rays);
      final hit = p.center.hit;
      if (hit != null) {
        hasHit = true;
        tmin = min(tmin, hit.distance);
        tmax = max(tmax, hit.distance);
      }
    }
    final image = ['P3', '${s.w} ${s.h}', '255'],
        normal = ['P3', '${s.w} ${s.h}', '255'],
        albedo = ['P3', '${s.w} ${s.h}', '255'],
        depth = ['P2', '${s.w} ${s.h}', '255'],
        cost = ['P2', '${s.w} ${s.h}', '255'],
        objects = <String>[],
        lights = <String>[],
        rayDepth = <String>[];
    for (var y = 0; y < s.h; y++) {
      final ic = <String>[],
          nc = <String>[],
          ac = <String>[],
          dc = <String>[],
          cc = <String>[],
          ob = StringBuffer(),
          li = StringBuffer(),
          rd = StringBuffer();
      for (var x = 0; x < s.w; x++) {
        final p = pixels[y * s.w + x];
        ic.add(p.color.toString());
        var n = zero, a = zero, d = 0;
        final hit = p.center.hit;
        if (hit != null) {
          a = p.center.base;
          n = p.center.normal.map(
            (v) => floorDiv(
              (v + scaleUnit) * 255,
              2 * scaleUnit,
            ).clamp(0, 255).toInt(),
          );
          d = tmax == tmin
              ? 255
              : 255 - floorDiv(235 * (hit.distance - tmin), tmax - tmin);
          li.write(p.center.illumination);
        } else {
          li.write('.');
        }
        nc.add(n.toString());
        ac.add(a.toString());
        dc.add('$d');
        cc.add('${floorDiv(255 * p.rays, cmax)}');
        ob.write(p.label);
        rd.write(p.depth);
      }
      image.add(ic.join(' '));
      normal.add(nc.join(' '));
      albedo.add(ac.join(' '));
      depth.add(dc.join(' '));
      cost.add(cc.join(' '));
      objects.add(ob.toString());
      lights.add(li.toString());
      rayDepth.add(rd.toString());
    }
    writeLines('image.ppm', image);
    writeLines('normal.ppm', normal);
    writeLines('albedo.ppm', albedo);
    writeLines('depth.pgm', depth);
    writeLines('cost.pgm', cost);
    writeLines('object_map.txt', objects);
    writeLines('light_map.txt', lights);
    writeLines('ray_depth.txt', rayDepth);
    return (tmin, tmax, cmax, hasHit);
  }

  void stats(int tmin, int tmax, int cmax, bool hasHit) {
    final s = settings,
        total = rays.fold(0, (a, b) => a + b),
        lines = [
          'image ${s.w} ${s.h}',
          'supersampled $supersampled',
          'rays primary ${rays[0]} reflection ${rays[1]} refraction ${rays[2]} shadow ${rays[3]} total $total',
          'misses primary ${misses[0]} reflection ${misses[1]} refraction ${misses[2]}',
          'depth ${depths.join(' ')}',
        ];
    for (var k = 0; k < 4; k++) {
      lines.add(
        'tests ${rayKinds[k]} nodes ${nodeTests[k]} objects ${objectTests[k]}',
      );
    }
    lines.addAll([
      'total_internal_reflection $tir',
      'clamped $clamped',
      hasHit ? 'distance $tmin $tmax' : 'distance none',
    ]);
    var color = zero;
    final hist = List.filled(8, 0);
    for (final p in pixels) {
      color = color + p.color;
      final brightness = floorDiv(
        299 * p.color.x + 587 * p.color.y + 114 * p.color.z,
        1000,
      );
      hist[brightness ~/ 32]++;
    }
    color = color.map((v) => floorDiv(v, pixels.length));
    lines.addAll([
      'max_pixel_rays $cmax',
      'mean $color',
      'histogram ${hist.join(' ')}',
    ]);
    void visit(Node? node) {
      if (node == null) return;
      final kind = node.left == null
          ? 'leaf ${node.objects.map((o) => o.label).join()}'
          : 'inner';
      lines.add(
        'node ${node.depth} $kind box ${node.box.lo} ${node.box.hi} visits ${node.visits}',
      );
      visit(node.left);
      visit(node.right);
    }

    visit(root);
    for (final o in scene.objects) {
      var count = 0, loX = s.w, loY = s.h, hiX = -1, hiY = -1, col = zero;
      for (var i = 0; i < pixels.length; i++) {
        final p = pixels[i];
        if (p.label == o.label) {
          count++;
          final x = i % s.w, y = i ~/ s.w;
          loX = min(loX, x);
          loY = min(loY, y);
          hiX = max(hiX, x);
          hiY = max(hiY, y);
          col = col + p.color;
        }
      }
      var suffix = 'box none color none';
      if (count > 0) {
        col = col.map((v) => floorDiv(v, count));
        suffix = 'box $loX $loY $hiX $hiY color $col';
      }
      lines.add(
        'object ${o.label} ${o.kind} primary ${o.primary} secondary ${o.secondary} shadow ${o.shadow} pixels $count $suffix',
      );
    }
    for (var i = 0; i < scene.lights.length; i++) {
      final l = scene.lights[i];
      var count = 0;
      for (final p in pixels) {
        if (p.center.hit != null && p.center.lit[i] > 0) count++;
      }
      lines.add(
        'light ${i + 1} ${l.kind} samples ${l.k * l.k} pixels $count shadow_rays ${l.shadow} blocked ${l.blocked} attenuated ${l.attenuated} backfacing ${l.backfacing} outside ${l.outside}',
      );
    }
    writeLines('stats.txt', lines);
  }

  void queries() {
    active = false;
    final lines = <String>[],
        queries = File('input/queries.txt').readAsLinesSync();
    for (var index = 0; index < queries.length; index++) {
      final line = queries[index], a = line.split(' ');
      lines.add('query ${index + 1} $line');
      switch (a[0]) {
        case 'pixel':
          final v = integers(a.sublist(1)),
              p = pixels[v[1] * settings.w + v[0]],
              distance = p.center.hit?.distance.toString() ?? 'none';
          lines.add(
            'label ${p.label} distance $distance color ${p.color} samples ${p.samples} rays ${p.rays}',
          );
        case 'trace':
          final v = integers(a.sublist(1));
          trace(camera(4 * v[0] + 2, 4 * v[1] + 2), 0, 0, null, lines);
        case 'ray':
          final v = integers(a.sublist(1));
          trace(
            Ray(Vec.fromList(v), Vec.fromList(v.sublist(3)).normalized),
            0,
            0,
            null,
            lines,
          );
        case 'object':
          final o = scene.objects.firstWhere((o) => o.label == a[1]),
              suffix = o.kind == 'plane'
                  ? 'bounds none leaf none'
                  : 'bounds ${o.bounds.lo} ${o.bounds.hi} leaf ${o.leafDepth}';
          lines.add('${o.kind} material ${o.material.name} $suffix');
        case 'visible':
          final v = integers(a.sublist(1)),
              rel = Vec.fromList(v) - scene.eye,
              ray = Ray(scene.eye, rel.normalized),
              visible = occluders(ray, rel.length - settings.epsilon).isEmpty
                  ? 'yes'
                  : 'no',
              h = nearest(ray, 0);
          lines.add(
            h == null
                ? '$visible first none'
                : '$visible first ${h.object.label} t ${h.distance}',
          );
        case 'shadow':
          final p = Vec.fromList(integers(a.sublist(1)));
          for (var i = 0; i < scene.lights.length; i++) {
            final l = scene.lights[i], set = <int>{};
            var factor = 0;
            for (final sample in samples(l, p)) {
              var f = cone(l, sample.direction);
              for (final o in occluders(
                Ray(p, sample.direction),
                sample.distance,
              )) {
                f = mul(f, o.material.kt);
                set.add(o.id);
              }
              factor += f;
            }
            final labels = scene.objects
                .where((o) => set.contains(o.id))
                .map((o) => o.label)
                .join();
            lines.add(
              'light ${i + 1} factor $factor occluders ${labels.isEmpty ? 'none' : labels}',
            );
          }
        case 'region':
          final v = integers(a.sublist(1)), labels = <String, int>{};
          var count = 0, color = zero;
          for (var y = v[1]; y <= v[3]; y++) {
            for (var x = v[0]; x <= v[2]; x++) {
              final p = pixels[y * settings.w + x];
              count++;
              color = color + p.color;
              labels[p.label] = (labels[p.label] ?? 0) + 1;
            }
          }
          color = color.map((c) => floorDiv(c, count));
          lines.add('pixels $count mean $color');
          for (final label in [...scene.objects.map((o) => o.label), '.']) {
            if ((labels[label] ?? 0) > 0)
              lines.add('label $label ${labels[label]}');
          }
      }
    }
    writeLines('queries.txt', lines);
  }
}

void main() {
  final scene = readScene(),
      settings = readSettings(),
      bounded = <SceneObject>[];
  for (final o in scene.objects) {
    if (o.kind != 'plane') {
      o.bounds = bounding(o, settings.pad);
      bounded.add(o);
    }
  }
  final r = Renderer(scene, settings, build(bounded, 0));
  r.render();
  final (tmin, tmax, cmax, hit) = r.images();
  r.stats(tmin, tmax, cmax, hit);
  r.queries();
}
