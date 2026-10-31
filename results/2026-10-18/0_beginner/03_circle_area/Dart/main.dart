void main() {
  const radii = [3, 7, 12, 25, 41];
  const pi = 3.141592653589793;
  for (final radius in radii) {
    final area = pi * radius * radius;
    final circumference = 2 * pi * radius;
    print(
      'r=$radius area=${area.toStringAsFixed(3)} '
      'circumference=${circumference.toStringAsFixed(3)}',
    );
  }
}
