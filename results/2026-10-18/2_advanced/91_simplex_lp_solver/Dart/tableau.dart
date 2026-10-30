part of 'main.dart';

class Tableau {
  final List<List<Fraction>> t = [];
  final List<Fraction> beta = [];
  List<int> basis = [];
  (List<Fraction>, Fraction) reduced(List<Fraction> cost) {
    final r = List<Fraction>.of(cost);
    var z = zero;
    for (var i = 0; i < basis.length; i++) {
      final basic = basis[i];
      z = z.add(cost[basic].mul(beta[i]));
      for (var k = 0; k < r.length; k++) {
        r[k] = r[k].sub(cost[basic].mul(t[i][k]));
      }
    }
    return (r, z);
  }

  void pivot(int p, int q) {
    final factor = t[p][q];
    for (var k = 0; k < t[p].length; k++) {
      t[p][k] = t[p][k].div(factor);
    }
    beta[p] = beta[p].div(factor);
    for (var i = 0; i < t.length; i++) {
      if (i == p) continue;
      final f = t[i][q];
      for (var k = 0; k < t[i].length; k++) {
        t[i][k] = t[i][k].sub(f.mul(t[p][k]));
      }
      beta[i] = beta[i].sub(f.mul(beta[p]));
    }
    basis[p] = q;
  }

  List<String> display(
    String heading,
    List<String> columns,
    List<String> rows,
    List<Fraction> cost,
    Fraction constant,
    int sign,
  ) {
    final out = ['TABLEAU $heading', 'COLUMNS ${columns.join(' ')}'];
    for (var i = 0; i < t.length; i++) {
      out.add(
        'ROW ${rows[i]} ${columns[basis[i]]} ${t[i].join(' ')} | ${beta[i]}',
      );
    }
    final (r, z) = reduced(cost);
    out.add('COST ${r.join(' ')} | ${constant.add(Fraction(sign).mul(z))}');
    return out;
  }
}
