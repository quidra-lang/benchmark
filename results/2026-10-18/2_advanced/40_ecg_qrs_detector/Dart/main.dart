import 'dart:io';
import 'dart:math' as math;
part 'signal_io.dart';
part 'filters.dart';
part 'detector.dart';
part 'hrv.dart';
part 'report.dart';

const labels = ['N', 'V', 'A'],
    peakClasses = ['qrs', 'searchback', 'twave', 'refractory', 'noise'];

class Thresholds {
  final int i1, i2, f1, f2;
  Thresholds(this.i1, this.i2, this.f1, this.f2);
}

Thresholds thresholds(Levels l) {
  final i = l.npki + floorDiv(l.spki - l.npki, 4),
      f = l.npkf + floorDiv(l.spkf - l.npkf, 4);
  return Thresholds(i, floorDiv(i, 2), f, floorDiv(f, 2));
}

class Detection {
  final List<Peak> registered;
  final Levels initial, finalLevels;
  final Thresholds finalThresholds;
  final int ra1, ra2;
  Detection(
    this.registered,
    this.initial,
    this.finalLevels,
    this.finalThresholds,
    this.ra1,
    this.ra2,
  );
}

Detection detectBeats(List<Peak> peaks, Signals s, Map<String, int> p) {
  final initial = initialLevels(s),
      levels = initial.copy(),
      registered = <Peak>[],
      intervals = <int>[];
  var ra1 = 200, ra2 = 200;
  void register(Peak peak) {
    if (registered.isNotEmpty) {
      final elapsed = peak.time - registered.last.time;
      intervals.add(elapsed);
      if (intervals.length > 8) intervals.removeAt(0);
      ra1 = sum(intervals) ~/ intervals.length;
      if (92 * ra1 <= 100 * elapsed && 100 * elapsed <= 116 * ra1) ra2 = ra1;
    }
    registered.add(peak);
  }

  void update(Peak peak, String category) {
    if (category == 'signal') {
      levels.spki = floorDiv(peak.peakI + 7 * levels.spki, 8);
      levels.spkf = floorDiv(peak.peakF + 7 * levels.spkf, 8);
    } else if (category == 'noise') {
      levels.npki = floorDiv(peak.peakI + 7 * levels.npki, 8);
      levels.npkf = floorDiv(peak.peakF + 7 * levels.npkf, 8);
    } else {
      levels.spki = floorDiv(peak.peakI + 3 * levels.spki, 4);
      levels.spkf = floorDiv(peak.peakF + 3 * levels.spkf, 4);
    }
  }

  void searchBack(int time) {
    while (true) {
      final lastTime = registered.isEmpty ? 0 : registered.last.time;
      if (time - lastTime <= ra2 * p['searchback_percent']! ~/ 100) break;
      final t = thresholds(levels);
      Peak? chosen;
      for (final candidate in peaks) {
        if (candidate.category == 'noise' &&
            lastTime < candidate.time &&
            candidate.time < time &&
            candidate.peakI > t.i2 &&
            candidate.peakF > t.f2 &&
            (chosen == null || candidate.peakI > chosen.peakI))
          chosen = candidate;
      }
      if (chosen == null) break;
      update(chosen, 'searchback');
      chosen.category = 'searchback';
      register(chosen);
    }
  }

  for (final peak in peaks) {
    searchBack(peak.time);
    final t = thresholds(levels);
    peak.thresholdI = t.i1;
    peak.thresholdF = t.f1;
    final last = registered.isEmpty ? null : registered.last;
    if (last != null && peak.time - last.time < p['refractory_ms']! ~/ 5) {
      peak.category = 'refractory';
      continue;
    }
    if (peak.peakI > t.i1 && peak.peakF > t.f1) {
      if (last != null &&
          peak.time - last.time < p['twave_ms']! ~/ 5 &&
          2 * peak.slope < last.slope) {
        peak.category = 'twave';
        update(peak, 'noise');
      } else {
        peak.category = 'qrs';
        update(peak, 'signal');
        register(peak);
      }
    } else {
      peak.category = 'noise';
      update(peak, 'noise');
    }
  }
  searchBack(s.integrated.length);
  return Detection(
    registered,
    initial,
    levels.copy(),
    thresholds(levels),
    ra1,
    ra2,
  );
}

