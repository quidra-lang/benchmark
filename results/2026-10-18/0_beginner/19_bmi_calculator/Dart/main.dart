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
  for (final p in [('Aiko',158,45),('Kenji',172,68),('Mika',165,70),('Ryo',180,101),('Yuki',150,52)]) {
    final bmi=(p.$3*10000)/(p.$2*p.$2);
    final category=bmi<18.5?'underweight':bmi<25?'normal':bmi<30?'overweight':'obese';
    out.writeln('${p.$1}: BMI ${fixed(bmi,1)} ($category)');
  }
  stdout.write(out);
}
