import 'scoring.dart';

int modulo(int number, [int modulus = 26]) =>
    (number % modulus + modulus) % modulus;

int inverse(int a) {
  for (var i = 1; i < 26; i++) {
    if (a * i % 26 == 1) return i;
  }
  throw StateError('Noninvertible affine key');
}

String applySubstitution(String text, String cipher, String key, bool encrypt) {
  var a = 1;
  var b = 0;
  if (cipher == 'caesar') b = int.parse(key);
  if (cipher == 'affine') {
    final pair = key.split(',');
    a = int.parse(pair[0]);
    b = int.parse(pair[1]);
  }
  final inv = cipher == 'affine' ? inverse(a) : 1;
  final plaintext = <int>[];
  final output = StringBuffer();
  var letterIndex = 0;
  for (var i = 0; i < text.length; i++) {
    final char = text[i];
    if (!isLetter(char)) {
      output.write(char);
      continue;
    }
    final x = letterValue(char);
    var shift = 0;
    if (cipher == 'vigenere') {
      shift = letterValue(key[letterIndex % key.length]);
    } else if (cipher == 'autokey') {
      shift = letterIndex < key.length ? letterValue(key[letterIndex])
          : plaintext[letterIndex - key.length];
    }
    final y = switch (cipher) {
      'caesar' => modulo(x + (encrypt ? b : -b)),
      'affine' => encrypt ? modulo(a * x + b) : modulo(inv * (x - b)),
      'vigenere' || 'autokey' => modulo(x + (encrypt ? shift : -shift)),
      _ => throw StateError('Unknown substitution cipher'),
    };
    plaintext.add(encrypt ? x : y);
    final base = char.codeUnitAt(0) >= 97 ? 97 : 65;
    output.writeCharCode(base + y);
    letterIndex++;
  }
  return output.toString();
}
