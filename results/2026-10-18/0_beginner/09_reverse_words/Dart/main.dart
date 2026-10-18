import 'dart:io';

void main() {
  const sentence = 'every program starts with a single line';
  final charactersReversed = sentence.split('').reversed.join();
  final wordsReversed = sentence.split(' ').reversed.join(' ');
  stdout.write('$charactersReversed\n$wordsReversed\n');
}
