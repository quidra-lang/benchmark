void main() {
    const originals = [[[2, -1, 3, 7], [4, 1, -2, 3], [-3, 5, 1, -4]], [[1, 3, -2, 4, 6], [5, -2,
        1, 3, -7], [-2, 4, 6, -1, 9], [3, 1, -4, 2, 5]]];
    for (var system = 0; system < originals.length; system++) {
        final a = [for (final row in originals[system]) row.map((v) => v.toDouble()).toList()], n = originals[system].length;
        for (var k = 0; k < n; k++) {
            var pivot = k;
            for (var i = k; i < n; i++) {
                if (a[i][k].abs() > a[pivot][k].abs())
                    pivot = i;
            }
            if (pivot != k) {
                final row = a[k];
                a[k] = a[pivot];
                a[pivot] = row;
            }
            for (var i = k + 1; i < n; i++) {
                final f = a[i][k] / a[k][k];
                for (var j = k; j <= n; j++)
                    a[i][j] = a[i][j] - f * a[k][j];
            }
        }
        final x = List.filled(n, 0.0);
        for (var i = n - 1; i >= 0; i--) {
            var s = a[i][n];
            for (var j = i + 1; j < n; j++)
                s = s - a[i][j] * x[j];
            x[i] = s / a[i][i];
        }
        print('system ${system+1}:');
        for (var i = 0; i < n; i++)
            print('x${i+1} = ${x[i].toStringAsFixed(4)}');
    }
}
