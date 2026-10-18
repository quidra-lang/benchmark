import 'dart:io';
import 'dart:math' as math;

const bases = 'ACGT';
const symbols = '_ACMGRSVTWYHKDBN';
const aminoAcids = 'ACDEFGHIKLMNPQRSTVWY';
const residueMasses = [71079, 103139, 115089, 129116, 147177, 57052, 137141, 113160, 128174, 113160, 131193, 114104, 97117, 128131, 156188, 87078, 101105, 99133, 186213, 163176];
const enzymeNames = ['EcoRI', 'BamHI', 'HindIII', 'PstI', 'SmaI', 'KpnI', 'XbaI', 'NotI', 'EcoRV', 'HaeIII', 'AluI', 'TaqI', 'Sau3AI', 'HincII', 'AvaI'];
const recognition = ['GAATTC', 'GGATCC', 'AAGCTT', 'CTGCAG', 'CCCGGG', 'GGTACC', 'TCTAGA', 'GCGGCCGC', 'GATATC', 'GGCC', 'AGCT', 'TCGA', 'GATC', 'GTYRAC', 'CYCGRG'];
const cutOffsets = [1, 1, 1, 5, 3, 5, 1, 2, 3, 2, 2, 1, 0, 3, 1];
const schemas = <String, List<String>>{
  'SEQ': ['new', 'seq'], 'SLICE': ['name', 'pos', 'pos', 'new'], 'JOIN': ['join'],
  'MUTATE': ['name', 'pos', 'base'], 'DEL': ['name'], 'LIST': [],
  'REVCOMP': ['name'], 'COMPLEMENT': ['name'], 'REVERSE': ['name'], 'TRANSCRIBE': ['name'],
  'TRANSLATE': ['name', 'frame'], 'CODONS': ['name', 'frame'], 'PROTEIN': ['name', 'frame'],
  'ORFS': ['name', '1:200'], 'GC': ['name'], 'GCWINDOW': ['name', '1:500', '1:500'],
  'SKEW': ['name'], 'KMERS': ['name', '1:12', '1:100'], 'FIND': ['name', 'motif'],
  'RESTRICT': ['restrict'], 'PALINDROMES': ['name', '2:20', '2:20'],
  'REPEATS': ['name', '1:6', '1:6', '2:50'], 'HAMMING': ['name', 'name'],
  'ALIGN': ['name', 'name', 'mode', '1:20', '-20:0', '-20:-1'],
  'CONSENSUS': ['consensus'], 'TM': ['name'], 'MASS': ['name'], 'PRIMER': ['name'],
  'FOLD': ['name', '0:10'], 'ASSEMBLE': ['assemble'], 'PACK': ['name'], 'UNPACK': ['new', '1:500', 'hex'],
};
class DnaError implements Exception {
  final String reason;
  DnaError(this.reason);
}
Never fail(String s) => throw DnaError(s);
String reverse(String s) => s.split('').reversed.join();
String complement(String s) => s.split('').map((c) {
  final mask = symbols.indexOf(c), comp = ((mask & 1) << 3) | ((mask & 2) << 1) | ((mask & 4) >> 1) | ((mask & 8) >> 3);
  return symbols[comp];
}).join();
String revcomp(String s) => reverse(complement(s));
int gc(String s) => s.codeUnits.where((c) => c == 67 || c == 71).length;
String hundredths(int q) => '${q ~/ 100}.${(q % 100).toString().padLeft(2, '0')}';
String pct(int a, int b) => hundredths(10000 * a ~/ b);
String milli(int w) => '${w ~/ 1000}.${(w % 1000).toString().padLeft(3, '0')}';
String listText(Iterable<Object> xs) {
  final items = xs.toList();
  return items.isEmpty ? 'none' : items.join(' ');
}
bool transition(String a, String b) => a != b && ('AG'.contains(a) && 'AG'.contains(b) || 'CT'.contains(a) && 'CT'.contains(b));
String aa(String codon) {
  const code = 'FFLLSSSSYY**CC*WLLLLPPPPHHQQRRRRIIIMTTTTNNKKSSRRVVVVAAAADDEEGGGG';
  return code[16 * 'TCAG'.indexOf(codon[0]) + 4 * 'TCAG'.indexOf(codon[1]) + 'TCAG'.indexOf(codon[2])];
}
List<String> codons(String s, int f) {
  final strand = f < 0 ? revcomp(s) : s;
  return [for (var i = f.abs() - 1; i + 2 < s.length; i += 3) strand.substring(i, i + 3)];
}
Map<String, int> counts(Iterable<String> items) {
  final result = <String, int>{};
  for (final item in items) result.update(item, (n) => n + 1, ifAbsent: () => 1);
  return result;
}
List<String> rankedCounts(Map<String, int> counts) => counts.keys.toList()..sort((a, b) {
  final c = counts[b]!.compareTo(counts[a]!);
  return c != 0 ? c : a.compareTo(b);
});
List<int> occurrences(String s, String motif) {
  final pattern = motif.split('').map((symbol) {
    final mask = symbols.indexOf(symbol);
    return '[${[for (var k = 0; k < 4; k++) if ((mask & (1 << k)) != 0) bases[k]].join()}]';
  }).join();
  return RegExp('(?=$pattern)').allMatches(s).map((match) => match.start + 1).toList();
}
int repeatCount(String s, int i, int u) {
  final unit = s.substring(i, i + u);
  var count = 1;
  while (i + (count + 1) * u <= s.length && s.substring(i + count * u, i + (count + 1) * u) == unit) count++;
  return count;
}
int tm(String s) {
  final n = s.length, count = gc(s);
  return n < 14 ? 10 * (2 * (n - count) + 4 * count) : (649 * n + 410 * count - 6724) ~/ n;
}
String temperature(int t) => '${t ~/ 10}.${t % 10}';
int mass(String s) {
  const weights = [331222, 307197, 347221, 322208];
  return s.split('').fold(0, (n, c) => n + weights[bases.indexOf(c)]) - (s.length - 1) * 18015;
}
class Dna {
  final registry = <String, String>{};
  List<int> validate(String op, List<String> a) {
    final schema = schemas[op];
    if (schema == null) fail('unknown command $op');
    var spec = schema;
    final n = a.length;
    if (op == 'JOIN') {
      if (n < 3 || n > 9) fail('wrong argument count');
      spec = ['new', ...List.filled(n - 1, 'name')];
    } else if (op == 'RESTRICT') {
      if (n < 2 || n > 7) fail('wrong argument count');
      spec = ['name', ...List.filled(n - 1, 'enzyme')];
    } else if (op == 'CONSENSUS') {
      if (n < 2 || n > 10) fail('wrong argument count');
      spec = List.filled(n, 'name');
    } else if (op == 'ASSEMBLE') {
      if (n < 4 || n > 10) fail('wrong argument count');
      spec = ['new', '1:100', ...List.filled(n - 2, 'name')];
    } else if (n != spec.length) {
      fail('wrong argument count');
    }
    final values = List.filled(n, 0), seen = <String>{};
    for (var i = 0; i < n; i++) {
      final s = a[i], kind = spec[i];
      if (kind == 'name') {
        if (!registry.containsKey(s)) fail('unknown sequence $s');
      } else if (kind == 'new') {
        if (!RegExp(r'^[a-z][a-z0-9]{0,9}$').hasMatch(s)) fail('invalid name $s');
      } else if (kind == 'seq') {
        for (var j = 0; j < s.length; j++) if (!bases.contains(s[j])) fail('invalid base ${s[j]} at ${j + 1}');
      } else if (kind == 'base') {
        if (s.length != 1 || !bases.contains(s)) fail('invalid base $s');
      } else if (kind == 'motif') {
        if (s.isEmpty || s.length > 30 || s.split('').any((c) => symbols.indexOf(c) < 1)) fail('invalid motif $s');
      } else if (kind == 'enzyme') {
        if (!enzymeNames.contains(s)) fail('unknown enzyme $s');
        if (!seen.add(s)) fail('duplicate enzyme $s');
      } else if (kind == 'mode') {
        if (s != 'GLOBAL' && s != 'LOCAL') fail('invalid mode $s');
      } else if (kind == 'hex') {
        if (s.length != 2 * ((values[1] + 3) ~/ 4) || !RegExp(r'^[0-9A-F]+$').hasMatch(s)) fail('invalid hex');
      } else {
        if (!RegExp(r'^-?[0-9]{1,6}$').hasMatch(s)) fail('invalid number $s');
        final v = int.parse(s);
        final range = kind == 'pos' ? [1, registry[a[0]]!.length] : kind == 'frame' ? [-3, 3] : kind.split(':').map(int.parse).toList();
        if (v < range[0] || v > range[1] || kind == 'frame' && v == 0) fail('invalid number $s');
        values[i] = v;
      }
    }
    return values;
  }
  void store(String name, String s, StringBuffer out) {
    if (s.length > 500) fail('too long');
    final verb = registry.containsKey(name) ? 'replaced' : 'stored';
    registry[name] = s;
    out.writeln('$verb $name ${s.length} nt');
  }
  void align(String a, String b, bool local, int match, int mismatch, int gap, StringBuffer out) {
    final m = a.length, n = b.length, h = List.generate(a.length + 1, (_) => List.filled(b.length + 1, 0));
    if (!local) {
      for (var i = 0; i <= m; i++) h[i][0] = i * gap;
      for (var j = 0; j <= n; j++) h[0][j] = j * gap;
    }
    var score = 0, i1 = 0, j1 = 0;
    for (var i = 1; i <= m; i++) {
      for (var j = 1; j <= n; j++) {
        h[i][j] = math.max(math.max(h[i - 1][j - 1] + (a[i - 1] == b[j - 1] ? match : mismatch), h[i - 1][j] + gap), h[i][j - 1] + gap);
        if (local) {
          h[i][j] = math.max(0, h[i][j]);
          if (h[i][j] > score) {
            score = h[i][j];
            i1 = i;
            j1 = j;
          }
        }
      }
    }
    if (!local) {
      score = h[m][n];
      i1 = m;
      j1 = n;
    }
    if (local && score == 0) {
      out.writeln('score 0');
      return;
    }
    var i = i1, j = j1;
    final top = <String>[], bottom = <String>[];
    while (local ? h[i][j] != 0 : i != 0 || j != 0) {
      if (i > 0 && j > 0 && h[i][j] == h[i - 1][j - 1] + (a[i - 1] == b[j - 1] ? match : mismatch)) {
        top.add(a[--i]);
        bottom.add(b[--j]);
      } else if (i > 0 && h[i][j] == h[i - 1][j] + gap) {
        top.add(a[--i]);
        bottom.add('-');
      } else {
        top.add('-');
        bottom.add(b[--j]);
      }
    }
    final aa = top.reversed.toList(), bb = bottom.reversed.toList();
    final middle = List.generate(aa.length, (k) => aa[k] == '-' || bb[k] == '-' ? '-' : aa[k] == bb[k] ? '|' : '*');
    out.writeln('score $score a ${i + 1}-$i1 b ${j + 1}-$j1 identity ${middle.where((c) => c == '|').length}/${aa.length} gaps ${middle.where((c) => c == '-').length}');
    out.writeln(aa.join());
    out.writeln(middle.join());
    out.writeln(bb.join());
  }
  void fold(String s, int loop, StringBuffer out) {
    final n = s.length, dp = List.generate(s.length, (_) => List.filled(s.length, 0));
    int value(int i, int j) => i > j ? 0 : dp[i][j];
    bool pair(int i, int j) => ['AT', 'TA', 'CG', 'GC', 'GT', 'TG'].contains('${s[i]}${s[j]}');
    for (var length = 2; length <= n; length++) {
      for (var i = 0; i + length <= n; i++) {
        final j = i + length - 1;
        dp[i][j] = dp[i][j - 1];
        for (var k = i; k <= j - loop - 1; k++) if (pair(k, j)) dp[i][j] = math.max(dp[i][j], value(i, k - 1) + 1 + value(k + 1, j - 1));
      }
    }
    final structure = List.filled(n, '.'), stack = <(int, int)>[(0, n - 1)];
    while (stack.isNotEmpty) {
      final (i, j) = stack.removeLast();
      if (value(i, j) == 0) continue;
      if (value(i, j) == value(i, j - 1)) {
        stack.add((i, j - 1));
        continue;
      }
      for (var k = i; k <= j - loop - 1; k++) {
        if (pair(k, j) && value(i, k - 1) + 1 + value(k + 1, j - 1) == value(i, j)) {
          structure[k] = '(';
          structure[j] = ')';
          stack.add((i, k - 1));
          stack.add((k + 1, j - 1));
          break;
        }
      }
    }
    out.writeln(structure.join());
    out.writeln('pairs ${dp[0][n - 1]}');
  }
  void execute(List<String> tokens, StringBuffer out) {
    final op = tokens[0], a = tokens.sublist(1), v = validate(op, a);
    final name = a.isEmpty ? '' : a[0], s = registry[name] ?? '', n = s.length;
    if (op == 'SEQ') {
      store(name, a[1], out);
    } else if (op == 'SLICE') {
      store(a[3], v[1] <= v[2] ? s.substring(v[1] - 1, v[2]) : revcomp(s.substring(v[2] - 1, v[1])), out);
    } else if (op == 'JOIN') {
      store(name, a.skip(1).map((id) => registry[id]!).join(), out);
    } else if (op == 'MUTATE') {
      final p = v[1] - 1, old = s[v[1] - 1];
      if (old == a[2]) fail('no change');
      registry[name] = s.substring(0, p) + a[2] + s.substring(p + 1);
      out.writeln('$name $old${p + 1}${a[2]} ${transition(old, a[2]) ? 'transition' : 'transversion'}');
    } else if (op == 'DEL') {
      registry.remove(name);
      out.writeln('deleted $name');
    } else if (op == 'LIST') {
      final names = registry.keys.toList()..sort();
      if (names.isEmpty) out.writeln('no sequences');
      for (final name in names) out.writeln('$name ${registry[name]!.length} nt');
    } else if (['REVCOMP', 'COMPLEMENT', 'REVERSE', 'TRANSCRIBE'].contains(op)) {
      out.writeln(op == 'REVCOMP' ? revcomp(s) : op == 'COMPLEMENT' ? complement(s) : op == 'REVERSE' ? reverse(s) : s.replaceAll('T', 'U'));
    } else if (['TRANSLATE', 'CODONS', 'PROTEIN'].contains(op)) {
      final cs = codons(s, v[1]);
      final translation = cs.map(aa).join();
      if (op == 'TRANSLATE') {
        out.writeln(translation.isEmpty ? 'none' : translation);
      } else if (op == 'CODONS') {
        final freq = counts(cs);
        if (freq.isEmpty) out.writeln('none');
        for (final c in rankedCounts(freq)) out.writeln('$c ${aa(c)} ${freq[c]}');
      } else {
        final protein = translation.split('*').first;
        if (protein.isEmpty) fail('empty protein');
        var weight = 18015, charge = 0;
        for (final c in protein.split('')) {
          weight += residueMasses[aminoAcids.indexOf(c)];
          if ('KR'.contains(c)) charge++;
          if ('DE'.contains(c)) charge--;
        }
        final freq = counts(protein.split(''));
        out.writeln(protein);
        out.writeln('length ${protein.length} mass ${milli(weight)} charge ${charge > 0 ? '+' : ''}$charge');
        out.writeln(rankedCounts(freq).map((c) => '$c=${freq[c]}').join(' '));
      }
    } else if (op == 'ORFS') {
      final results = <(int, int, int, String)>[];
      for (final f in [1, 2, 3, -1, -2, -3]) {
        final cs = codons(s, f);
        int? start;
        for (var i = 0; i < cs.length; i++) {
          if (start == null && cs[i] == 'ATG') {
            start = i;
          } else if (start != null && aa(cs[i]) == '*') {
            if (i - start >= v[1]) {
              final left = f.abs() + 3 * start, right = f.abs() + 3 * i + 2;
              results.add((f < 0 ? n + 1 - right : left, f < 0 ? n + 1 - left : right, f, cs.sublist(start, i).map(aa).join()));
            }
            start = null;
          }
        }
      }
      results.sort((a, b) => a.$1.compareTo(b.$1));
      if (results.isEmpty) out.writeln('none');
      for (final r in results) out.writeln('${r.$3 > 0 ? '+' : ''}${r.$3} ${r.$1} ${r.$2} ${r.$4.length} ${r.$4}');
    } else if (op == 'GC') {
      final freq = counts(s.split(''));
      out.writeln('${bases.split('').map((c) => '$c=${freq[c] ?? 0}').join(' ')} GC=${pct(gc(s), n)}%');
    } else if (op == 'GCWINDOW') {
      if (v[1] > n) fail('window too large');
      for (var i = 0; i + v[1] <= n; i += v[2]) out.writeln('${i + 1}-${i + v[1]} ${pct(gc(s.substring(i, i + v[1])), v[1])}%');
    } else if (op == 'SKEW') {
      final values = [0];
      for (final c in s.split('')) values.add(values.last + (c == 'G' ? 1 : c == 'C' ? -1 : 0));
      final low = values.reduce(math.min), high = values.reduce(math.max);
      out.writeln('min $low at ${List.generate(n + 1, (i) => i).where((i) => values[i] == low).join(' ')}');
      out.writeln('max $high at ${List.generate(n + 1, (i) => i).where((i) => values[i] == high).join(' ')}');
    } else if (op == 'KMERS') {
      if (v[1] > n) fail('k too large');
      final freq = counts([for (var i = 0; i + v[1] <= n; i++) s.substring(i, i + v[1])]);
      out.writeln('${n - v[1] + 1} windows ${freq.length} distinct');
      for (final k in rankedCounts(freq).take(v[2])) out.writeln('$k ${freq[k]}');
    } else if (op == 'FIND') {
      out.writeln('forward ${listText(occurrences(s, a[1]))}');
      out.writeln('reverse ${listText(occurrences(s, revcomp(a[1])))}');
    } else if (op == 'RESTRICT') {
      final cuts = <int>{};
      for (final e in a.skip(1)) {
        final k = enzymeNames.indexOf(e);
        final points = occurrences(s, recognition[k]).map((p) => p + cutOffsets[k] - 1).where((p) => p > 0 && p < n).toList();
        cuts.addAll(points);
        out.writeln('$e ${listText(points)}');
      }
      final positions = [0, ...(cuts.toList()..sort()), n];
      final sizes = [for (var i = 1; i < positions.length; i++) positions[i] - positions[i - 1]]
        ..sort((a, b) => b.compareTo(a));
      out.writeln('fragments ${[for (var i = 1; i < positions.length; i++) '${positions[i - 1] + 1}-${positions[i]}'].join(' ')}');
      out.writeln('sizes ${sizes.join(' ')}');
    } else if (op == 'PALINDROMES') {
      if (v[1] > v[2]) fail('invalid range');
      var found = false;
      for (var i = 0; i < n; i++) for (var len = v[1]; len <= v[2] && i + len <= n; len++) {
        final part = s.substring(i, i + len);
        if (part == revcomp(part)) {
          found = true;
          out.writeln('${i + 1} $len $part');
        }
      }
      if (!found) out.writeln('none');
    } else if (op == 'REPEATS') {
      if (v[1] > v[2]) fail('invalid range');
      final results = <(int, int, int, String)>[];
      for (var u = v[1]; u <= v[2]; u++) {
        var i = 0;
        while (i + u <= n) {
          final unit = s.substring(i, i + u), count = repeatCount(s, i, u);
          var primitive = true;
          for (var d = 1; d < u; d++) if (u % d == 0 && unit.substring(0, d) * (u ~/ d) == unit) primitive = false;
          if (primitive && count >= v[3]) {
            results.add((i, u, count, unit));
            i += count * u;
          } else {
            i++;
          }
        }
      }
      results.sort((a, b) {
        final c = a.$1.compareTo(b.$1);
        return c != 0 ? c : a.$2.compareTo(b.$2);
      });
      if (results.isEmpty) out.writeln('none');
      for (final r in results) out.writeln('${r.$1 + 1}-${r.$1 + r.$2 * r.$3} ${r.$4}x${r.$3}');
    } else if (op == 'HAMMING') {
      final b = registry[a[1]]!;
      if (n != b.length) fail('length mismatch');
      var distance = 0, transitions = 0;
      for (var i = 0; i < n; i++) {
        if (s[i] != b[i]) {
          distance++;
          if (transition(s[i], b[i])) transitions++;
        }
      }
      out.writeln('distance $distance transitions $transitions transversions ${distance - transitions}');
    } else if (op == 'ALIGN') {
      align(s, registry[a[1]]!, a[2] == 'LOCAL', v[3], v[4], v[5], out);
    } else if (op == 'CONSENSUS') {
      final seqs = a.map((id) => registry[id]!).toList();
      if (seqs.any((s) => s.length != n)) fail('length mismatch');
      final profile = List.generate(4, (_) => List.filled(n, 0)), consensus = <String>[], iupac = <String>[];
      for (var i = 0; i < n; i++) {
        for (final seq in seqs) profile[bases.indexOf(seq[i])][i]++;
        final maxCount = profile.map((row) => row[i]).reduce(math.max);
        final winners = [for (var k = 0; k < 4; k++) if (profile[k][i] == maxCount) k];
        consensus.add(bases[winners.first]);
        iupac.add(symbols[winners.fold(0, (mask, k) => mask | (1 << k))]);
      }
      for (var k = 0; k < 4; k++) out.writeln('${bases[k]} ${profile[k].join(' ')}');
      out.writeln('consensus ${consensus.join()}');
      out.writeln('iupac ${iupac.join()}');
    } else if (op == 'TM') {
      out.writeln('Tm ${temperature(tm(s))} ${n < 14 ? 'wallace' : 'gc'}');
    } else if (op == 'MASS') {
      final single = mass(s);
      out.writeln('ss ${milli(single)} ds ${milli(single + mass(revcomp(s)))}');
    } else if (op == 'PRIMER') {
      final maxRun = RegExp(r'([ACGT])\1*').allMatches(s).map((run) => run[0]!.length).reduce(math.max);
      var repeat = 0, selfcomp = 0;
      for (var i = 0; i + 1 < n; i++) if (s[i] != s[i + 1]) repeat = math.max(repeat, repeatCount(s, i, 2));
      for (var center = 1; center < n; center++) {
        var left = center - 1, right = center;
        while (left >= 0 && right < n && bases.indexOf(s[left]) + bases.indexOf(s[right]) == 3) {
          selfcomp = math.max(selfcomp, right - left + 1);
          left--;
          right++;
        }
      }
      final clamp = gc(s.substring(math.max(0, n - 5))), count = gc(s), t = tm(s);
      final names = ['length', 'gc', 'tm', 'clamp', 'run', 'repeat', 'selfcomp'];
      final values = ['$n', pct(count, n), temperature(t), '$clamp', '$maxRun', '$repeat', '$selfcomp'];
      final passes = [n >= 18 && n <= 25, 40 * n <= 100 * count && 100 * count <= 60 * n, t >= 520 && t <= 620, clamp >= 1 && clamp <= 3, maxRun <= 4, repeat <= 4, selfcomp <= 6];
      for (var i = 0; i < 7; i++) out.writeln('${names[i]} ${values[i]} ${passes[i] ? 'OK' : 'FAIL'}');
      out.writeln(passes.every((x) => x) ? 'PASS' : 'FAIL ${[for (var i = 0; i < 7; i++) if (!passes[i]) names[i]].join(' ')}');
    } else if (op == 'FOLD') {
      if (n > 100) fail('too long');
      fold(s, v[1], out);
    } else if (op == 'ASSEMBLE') {
      var fragments = {for (final id in a.skip(2)) registry[id]!}.toList();
      fragments = fragments.where((s) => !fragments.any((b) => s != b && b.contains(s))).toList();
      while (fragments.length > 1) {
        var best = 0, bx = 0, by = 0;
        for (var x = 0; x < fragments.length; x++) for (var y = 0; y < fragments.length; y++) {
          if (x == y) continue;
          for (var o = math.min(fragments[x].length, fragments[y].length) - 1; o > best; o--) {
            if (fragments[x].endsWith(fragments[y].substring(0, o))) {
              best = o;
              bx = x;
              by = y;
              break;
            }
          }
        }
        if (best < v[1]) break;
        final merged = fragments[bx] + fragments[by].substring(best);
        fragments[bx] = merged;
        fragments = [for (var i = 0; i < fragments.length; i++) if (i == bx || i != by && !merged.contains(fragments[i])) fragments[i]];
      }
      final longest = fragments.reduce((a, b) => a.length >= b.length ? a : b);
      if (longest.length > 500) fail('too long');
      out.writeln('contigs ${fragments.length}');
      for (final f in fragments) out.writeln('${f.length} $f');
      store(name, longest, out);
    } else if (op == 'PACK') {
      final hex = StringBuffer();
      for (var i = 0; i < n; i += 4) {
        var value = 0;
        for (var j = 0; j < 4; j++) value = value * 4 + (i + j < n ? bases.indexOf(s[i + j]) : 0);
        hex.write(value.toRadixString(16).toUpperCase().padLeft(2, '0'));
      }
      out.writeln('$n $hex');
    } else if (op == 'UNPACK') {
      final codes = <int>[];
      for (var i = 0; i < a[2].length; i += 2) {
        final value = int.parse(a[2].substring(i, i + 2), radix: 16);
        codes.addAll([value ~/ 64, value ~/ 16 % 4, value ~/ 4 % 4, value % 4]);
      }
      if (codes.skip(v[1]).any((c) => c != 0)) fail('invalid padding');
      store(name, codes.take(v[1]).map((c) => bases[c]).join(), out);
    }
  }
}
void main() {
  final dna = Dna(), output = StringBuffer(), n = int.parse(stdin.readLineSync()!);
  for (var i = 0; i < n; i++) {
    final a = stdin.readLineSync()!.split(' '), draft = StringBuffer();
    try {
      dna.execute(a, draft);
      output.write(draft);
    } on DnaError catch (e) {
      output.writeln('ERROR ${e.reason}');
    }
  }
  stdout.write(output);
}
