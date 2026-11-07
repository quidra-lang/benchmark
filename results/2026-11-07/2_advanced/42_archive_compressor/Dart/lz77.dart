part of 'main.dart';

class Token {
  final int literal, distance, length;
  Token.literal(this.literal) : distance = 0, length = 0;
  Token.match(this.distance, this.length) : literal = 0;
}

List<Token> tokenize(List<int> data, int b, int k) {
  final window = 1 << b,
      lookahead = (1 << k) + 2,
      prefixes = <int, List<int>>{},
      tokens = <Token>[];
  var position = 0;
  int prefix(int i) => (data[i] << 16) | (data[i + 1] << 8) | data[i + 2];
  while (position < data.length) {
    var distance = 0, longest = 0;
    final limit = math.min(lookahead, data.length - position);
    if (limit >= 3) {
      final candidates = prefixes[prefix(position)] ?? <int>[];
      for (var j = candidates.length - 1; j >= 0; j--) {
        final start = candidates[j];
        if (start < position - window) break;
        final d = position - start;
        var length = 3;
        while (length < limit &&
            data[position + length] == data[position + length - d]) {
          length++;
        }
        if (length > longest) {
          distance = d;
          longest = length;
        }
        if (longest == limit) break;
      }
    }
    var consumed = 1;
    if (longest >= 3) {
      tokens.add(Token.match(distance, longest));
      consumed = longest;
    } else {
      tokens.add(Token.literal(data[position]));
    }
    for (
      var start = position;
      start < math.min(position + consumed, data.length - 2);
      start++
    ) {
      prefixes.putIfAbsent(prefix(start), () => []).add(start);
    }
    position += consumed;
  }
  return tokens;
}

void copyMatch(List<int> out, int d, int length, int n) {
  if (d > out.length) throw DecodeError('bad_offset', out.length);
  if (out.length + length > n) throw DecodeError('overrun', out.length);
  for (var i = 0; i < length; i++) {
    out.add(out[out.length - d]);
  }
}
