part of 'main.dart';

class Plane {
  final int w, h;
  final List<int> a;
  Plane(this.w, this.h) : a = List.filled(w * h, 0);
}

int floor(int a, int b) => a ~/ b - (a < 0 && a % b != 0 ? 1 : 0);
int clamp(int a) => a.clamp(0, 255).toInt();
List<Plane> colors(Image im) {
  final p = List.generate(3, (_) => Plane(im.w, im.h));
  for (var i = 0; i < im.w * im.h; i++) {
    final r = im.rgb[3 * i], g = im.rgb[3 * i + 1], b = im.rgb[3 * i + 2];
    p[0].a[i] = floor(19595 * r + 38470 * g + 7471 * b + 32768, 65536);
    p[1].a[i] = floor(-11059 * r - 21709 * g + 32768 * b + 8421375, 65536);
    p[2].a[i] = floor(32768 * r - 27439 * g - 5329 * b + 8421375, 65536);
  }
  return p;
}

List<int> toRgb(int y, int cb, int cr) => [
  clamp(y + floor(91881 * (cr - 128) + 32768, 65536)),
  clamp(y + floor(-22554 * (cb - 128) - 46802 * (cr - 128) + 32768, 65536)),
  clamp(y + floor(116130 * (cb - 128) + 32768, 65536)),
];
List<Plane> componentPlanes(Image im, Geometry g) {
  final a = colors(im), p = <Plane>[];
  for (var k = 0; k < 3; k++) {
    final c = g.components[k],
        plane = Plane(
          8 * g.components[k].h * g.mx,
          8 * g.components[k].v * g.my,
        );
    final fx = g.hmax ~/ c.h, fy = g.vmax ~/ c.v;
    for (var y = 0; y < plane.h; y++) {
      for (var x = 0; x < plane.w; x++) {
        var sum = 0;
        for (var j = 0; j < fy; j++) {
          for (var i = 0; i < fx; i++) {
            sum +=
                a[k].a[min(fy * y + j, im.h - 1) * im.w +
                    min(fx * x + i, im.w - 1)];
          }
        }
        plane.a[y * plane.w + x] = sum ~/ (fx * fy);
      }
    }
    p.add(plane);
  }
  return p;
}

(List<Plane>, Image) upsample(List<Plane> p, Geometry g) {
  final a = List.generate(3, (_) => Plane(g.w, g.h)),
      im = Image(g.w, g.h, List.filled(3 * g.w * g.h, 0));
  for (var k = 0; k < 3; k++) {
    final c = g.components[k];
    for (var y = 0; y < g.h; y++) {
      for (var x = 0; x < g.w; x++) {
        a[k].a[y * g.w + x] =
            p[k].a[(y * c.v ~/ g.vmax) * p[k].w + x * c.h ~/ g.hmax];
      }
    }
  }
  for (var i = 0; i < g.w * g.h; i++) {
    im.rgb.setRange(3 * i, 3 * i + 3, toRgb(a[0].a[i], a[1].a[i], a[2].a[i]));
  }
  return (a, im);
}
