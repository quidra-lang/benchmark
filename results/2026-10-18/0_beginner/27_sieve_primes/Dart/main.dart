import 'dart:io';
import 'dart:math' as math;


void main() {
  final out = StringBuffer();
  final prime=List.filled(201,true); prime[0]=false;prime[1]=false;
  for(var p=2;p<=200;p++) {if(prime[p]) {for(var m=2*p;m<=200;m+=p) prime[m]=false;}}
  final values=[for(var p=2;p<=200;p++) if(prime[p]) p];
  out.writeln('count: ${values.length}');
  for(var i=0;i<values.length;i+=10) out.writeln(values.sublist(i,math.min(i+10,values.length)).join(' '));
  stdout.write(out);
}
