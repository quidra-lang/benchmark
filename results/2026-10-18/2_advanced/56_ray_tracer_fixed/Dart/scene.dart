part of 'main.dart';

class Material {
  final String name;
  final Vec color;
  final int kd, ks, exponent, kr, kt, ior;
  bool checker = false;
  Vec second = zero;
  int size = 1;
  Material(this.name, List<int> v)
    : color = Vec.fromList(v),
      kd = v[3],
      ks = v[4],
      exponent = v[5],
      kr = v[6],
      kt = v[7],
      ior = v[8];
}

class SceneObject {
  final int id;
  final String label, kind;
  final Material material;
  Vec p = zero, n = zero, lo = zero, hi = zero;
  int radius = 0, leafDepth = 0, primary = 0, secondary = 0, shadow = 0;
  late Bounds bounds;
  SceneObject(this.id, this.label, this.kind, this.material);
}

class Light {
  final String kind;
  Vec p = zero, direction = zero, u = zero, v = zero;
  int outer = 0,
      inner = 0,
      intensity = 0,
      k = 1,
      shadow = 0,
      blocked = 0,
      attenuated = 0,
      backfacing = 0,
      outside = 0;
  Light(this.kind);
}

class Fog {
  final Vec color;
  final int start, end;
  Fog(this.color, this.start, this.end);
}

class Scene {
  Vec eye = zero, forward = zero, right = zero, up = zero, background = zero;
  int hw = 0, hh = 0, ambient = 0;
  Fog? fog;
  final objects = <SceneObject>[], lights = <Light>[];
}

List<int> integers(List<String> a) => a.map(int.parse).toList();
Scene readScene() {
  final s = Scene(), materials = <String, Material>{};
  for (final line in File('input/scene.txt').readAsLinesSync()) {
    if (line.isEmpty || line.startsWith('#')) continue;
    final a = line.split(' ');
    switch (a[0]) {
      case 'material':
        materials[a[1]] = Material(a[1], integers(a.sublist(2)));
      case 'checker':
        final v = integers(a.sublist(2)), m = materials[a[1]]!;
        m.checker = true;
        m.second = Vec.fromList(v);
        m.size = v[3];
      case 'sphere':
      case 'plane':
      case 'box':
        final v = integers(a.sublist(3)),
            o = SceneObject(s.objects.length, a[1], a[0], materials[a[2]]!);
        if (o.kind == 'sphere') {
          o.p = Vec.fromList(v);
          o.radius = v[3];
        } else if (o.kind == 'plane') {
          o.p = Vec.fromList(v);
          o.n = Vec.fromList(v.sublist(3)).normalized;
        } else {
          o.lo = Vec.fromList(v);
          o.hi = Vec.fromList(v.sublist(3));
        }
        s.objects.add(o);
      case 'point':
      case 'spot':
      case 'sun':
      case 'area':
        final v = integers(a.sublist(1)), l = Light(a[0]);
        switch (l.kind) {
          case 'point':
            l.p = Vec.fromList(v);
            l.intensity = v[3];
          case 'spot':
            l.p = Vec.fromList(v);
            l.direction = Vec.fromList(v.sublist(3)).normalized;
            l.outer = v[6];
            l.inner = v[7];
            l.intensity = v[8];
          case 'sun':
            l.direction = (-Vec.fromList(v)).normalized;
            l.intensity = v[3];
          case 'area':
            l.p = Vec.fromList(v);
            l.u = Vec.fromList(v.sublist(3));
            l.v = Vec.fromList(v.sublist(6));
            l.k = v[9];
            l.intensity = v[10];
        }
        s.lights.add(l);
      default:
        final v = integers(a.sublist(1));
        switch (a[0]) {
          case 'eye':
            s.eye = Vec.fromList(v);
          case 'forward':
            s.forward = Vec.fromList(v);
          case 'right':
            s.right = Vec.fromList(v);
          case 'up':
            s.up = Vec.fromList(v);
          case 'view':
            s.hw = v[0];
            s.hh = v[1];
          case 'background':
            s.background = Vec.fromList(v);
          case 'ambient':
            s.ambient = v[0];
          case 'fog':
            s.fog = Fog(Vec.fromList(v), v[3], v[4]);
        }
    }
  }
  return s;
}
