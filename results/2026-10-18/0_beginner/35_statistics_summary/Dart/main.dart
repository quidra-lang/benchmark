import 'dart:io';
import 'dart:math' as math;

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
  const values=[72,85,64,90,85,58,77,85,69,93,71];
  final sorted=values.toList()..sort();final mean=values.reduce((a,b)=>a+b)/values.length;
  var squares=0.0;for(final v in values) {final d=v-mean;squares+=d*d;}
  var mode=sorted.first,best=0;
  for(final v in sorted) {final count=values.where((x)=>x==v).length;if(count>best) {best=count;mode=v;}}
  out.writeln('mean: ${fixed(mean,3)}\nmedian: ${sorted[values.length~/2]}\nmode: $mode\nrange: ${sorted.last-sorted.first}\nstdev: ${fixed(math.sqrt(squares/values.length),3)}');
  stdout.write(out);
}
