void main() {
  for (final n in [0, 10, 255, 1000, 43981, 65535]) {
    print(
      '$n: bin=${n.toRadixString(2)} oct=${n.toRadixString(8)} hex=${n.toRadixString(16).toUpperCase()}',
    );
  }
}
