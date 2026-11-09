import 'dart:math' as math;
import 'season.dart';

List<List<double>> realMatrix(int size) =>
    List.generate(size, (_) => List.filled(size, 0.0));

List<double> choleskySolve(List<List<double>> matrix, List<double> vector) {
  final size = vector.length;
  final lower = realMatrix(size);
  for (var i = 0; i < size; i++) {
    for (var j = 0; j <= i; j++) {
      var total = 0.0;
      for (var k = 0; k < j; k++) {
        total += lower[i][k] * lower[j][k];
      }
      lower[i][j] = j < i
          ? (matrix[i][j] - total) / lower[j][j]
          : math.sqrt(matrix[i][i] - total);
    }
  }
  final forward = List.filled(size, 0.0);
  for (var i = 0; i < size; i++) {
    var total = 0.0;
    for (var k = 0; k < i; k++) {
      total += lower[i][k] * forward[k];
    }
    forward[i] = (vector[i] - total) / lower[i][i];
  }
  final solution = List.filled(size, 0.0);
  for (var i = size - 1; i >= 0; i--) {
    var total = 0.0;
    for (var k = i + 1; k < size; k++) {
      total += lower[k][i] * solution[k];
    }
    solution[i] = (forward[i] - total) / lower[i][i];
  }
  return solution;
}

List<double> gaussianSolve(List<List<double>> matrix, List<double> vector) {
  final size = vector.length;
  for (var k = 0; k < size; k++) {
    var pivot = k;
    for (var row = k + 1; row < size; row++) {
      if (matrix[row][k].abs() > matrix[pivot][k].abs()) pivot = row;
    }
    final savedRow = matrix[k];
    matrix[k] = matrix[pivot];
    matrix[pivot] = savedRow;
    final savedValue = vector[k];
    vector[k] = vector[pivot];
    vector[pivot] = savedValue;
    for (var i = k + 1; i < size; i++) {
      final factor = matrix[i][k] / matrix[k][k];
      for (var j = k; j < size; j++) {
        matrix[i][j] -= factor * matrix[k][j];
      }
      vector[i] -= factor * vector[k];
    }
  }
  final solution = List.filled(size, 0.0);
  for (var i = size - 1; i >= 0; i--) {
    var total = 0.0;
    for (var j = i + 1; j < size; j++) {
      total += matrix[i][j] * solution[j];
    }
    solution[i] = (vector[i] - total) / matrix[i][i];
  }
  return solution;
}

List<double> colleyRatings(int count, List<Match> matches) {
  final matrix = realMatrix(count);
  final balance = List.filled(count, 0);
  for (var i = 0; i < count; i++) {
    matrix[i][i] = 2;
  }
  for (final match in matches) {
    final i = match.home;
    final j = match.away;
    matrix[i][i]++;
    matrix[j][j]++;
    matrix[i][j]--;
    matrix[j][i]--;
    if (match.margin > 0) {
      balance[i]++;
      balance[j]--;
    } else if (match.margin < 0) {
      balance[i]--;
      balance[j]++;
    }
  }
  return choleskySolve(matrix, [for (final value in balance) 1 + value / 2]);
}

(List<double>, double) masseyRatings(int count, List<Match> matches) {
  final last = count;
  final matrix = realMatrix(count + 1);
  final vector = List.filled(count + 1, 0.0);
  for (final match in matches) {
    final i = match.home;
    final j = match.away;
    matrix[i][i]++;
    matrix[j][j]++;
    matrix[i][j]--;
    matrix[j][i]--;
    matrix[i][last]++;
    matrix[last][i]++;
    matrix[j][last]--;
    matrix[last][j]--;
    matrix[last][last]++;
    vector[i] += match.margin;
    vector[j] -= match.margin;
    vector[last] += match.margin;
  }
  matrix[count - 1] = [...List.filled(count, 1.0), 0.0];
  vector[count - 1] = 0;
  final solution = gaussianSolve(matrix, vector);
  return (solution.sublist(0, count), solution[last]);
}
