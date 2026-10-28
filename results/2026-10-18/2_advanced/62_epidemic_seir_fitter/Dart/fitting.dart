part of 'main.dart';

class GoldenRecord {
  final double a, b, c, d, fc, fd;
  GoldenRecord(this.a, this.b, this.c, this.d, this.fc, this.fd);
}

class GoldenResult {
  final double x, value;
  final List<GoldenRecord> records;
  GoldenResult(this.x, this.value, this.records);
}

GoldenResult golden(
  double Function(double) f,
  double lower,
  double upper,
  int n,
) {
  const phi = .6180339887498949;
  var a = lower,
      b = upper,
      c = b - phi * (b - a),
      d = a + phi * (b - a),
      fc = f(c),
      fd = f(d);
  final records = [GoldenRecord(a, b, c, d, fc, fd)];
  for (var i = 0; i < n; i++) {
    if (fc < fd) {
      b = d;
      d = c;
      fd = fc;
      c = b - phi * (b - a);
      fc = f(c);
    } else {
      a = c;
      c = d;
      fc = fd;
      d = a + phi * (b - a);
      fd = f(d);
    }
    records.add(GoldenRecord(a, b, c, d, fc, fd));
  }
  return fc < fd ? GoldenResult(c, fc, records) : GoldenResult(d, fd, records);
}

class Vertex {
  final double beta, gamma, value;
  final int number;
  Vertex(this.beta, this.gamma, this.value, this.number);
}

class NelderRecord {
  final String operation;
  final Vertex best;
  NelderRecord(this.operation, this.best);
}

class NelderResult {
  final List<Vertex> initial, finalVertices;
  final List<NelderRecord> records;
  NelderResult(this.initial, this.finalVertices, this.records);
}

int vertexCompare(Vertex a, Vertex b) {
  final c = a.value.compareTo(b.value);
  return c != 0 ? c : a.number.compareTo(b.number);
}

NelderResult nelder(
  double Function(double, double) f,
  double beta,
  double gamma,
  Params p,
) {
  var serial = 0;
  Vertex create(double b, double g) => Vertex(b, g, f(b, g), serial++);
  final vertices = [
        create(beta, gamma),
        create(beta + p.deltaBeta, gamma),
        create(beta, gamma + p.deltaGamma),
      ],
      initial = List<Vertex>.empty(growable: true),
      records = <NelderRecord>[];
  initial.addAll(vertices);
  for (var iteration = 0; iteration < p.nelder; iteration++) {
    vertices.sort(vertexCompare);
    final x1 = vertices[0],
        x2 = vertices[1],
        x3 = vertices[2],
        ob = (x1.beta + x2.beta) / 2,
        og = (x1.gamma + x2.gamma) / 2,
        rb = ob + p.alpha * (ob - x3.beta),
        rg = og + p.alpha * (og - x3.gamma),
        fr = f(rb, rg);
    var operation = 'reflect', ab = rb, ag = rg, av = fr, shrink = false;
    if (fr < x1.value) {
      final eb = ob + p.chi * (rb - ob),
          eg = og + p.chi * (rg - og),
          fe = f(eb, eg);
      if (fe < fr) {
        operation = 'expand';
        ab = eb;
        ag = eg;
        av = fe;
      }
    } else if (fr < x2.value) {
    } else if (fr < x3.value) {
      final cb = ob + p.psi * (rb - ob),
          cg = og + p.psi * (rg - og),
          fc = f(cb, cg);
      if (fc <= fr) {
        operation = 'contract_out';
        ab = cb;
        ag = cg;
        av = fc;
      } else {
        shrink = true;
      }
    } else {
      final cb = ob + p.psi * (x3.beta - ob),
          cg = og + p.psi * (x3.gamma - og),
          fc = f(cb, cg);
      if (fc < x3.value) {
        operation = 'contract_in';
        ab = cb;
        ag = cg;
        av = fc;
      } else {
        shrink = true;
      }
    }
    if (shrink) {
      operation = 'shrink';
      vertices[1] = create(
        x1.beta + p.omega * (x2.beta - x1.beta),
        x1.gamma + p.omega * (x2.gamma - x1.gamma),
      );
      vertices[2] = create(
        x1.beta + p.omega * (x3.beta - x1.beta),
        x1.gamma + p.omega * (x3.gamma - x1.gamma),
      );
    } else {
      vertices[2] = Vertex(ab, ag, av, serial++);
    }
    vertices.sort(vertexCompare);
    records.add(NelderRecord(operation, vertices.first));
  }
  return NelderResult(initial, List.of(vertices), records);
}