class Beat {
  final int number, sample, rr, hr, width;
  final Peak peak;
  final String label, method;
  Annotation? annotation;
  int offset = 0;
  Beat(
    this.number,
    this.sample,
    this.peak,
    this.rr,
    this.hr,
    this.width,
    this.label,
    this.method,
  );
}

List<Beat> buildBeatList(
  List<Peak> registered,
  List<int> band,
  Map<String, int> p,
) {
  final beats = <Beat>[];
  for (final peak in registered) {
    final number = beats.length + 1,
        sample = math.max(0, peak.r - 21),
        rr = beats.isEmpty ? 0 : 5 * (sample - beats.last.sample),
        width = widthMS(band, peak.r);
    var label = 'N';
    if (number >= 10) {
      var preceding = 0;
      for (var k = number - 8; k < number; k++) {
        preceding += beats[k - 1].rr;
      }
      if (800 * rr < p['premature_percent']! * preceding)
        label = width > p['qrs_width_ms']! ? 'V' : 'A';
    }
    beats.add(
      Beat(
        number,
        sample,
        peak,
        rr,
        rr == 0 ? 0 : rdiv(6000000, rr),
        width,
        label,
        peak.category == 'qrs' ? 'threshold' : 'searchback',
      ),
    );
  }
  return beats;
}

void matchAnnotations(
  List<Beat> beats,
  List<Annotation> refs,
  Map<String, int> p,
) {
  final tolerance = p['match_ms']! ~/ 5;
  for (final b in beats) {
    Annotation? chosen;
    var best = 0;
    for (final ref in refs) {
      final distance = (ref.sample - b.sample).abs();
      if (ref.beat == null &&
          distance <= tolerance &&
          (chosen == null || distance < best)) {
        chosen = ref;
        best = distance;
      }
    }
    if (chosen != null) {
      chosen.beat = b;
      b.annotation = chosen;
      b.offset = 5 * (b.sample - chosen.sample);
    }
  }
}

List<String> beatLines(List<Beat> beats) => [
  'beat,sample,time_ms,rr_ms,hr_bpm,width_ms,label,method,ref_sample,ref_label',
  for (final b in beats)
    '${b.number},${b.sample},${5 * b.sample},${optional(b.rr)},${b.rr == 0 ? '-' : two(b.hr)},${b.width},${b.label},${b.method},${b.annotation?.sample ?? '-'},${b.annotation?.label ?? '-'}',
];
List<String> peakLines(List<Peak> peaks) => [
  'peak,sample,r_sample,peak_i,peak_f,slope,thr_i,thr_f,class',
  for (var i = 0; i < peaks.length; i++)
    '${i + 1},${peaks[i].time},${peaks[i].r},${peaks[i].peakI},${peaks[i].peakF},${peaks[i].slope},${peaks[i].thresholdI},${peaks[i].thresholdF},${peaks[i].category}',
];
List<String> orderedTexts(List<(int, int, String)> records) {
  records.sort(
    (a, b) => a.$1 != b.$1 ? a.$1.compareTo(b.$1) : a.$2.compareTo(b.$2),
  );
  return records.map((r) => r.$3).toList();
}

List<String> matchingLines(List<Beat> beats, List<Annotation> refs) {
  final records = <(int, int, String)>[];
  for (final ref in refs) {
    final b = ref.beat;
    records.add((
      ref.sample,
      0,
      b == null
          ? '${ref.sample},${ref.label},-,-,-,-,FN,-'
          : '${ref.sample},${ref.label},${b.number},${b.sample},${b.label},${b.offset},TP,${ref.label == b.label ? 'yes' : 'no'}',
    ));
  }
  for (final b in beats) {
    if (b.annotation == null)
      records.add((
        b.sample,
        1,
        '-,-,${b.number},${b.sample},${b.label},-,FP,-',
      ));
  }
  return [
    'ref_sample,ref_label,beat,beat_sample,beat_label,offset_ms,status,agree',
    ...orderedTexts(records),
  ];
}

