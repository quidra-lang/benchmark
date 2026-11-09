class Minstd {
  int state;
  Minstd(this.state);
  int draw() => state = 48271 * state % 2147483647;
}
int selectWeighted(List<int> weights, int value) {
  var sum = 0; for (final weight in weights) { sum += weight; } final remainder = value % sum; var total = 0;
  for (var j = 0; j < weights.length; j++) { total += weights[j]; if (remainder < total) return j; } throw StateError('weights');
}
