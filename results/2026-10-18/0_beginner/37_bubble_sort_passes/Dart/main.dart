void main() {
    final a = [27, 64, 13, 88, 41, 5, 72, 36];
    var total = 0;
    for (var pass = 1; pass <= 7; pass++) {
        var swapped = false;
        for (var j = 0; j < 8 - pass; j++) {
            if (a[j] > a[j + 1]) {
                final value = a[j];
                a[j] = a[j + 1];
                a[j + 1] = value;
                total++;
                swapped = true;
            }
        }
        print('pass $pass: ${a.join(' ')}');
        if (!swapped)
            break;
    }
    print('swaps: $total');
}