List<String> signalExcerpt(
  List<int> samples,
  Signals s,
  Map<String, int> p,
) => [
  'sample,ecg,lowpass,bandpass,derivative,squared,integrated',
  for (var n = 0; n < p['excerpt_ms']! ~/ 5; n++)
    '$n,${samples[n]},${s.lowpass[n]},${s.bandpass[n]},${s.derivative[n]},${s.squared[n]},${s.integrated[n]}',
];

class Segment {
  final int startMS, endMS;
  int refs = 0, tp = 0, fp = 0, fn = 0, noisePeaks = 0, beats = 0;
  final rr = <int>[];
  Segment(this.startMS, this.endMS);
}

List<Segment> segmentRows(
  List<Beat> beats,
  List<Annotation> refs,
  List<Peak> peaks,
  int count,
  Map<String, int> p,
) {
  final g = p['segment_ms']! ~/ 5, segments = <Segment>[];
  for (var start = 0; start < count; start += g) {
    final stop = math.min(start + g, count), s = Segment(5 * start, 5 * stop);
    for (final ref in refs) {
      if (start <= ref.sample && ref.sample < stop) {
        s.refs++;
        if (ref.beat != null) s.tp++;
      }
    }
    s.fn = s.refs - s.tp;
    for (final b in beats) {
      if (start <= b.sample && b.sample < stop) {
        s.beats++;
        if (b.annotation == null) s.fp++;
        if (b.rr > 0) s.rr.add(b.rr);
      }
    }
    for (final peak in peaks) {
      if (peak.category == 'noise' && start <= peak.time && peak.time < stop)
        s.noisePeaks++;
    }
    segments.add(s);
  }
  return segments;
}

List<String> matchingErrors(
  List<Beat> beats,
  List<Annotation> refs,
) => orderedTexts([
  for (final b in beats)
    if (b.annotation == null)
      (
        b.sample,
        0,
        'false_positive beat=${b.number} sample=${b.sample} time_ms=${5 * b.sample} label=${b.label}',
      ),
  for (final ref in refs)
    if (ref.beat == null)
      (
        ref.sample,
        1,
        'false_negative sample=${ref.sample} time_ms=${5 * ref.sample} label=${ref.label}',
      ),
]);
String levelsText(Levels l) =>
    'spki=${l.spki} npki=${l.npki} spkf=${l.spkf} npkf=${l.npkf}';
