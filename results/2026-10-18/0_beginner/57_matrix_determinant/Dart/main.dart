import 'dart:io';

int det(List<List<int>> matrix) {
    if (matrix.length == 1)
        return matrix[0][0];
    var result = 0;
    for (var j = 0; j < matrix.length; j++) {
        final minor = [for (final row in matrix.skip(1))[for (var c = 0; c < row.length; c++) if (c != j) row[c]]];
        final term = matrix[0][j] * det(minor);
        result += j % 2 == 0 ? term : -term;
    }
    return result;
}

void main() {
    final out = StringBuffer();
    const matrices = [[[2, -3, 1], [5, 4, -2], [-1, 6, 3]], [[3, 0, -2, 5], [1, 4, 7, -3], [-6, 2,
        1, 8], [9, -5, 3, 2]], [[4, -1, 7, 0, -3], [2, 8, -5, 6, 1], [-9, 3, 2, -4, 5], [6, 0, -7, 3,
        -2], [1, -6, 4, 9, 8]]];
    for (final matrix in matrices)
        out.writeln('det(${matrix.length}x${matrix.length}) = ${det(matrix)}');
    stdout.write(out);
}
