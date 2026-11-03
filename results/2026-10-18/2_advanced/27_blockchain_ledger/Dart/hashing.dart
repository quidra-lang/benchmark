String digest(String text) {
  final result = StringBuffer();
  for (final lane in [
    (1000003, 11),
    (1500007, 23),
    (2750159, 37),
    (4194301, 53),
  ]) {
    var value = lane.$2;
    for (final code in text.codeUnits) {
      value = (value * lane.$1 + code) % 2147483647;
    }
    for (final extra in [text.length, 0, 0]) {
      value = (value * lane.$1 + extra) % 2147483647;
    }
    result.write(value.toRadixString(16).padLeft(8, '0'));
  }
  return result.toString();
}

String merkleRoot(Iterable<String> hashes) {
  var level = hashes.toList();
  while (level.length > 1) {
    if (level.length.isOdd) level.add(level.last);
    level = [
      for (var i = 0; i < level.length; i += 2) digest(level[i] + level[i + 1]),
    ];
  }
  return level.single;
}

String short(String value) => value.substring(0, 8);