List<String> performanceLines(
  List<Beat> beats,
  List<Annotation> refs,
  List<Peak> peaks,
  Detection d,
  Map<String, int> p,
  List<Segment> segments,
  int count,
) {
  final classes = <String, int>{},
      referenceTypes = <String, int>{},
      detectedTypes = <String, int>{},
      confusion = <(String, String), int>{},
      offsets = <int>[];
  for (final peak in peaks) {
    final kind = peak.category!;
    classes[kind] = (classes[kind] ?? 0) + 1;
  }
  var tp = 0, fp = 0;
  for (final ref in refs) {
    referenceTypes[ref.label] = (referenceTypes[ref.label] ?? 0) + 1;
    final label = ref.beat?.label ?? 'miss';
    if (ref.beat != null) tp++;
    final key = (ref.label, label);
    confusion[key] = (confusion[key] ?? 0) + 1;
  }
  for (final b in beats) {
    detectedTypes[b.label] = (detectedTypes[b.label] ?? 0) + 1;
    if (b.annotation == null) {
      fp++;
      final key = ('extra', b.label);
      confusion[key] = (confusion[key] ?? 0) + 1;
    } else {
      offsets.add(b.offset);
    }
  }
  final fn = refs.length - tp;
  final lines = [
    'DETECTOR',
    'samples $count',
    'duration_ms ${5 * count}',
    'peaks ${peaks.length} ${peakClasses.map((kind) => '$kind=${classes[kind] ?? 0}').join(' ')}',
    'initial_levels ${levelsText(d.initial)}',
    'final_levels ${levelsText(d.finalLevels)}',
    'final_thresholds thr_i=${d.finalThresholds.i1} thr_f=${d.finalThresholds.f1}',
    'final_rr_averages rravg1_ms=${5 * d.ra1} rravg2_ms=${5 * d.ra2}',
    'MATCHING',
    'tolerance_ms ${p['match_ms']}',
    'references ${refs.length} ${labels.map((label) => '$label=${referenceTypes[label] ?? 0}').join(' ')}',
    'detections ${beats.length} ${labels.map((label) => '$label=${detectedTypes[label] ?? 0}').join(' ')}',
    'true_positives $tp',
    'false_positives $fp',
    'false_negatives $fn',
    'sensitivity ${ratio(tp, tp + fn)}',
    'positive_predictivity ${ratio(tp, tp + fp)}',
    'detection_error_rate ${ratio(fp + fn, refs.length)}',
  ];
  final methods = <String>[];
  for (final method in ['threshold', 'searchback']) {
    final selected = beats.where((b) => b.method == method).toList();
    methods.add(
      '$method=${selected.where((b) => b.annotation != null).length}/${selected.length}',
    );
  }
  lines.add('by_method ${methods.join(' ')}');
  if (offsets.isEmpty) {
    lines.add('offset_ms none');
  } else {
    final absolute = offsets.map((v) => v.abs()).toList();
    lines.add(
      'offset_ms mean=${two(rdiv(100 * sum(offsets), offsets.length))} mean_abs=${two(rdiv(100 * sum(absolute), offsets.length))} max_abs=${absolute.reduce(math.max)}',
    );
  }
  lines.addAll([
    'CONFUSION',
    'ref  ${labels.map((label) => label.padLeft(6)).join()}  miss',
  ]);
  for (final refLabel in labels) {
    lines.add(
      '$refLabel    ${[...labels, 'miss'].map((label) => '${confusion[(refLabel, label)] ?? 0}'.padLeft(6)).join()}',
    );
  }
  lines.add(
    'extra${labels.map((label) => '${confusion[('extra', label)] ?? 0}'.padLeft(6)).join()}',
  );
  for (final (label, prefix) in [('V', 'veb'), ('A', 'sveb')]) {
    final correct = confusion[(label, label)] ?? 0;
    lines.addAll([
      '${prefix}_sensitivity ${ratio(correct, referenceTypes[label] ?? 0)}',
      '${prefix}_positive_predictivity ${ratio(correct, detectedTypes[label] ?? 0)}',
    ]);
  }
  lines.add(
    'SEGMENTS segment_ms=${p['segment_ms']} segments=${segments.length}',
  );
  for (final s in segments) {
    lines.add(
      '${s.startMS.toString().padLeft(6)}-${s.endMS.toString().padLeft(6)} refs=${s.refs} tp=${s.tp} fp=${s.fp} fn=${s.fn} noise_peaks=${s.noisePeaks}',
    );
  }
  lines.add('ERRORS count=${fp + fn}');
  lines.addAll(matchingErrors(beats, refs));
  return lines;
}

class PrematureDetail {
  final Beat beat;
  final int nextRR, mean, prematurity;
  final String compensation;
  PrematureDetail(
    this.beat,
    this.nextRR,
    this.mean,
    this.prematurity,
    this.compensation,
  );
}

List<PrematureDetail> prematureDetails(List<Beat> beats) {
  final details = <PrematureDetail>[];
  for (final b in beats) {
    if (b.label == 'N') continue;
    var preceding = 0;
    for (var k = b.number - 8; k < b.number; k++) {
      preceding += beats[k - 1].rr;
    }
    var next = 0, compensation = '-';
    if (b.number < beats.length) {
      next = beats[b.number].rr;
      final total = b.rr + next;
      compensation = 10 * (4 * total - preceding).abs() <= preceding
          ? 'full'
          : 4 * total < preceding
          ? 'partial'
          : 'long';
    }
    details.add(
      PrematureDetail(
        b,
        next,
        rdiv(100 * preceding, 8),
        rdiv(80000 * b.rr, preceding),
        compensation,
      ),
    );
  }
  return details;
}

class PrematureRun {
  final String label, kind;
  final int first, last, length, startMS;
  PrematureRun(
    this.label,
    this.kind,
    this.first,
    this.last,
    this.length,
    this.startMS,
  );
}

