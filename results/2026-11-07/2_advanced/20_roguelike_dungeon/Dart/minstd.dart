class Minstd {
  int state;
  Minstd(this.state);
  int draw() {
    state = (48271 * state) % 2147483647;
    return state;
  }
  int rnd(int n) => draw() % n;
  int roll(int count, int sides) {
    var total = 0;
    for (var i = 0; i < count; i++) {
      total += 1 + rnd(sides);
    }
    return total;
  }
  int select(List<int> weights) {
    final q = rnd(weights.fold(0, (sum, weight) => sum + weight));
    var total = 0;
    for (var i = 0; i < weights.length; i++) {
      total += weights[i];
      if (q < total) {
        return i;
      }
    }
    throw StateError('Empty weights');
  }
}
