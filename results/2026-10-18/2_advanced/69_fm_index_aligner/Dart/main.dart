import 'dart:io';
import 'dart:math';

part 'sequence_io.dart';
part 'suffix_array.dart';
part 'fm_index.dart';
part 'search.dart';
part 'sam_writer.dart';

class Alignment {
  int r, pos, strand;
  final String operations;
  final int score, mm;
  Alignment({
    this.r = 0,
    this.pos = 0,
    this.strand = 0,
    this.operations = '',
    this.score = 0,
    this.mm = 0,
  });
}

class Mapping {
  bool mapped = false;
  String method = '';
  List<String> core = ['', ''];
  final int length, trim;
  int score = 0, x0 = 0, x1 = 0, mapq = 0;
  final List<Alignment> alignments = [];
  Mapping(this.length, this.trim);
}

class SearchCounters {
  int calls = 0,
      nodes = 0,
      leaves = 0,
      hits = 0,
      seedReads = 0,
      seeds = 0,
      withN = 0,
      repetitive = 0,
      withoutHit = 0,
      candidates = 0,
      passing = 0;
}

const unreachable = -1000000;

class DPRow {
  final int lo;
  final List<int> h, e, f;
  DPRow(this.lo, int width)
    : h = List.filled(width, unreachable),
      e = List.filled(width, unreachable),
      f = List.filled(width, unreachable);
  int value(String kind, int j) {
    final i = j - lo;
    if (i < 0 || i >= h.length) return unreachable;
    return kind == 'E'
        ? e[i]
        : kind == 'F'
        ? f[i]
        : h[i];
  }
}

(int, int) position(List<Reference> refs, int p) {
  for (var r = 0; r < refs.length; r++) {
    final reference = refs[r];
    if (p >= reference.offset &&
        p < reference.offset + reference.sequence.length)
      return (r, p - reference.offset);
  }
  return (-1, -1);
}

String positionName(List<Reference> refs, int p) {
  final (r, offset) = position(refs, p);
  return r < 0 ? '*' : '${refs[r].name}:${offset + 1}';
}

int comparePositions(Alignment a, Alignment b) {
  var c = a.r.compareTo(b.r);
  if (c != 0) return c;
  c = a.pos.compareTo(b.pos);
  return c != 0 ? c : a.strand.compareTo(b.strand);
}

Alignment? align(String w, String s, int c, int band, List<int> scores) {
  final length = w.length,
      size = s.length,
      rows = List.generate(w.length + 1, (_) => DPRow(0, 0));
  int get(int i, int j, String kind) =>
      i < 0 || i > length ? unreachable : rows[i].value(kind, j);
  for (var i = 0; i <= length; i++) {
    final lo = max(0, i + c - band), hi = min(size, i + c + band);
    final row = DPRow(lo, max(0, hi - lo + 1));
    rows[i] = row;
    for (var j = lo; j <= hi; j++) {
      final k = j - lo;
      if (i == 0) {
        row.h[k] = 0;
        continue;
      }
      final h = get(i - 1, j, 'H'), f = get(i - 1, j, 'F');
      if (h > unreachable) row.f[k] = h - scores[2] - scores[3];
      if (f > unreachable) row.f[k] = max(row.f[k], f - scores[3]);
      if (j >= 1) {
        final h = get(i, j - 1, 'H'), e = get(i, j - 1, 'E');
        if (h > unreachable) row.e[k] = h - scores[2] - scores[3];
        if (e > unreachable) row.e[k] = max(row.e[k], e - scores[3]);
        final diagonal = get(i - 1, j - 1, 'H');
        if (diagonal > unreachable) {
          final score = w[i - 1] == s[j - 1] ? scores[0] : -scores[1];
          row.h[k] = diagonal + score;
        }
      }
      row.h[k] = max(row.h[k], max(row.f[k], row.e[k]));
    }
  }
  var best = unreachable, j = -1;
  for (var k = 0; k < rows[length].h.length; k++) {
    final value = rows[length].h[k];
    if (value > best) {
      best = value;
      j = rows[length].lo + k;
    }
  }
  if (j < 0) return null;
  var i = length, state = 'H';
  final operations = <String>[];
  while (true) {
    if (state == 'H') {
      if (i == 0) break;
      final diagonal = get(i - 1, j - 1, 'H'),
          score = j >= 1 && w[i - 1] == s[j - 1] ? scores[0] : -scores[1];
      if (j >= 1 &&
          diagonal > unreachable &&
          get(i, j, 'H') == diagonal + score) {
        operations.add('M');
        i--;
        j--;
        continue;
      }
      state = get(i, j, 'F') > unreachable && get(i, j, 'H') == get(i, j, 'F')
          ? 'I'
          : 'D';
    } else if (state == 'I') {
      operations.add('I');
      final previous = get(i - 1, j, 'F');
      state = previous > unreachable && get(i, j, 'F') == previous - scores[3]
          ? 'I'
          : 'H';
      i--;
    } else {
      operations.add('D');
      final previous = get(i, j - 1, 'E');
      state = previous > unreachable && get(i, j, 'E') == previous - scores[3]
          ? 'D'
          : 'H';
      j--;
    }
  }
  return Alignment(pos: j, operations: operations.reversed.join(), score: best);
}