List<PrematureRun> prematureRuns(List<Beat> beats) {
  final runs = <PrematureRun>[];
  for (final label in ['V', 'A']) {
    final indices = [
      for (final b in beats)
        if (b.label == label) b.number,
    ];
    for (final (first, last) in consecutiveRanges(indices)) {
      final length = last - first + 1,
          kind = length == 1
              ? 'isolated'
              : length == 2
              ? 'couplet'
              : 'run';
      runs.add(
        PrematureRun(
          label,
          kind,
          first,
          last,
          length,
          5 * beats[first - 1].sample,
        ),
      );
    }
  }
  runs.sort((a, b) => a.first.compareTo(b.first));
  return runs;
}

class RhythmEvent {
  final String kind;
  final int first, last, startMS, intervals, cycles, rr, meanHR;
  RhythmEvent(
    this.kind,
    this.first,
    this.last,
    this.startMS, {
    this.intervals = 0,
    this.cycles = 0,
    this.rr = 0,
    this.meanHR = 0,
  });
}

List<RhythmEvent> arrhythmiaEvents(List<Beat> beats, Map<String, int> p) {
  final events = <RhythmEvent>[];
  for (final b in beats.skip(1)) {
    if (b.rr > p['pause_ms']!)
      events.add(
        RhythmEvent(
          'pause',
          b.number - 1,
          b.number,
          5 * beats[b.number - 2].sample,
          rr: b.rr,
        ),
      );
  }
  for (final kind in ['bradycardia', 'tachycardia']) {
    final indices = [
      for (final b in beats.skip(1))
        if (kind == 'bradycardia'
            ? b.rr > p['brady_ms']!
            : b.rr < p['tachy_ms']!)
          b.number,
    ];
    for (final (first, last) in consecutiveRanges(indices)) {
      final count = last - first + 1;
      if (count < 3) continue;
      var total = 0;
      for (var k = first; k <= last; k++) {
        total += beats[k - 1].rr;
      }
      events.add(
        RhythmEvent(
          kind,
          first - 1,
          last,
          5 * beats[first - 2].sample,
          intervals: count,
          meanHR: rdiv(6000000 * count, total),
        ),
      );
    }
  }
  final indices = [
        for (final b in beats)
          if (b.label == 'V') b.number,
      ],
      lookup = {for (final b in beats) b.number: b.label};
  for (final (kind, span) in [('bigeminy', 2), ('trigeminy', 3)]) {
    for (final chain in linkedSequences(indices, span, lookup)) {
      if (chain.length >= 3)
        events.add(
          RhythmEvent(
            kind,
            chain.first,
            chain.last,
            5 * beats[chain.first - 1].sample,
            cycles: chain.length,
          ),
        );
    }
  }
  return events;
}

String eventLine(RhythmEvent e) => e.kind == 'pause'
    ? 'pause beats=${e.first}-${e.last} rr_ms=${e.rr} start_ms=${e.startMS}'
    : e.kind == 'bradycardia' || e.kind == 'tachycardia'
    ? '${e.kind} beats=${e.first}-${e.last} intervals=${e.intervals} mean_hr=${two(e.meanHR)} start_ms=${e.startMS}'
    : '${e.kind} beats=${e.first}-${e.last} cycles=${e.cycles} start_ms=${e.startMS}';
