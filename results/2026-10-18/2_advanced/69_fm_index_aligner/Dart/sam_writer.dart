part of 'main.dart';

String ratio(int x, int y) {
  if (y == 0) return '-';
  final value = (x * 10000 + y ~/ 2) ~/ y;
  return '${value ~/ 10000}.${(value % 10000).toString().padLeft(4, '0')}';
}

String samHeader(List<Reference> refs) {
  final s = StringBuffer('@HD\tVN:1.6\tSO:unsorted\n');
  for (final r in refs) {
    s.writeln('@SQ\tSN:${r.name}\tLN:${r.sequence.length}');
  }
  s.writeln('@PG\tID:fm_index_aligner\tPN:fm_index_aligner\tVN:1.0');
  return s.toString();
}

String samRecord(
  Read read,
  Mapping m,
  List<Reference> refs,
  int maxAlternatives,
) {
  if (!m.mapped)
    return [
      read.name,
      '4',
      '*',
      '0',
      '0',
      '*',
      '*',
      '0',
      '0',
      read.bases,
      read.quality,
      'YM:Z:${m.method}',
    ].join('\t');
  final a = m.alignments[0];
  final (cigar, nm, md) = describe(a, m.core, refs, m.trim);
  final flag = a.strand == 0 ? 0 : 16,
      bases = a.strand == 0 ? read.bases : reverseComplement(read.bases),
      quality = a.strand == 0 ? read.quality : reverse(read.quality);
  final fields = [
    read.name,
    '$flag',
    refs[a.r].name,
    '${a.pos + 1}',
    '${m.mapq}',
    cigar,
    '*',
    '0',
    '0',
    bases,
    quality,
    'NM:i:$nm',
    'MD:Z:$md',
    'AS:i:${m.score}',
    'X0:i:${m.x0}',
    'X1:i:${m.x1}',
    'YM:Z:${m.method}',
  ];
  final others = m.alignments.length - 1;
  if (others > 0 && others <= maxAlternatives) {
    final xa = StringBuffer('XA:Z:');
    for (final a in m.alignments.skip(1)) {
      final (cigar, nm, _) = describe(a, m.core, refs, m.trim);
      xa.write(
        '${refs[a.r].name},${a.strand == 0 ? '+' : '-'}${a.pos + 1},$cigar,$nm;',
      );
    }
    fields.add(xa.toString());
  }
  return fields.join('\t');
}

void write(String path, StringBuffer s) =>
    File(path).writeAsStringSync(s.toString());
