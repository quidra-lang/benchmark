part of 'main.dart';

List<String> docTree(Doc d, int depth) {
  final prefix = repeated(' ', 2 * depth), out = <String>[];
  switch (d.kind) {
    case 'text':
    case 'suffix':
      out.add('$prefix${d.kind} "${d.text}"');
      break;
    case 'if_break':
      out.add('${prefix}if_break "${d.text}" "${d.other}"');
      break;
    case 'line':
    case 'softline':
    case 'hardline':
    case 'break_parent':
      out.add('$prefix${d.kind}');
      break;
    case 'concat':
      for (final child in d.children) {
        out.addAll(docTree(child, depth));
      }
      break;
    case 'group':
    case 'nest':
    case 'align':
      var label = d.kind;
      if (d.kind == 'group') label += ' ${d.mode}';
      if (d.kind == 'nest') label += ' ${d.number}';
      out.add('$prefix$label');
      out.addAll(docTree(d.children.first, depth + 1));
      break;
  }
  return out;
}

class DiffOp {
  final bool delete;
  final String line;
  DiffOp(this.delete, this.line);
}

class Hunk {
  final int oldLine, newLine;
  int deletes = 0, inserts = 0;
  final List<DiffOp> operations = [];
  Hunk(this.oldLine, this.newLine);
}

List<String> diffLines(List<String> a, List<String> b) {
  final n = a.length,
      m = b.length,
      lcs = List.generate(n + 1, (_) => List.filled(m + 1, 0));
  for (var i = n - 1; i >= 0; i--) {
    for (var j = m - 1; j >= 0; j--) {
      lcs[i][j] = a[i] == b[j]
          ? lcs[i + 1][j + 1] + 1
          : max(lcs[i + 1][j], lcs[i][j + 1]);
    }
  }
  final hunks = <Hunk>[];
  var i = 0, j = 0, deletes = 0, inserts = 0;
  while (i < n || j < m) {
    if (i < n && j < m && a[i] == b[j]) {
      i++;
      j++;
      continue;
    }
    final h = Hunk(i, j);
    while ((i < n || j < m) && !(i < n && j < m && a[i] == b[j])) {
      if (j == m || i < n && lcs[i + 1][j] >= lcs[i][j + 1]) {
        h.operations.add(DiffOp(true, a[i++]));
        h.deletes++;
      } else {
        h.operations.add(DiffOp(false, b[j++]));
        h.inserts++;
      }
    }
    deletes += h.deletes;
    inserts += h.inserts;
    hunks.add(h);
  }
  final out = ['hunks=${hunks.length} deleted=$deletes inserted=$inserts'];
  for (final h in hunks) {
    final old = h.oldLine + (h.deletes > 0 ? 1 : 0),
        next = h.newLine + (h.inserts > 0 ? 1 : 0);
    out.add('@@ -$old,${h.deletes} +$next,${h.inserts} @@');
    for (final op in h.operations) {
      out.add('${op.delete ? '-' : '+'}${op.line}');
    }
  }
  return out;
}
