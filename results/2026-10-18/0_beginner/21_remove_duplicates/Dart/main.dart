void main() {
  const values = [12, 5, 12, 8, 3, 5, 20, 8, 8, 15, 3, 7, 20, 12, 9];
  final unique = {...values};
  print(unique.join(' '));
  print('removed: ${values.length - unique.length}');
}
