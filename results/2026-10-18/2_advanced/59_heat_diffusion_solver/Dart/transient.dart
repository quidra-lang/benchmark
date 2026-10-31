part of 'main.dart';

class Face {
  final int neighbor;
  double g = 0, theta = 0;
  bool boundary = false;
  Face(this.neighbor);
}

class Plate {
  final Mesh mesh;
  final List<Material> materials;
  final List<int> materialIndex;
  final List<List<Face>> faces;
  final List<double> c, a, beta, sall;
  Plate(this.mesh, this.materials, this.materialIndex)
    : faces = mesh.neighbors.map((row) => row.map(Face.new).toList()).toList(),
      c = List.filled(mesh.codes.length, 0),
      a = List.filled(mesh.codes.length, 0),
      beta = List.filled(mesh.codes.length, 0),
      sall = List.filled(mesh.codes.length, 0);
}

double flows(Plate plate, List<double> x, int p, int first, int last) {
  var s = 0.0;
  for (var face = first; face <= last; face++) {
    final f = plate.faces[p][face];
    if (f.neighbor >= 0) {
      s += f.g * (x[f.neighbor] - x[p]);
    } else if (f.boundary) {
      s += f.g * (f.theta - x[p]);
    }
  }
  return s;
}

List<double> thomas(
  List<double> lower,
  List<double> diagonal,
  List<double> upper,
  List<double> rhs,
) {
  final n = rhs.length,
      nu = List.filled(n, 0.0),
      phi = List.filled(n, 0.0),
      y = List.filled(n, 0.0);
  nu[0] = upper[0] / diagonal[0];
  phi[0] = rhs[0] / diagonal[0];
  for (var i = 1; i < n; i++) {
    final kappa = diagonal[i] - lower[i] * nu[i - 1];
    nu[i] = upper[i] / kappa;
    phi[i] = (rhs[i] - lower[i] * phi[i - 1]) / kappa;
  }
  y[n - 1] = phi[n - 1];
  for (var i = n - 2; i >= 0; i--) {
    y[i] = phi[i] - nu[i] * y[i + 1];
  }
  return y;
}

List<double> sweep(Plate plate, double tau, List<double> rhs, bool horizontal) {
  final mesh = plate.mesh,
      groups = horizontal ? mesh.h : mesh.w,
      size = horizontal ? mesh.w : mesh.h,
      first = horizontal ? 0 : 2,
      out = List.filled(rhs.length, 0.0);
  for (var group = 0; group < groups; group++) {
    final cells = List.filled(size, 0),
        lower = List.filled(size, 0.0),
        diagonal = List.filled(size, 0.0),
        upper = List.filled(size, 0.0),
        phi = List.filled(size, 0.0);
    for (var i = 0; i < size; i++) {
      final p = horizontal ? group * mesh.w + i : i * mesh.w + group,
          l = plate.faces[p][first],
          r = plate.faces[p][first + 1];
      cells[i] = p;
      if (l.neighbor >= 0) lower[i] = -l.g;
      if (r.neighbor >= 0) upper[i] = -r.g;
      diagonal[i] = plate.c[p] / tau + l.g + r.g;
      phi[i] = rhs[p];
      if (l.boundary) phi[i] += l.g * l.theta;
      if (r.boundary) phi[i] += r.g * r.theta;
    }
    final y = thomas(lower, diagonal, upper, phi);
    for (var i = 0; i < size; i++) {
      out[cells[i]] = y[i];
    }
  }
  return out;
}

(List<double>, List<double>?) step(
  Plate plate,
  List<double> old,
  List<double> source,
  double dt,
  String method,
) {
  final rhs = List.filled(old.length, 0.0);
  if (method == 'ftcs') {
    for (var p = 0; p < old.length; p++) {
      rhs[p] =
          old[p] + dt * (flows(plate, old, p, 0, 3) + source[p]) / plate.c[p];
    }
    return (rhs, null);
  }
  final tau = method == 'crank_nicolson' ? dt / 2 : dt;
  for (var p = 0; p < old.length; p++) {
    rhs[p] = plate.c[p] / tau * old[p] + flows(plate, old, p, 2, 3) + source[p];
  }
  final y = sweep(plate, tau, rhs, true);
  for (var p = 0; p < old.length; p++) {
    rhs[p] = method == 'backward_euler'
        ? plate.c[p] / dt * y[p] - flows(plate, old, p, 2, 3)
        : plate.c[p] / tau * y[p] + flows(plate, y, p, 0, 1) + source[p];
  }
  return (sweep(plate, tau, rhs, false), y);
}
