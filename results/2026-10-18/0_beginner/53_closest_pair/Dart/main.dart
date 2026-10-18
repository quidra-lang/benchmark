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
  const p=[(12,-7),(-33,25),(41,18),(-8,-44),(27,39),(-46,-12),(5,14),(36,-29),(-19,47),(-2,3)];
  var nearest=1<<60,farthest=-1;var nearPair=(0,0),farPair=(0,0);
  for(var i=0;i<p.length;i++) {for(var j=i+1;j<p.length;j++) {final dx=p[i].$1-p[j].$1,dy=p[i].$2-p[j].$2,d=dx*dx+dy*dy;if(d<nearest) {nearest=d;nearPair=(i,j);}if(d>farthest) {farthest=d;farPair=(i,j);}}}
  out.writeln('closest: P${nearPair.$1} P${nearPair.$2} ${fixed(math.sqrt(nearest),4)}');out.writeln('farthest: P${farPair.$1} P${farPair.$2} ${fixed(math.sqrt(farthest),4)}');
  stdout.write(out);
}
