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
  for(final s in [[1,-3,-10],[-2,5,4],[3,1,-2],[4,-12,9],[1,2,5],[-2,3,-4]]) {
    final a=s[0],b=s[1],c=s[2],disc=s[1]*s[1]-4*s[0]*s[2];final numerator=-b.toDouble(),denominator=2.0*a;
    out.write('$a $b $c: ');
    if(disc>0) {final r1=(numerator+math.sqrt(disc))/denominator,r2=(numerator-math.sqrt(disc))/denominator;out.write('x1 = ${fixed(math.max(r1,r2),4)}, x2 = ${fixed(math.min(r1,r2),4)}');}
    else if(disc==0) {out.write('x = ${fixed(numerator/denominator,4)}');}
    else {final p=numerator/denominator,q=math.sqrt(-disc)/(2*a.abs());out.write('x = ${fixed(p,4)} + ${fixed(q,4)}i, ${fixed(p,4)} - ${fixed(q,4)}i');}
    out.writeln();
  }
  stdout.write(out);
}
