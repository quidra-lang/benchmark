import 'slots.dart';
import 'word_index.dart';

class GridState {
  final List<int> letters;
  final List<int> words;
  final List<bool> used;
  GridState(List<int> initial, int count, int wordCount) : letters = [...initial], words = List.filled(count, -1), used = List.filled(wordCount, false);
  GridState._(this.letters, this.words, this.used);
  GridState copy() => GridState._([...letters], [...words], [...used]);
  List<int> pattern(Slot slot) => [for (final cell in slot.cells) letters[cell]];

  List<int> assign(Slot slot, int id, WordIndex index) {
    final changed = <int>[];
    for (var i = 0; i < slot.length; i++) {
      final cell = slot.cells[i];
      if (letters[cell] == 46) {
        letters[cell] = index.words[id].letters[i];
        changed.add(cell);
      }
    }
    words[slot.index] = id;
    used[id] = true;
    return changed;
  }

  void unassign(Slot slot, List<int> changed) {
    for (final cell in changed) {
      letters[cell] = 46;
    }
    used[words[slot.index]] = false;
    words[slot.index] = -1;
  }
}

class Attempt {
  final Layout layout;
  final WordIndex index;
  final GridState state;
  GridState best;
  final int minimum;
  final int budget;
  var nodes = 0, backtracks = 0, prunes = 0, deadEnds = 0, maxDepth = 0;
  final sequence = <int>[];
  final List<int> failures;
  final trace = <String>[];
  var outcome = '';
  Attempt(this.layout, this.index, GridState initial, this.minimum, this.budget) : state = initial.copy(), best = initial.copy(), failures = List.filled(layout.slots.length, 0);
  void run() {
    outcome = switch (search()) {'complete' => 'filled', 'abort' => 'budget', _ => 'unfillable'};
  }
  GridState get finalState => outcome == 'filled' ? state : best;
  List<int> candidates(Slot slot) => index.candidates(state.pattern(slot), minimum, state.used);

  String search() {
    var chosen = -1;
    var choices = <int>[];
    for (final slot in layout.slots) {
      if (state.words[slot.index] >= 0) {
        continue;
      }
      final available = candidates(slot);
      if (chosen < 0 || available.length < choices.length) {
        chosen = slot.index;
        choices = available;
      }
    }
    if (chosen < 0) {
      return 'complete';
    }
    if (choices.isEmpty) {
      deadEnds++;
      failures[chosen]++;
      return 'fail';
    }
    final slot = layout.slots[chosen];
    for (final word in choices) {
      if (nodes == budget) {
        return 'abort';
      }
      nodes++;
      final changed = state.assign(slot, word, index);
      sequence.add(chosen);
      var wiped = -1;
      for (final other in slot.crossings) {
        if (state.words[other] < 0 && candidates(layout.slots[other]).isEmpty) {
          wiped = other;
          break;
        }
      }
      if (nodes <= 10) {
        trace.add('${slot.label}=${index.words[word].text}${wiped >= 0 ? '!' : ''}');
      }
      var result = 'fail';
      if (wiped >= 0) {
        prunes++;
        failures[wiped]++;
      } else {
        if (sequence.length > maxDepth) {
          maxDepth = sequence.length;
          best = state.copy();
        }
        result = search();
      }
      if (result != 'fail') {
        return result;
      }
      state.unassign(slot, changed);
      sequence.removeLast();
      backtracks++;
    }
    return 'fail';
  }
}
