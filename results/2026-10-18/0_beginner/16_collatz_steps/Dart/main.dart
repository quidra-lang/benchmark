import 'dart:math' as math;

void main() {
    for (final initial in [1, 6, 27, 97, 871]) {
        var n = initial, steps = 0, maximum = n;
        while (n != 1) {
            n = n % 2 == 0 ? n ~/ 2 : 3 * n + 1;
            steps++;
            maximum = math.max(maximum, n);
        }
        print('$initial: steps=$steps max=$maximum');
    }
}
