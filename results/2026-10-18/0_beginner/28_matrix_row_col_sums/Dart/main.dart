import 'dart:io';


void main() {
  final out = StringBuffer();
  const matrix=[[125,340,78,912,456],[603,27,819,150,384],[0,765,231,498,62],[947,113,586,39,720]];
  final columns=List.filled(5,0);var total=0;
  for(final row in matrix) {
    var sum=0;
    for(var j=0;j<5;j++) {final v=row[j];sum+=v;columns[j]+=v;out.write(v.toString().padLeft(6));}
    total+=sum;out.writeln(sum.toString().padLeft(6));
  }
  for(final v in columns) out.write(v.toString().padLeft(6));
  out.writeln(total.toString().padLeft(6));
  stdout.write(out);
}
