import 'dart:io';


void main() {
  final out = StringBuffer();
  const a=[[3,-2,5,1],[-4,7,0,6],[2,9,-8,-3]];
  const b=[[1,4],[-5,2],[6,-1],[0,7]];
  for(final row in a) {
    for(var j=0;j<2;j++) {var value=0;for(var k=0;k<4;k++) value+=row[k]*b[k][j];out.write(value.toString().padLeft(5));}
    out.writeln();
  }
  stdout.write(out);
}
