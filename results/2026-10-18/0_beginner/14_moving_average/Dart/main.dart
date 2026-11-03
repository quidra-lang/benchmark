void main() {
  const sales = [120, 135, 98, 143, 160, 152, 171, 149, 188, 176];
  for (var i = 2; i < sales.length; i++) {
    final average = (sales[i - 2] + sales[i - 1] + sales[i]) / 3;
    print('day ${i + 1}: ${average.toStringAsFixed(2)}');
  }
}
