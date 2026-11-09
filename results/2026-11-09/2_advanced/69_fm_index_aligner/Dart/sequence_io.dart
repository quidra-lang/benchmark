part of 'main.dart';

class Reference {
  final String name;
  String sequence = '';
  int masked = 0, offset = 0;
  Reference(this.name);
}

class Read {
  final String name, bases, quality;
  Read(this.name, this.bases, this.quality);
}

(List<Reference>, List<Read>, Map<String, List<int>>) readInput() {
  final references = <Reference>[];
  for (final line in File('input/reference.fasta').readAsLinesSync()) {
    if (line.startsWith('>')) {
      references.add(Reference(line.substring(1).split(' ').first));
    } else {
      final r = references.last;
      for (final c in line.codeUnits) {
        if (c >= 97 && c <= 122) r.masked++;
      }
      r.sequence += line.toUpperCase();
    }
  }
  final lines = File('input/reads.fastq').readAsLinesSync(), reads = <Read>[];
  for (var i = 0; i < lines.length; i += 4) {
    reads.add(Read(lines[i].substring(1), lines[i + 1], lines[i + 3]));
  }
  final params = <String, List<int>>{};
  for (final line in File('input/params.txt').readAsLinesSync()) {
    final a = line.split(' ');
    params[a[0]] = a.skip(1).map(int.parse).toList();
  }
  return (references, reads, params);
}

String reverse(String s) => String.fromCharCodes(s.codeUnits.reversed);
String reverseComplement(String s) => s
    .split('')
    .reversed
    .map((c) => const {'A': 'T', 'C': 'G', 'G': 'C', 'T': 'A', 'N': 'N'}[c]!)
    .join();