Mapping mapRead(
  Read read,
  List<Reference> refs,
  FMIndex forward,
  FMIndex reverse,
  Map<String, List<int>> params,
  SearchCounters counters,
) {
  var length = read.bases.length;
  while (length > 0 &&
      read.quality.codeUnitAt(length - 1) - 33 < params['TRIM_QUALITY']![0]) {
    length--;
  }
  final m = Mapping(length, read.bases.length - length);
  if (length < params['MIN_READ_LENGTH']![0]) {
    m.method = 'SHORT';
    return m;
  }
  m.core = [
    read.bases.substring(0, length),
    reverseComplement(read.bases.substring(0, length)),
  ];
  var zs = params['MAX_MISMATCHES']![0];
  for (final w in m.core) {
    if (!forward.exact(w).empty) {
      zs = 1;
      break;
    }
  }
  final hits = <Alignment>[];
  for (var strand = 0; strand < 2; strand++) {
    final result = backtrack(forward, reverse, m.core[strand], zs);
    counters.calls++;
    counters.nodes += result.nodes;
    counters.leaves += result.leaves.length;
    counters.hits += result.hits;
    for (final leaf in result.leaves) {
      for (var row = leaf.interval.lo; row < leaf.interval.hi; row++) {
        final (p, _) = forward.locate(row);
        final (r, offset) = position(refs, p);
        hits.add(
          Alignment(
            r: r,
            pos: offset,
            strand: strand,
            operations: 'M' * length,
            mm: leaf.mismatches,
          ),
        );
      }
    }
  }
  final scores = params['SCORES']!;
  if (hits.isNotEmpty) {
    hits.sort((a, b) {
      final c = a.mm.compareTo(b.mm);
      return c != 0 ? c : comparePositions(a, b);
    });
    final best = hits[0].mm;
    for (final hit in hits) {
      if (hit.mm == best) m.x0++;
      if (hit.mm == best + 1) m.x1++;
      if (hit.mm <= best + 1) m.alignments.add(hit);
    }
    m.mapped = true;
    m.method = best == 0 ? 'EXACT' : 'MISMATCH';
    m.score = (length - best) * scores[0] - best * scores[1];
    m.mapq = m.x0 >= 2
        ? 0
        : m.x1 == 0
        ? 60 - 12 * best
        : max(30 - 12 * best - 3 * m.x1, 1);
    return m;
  }
  final seedLength = params['SEED_LENGTH']![0];
  m.method = 'NOHIT';
  if (length < seedLength) return m;
  counters.seedReads++;
  final candidateSet = <(int, int, int)>{};
  for (var strand = 0; strand < 2; strand++) {
    final w = m.core[strand];
    for (var o = 0; o + seedLength <= length; o += params['SEED_STEP']![0]) {
      counters.seeds++;
      final seed = w.substring(o, o + seedLength);
      if (seed.contains('N')) {
        counters.withN++;
        continue;
      }
      final iv = forward.exact(seed), count = iv.hi - iv.lo;
      if (count > params['MAX_SEED_HITS']![0]) {
        counters.repetitive++;
        continue;
      }
      if (count == 0) {
        counters.withoutHit++;
        continue;
      }
      for (var row = iv.lo; row < iv.hi; row++) {
        final (p, _) = forward.locate(row);
        final (r, e) = position(refs, p);
        candidateSet.add((strand, r, e - o));
      }
    }
  }
  final candidates = candidateSet.toList()
    ..sort((a, b) {
      var c = a.$1.compareTo(b.$1);
      if (c != 0) return c;
      c = a.$2.compareTo(b.$2);
      return c != 0 ? c : a.$3.compareTo(b.$3);
    });
  counters.candidates += candidates.length;
  final accepted = <(int, int, int), Alignment>{};
  for (final (strand, r, c) in candidates) {
    final a = align(
      m.core[strand],
      refs[r].sequence,
      c,
      params['BAND_WIDTH']![0],
      scores,
    );
    if (a == null ||
        100 * a.score < params['MIN_SCORE_PERCENT']![0] * scores[0] * length)
      continue;
    a.r = r;
    a.strand = strand;
    final key = (a.r, a.pos, a.strand), old = accepted[key];
    if (old == null || a.score > old.score) accepted[key] = a;
  }
  counters.passing += accepted.length;
  if (accepted.isEmpty) return m;
  m.alignments.addAll(accepted.values);
  m.alignments.sort((a, b) {
    final c = b.score.compareTo(a.score);
    return c != 0 ? c : comparePositions(a, b);
  });
  m.mapped = true;
  m.method = 'SEED';
  m.score = m.alignments[0].score;
  var second = 0;
  for (final a in m.alignments) {
    if (a.score == m.score) {
      m.x0++;
    } else {
      second = max(second, a.score);
    }
  }
  m.x1 = m.alignments.length - m.x0;
  if (m.x0 == 1) m.mapq = 60 * (m.score - second) ~/ m.score;
  return m;
}

