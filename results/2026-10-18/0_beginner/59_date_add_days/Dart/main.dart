import 'dart:io';


void main() {
  final out = StringBuffer();
  const lengths=[31,28,31,30,31,30,31,31,30,31,30,31];String date(int y,int m,int d)=>'${y.toString().padLeft(4,'0')}-${m.toString().padLeft(2,'0')}-${d.toString().padLeft(2,'0')}';
  for(final c in [[1999,12,25,10],[2000,2,27,3],[2021,2,20,14],[2023,11,15,120],[2026,10,17,1500]]) {var y=c[0],m=c[1],d=c[2];
    for(var i=0;i<c[3];i++) {var days=lengths[m-1];if(m==2 && y%4==0 && (y%100!=0||y%400==0))days=29;d++;if(d>days) {d=1;m++;if(m>12){m=1;y++;}}}
    out.writeln('${date(c[0],c[1],c[2])} + ${c[3]} days = ${date(y,m,d)}');
  }
  stdout.write(out);
}
