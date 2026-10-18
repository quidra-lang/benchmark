import 'dart:io';


void main() {
  final out = StringBuffer();
  const pairs=[(1000,'M'),(900,'CM'),(500,'D'),(400,'CD'),(100,'C'),(90,'XC'),(50,'L'),(40,'XL'),(10,'X'),(9,'IX'),(5,'V'),(4,'IV'),(1,'I')];
  const values={'I':1,'V':5,'X':10,'L':50,'C':100,'D':500,'M':1000};
  for(final n in [9,14,49,94,444,1994,2768,3999]) {
    var remaining=n;final buffer=StringBuffer();for(final p in pairs) {while(remaining>=p.$1) {buffer.write(p.$2);remaining-=p.$1;}}
    final roman=buffer.toString();var decoded=0;for(var i=0;i<roman.length;i++) {final v=values[roman[i]]!;decoded+=i+1<roman.length && v<values[roman[i+1]]! ? -v:v;}
    out.writeln('$n -> $roman -> $decoded');
  }
  stdout.write(out);
}
