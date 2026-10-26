class Minstd {
  int state;
  Minstd(this.state);
  int draw() {
    state = 48271 * state % 2147483647;
    return state;
  }
  int below(int limit) => draw() % limit;
  void shuffle<T>(List<T> items) {
    for (var index = items.length - 1; index > 0; index--) {
      final other = below(index + 1), saved = items[index];
      items[index] = items[other];
      items[other] = saved;
    }
  }
}