(String, int, String) describe(
  Alignment a,
  List<String> core,
  List<Reference> refs,
  int trim,
) {
  final cigar = StringBuffer(), md = StringBuffer();
  if (trim > 0 && a.strand == 1) cigar.write('${trim}S');
  for (var i = 0; i < a.operations.length;) {
    var j = i + 1;
    while (j < a.operations.length && a.operations[j] == a.operations[i]) {
      j++;
    }
    cigar.write('${j - i}${a.operations[i]}');
    i = j;
  }
  if (trim > 0 && a.strand == 0) cigar.write('${trim}S');
  final w = core[a.strand], s = refs[a.r].sequence;
  var i = 0, j = a.pos, u = 0, nm = 0;
  for (var k = 0; k < a.operations.length;) {
    final op = a.operations[k];
    if (op == 'M') {
      if (w[i] == s[j]) {
        u++;
      } else {
        md.write('$u${s[j]}');
        u = 0;
        nm++;
      }
      i++;
      j++;
      k++;
    } else if (op == 'I') {
      i++;
      nm++;
      k++;
    } else {
      md.write('$u^');
      u = 0;
      while (k < a.operations.length && a.operations[k] == 'D') {
        md.write(s[j]);
        j++;
        nm++;
        k++;
      }
    }
  }
  md.write(u);
  return (cigar.toString(), nm, md.toString());
}

int bwtRuns(String s) {
  var n = 0;
  for (var i = 0; i < s.length; i++) {
    if (i == 0 || s[i] != s[i - 1]) n++;
  }
  return n;
}

