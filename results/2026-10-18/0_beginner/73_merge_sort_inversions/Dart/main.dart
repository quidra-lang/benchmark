import 'dart:io';

void main() {
    final out = StringBuffer();
    final a = [47, 12, 85, 33, 6, 71, 29, 58, 90, 14];
    var inversions = 0;
    void mergeSort(int l, int r) {
        if (l == r)
            return;
        final m = (l + r) ~/ 2;
        mergeSort(l, m);
        mergeSort(m + 1, r);
        final temp = <int>[];
        var i = l, j = m + 1;
        while (i <= m && j <= r) {
            if (a[i] < a[j]) {
                temp.add(a[i++]);
            } else {
                inversions += m - i + 1;
                temp.add(a[j++]);
            }
        }
        while (i <= m)
            temp.add(a[i++]);
        while (j <= r)
            temp.add(a[j++]);
        for (var k = 0; k < temp.length; k++)
            a[l + k] = temp[k];
        out.writeln('merge [$l..$r]: ${temp.join(' ')}');
    }
    mergeSort(0, 9);
    out.writeln('sorted: ${a.join(' ')}\ninversions: $inversions');
    stdout.write(out);
}
