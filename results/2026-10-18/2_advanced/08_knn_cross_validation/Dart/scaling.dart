import 'dart:math';
import 'dataset.dart';

class Scaling {
  final centers = <double>[], scales = <double>[];
  Scaling(List<DataRow> rows, String method) {
    for (var j = 0; j < rows.first.values.length; j++) {
      late double center, scale;
      if (method == 'standard') {
        var sum = 0.0;
        for (final row in rows) { sum += row.values[j]; }
        center = sum / rows.length;
        var squares = 0.0;
        for (final row in rows) { final difference = row.values[j] - center; squares += difference * difference; }
        scale = rows.length == 1 ? 0.0 : sqrt(squares / (rows.length - 1));
      } else {
        center = rows.first.values[j]; var highest = center;
        for (final row in rows) { center = min(center, row.values[j]); highest = max(highest, row.values[j]); }
        scale = highest - center;
      }
      centers.add(center); scales.add(scale);
    }
  }
  List<double> transform(List<double> values, List<int> features) => [for (final j in features) scales[j] > 0 ? (values[j] - centers[j]) / scales[j] : 0.0];
}
