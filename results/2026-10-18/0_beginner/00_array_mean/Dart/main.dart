void main() {
    const values = [48, 73, 56, 91, 35, 62, 84];
    final mean = values.reduce((a, b) => a + b) / values.length;
    print(mean.toStringAsFixed(2));
}
