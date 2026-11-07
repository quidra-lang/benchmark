part of 'main.dart';

class Material {
  final String code, name;
  final double k, rho, cp;
  final cells = <int>[];
  Material(this.code, this.name, this.k, this.rho, this.cp);
}

(List<Material>, List<int>) readMaterials(Mesh mesh) {
  final out = <Material>[], index = <String, int>{};
  for (final line in readLines('input/materials.txt')) {
    final a = line.split(' ');
    index[a[0]] = out.length;
    out.add(
      Material(
        a[0],
        a[1],
        double.parse(a[2]),
        double.parse(a[3]),
        double.parse(a[4]),
      ),
    );
  }
  final cells = List.generate(mesh.codes.length, (p) => index[mesh.codes[p]]!);
  for (var p = 0; p < cells.length; p++) {
    out[cells[p]].cells.add(p);
  }
  return (out, cells);
}

double capacity(Material m, Mesh mesh) =>
    m.rho * m.cp * mesh.dx * mesh.dx * mesh.thickness;
double interiorConductance(double k1, double k2, double d) =>
    2 * k1 * k2 / (k1 + k2) * d;
double fixedConductance(double k, double d) => 2 * k * d;
double convectiveConductance(double k, double h, Mesh mesh) =>
    1 / (1 / (h * mesh.dx * mesh.thickness) + 1 / (2 * k * mesh.thickness));
