part of 'main.dart';

class Huffman {
  final List<int> bits, values;
  final List<int> length = List.filled(256, 0), code = List.filled(256, 0);
  Huffman(this.bits, this.values) {
    var n = 0, k = 0;
    for (var l = 1; l <= 16; l++) {
      for (var i = 0; i < bits[l]; i++) {
        final v = values[k++];
        length[v] = l;
        code[v] = n++;
      }
      n *= 2;
    }
  }
}

int category(int a) {
  a = a.abs();
  var n = 0;
  while (a > 0) {
    n++;
    a >>= 1;
  }
  return n;
}

int extra(int a) => a < 0 ? a + (1 << category(a)) - 1 : a;
int decodedExtra(int w, int n) => n == 0
    ? 0
    : w < 1 << (n - 1)
    ? w - (1 << n) + 1
    : w;
Huffman optimized(List<int> count) {
  final freq = [...count, 1],
      size = List.filled(257, 0),
      next = List.filled(257, -1);
  while (true) {
    var a = -1, b = -1;
    for (var v = 0; v <= 256; v++) {
      if (freq[v] > 0 && (a < 0 || freq[v] <= freq[a])) a = v;
    }
    for (var v = 0; v <= 256; v++) {
      if (v != a && freq[v] > 0 && (b < 0 || freq[v] <= freq[b])) b = v;
    }
    if (b < 0) break;
    freq[a] += freq[b];
    freq[b] = 0;
    size[a]++;
    while (next[a] >= 0) {
      a = next[a];
      size[a]++;
    }
    next[a] = b;
    size[b]++;
    while (next[b] >= 0) {
      b = next[b];
      size[b]++;
    }
  }
  final lengths = List.filled(258, 0);
  var longest = 0;
  for (final n in size) {
    if (n > 0) {
      lengths[n]++;
      longest = max(longest, n);
    }
  }
  for (var l = longest; l >= 17; l--) {
    while (lengths[l] > 0) {
      var j = l - 2;
      while (lengths[j] == 0) {
        j--;
      }
      lengths[l] -= 2;
      lengths[l - 1]++;
      lengths[j + 1] += 2;
      lengths[j]--;
    }
  }
  for (var l = 16; l >= 1; l--) {
    if (lengths[l] > 0) {
      lengths[l]--;
      break;
    }
  }
  final values = [
    for (var v = 0; v < 256; v++)
      if (size[v] > 0) v,
  ];
  values.sort((a, b) {
    final c = size[a].compareTo(size[b]);
    return c != 0 ? c : a.compareTo(b);
  });
  return Huffman(lengths.sublist(0, 17), values);
}
