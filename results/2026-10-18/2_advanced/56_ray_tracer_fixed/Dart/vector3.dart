part of 'main.dart';

class Vec {
  final int x, y, z;
  const Vec(this.x, this.y, this.z);
  factory Vec.fromList(List<int> a) => Vec(a[0], a[1], a[2]);
  int operator [](int a) => a == 0
      ? x
      : a == 1
      ? y
      : z;
  Vec operator +(Vec b) => Vec(x + b.x, y + b.y, z + b.z);
  Vec operator -(Vec b) => Vec(x - b.x, y - b.y, z - b.z);
  Vec operator -() => Vec(-x, -y, -z);
  Vec scaled(int k) => Vec(mul(x, k), mul(y, k), mul(z, k));
  int dot(Vec b) => floorDiv(x * b.x + y * b.y + z * b.z, scaleUnit);
  int get length => isqrt(x * x + y * y + z * z);
  Vec get normalized {
    final l = length;
    return Vec(
      floorDiv(x * scaleUnit, l),
      floorDiv(y * scaleUnit, l),
      floorDiv(z * scaleUnit, l),
    );
  }

  Vec map(int Function(int) f) => Vec(f(x), f(y), f(z));
  @override
  String toString() => '$x $y $z';
}

const zero = Vec(0, 0, 0);