List<String> hrvLines(
  List<Beat> beats,
  List<Segment> segments,
  Map<String, int> p,
) {
  final rr = RRStatistics(beats), nn = NNStatistics(beats);
  final lines = [
    'RR',
    'beats ${beats.length}',
    'intervals ${rr.count}',
    'mean_rr_ms ${maybeTwo(rr.meanRR)}',
  ];
  if (rr.shortest == null) {
    lines.addAll(['min_rr_ms none', 'max_rr_ms none', 'mean_hr_bpm none']);
  } else {
    lines.addAll([
      'min_rr_ms ${rr.shortest!.rr} beat=${rr.shortest!.number}',
      'max_rr_ms ${rr.longest!.rr} beat=${rr.longest!.number}',
      'mean_hr_bpm ${maybeTwo(rr.meanHR)}',
    ]);
  }
  lines.addAll([
    'NN',
    'intervals ${nn.e}',
    'mean_nn_ms ${maybeTwo(nn.meanNN)}',
    'sdnn_ms ${maybeTwo(nn.sdnn)}',
    'differences ${nn.k}',
    'rmssd_ms ${maybeTwo(nn.rmssd)}',
    'sdsd_ms ${maybeTwo(nn.sdsd)}',
    'nn50 ${nn.nn50}',
    'pnn50 ${nn.pnn50 == null ? 'none' : '${two(nn.pnn50!)}%'}',
    'sd1_ms ${maybeTwo(nn.sd1)}',
    'sd2_ms ${maybeTwo(nn.sd2)}',
    'HISTOGRAM bin_ms=7.8125 bins=${nn.histogram.length} max=${nn.histogramMax}',
  ]);
  final bins = nn.histogram.keys.toList()..sort();
  for (final bin in bins) {
    final count = nn.histogram[bin]!;
    lines.add(
      '${four(78125 * bin).padLeft(10)} ${four(78125 * (bin + 1)).padLeft(10)} ${count.toString().padLeft(3)} |${'#' * count}',
    );
  }
  lines.add(
    nn.e == 0
        ? 'triangular_index none'
        : 'triangular_index ${fraction(nn.e, nn.histogramMax)} ${two(nn.triangular!)}',
  );
  final premature = prematureDetails(beats);
  lines.add(
    'PREMATURE count=${premature.length} V=${premature.where((d) => d.beat.label == 'V').length} A=${premature.where((d) => d.beat.label == 'A').length}',
  );
  for (final d in premature) {
    final b = d.beat;
    lines.add(
      'beat=${b.number} sample=${b.sample} label=${b.label} rr_ms=${b.rr} next_rr_ms=${optional(d.nextRR)} mean_ms=${two(d.mean)} prematurity=${two(d.prematurity)}% compensation=${d.compensation} width_ms=${b.width} ref=${b.annotation?.label ?? '-'}',
    );
  }
  final runs = prematureRuns(beats);
  lines.add('RUNS count=${runs.length}');
  for (final r in runs) {
    lines.add(
      '${r.label} ${r.kind} beats=${r.first}-${r.last} length=${r.length} start_ms=${r.startMS}',
    );
  }
  final events = arrhythmiaEvents(beats, p);
  lines.add('EVENTS count=${events.length}');
  lines.addAll(events.map(eventLine));
  lines.add('TREND segment_ms=${p['segment_ms']} segments=${segments.length}');
  for (final s in segments) {
    final header =
        '${s.startMS.toString().padLeft(6)}-${s.endMS.toString().padLeft(6)} beats=${s.beats} ';
    if (s.rr.isEmpty) {
      lines.add('${header}mean_hr=none min_hr=none max_hr=none |');
      continue;
    }
    final hr = rdiv(6000000 * s.rr.length, sum(s.rr)),
        lo = s.rr.reduce(math.min),
        hi = s.rr.reduce(math.max);
    lines.add(
      '${header}mean_hr=${two(hr)} min_hr=${two(rdiv(6000000, hi))} max_hr=${two(rdiv(6000000, lo))} |${'#' * rdiv(hr, 500)}',
    );
  }
  return lines;
}

int scale(int value, int top, int bottom, int rows) =>
    top <= bottom ? 0 : rdiv((top - value) * (rows - 1), top - bottom);
String drawAxis(int columns, bool Function(int) marker) =>
    '       +${[for (var i = 0; i < columns; i++) marker(i) ? '+' : '-'].join()}+';
String drawLabels(String heading, List<(int, String)> markers) {
  final buffer = '${heading.padLeft(6)}  '.split('');
  for (final (column, text) in markers) {
    final position = 8 + column;
    while (buffer.length < position + text.length) {
      buffer.add(' ');
    }
    for (var i = 0; i < text.length; i++) {
      buffer[position + i] = text[i];
    }
  }
  return buffer.join().replaceFirst(RegExp(r' +$'), '');
}

