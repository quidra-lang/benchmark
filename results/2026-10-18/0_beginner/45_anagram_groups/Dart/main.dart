import 'dart:io';


void main() {
  final out = StringBuffer();
  const words=['listen','stone','night','silent','notes','apple','thing','enlist','earth','onset','heart','tones'];
  final groups=<String,List<String>>{};
  for(final word in words) {final chars=word.split('')..sort();final key=chars.join();groups.putIfAbsent(key,()=>[]).add(word);}
  for(final group in groups.values) out.writeln(group.join(' '));
  stdout.write(out);
}
