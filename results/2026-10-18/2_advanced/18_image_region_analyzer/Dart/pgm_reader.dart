import 'dart:io';

class Image {
  final String name;
  final int width;
  final int height;
  final int maxval;
  final List<List<int>> pixels;
  Image(this.name, this.width, this.height, this.maxval, this.pixels);
}

String readText(String path) => File(path).readAsStringSync();

List<Image> readImages(String path) {
  final words = <String>[];
  for (final line in readText(path).split('\n')) {
    words.addAll(line.split('#').first.split(' ').where((word) => word.isNotEmpty));
  }
  final images = <Image>[];
  var position = 0;
  while (position < words.length) {
    final name = words[position + 1];
    final width = int.parse(words[position + 3]);
    final height = int.parse(words[position + 4]);
    final maxval = int.parse(words[position + 5]);
    position += 6;
    final pixels = List.generate(height, (_) => List.generate(width, (_) => int.parse(words[position++])));
    images.add(Image(name, width, height, maxval, pixels));
  }
  return images;
}