List<String> waveformChart(List<int> upper, List<int> lower, int height) {
  final top = upper.reduce(math.max),
      bottom = lower.reduce(math.min),
      zero = bottom <= 0 && top >= 0 ? scale(0, top, bottom, height) : -1,
      lines = <String>[];
  for (var row = 0; row < height; row++) {
    final label = row == 0
        ? '$top'
        : row == height - 1
        ? '$bottom'
        : row == zero
        ? '0'
        : '';
    final cells = [
      for (var i = 0; i < upper.length; i++)
        scale(upper[i], top, bottom, height) <= row &&
                row <= scale(lower[i], top, bottom, height)
            ? '#'
            : row == zero
            ? '-'
            : ' ',
    ].join();
    lines.add('${label.padLeft(6)} |$cells|');
  }
  return lines;
}

List<String> tachogramChart(List<Beat> beats, int height) {
  final intervals = beats.skip(1).map((b) => b.rr).toList();
  if (intervals.isEmpty) return ['TACHOGRAM intervals=0', 'POINCARE points=0'];
  final lo = intervals.reduce(math.min),
      hi = intervals.reduce(math.max),
      lines = [
        'TACHOGRAM intervals=${intervals.length} min_ms=$lo max_ms=$hi rows=$height',
      ];
  for (var row = 0; row < height; row++) {
    final label = row == 0
        ? '$hi'
        : row == height - 1
        ? '$lo'
        : '';
    final cells = intervals
        .map((v) => scale(v, hi, lo, height) == row ? '*' : ' ')
        .join();
    lines.add('${label.padLeft(6)} |$cells|');
  }
  lines.addAll([
    drawAxis(intervals.length, (j) => (j + 2) % 10 == 0),
    drawLabels('beat', [
      for (var j = 0; j < intervals.length; j++)
        if ((j + 2) % 10 == 0) (j, '${j + 2}'),
    ]),
    ' label |${beats.skip(1).map((b) => b.label).join()}|',
  ]);
  return lines;
}

List<String> poincareChart(List<Beat> beats, int size) {
  final intervals = beats.skip(1).map((b) => b.rr).toList();
  if (intervals.isEmpty) return [];
  final lo = intervals.reduce(math.min),
      hi = intervals.reduce(math.max),
      points = <(int, int), int>{};
  for (var i = 0; i < intervals.length - 1; i++) {
    final left = intervals[i],
        right = intervals[i + 1],
        column = hi > lo ? rdiv((left - lo) * (size - 1), hi - lo) : 0,
        row = scale(right, hi, lo, size);
    final key = (row, column);
    points[key] = (points[key] ?? 0) + 1;
  }
  final lines = [
    'POINCARE points=${intervals.length - 1} size=$size min_ms=$lo max_ms=$hi',
  ];
  for (var row = 0; row < size; row++) {
    final label = row == 0
            ? '$hi'
            : row == size - 1
            ? '$lo'
            : '',
        cells = <String>[];
    for (var column = 0; column < size; column++) {
      final count = points[(row, column)] ?? 0;
      cells.add(
        count == 0
            ? '.'
            : count <= 9
            ? '$count'
            : '#',
      );
    }
    lines.add('${label.padLeft(6)} |${cells.join()}|');
  }
  final text = '${' ' * 8}$lo',
      highText = '$hi',
      highStart = 8 + size - '$hi'.length;
  lines.addAll([
    drawAxis(size, (_) => false),
    '$text${' ' * math.max(0, highStart - text.length)}$highText',
  ]);
  return lines;
}

