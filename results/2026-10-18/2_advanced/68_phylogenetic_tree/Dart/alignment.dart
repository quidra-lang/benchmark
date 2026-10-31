part of 'main.dart';

class SequenceRecord {
  final String name;
  String sequence;
  final int line;
  SequenceRecord(this.name, this.sequence, this.line);
}

class ColumnClass {
  int constant = 0, variable = 0, informative = 0, gapped = 0, empty = 0;
}

const baseSets = {
  'A': 1,
  'C': 2,
  'G': 4,
  'T': 8,
  'R': 5,
  'Y': 10,
  'S': 6,
  'W': 9,
  'K': 12,
  'M': 3,
  'B': 14,
  'D': 13,
  'H': 11,
  'V': 7,
  'N': 15,
  '-': 15,
};
String readText(String path) => File(path).readAsStringSync();
List<SequenceRecord> readFASTA() {
  final a = <SequenceRecord>[];
  final lines = File('input/alignment.fasta').readAsLinesSync();
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    if (line.startsWith('>')) {
      a.add(SequenceRecord(line.substring(1).split(' ').first, '', i + 1));
    } else {
      a.last.sequence += line.toUpperCase();
    }
  }
  return a;
}

bool isBase(String c) => c == 'A' || c == 'C' || c == 'G' || c == 'T';
(List<String>, int) patterns(List<SequenceRecord> taxa, int length) {
  final a = [
    for (var col = 0; col < length; col++)
      taxa.map((t) => t.sequence[col]).join(),
  ];
  return (a, a.toSet().length);
}

ColumnClass classify(List<SequenceRecord> taxa, int length) {
  final a = ColumnClass();
  for (var col = 0; col < length; col++) {
    final count = List.filled(4, 0);
    var gap = false;
    for (final t in taxa) {
      final c = t.sequence[col];
      if (c == '-') gap = true;
      final index = 'ACGT'.indexOf(c);
      if (index >= 0) count[index]++;
    }
    final kinds = count.where((n) => n > 0).length,
        repeated = count.where((n) => n >= 2).length;
    if (kinds == 0) {
      a.empty++;
    } else if (kinds == 1) {
      a.constant++;
    } else {
      a.variable++;
    }
    if (repeated >= 2) a.informative++;
    if (gap) a.gapped++;
  }
  return a;
}
