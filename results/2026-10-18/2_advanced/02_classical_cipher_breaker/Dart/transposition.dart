import 'dart:math';

int railNumber(int position, int rails) {
  final cycle = 2 * rails - 2;
  final offset = position % cycle;
  return min(offset, cycle - offset);
}

String railFence(String text, int rails, bool encrypt) {
  final order = List.generate(text.length, (i) => i);
  order.sort((a, b) {
    final result = railNumber(a, rails).compareTo(railNumber(b, rails));
    return result != 0 ? result : a.compareTo(b);
  });
  final output = List.filled(text.length, '');
  for (var i = 0; i < order.length; i++) {
    if (encrypt) {
      output[i] = text[order[i]];
    } else {
      output[order[i]] = text[i];
    }
  }
  return output.join();
}

List<int> columnOrder(String key) {
  final order = List.generate(key.length, (i) => i);
  order.sort((a, b) {
    final result = key[a].compareTo(key[b]);
    return result != 0 ? result : a.compareTo(b);
  });
  return order;
}

String rankString(String key) {
  final rank = List.filled(key.length, '');
  final order = columnOrder(key);
  for (var i = 0; i < order.length; i++) {
    rank[order[i]] = String.fromCharCode(49 + i);
  }
  return rank.join();
}

String columnar(String text, String key, bool encrypt) {
  final output = List.filled(text.length, '');
  var pointer = 0;
  for (final column in columnOrder(key)) {
    for (var index = column; index < text.length; index += key.length) {
      if (encrypt) {
        output[pointer++] = text[index];
      } else {
        output[index] = text[pointer++];
      }
    }
  }
  return output.join();
}
