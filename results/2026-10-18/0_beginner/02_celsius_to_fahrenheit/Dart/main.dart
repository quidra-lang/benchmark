void main() {
    const temperatures = [-40, -15, -3, 0, 22, 37, 100];
    for (final celsius in temperatures) {
        final fahrenheit = celsius * 9 / 5 + 32;
        print('$celsius C = ${fahrenheit.toStringAsFixed(1)} F');
    }
}
