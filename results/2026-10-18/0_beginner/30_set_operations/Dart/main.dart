import 'dart:io';


void main() {
  final out = StringBuffer();
  final a={12,5,8,21,5,17,3,12,9}, b={8,14,21,6,14,3,25,6};
  final sets=[a.union(b),a.intersection(b),a.difference(b),a.difference(b).union(b.difference(a))];
  const labels=['union','intersection','difference','symmetric difference'];
  for(var i=0;i<4;i++) {final values=sets[i].toList()..sort();out.writeln('${labels[i]}: ${values.join(' ')}');}
  stdout.write(out);
}
