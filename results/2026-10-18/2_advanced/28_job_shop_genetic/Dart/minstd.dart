class Minstd {
  int state;
  Minstd(this.state);
  int draw() {
    state = 48271 * state % 2147483647;
    return state;
  }

  int below(int limit) => draw() % limit;
  bool chance((int, int) fraction) => draw() % fraction.$2 < fraction.$1;
  void shuffle(List<int> items) {
    for (var size = items.length; size > 1; size--) {
      final j = below(size), saved = items[size - 1];
      items[size - 1] = items[j];
      items[j] = saved;
    }
  }
}
