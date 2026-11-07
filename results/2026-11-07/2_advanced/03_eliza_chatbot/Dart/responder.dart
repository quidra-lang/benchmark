import 'script_loader.dart';

List<String> reflect(List<String> words, Map<String, Substitution> replacements) => words.expand((word) => replacements[word]?.replacement ?? [word]).toList();
List<String> binding(List<List<String>> bindings, int number) => number > 0 && number <= bindings.length ? bindings[number - 1] : [];

String buildReply(String template, List<List<String>> bindings, Map<String, Substitution> replacements) {
  final text = StringBuffer();
  var index = 0;
  while (index < template.length) {
    final number = index + 3 <= template.length ? reference(template.substring(index, index + 3)) : null;
    if (number != null) { text.write(reflect(binding(bindings, number), replacements).join(' ')); index += 3; }
    else text.write(template[index++]);
  }
  final reply = text.toString().split(' ').where((word) => word.isNotEmpty).join(' ');
  return reply.isEmpty ? reply : reply[0].toUpperCase() + reply.substring(1);
}

List<String> restate(List<String> arguments, List<List<String>> bindings) => arguments.expand((word) {
  final number = reference(word);
  return number == null ? [word] : binding(bindings, number);
}).toList();

List<String> wrapReply(String text) {
  final words = text.split(' ').where((word) => word.isNotEmpty).toList();
  if (words.isEmpty) return ['ELIZA:'];
  final lines = ['ELIZA: ${words.first}'];
  for (final word in words.skip(1)) {
    if (lines.last.length + word.length + 1 <= 72) lines[lines.length - 1] += ' $word';
    else lines.add('       $word');
  }
  return lines;
}
