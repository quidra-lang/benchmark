import 'dart:io';

String fixed(double value, int places) {
  var scale = 1;
  for (var i = 0; i < places; i++) scale *= 10;
  final scaled = (value.abs() * scale + 0.5).floor();
  final sign = value < 0 ? '-' : '';
  if (places == 0) return '$sign$scaled';
  return '$sign${scaled ~/ scale}.${(scaled % scale).toString().padLeft(places, '0')}';
}


void main() {
  final out = StringBuffer();
  final words='we planted beans and carrots in the garden behind our old house'.split(' ');
  var longest=words.first, shortest=words.first, total=0;
  for(final word in words) {
    if(word.length>longest.length) longest=word;
    if(word.length<shortest.length) shortest=word;
    total+=word.length;
  }
  out.writeln('words: ${words.length}\nlongest: $longest\nshortest: $shortest\naverage length: ${fixed(total/words.length,2)}');
  stdout.write(out);
}
