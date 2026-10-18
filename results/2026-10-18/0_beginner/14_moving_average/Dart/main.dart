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
  const sales = [120,135,98,143,160,152,171,149,188,176];
  for (var i = 2; i < sales.length; i++) {
    final average = (sales[i-2]+sales[i-1]+sales[i]) / 3;
    out.writeln('day ${i+1}: ${fixed(average,2)}');
  }
  stdout.write(out);
}
