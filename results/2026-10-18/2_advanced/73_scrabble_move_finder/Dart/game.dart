part of 'main.dart';

class Generator {
  int state;
  Generator(this.state);
  int next() {
    state = 48271 * state % 2147483647;
    return state;
  }

  void shuffle(List<String> bag) {
    for (var i = bag.length - 1; i >= 1; i--) {
      final j = next() % (i + 1), temporary = bag[i];
      bag[i] = bag[j];
      bag[j] = temporary;
    }
  }
}

List<String> newBag(Tiles tiles, Generator g) {
  final bag = <String>[];
  for (var i = 0; i < 27; i++) {
    final letter = i == 26 ? '?' : String.fromCharCode(65 + i);
    for (var k = 0; k < tiles.count[i]; k++) {
      bag.add(letter);
    }
  }
  g.shuffle(bag);
  return bag;
}

String draw(List<String> bag, int k) {
  final drawn = StringBuffer();
  for (var i = 0; i < k && bag.isNotEmpty; i++) {
    drawn.write(bag.removeLast());
  }
  return drawn.toString();
}

String exchange(List<String> bag, String putBack, Generator g) {
  final drawn = draw(bag, putBack.length), letters = putBack.split('')..sort();
  bag.addAll(letters);
  g.shuffle(bag);
  return drawn;
}

int collectionValue(String collection, Tiles tiles) {
  var value = 0;
  for (var i = 0; i < collection.length; i++) {
    value += tiles.value[tileIndex(collection[i])];
  }
  return value;
}
