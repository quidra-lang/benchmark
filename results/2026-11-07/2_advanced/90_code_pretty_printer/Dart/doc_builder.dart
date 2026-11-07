part of 'main.dart';

class Doc {
  final String kind, text, other;
  final int number;
  final List<Doc> children;
  final bool forced;
  String mode = '';
  Doc(
    this.kind, {
    this.text = '',
    this.other = '',
    this.number = 0,
    List<Doc>? children,
    this.forced = false,
  }) : children = children ?? [];
}

Doc text(String s) => Doc('text', text: s);
Doc marker(String kind) => Doc(kind);
Doc cat(List<Doc> docs) {
  final out = <Doc>[];
  void add(Doc d) {
    if (d.kind == 'concat') {
      for (final child in d.children) {
        add(child);
      }
      return;
    }
    if (d.kind == 'text') {
      if (d.text.isEmpty) return;
      if (out.isNotEmpty && out.last.kind == 'text') {
        out[out.length - 1] = text(out.last.text + d.text);
        return;
      }
    }
    out.add(d);
  }

  for (final d in docs) {
    add(d);
  }
  return out.isEmpty
      ? text('')
      : out.length == 1
      ? out.first
      : Doc('concat', children: out);
}

bool forceBroken(Doc d) =>
    d.kind == 'hardline' ||
    d.kind == 'break_parent' ||
    d.children.any(forceBroken);
Doc group(List<Doc> docs) {
  final child = cat(docs);
  return Doc('group', children: [child], forced: forceBroken(child));
}

Doc nest(int n, List<Doc> docs) =>
    Doc('nest', number: n, children: [cat(docs)]);
Doc align(List<Doc> docs) => Doc('align', children: [cat(docs)]);
Doc suffix(String s) => Doc('suffix', text: s);
Doc ifBreak(String a, String b) => Doc('if_break', text: a, other: b);
(int, int, int) groupMetrics(Doc d) {
  var groups = 0, broken = 0, forced = 0;
  if (d.kind == 'group') {
    groups++;
    if (d.mode == 'break' || d.mode == 'forced') broken++;
    if (d.mode == 'forced') forced++;
  }
  for (final child in d.children) {
    final (g, b, f) = groupMetrics(child);
    groups += g;
    broken += b;
    forced += f;
  }
  return (groups, broken, forced);
}