String yes(bool b) => b ? 'yes' : 'no';
void reportIndex(
  StringBuffer out,
  List<Reference> refs,
  FMIndex forward,
  FMIndex reverse,
  Map<String, List<int>> params,
) {
  final n = forward.text.length;
  out.writeln('text length $n sequences ${refs.length}');
  for (final r in refs) {
    final gc = r.sequence.split('').where((c) => c == 'G' || c == 'C').length;
    out.writeln(
      'sequence ${r.name} length ${r.sequence.length} offset ${r.offset} gc ${ratio(gc, r.sequence.length)} masked ${r.masked}',
    );
  }
  final symbols = List.filled(6, 0);
  for (var i = 0; i < n; i++) {
    symbols[symbol(forward.text[i])]++;
  }
  out.writeln(
    'symbols \$ ${symbols[0]} # ${symbols[1]} A ${symbols[2]} C ${symbols[3]} G ${symbols[4]} T ${symbols[5]}',
  );
  out.writeln();
  out.writeln('forward_index');
  final classes = forward.suffix.classes;
  out.writeln('suffix_array rounds ${classes.length - 1}');
  for (var t = 0; t < classes.length; t++) {
    out.writeln('round $t prefix_length ${1 << t} classes ${classes[t]}');
  }
  final check = adjacent(forward.text, forward.suffix.sa);
  out.writeln(
    'sa_check pairs ${n - 1} ordered ${check.ordered} lcp_sum ${check.lcpSum} mean_lcp ${ratio(check.lcpSum, n - 1)} max_lcp ${check.maxLcp}',
  );
  out.writeln(
    'longest_repeat ${check.maxLcp} ${positionName(refs, forward.suffix.sa[check.star - 1])} ${positionName(refs, forward.suffix.sa[check.star])}',
  );
  final seedLength = params['SEED_LENGTH']![0], kmers = <String, int>{};
  var occurrences = 0;
  for (var p = 0; p + seedLength <= n; p++) {
    final kmer = forward.text.substring(p, p + seedLength);
    if (!kmer.contains('#') && !kmer.contains(r'$')) {
      kmers[kmer] = (kmers[kmer] ?? 0) + 1;
      occurrences++;
    }
  }
  var unique = 0, maxOccurrence = 0;
  for (final count in kmers.values) {
    if (count == 1) unique++;
    maxOccurrence = max(maxOccurrence, count);
  }
  out.writeln(
    'kmers length $seedLength occurrences $occurrences distinct ${kmers.length} unique $unique max_occurrence $maxOccurrence unique_fraction ${ratio(unique, occurrences)}',
  );
  out.writeln(
    'bwt runs ${bwtRuns(forward.bwt)} head ${forward.bwt.substring(0, min(60, n))}',
  );
  out.writeln(
    'c_array \$ ${forward.c[0]} # ${forward.c[1]} A ${forward.c[2]} C ${forward.c[3]} G ${forward.c[4]} T ${forward.c[5]}',
  );
  out.writeln(
    'occ interval ${forward.occInterval} checkpoints ${forward.checkpoints.length}',
  );
  out.writeln(
    'sa_sample interval ${params['SA_SAMPLE_INTERVAL']![0]} samples ${forward.sample.length}',
  );
  var correct = 0, totalSteps = 0, maxSteps = 0;
  for (var row = 0; row < n; row++) {
    final (p, steps) = forward.locate(row);
    if (p == forward.suffix.sa[row]) correct++;
    totalSteps += steps;
    maxSteps = max(maxSteps, steps);
  }
  out.writeln(
    'locate rows $n correct $correct total_steps $totalSteps max_steps $maxSteps mean_steps ${ratio(totalSteps, n)}',
  );
  out.writeln(
    'inverse_bwt identical ${yes(forward.inverse() == forward.text)}',
  );
  out.writeln();
  out.writeln('reverse_index');
  out.writeln('suffix_array rounds ${reverse.suffix.classes.length - 1}');
  final reverseCheck = adjacent(reverse.text, reverse.suffix.sa);
  out.writeln('sa_check pairs ${n - 1} ordered ${reverseCheck.ordered}');
  out.writeln(
    'bwt runs ${bwtRuns(reverse.bwt)} head ${reverse.bwt.substring(0, min(60, n))}',
  );
  out.writeln(
    'inverse_bwt identical ${yes(reverse.inverse() == reverse.text)}',
  );
  out.writeln();
  out.writeln('direct_sort');
  var count = 0;
  for (final r in refs) {
    if (r.sequence.length > params['DIRECT_SORT_LIMIT']![0]) continue;
    final u = r.sequence + r'$', a = suffixArray(u), b = directSort(u);
    var identical = true;
    for (var i = 0; i < a.sa.length; i++) {
      if (a.sa[i] != b[i]) identical = false;
    }
    out.writeln(
      '${r.name} length ${u.length} rounds ${a.classes.length - 1} identical ${yes(identical)}',
    );
    count++;
  }
  if (count == 0) out.writeln('none');
  out.writeln();
  final occBytes = 24 * forward.checkpoints.length,
      sampleBytes = 4 * forward.sample.length,
      bitmapBytes = (n + 7) ~/ 8;
  final total = n + occBytes + sampleBytes + bitmapBytes;
  out.writeln(
    'index_size bwt_bytes $n occ_bytes $occBytes sample_bytes $sampleBytes bitmap_bytes $bitmapBytes total_bytes $total full_bytes ${5 * n} ratio ${ratio(total, 5 * n)}',
  );
}

