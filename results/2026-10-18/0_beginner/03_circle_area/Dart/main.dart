void main() {
    const radii = [3, 7, 12, 25, 41];
    const pi = 3.141592653589793;
    for (final radius in radii) {
        final r = radius.toDouble();
        final area = (pi * r) * r;
        final circumference = (2.0 * pi) * r;
        print('r=$radius area=${area.toStringAsFixed(3)} '
            'circumference=${circumference.toStringAsFixed(3)}');
    }
}
