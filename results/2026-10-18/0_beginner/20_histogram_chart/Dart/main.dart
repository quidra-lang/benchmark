import 'dart:io';


void main() {
  final out = StringBuffer();
  const names=['Mon','Tue','Wed','Thu','Fri','Sat','Sun'];
  const counts=[7,12,4,15,9,18,11];
  for(var i=0;i<names.length;i++) out.writeln('${names[i]} | ${'*'*counts[i]} ${counts[i]}');
  stdout.write(out);
}