void main() {
  final (refs, reads, params) = readInput();
  final text = StringBuffer();
  for (var i = 0; i < refs.length; i++) {
    refs[i].offset = text.length;
    text.write(refs[i].sequence);
    if (i + 1 < refs.length) text.write('#');
  }
  final joined = text.toString(),
      forward = buildIndex(
        joined + r'$',
        params['OCC_INTERVAL']![0],
        params['SA_SAMPLE_INTERVAL']![0],
      ),
      backward = buildIndex(
        reverse(joined) + r'$',
        params['OCC_INTERVAL']![0],
        0,
      );
  final counters = SearchCounters(),
      mappings = <Mapping>[],
      sam = StringBuffer(samHeader(refs)),
      indexOut = StringBuffer(),
      coverage = StringBuffer(),
      variants = StringBuffer(),
      summary = StringBuffer();
  for (final read in reads) {
    final m = mapRead(read, refs, forward, backward, params, counters);
    mappings.add(m);
    sam.writeln(samRecord(read, m, refs, params['MAX_ALT_HITS']![0]));
  }
  reportIndex(indexOut, refs, forward, backward, params);
  final depth = [for (final ref in refs) List.filled(ref.sequence.length, 0)],
      zeroStarts = [
        for (final ref in refs) List.filled(ref.sequence.length, 0),
      ],
      pileup = [
        for (final ref in refs)
          List.generate(
            ref.sequence.length,
            (_) => List.generate(2, (_) => List.filled(4, 0)),
          ),
      ];
  var mapped = 0,
      unique = 0,
      multi = 0,
      trimmed = 0,
      trimmedBases = 0,
      short = 0,
      nohit = 0,
      forwardCount = 0,
      reverseCount = 0;
  final methods = <String, int>{},
      referenceStats = List.generate(refs.length, (_) => List.filled(4, 0)),
      lengthBins = <int, List<int>>{};
  var minLength = reads.first.bases.length,
      maxLength = 0,
      maxOriginal = 0,
      nReads = 0,
      nBases = 0,
      nMapped = 0;
  final multiTargets = <String, int>{},
      mapqHistogram = <int, int>{},
      nmHistogram = <int, int>{};
  var aligned = 0, mismatches = 0;
  final substitutions = List.generate(4, (_) => List.filled(5, 0)),
      cycleAligned = List.filled(101, 0),
      cycleMismatches = List.filled(101, 0);
  var matchedQuality = 0,
      mismatchQuality = 0,
      matchedPairs = 0,
      mismatchPairs = 0;
  final qualityAligned = List.filled(5, 0),
      qualityMismatch = List.filled(5, 0),
      cigarCounts = List.filled(4, 0);
  var insertionEvents = 0,
      insertionBases = 0,
      deletionEvents = 0,
      deletionBases = 0;
  for (var ri = 0; ri < reads.length; ri++) {
    final read = reads[ri], m = mappings[ri];
    minLength = min(minLength, m.length);
    maxLength = max(maxLength, m.length);
    maxOriginal = max(maxOriginal, read.bases.length);
    if (m.trim > 0) trimmed++;
    trimmedBases += m.trim;
    final bin = m.length ~/ 10 * 10, binStats = lengthBins[bin] ??= [0, 0, 0];
    binStats[0]++;
    final containsN = read.bases.contains('N');
    if (containsN) {
      nReads++;
      nBases += read.bases.split('').where((b) => b == 'N').length;
    }
    if (!m.mapped) {
      if (m.method == 'SHORT') {
        short++;
      } else {
        nohit++;
      }
      continue;
    }
    mapped++;
    methods[m.method] = (methods[m.method] ?? 0) + 1;
    mapqHistogram[m.mapq] = (mapqHistogram[m.mapq] ?? 0) + 1;
    binStats[1]++;
    if (containsN) nMapped++;
    final a = m.alignments[0];
    referenceStats[a.r][0]++;
    if (a.strand == 0) {
      forwardCount++;
      referenceStats[a.r][2]++;
    } else {
      reverseCount++;
      referenceStats[a.r][3]++;
    }
    final isUnique = m.x0 == 1;
    if (isUnique) {
      unique++;
      binStats[2]++;
      referenceStats[a.r][1]++;
    } else {
      multi++;
      final targets = <int>{};
      for (final other in m.alignments) {
        final best = m.method == 'SEED'
            ? other.score == m.score
            : other.mm == a.mm;
        if (best) targets.add(other.r);
      }
      final names = [
        for (var r = 0; r < refs.length; r++)
          if (targets.contains(r)) refs[r].name,
      ].join('+');
      multiTargets[names] = (multiTargets[names] ?? 0) + 1;
    }
    final (_, nm, _) = describe(a, m.core, refs, m.trim);
    nmHistogram[nm] = (nmHistogram[nm] ?? 0) + 1;
    cigarCounts[3] += m.trim;
    if (m.mapq == 0) zeroStarts[a.r][a.pos]++;
    var i = 0, j = a.pos;
    final w = m.core[a.strand], reference = refs[a.r].sequence;
    for (var k = 0; k < a.operations.length; k++) {
      final op = a.operations[k];
      if (op == 'M') {
        cigarCounts[0]++;
        final cycle = a.strand == 0 ? i + 1 : m.length - i,
            quality =
                read.quality.codeUnitAt(a.strand == 0 ? i : m.length - i - 1) -
                33,
            match = w[i] == reference[j];
        if (m.mapq >= params['COVERAGE_MIN_MAPQ']![0]) {
          depth[a.r][j]++;
          if (w[i] != 'N' && quality >= params['VARIANTS']![1])
            pileup[a.r][j][a.strand]['ACGT'.indexOf(w[i])]++;
        }
        if (isUnique) {
          aligned++;
          cycleAligned[cycle]++;
          final qb = min(quality ~/ 10, 4);
          qualityAligned[qb]++;
          substitutions['ACGT'.indexOf(reference[j])]['ACGTN'.indexOf(w[i])]++;
          if (match) {
            matchedPairs++;
            matchedQuality += quality;
          } else {
            mismatches++;
            cycleMismatches[cycle]++;
            qualityMismatch[qb]++;
            mismatchPairs++;
            mismatchQuality += quality;
          }
        }
        i++;
        j++;
      } else if (op == 'I') {
        cigarCounts[1]++;
        i++;
        if (isUnique) {
          insertionBases++;
          if (k == 0 || a.operations[k - 1] != 'I') insertionEvents++;
        }
      } else {
        cigarCounts[2]++;
        j++;
        if (isUnique) {
          deletionBases++;
          if (k == 0 || a.operations[k - 1] != 'D') deletionEvents++;
        }
      }
    }
  }
  final window = params['COVERAGE_WINDOW']![0],
      mapq = params['COVERAGE_MIN_MAPQ']![0];
  coverage.writeln('window $window min_mapq $mapq');
  for (var r = 0; r < refs.length; r++) {
    final ref = refs[r];
    var covered = 0, total = 0, maximum = 0;
    for (final d in depth[r]) {
      if (d > 0) covered++;
      total += d;
      maximum = max(maximum, d);
    }
    coverage.writeln(
      'reference ${ref.name} length ${ref.sequence.length} covered $covered breadth ${ratio(covered, ref.sequence.length)} mean_depth ${ratio(total, ref.sequence.length)} max_depth $maximum',
    );
    final histogram = List.filled(maximum + 1, 0);
    for (final d in depth[r]) {
      histogram[d]++;
    }
    coverage.writeln(
      [
        'depth_histogram',
        for (var d = 0; d < histogram.length; d++) '$d:${histogram[d]}',
      ].join(' '),
    );
    for (var first = 0; first < ref.sequence.length; first += window) {
      final last = min(first + window, ref.sequence.length);
      var gc = 0, sum = 0, maximum = 0, zero = 0, mapq0 = 0;
      for (var j = first; j < last; j++) {
        if (ref.sequence[j] == 'G' || ref.sequence[j] == 'C') gc++;
        final d = depth[r][j];
        sum += d;
        maximum = max(maximum, d);
        if (d == 0) zero++;
        mapq0 += zeroStarts[r][j];
      }
      final width = last - first;
      coverage.writeln(
        '${ref.name} ${first + 1} $last gc ${ratio(gc, width)} sum $sum mean ${ratio(sum, width)} max $maximum zero $zero mapq0 $mapq0 |${'#' * (10 * sum ~/ width)}',
      );
    }
  }
  final vp = params['VARIANTS']!;
  variants.writeln(
    'min_depth ${vp[0]} min_base_quality ${vp[1]} min_alt_percent ${vp[2]} hom_percent ${vp[3]}',
  );
  var callable = 0, variantCount = 0, heterozygous = 0, homozygous = 0;
  for (var r = 0; r < refs.length; r++) {
    final ref = refs[r];
    for (var j = 0; j < pileup[r].length; j++) {
      final site = pileup[r][j], counts = List.filled(4, 0);
      var dp = 0;
      for (var b = 0; b < 4; b++) {
        counts[b] = site[0][b] + site[1][b];
        dp += counts[b];
      }
      if (dp < vp[0]) continue;
      callable++;
      var alt = -1, nAlt = -1;
      for (var b = 0; b < 4; b++) {
        if ('ACGT'[b] != ref.sequence[j] && counts[b] > nAlt) {
          alt = b;
          nAlt = counts[b];
        }
      }
      if (nAlt < 2 || 100 * nAlt < vp[2] * dp) continue;
      variantCount++;
      var genotype = '0/1';
      if (100 * nAlt >= vp[3] * dp) {
        genotype = '1/1';
        homozygous++;
      } else {
        heterozygous++;
      }
      variants.writeln(
        '${ref.name} ${j + 1} ${ref.sequence[j]}>${'ACGT'[alt]} depth $dp alt $nAlt fraction ${ratio(nAlt, dp)} genotype $genotype strands ${site[0][alt]} ${site[1][alt]} counts ${counts.join(' ')}',
      );
    }
  }
  variants.writeln(
    'callable $callable variants $variantCount heterozygous $heterozygous homozygous $homozygous',
  );
  summary.writeln(
    'reads total ${reads.length} trimmed $trimmed trimmed_bases $trimmedBases short $short',
  );
  summary.writeln(
    'mapped $mapped rate ${ratio(mapped, reads.length)} unique $unique multi $multi unmapped ${reads.length - mapped}',
  );
  summary.writeln('unmapped short $short nohit $nohit');
  summary.writeln(
    'method exact ${methods['EXACT'] ?? 0} mismatch ${methods['MISMATCH'] ?? 0} seed ${methods['SEED'] ?? 0}',
  );
  summary.writeln('strand forward $forwardCount reverse $reverseCount');
  for (var r = 0; r < refs.length; r++) {
    final v = referenceStats[r];
    summary.writeln(
      'reference ${refs[r].name} mapped ${v[0]} unique ${v[1]} forward ${v[2]} reverse ${v[3]}',
    );
  }
  summary.writeln('length_bins');
  for (var lo = minLength ~/ 10 * 10; lo <= maxLength; lo += 10) {
    final v = lengthBins[lo] ?? [0, 0, 0];
    summary.writeln(
      '$lo-${lo + 9} reads ${v[0]} mapped ${v[1]} unique ${v[2]}',
    );
  }
  summary.writeln('n_reads $nReads n_bases $nBases mapped $nMapped');
  summary.writeln('multi_targets');
  final targetNames = multiTargets.keys.toList()..sort();
  if (targetNames.isEmpty) summary.writeln('none');
  for (final name in targetNames) {
    summary.writeln('$name ${multiTargets[name]}');
  }
  summary.writeln('mapq_histogram');
  final mapqs = mapqHistogram.keys.toList()..sort((a, b) => b.compareTo(a));
  for (final q in mapqs) {
    summary.writeln('$q ${mapqHistogram[q]}');
  }
  summary.writeln('nm_histogram');
  final nms = nmHistogram.keys.toList()..sort();
  for (final nm in nms) {
    summary.writeln('$nm ${nmHistogram[nm]}');
  }
  summary.writeln(
    'error_profile aligned_bases $aligned mismatches $mismatches rate ${ratio(mismatches, aligned)}',
  );
  summary.writeln('substitutions');
  summary.writeln('ref A C G T N');
  for (var i = 0; i < 4; i++) {
    summary.writeln('${'ACGT'[i]} ${substitutions[i].join(' ')}');
  }
  summary.writeln('mismatch_by_cycle');
  for (var cycle = 1; cycle <= maxOriginal; cycle++) {
    summary.writeln(
      'cycle $cycle aligned ${cycleAligned[cycle]} mismatches ${cycleMismatches[cycle]} rate ${ratio(cycleMismatches[cycle], cycleAligned[cycle])}',
    );
  }
  summary.writeln(
    'quality matched $matchedPairs mean ${ratio(matchedQuality, matchedPairs)} mismatched $mismatchPairs mean ${ratio(mismatchQuality, mismatchPairs)}',
  );
  summary.writeln('quality_bins');
  final ranges = ['0-9', '10-19', '20-29', '30-39', '40-'];
  for (var i = 0; i < 5; i++) {
    summary.writeln(
      '${ranges[i]} aligned ${qualityAligned[i]} mismatches ${qualityMismatch[i]} rate ${ratio(qualityMismatch[i], qualityAligned[i])}',
    );
  }
  summary.writeln(
    'cigar M ${cigarCounts[0]} I ${cigarCounts[1]} D ${cigarCounts[2]} S ${cigarCounts[3]}',
  );
  summary.writeln(
    'indels insertions $insertionEvents $insertionBases deletions $deletionEvents $deletionBases',
  );
  summary.writeln(
    'search dfs_calls ${counters.calls} dfs_nodes ${counters.nodes} dfs_leaves ${counters.leaves} dfs_positions ${counters.hits}',
  );
  summary.writeln(
    'seeds reads ${counters.seedReads} seeds ${counters.seeds} with_n ${counters.withN} repetitive ${counters.repetitive} without_hit ${counters.withoutHit} candidates ${counters.candidates} passing ${counters.passing}',
  );
  Directory('output').createSync(recursive: true);
  final outputs = {
    'alignments.sam': sam,
    'coverage.txt': coverage,
    'variants.txt': variants,
    'index_stats.txt': indexOut,
    'summary.txt': summary,
  };
  for (final entry in outputs.entries) {
    write('output/${entry.key}', entry.value);
  }
}
