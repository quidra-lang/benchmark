import 'dart:io';


void main() {
  final out = StringBuffer();
  const a=[3,8,11,15,19,24,27,31,36,42,47,53,58,64,70,77];
  for(final target in [42,3,77,31,50,1]) {
    var lo=0,hi=15;int? found;out.write('$target: probes');
    while(lo<=hi) {final mid=(lo+hi)~/2;out.write(' $mid');if(a[mid]==target) {found=mid;break;}else if(a[mid]<target) {lo=mid+1;}else {hi=mid-1;}}
    out.writeln(found==null?' -> not found':' -> index $found');
  }
  stdout.write(out);
}
