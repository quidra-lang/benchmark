void main() {
  const sales = [120, 135, 98, 143, 160, 152, 171, 149, 188, 176];
  const windowSize = 3;
  for (var i = windowSize - 1; i < sales.length; i++) {
    final average = (sales[i - windowSize + 1] + sales[i - 1] + sales[i]) / windowSize;
    print('day ${i + 1}: ${average.toStringAsFixed(2)}');
  }
}
