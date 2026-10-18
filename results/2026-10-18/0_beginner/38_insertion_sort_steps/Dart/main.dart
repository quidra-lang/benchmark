import 'dart:io';


void main() {
  final out = StringBuffer();
  final a=[52,17,38,9,61,38,24,45];var total=0;
  for(var i=1;i<8;i++) {final v=a[i];var j=i,shifts=0;
    while(j>0 && a[j-1]>v) {a[j]=a[j-1];j--;shifts++;}a[j]=v;total+=shifts;
    out.writeln('i=$i shifts=$shifts: ${a.join(' ')}');
  }
  out.writeln('total shifts: $total');
  stdout.write(out);
}
