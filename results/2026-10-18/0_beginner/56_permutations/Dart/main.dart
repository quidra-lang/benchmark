import 'dart:io';


void main() {
  final out = StringBuffer();
  final used=List.filled(4,false),word=List.filled(4,'');var count=0;
  void permutations(int depth) {if(depth==4) {count++;out.writeln('$count: ${word.join()}');return;}
    for(var i=0;i<4;i++) {if(!used[i]) {used[i]=true;word[depth]='ABCD'[i];permutations(depth+1);used[i]=false;}}
  }
  permutations(0);
  stdout.write(out);
}
