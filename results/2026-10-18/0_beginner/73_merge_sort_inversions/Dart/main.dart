void main() {
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
        temp.addAll(a.getRange(i, m + 1));
        temp.addAll(a.getRange(j, r + 1));
        a.setRange(l, r + 1, temp);
        print('merge [$l..$r]: ${temp.join(' ')}');
    }
    mergeSort(0, 9);
    print('sorted: ${a.join(' ')}\ninversions: $inversions');
}
