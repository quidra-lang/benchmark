void main() {
  const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  const counts = [7, 12, 4, 15, 9, 18, 11];
  for (var i = 0; i < names.length; i++) {
    final count = counts[i];
    print('${names[i]} | ${'*' * count} $count');
  }
}
