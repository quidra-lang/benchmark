part of 'main.dart';

class Correction {
  final List<int> words, syndromes;
  final List<int> positions = [];
  bool ok = false;
  Correction(this.words, this.syndromes);
}

class Field {
  final exp = List.filled(255, 0), log = List.filled(256, 0);
  Field() {
    var value = 1;
    for (var i = 0; i < 255; i++) {
      exp[i] = value;
      log[value] = i;
      value <<= 1;
      if (value >= 256) value ^= 285;
    }
  }
  int power(int e) => exp[e % 255];
  int multiply(int a, int b) => a == 0 || b == 0 ? 0 : power(log[a] + log[b]);
  int divide(int a, int b) => a == 0 ? 0 : power(log[a] - log[b]);
  List<int> encode(List<int> data, int e) {
    var g = [1];
    for (var i = 0; i < e; i++) {
      final next = List.filled(g.length + 1, 0);
      for (var j = 0; j < g.length; j++) {
        next[j] ^= g[j];
        next[j + 1] ^= multiply(g[j], power(i));
      }
      g = next;
    }
    final out = [...data, ...List.filled(e, 0)];
    for (var i = 0; i < data.length; i++) {
      final factor = out[i];
      for (var j = 0; j < g.length; j++) {
        out[i + j] ^= multiply(factor, g[j]);
      }
    }
    return out.sublist(data.length);
  }

  List<int> syndromes(List<int> words, int e) {
    final out = List.filled(e, 0);
    for (var j = 0; j < e; j++) {
      for (final w in words) {
        out[j] = multiply(out[j], power(j)) ^ w;
      }
    }
    return out;
  }

  int polynomial(List<int> a, int x) {
    var value = 0;
    for (var i = a.length - 1; i >= 0; i--) {
      value = multiply(value, x) ^ a[i];
    }
    return value;
  }

  Correction correct(List<int> received, int e) {
    final s = syndromes(received, e), out = Correction(List.of(received), s);
    if (!nonzero(s)) {
      out.ok = true;
      return out;
    }
    var lambda = List.filled(e + 1, 0),
        b = List.filled(e + 1, 0),
        degree = 0,
        p = 1,
        beta = 1;
    lambda[0] = 1;
    b[0] = 1;
    for (var q = 0; q < e; q++) {
      var delta = s[q];
      for (var h = 1; h <= degree; h++) {
        delta ^= multiply(lambda[h], s[q - h]);
      }
      if (delta == 0) {
        p++;
        continue;
      }
      final old = List<int>.of(lambda), factor = divide(delta, beta);
      for (var h = 0; h + p <= e; h++) {
        lambda[h + p] ^= multiply(factor, b[h]);
      }
      if (2 * degree <= q) {
        degree = q + 1 - degree;
        b = old;
        beta = delta;
        p = 1;
      } else {
        p++;
      }
    }
    if (degree > e ~/ 2) return out;
    final positions = <int>[];
    for (var i = 0; i < received.length; i++) {
      final z = power(-(received.length - 1 - i));
      if (polynomial(lambda, z) == 0) positions.add(i);
    }
    if (positions.length != degree) return out;
    final omega = List.filled(e, 0);
    for (var i = 0; i < s.length; i++) {
      for (var h = 0; h < lambda.length; h++) {
        if (i + h < e) omega[i + h] ^= multiply(s[i], lambda[h]);
      }
    }
    final derivative = List.filled(e, 0);
    for (var h = 1; h < lambda.length; h += 2) {
      derivative[h - 1] = lambda[h];
    }
    for (final i in positions) {
      final x = power(received.length - 1 - i),
          z = power(-(received.length - 1 - i)),
          denominator = polynomial(derivative, z);
      if (denominator == 0) return out;
      out.words[i] ^= divide(multiply(x, polynomial(omega, z)), denominator);
    }
    if (nonzero(syndromes(out.words, e))) return out;
    for (var i = 0; i < received.length; i++) {
      if (out.words[i] != received[i]) out.positions.add(i);
    }
    out.ok = true;
    return out;
  }
}

bool nonzero(List<int> a) => a.any((v) => v != 0);