List<String> averageTemplate(
  List<int> samples,
  List<Beat> beats,
  String label,
  int height,
) {
  final chosen = beats
          .where(
            (b) =>
                b.label == label &&
                b.sample >= 60 &&
                b.sample <= samples.length - 100,
          )
          .toList(),
      count = chosen.length;
  if (count == 0) return ['TEMPLATE $label beats=0'];
  final baseline = chosen
          .map((b) => sum(samples.sublist(b.sample - 60, b.sample - 50)))
          .toList(),
      averaged = <int>[];
  for (var offset = -60; offset < 100; offset++) {
    var total = 0;
    for (var i = 0; i < count; i++) {
      total += 10 * samples[chosen[i].sample + offset] - baseline[i];
    }
    averaged.add(rdiv(total, 10 * count));
  }
  final maximum = averaged.reduce(math.max),
      minimum = averaged.reduce(math.min),
      maxIndex = averaged.indexOf(maximum),
      minIndex = averaged.indexOf(minimum);
  final upper = [
        for (var i = 0; i < 80; i++)
          math.max(averaged[2 * i], averaged[2 * i + 1]),
      ],
      lower = [
        for (var i = 0; i < 80; i++)
          math.min(averaged[2 * i], averaged[2 * i + 1]),
      ];
  return [
    'TEMPLATE $label beats=$count max_uv=$maximum max_ms=${5 * (maxIndex - 60)} min_uv=$minimum min_ms=${5 * (minIndex - 60)} rows=$height',
    ...waveformChart(upper, lower, height),
    drawAxis(80, (i) => i % 10 == 0),
    drawLabels('ms', [for (var i = 0; i < 80; i += 10) (i, '${10 * i - 300}')]),
  ];
}

List<String> chartLines(
  List<int> samples,
  List<Beat> beats,
  Map<String, int> p,
) => [
  ...tachogramChart(beats, p['chart_rows']!),
  ...poincareChart(beats, p['poincare_size']!),
  for (final label in labels)
    ...averageTemplate(samples, beats, label, p['chart_rows']!),
];
List<String> rhythmStripLines(
  List<int> samples,
  List<Beat> beats,
  List<Annotation> refs,
  Map<String, int> p,
) {
  final start = p['strip_start_ms']! ~/ 5,
      count = p['strip_ms']! ~/ 5,
      columns = count ~/ 10,
      height = p['strip_rows']!,
      end = start + count;
  final excerpt = samples.sublist(start, end), upper = <int>[], lower = <int>[];
  for (var column = 0; column < columns; column++) {
    final piece = excerpt.sublist(10 * column, 10 * column + 10);
    upper.add(piece.reduce(math.max));
    lower.add(piece.reduce(math.min));
  }
  final lines = [
    'RHYTHM start_ms=${p['strip_start_ms']} end_ms=${p['strip_start_ms']! + p['strip_ms']!} columns=$columns rows=$height max_uv=${excerpt.reduce(math.max)} min_uv=${excerpt.reduce(math.min)}',
    ...waveformChart(upper, lower, height),
    drawAxis(columns, (c) => c % 20 == 0),
    drawLabels('s', [
      for (var column = 0; column < columns; column += 20)
        (column, '${(p['strip_start_ms']! + 50 * column) ~/ 1000}'),
    ]),
  ];
  final beatMarkers = List.filled(columns, ' '),
      refMarkers = List.filled(columns, ' ');
  for (final b in beats) {
    if (start <= b.sample && b.sample < end)
      beatMarkers[(b.sample - start) ~/ 10] = b.label;
  }
  for (final ref in refs) {
    if (start <= ref.sample && ref.sample < end)
      refMarkers[(ref.sample - start) ~/ 10] = ref.label;
  }
  lines.addAll([
    ' beats |${beatMarkers.join()}|',
    '  refs |${refMarkers.join()}|',
  ]);
  return lines;
}

void main() {
  final samples = readECG(),
      refs = readAnnotations(),
      p = readParams(),
      signals = filterECG(samples),
      peaks = findPeaks(signals),
      detection = detectBeats(peaks, signals, p),
      beats = buildBeatList(detection.registered, signals.bandpass, p);
  matchAnnotations(beats, refs, p);
  final segments = segmentRows(beats, refs, peaks, samples.length, p);
  Directory('output').createSync(recursive: true);
  writeLines('beats.csv', beatLines(beats));
  writeLines('peaks.csv', peakLines(peaks));
  writeLines('matching.csv', matchingLines(beats, refs));
  writeLines('signals_excerpt.csv', signalExcerpt(samples, signals, p));
  writeLines(
    'performance.txt',
    performanceLines(
      beats,
      refs,
      peaks,
      detection,
      p,
      segments,
      samples.length,
    ),
  );
  writeLines('hrv.txt', hrvLines(beats, segments, p));
  writeLines('charts.txt', chartLines(samples, beats, p));
  writeLines('rhythm_strip.txt', rhythmStripLines(samples, beats, refs, p));
}
