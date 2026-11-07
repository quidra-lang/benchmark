import 'dart:math';
import 'dataset.dart';
import 'variable_charts.dart';

const attributeCharts = ['p', 'np', 'c', 'u'];

class CenterLine {
  final double value, fraction;
  CenterLine._(this.value, this.fraction);
  factory CenterLine(int chart, List<Lot> lots) {
    final defectives = integerSum(lots.map((l) => l.defectives)), defects = integerSum(lots.map((l) => l.defects)), inspected = integerSum(lots.map((l) => l.inspected));
    final fraction = defectives / inspected;
    final value = switch (chart) { 0 => fraction, 1 => defectives / lots.length, 2 => defects / lots.length, _ => defects / inspected };
    return CenterLine._(value, fraction);
  }
}

class LotPoint {
  final double value, lcl, ucl, z;
  final String status;
  LotPoint._(this.value, this.lcl, this.ucl, this.z, this.status);
  factory LotPoint(int chart, Lot lot, CenterLine center) {
    final cl = center.value;
    final (value, sigma) = switch (chart) {
      0 => (lot.defectives / lot.inspected, sqrt(cl * (1 - cl) / lot.inspected)),
      1 => (lot.defectives.toDouble(), sqrt(cl * (1 - center.fraction))),
      2 => (lot.defects.toDouble(), sqrt(cl)),
      _ => (lot.defects / lot.inspected, sqrt(cl / lot.inspected))
    };
    final lcl = max(0.0, cl - 3 * sigma), ucl = cl + 3 * sigma;
    return LotPoint._(value, lcl, ucl, (value - cl) / sigma, value > ucl ? 'high' : value < lcl ? 'low' : 'ok');
  }
}
