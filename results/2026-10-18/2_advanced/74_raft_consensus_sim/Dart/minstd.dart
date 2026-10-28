part of 'main.dart';

class Generator {
  int state, draws = 0;
  Generator(this.state);
  int between(int lo, int hi) {
    state = state * 48271 % 2147483647;
    draws++;
    return lo + state % (hi - lo + 1);
  }
}
