import 'dart:io';
import 'dart:math';

part 'records.dart';
part 'cleaning.dart';
part 'harmonic_fit.dart';
part 'predict.dart';
part 'report.dart';

class Harmonic {
  final double amp, phase, ampError, phaseError, snr;
  Harmonic(this.amp, this.phase, this.ampError, this.phaseError, this.snr);
}

class Day {
  final int hour;
  int nHigh = 0, nLow = 0;
  double? high, low;
  Day(this.hour);
}

class DailyMean {
  final int hour, filled;
  final double level;
  DailyMean(this.hour, this.filled, this.level);
}

class Result {
  final Station station;
  final int first, last;
  final List<int> times;
  final Model model;
  final Map<int, double> residual = {};
  final Map<String, Harmonic> harmonics = {};
  List<Extremum> extremes = [];
  final List<Day> days = [];
  List<double> predictions = [];
  double mhhw = 0, mllw = 0, mhw = 0, mlw = 0, mtl = 0, dtl = 0, mn = 0, gt = 0;
  Result(this.station, this.first, this.last, this.times, this.model);
}

(List<int>, List<String>) selectConstituents(
  int tau,
  List<Constituent> c,
  double rayleigh,
) {
  final selected = <int>[], status = List.filled(c.length, '');
  for (var i = 0; i < c.length; i++) {
    final co = c[i];
    if (co.speed * tau < 360 * rayleigh) {
      status[i] = 'short';
      continue;
    }
    for (final j in selected) {
      if ((co.speed - c[j].speed).abs() * tau < 360 * rayleigh) {
        status[i] = 'conflict:${c[j].name}';
        break;
      }
    }
    if (status[i].isEmpty) {
      status[i] = 'fitted';
      selected.add(i);
    }
  }
  return (selected, status);
}

double mean(List<double> a) {
  var sum = 0.0;
  for (final v in a) {
    sum += v;
  }
  return sum / a.length;
}

String extremaDate(Settings p, Extremum e) =>
    datetime(p, e.minute).substring(0, 10);
Result processStation(
  Station s,
  List<Constituent> c,
  Settings p,
  StringBuffer cleaning,
  StringBuffer constants,
  StringBuffer extremesOut,
  StringBuffer summary,
) {
  final numeric = s.values.keys.toList()..sort();
  final first = numeric.first, last = numeric.last, reason = <int, String>{};
  for (var t = first; t <= last; t++) {
    if (s.na.contains(t)) {
      reason[t] = 'na';
    } else if (!s.values.containsKey(t)) {
      reason[t] = 'absent';
    }
  }
  final runs = flatRuns(s.values, first, last, p.flat, reason),
      candidates = [
        for (final t in numeric)
          if (!reason.containsKey(t)) t,
      ];
  final (selected, status) = selectConstituents(last - first, c, p.rayleigh);
  final pre = fit(candidates, s.values, selected, c),
      preResidual = <int, double>{};
  var preSS = 0.0;
  for (final t in candidates) {
    final v = s.values[t]! - predict(pre, c, t.toDouble());
    preResidual[t] = v;
    preSS += v * v;
  }
  final (spikes, tested) = spikeTest(candidates, preResidual, p, reason);
  final times = [
        for (final t in candidates)
          if (!reason.containsKey(t)) t,
      ],
      gaps = listGaps(first, last, reason),
      counts = <String, int>{};
  for (final cause in reason.values) {
    counts[cause] = (counts[cause] ?? 0) + 1;
  }
  cleaning.writeln('station=${s.code} name=${s.name}');
  cleaning.writeln(
    'span start=${datetime(p, first * 60)} end=${datetime(p, last * 60)} hours=${last - first + 1} record_length=${last - first}',
  );
  cleaning.writeln(
    'counts rows=${s.rows} numeric=${numeric.length} na=${counts['na'] ?? 0} absent=${counts['absent'] ?? 0} flat=${counts['flat'] ?? 0} spikes=${counts['spike'] ?? 0} usable=${times.length}',
  );
  for (final run in runs) {
    cleaning.writeln(
      'flat start=${datetime(p, run.first * 60)} end=${datetime(p, run.last * 60)} value=${format(run.value, 3)} removed=${run.last - run.first}',
    );
  }
  cleaning.writeln(
    'spike_test window=${p.w} candidates=${candidates.length} tested=$tested prefit_rms=${format(sqrt(preSS / candidates.length), 4)}',
  );
  for (final sp in spikes) {
    cleaning.writeln(
      'spike time=${datetime(p, sp.time * 60)} value=${format(s.values[sp.time]!, 3)} residual=${format(sp.residual, 4)} median=${format(sp.median, 4)} mad=${format(sp.mad, 4)} limit=${format(sp.limit, 4)}',
    );
  }
  for (final gap in gaps) {
    cleaning.writeln(
      'gap start=${datetime(p, gap.first * 60)} end=${datetime(p, gap.last * 60)} hours=${gap.last - gap.first + 1} cause=${gap.cause}',
    );
  }
  final model = fit(times, s.values, selected, c),
      r = Result(s, first, last, times, model);
  var ss = 0.0, maxAbs = 0.0, hm = 0.0;
  for (final t in times) {
    final v = s.values[t]! - predict(model, c, t.toDouble());
    r.residual[t] = v;
    ss += v * v;
    maxAbs = max(maxAbs, v.abs());
    hm += s.values[t]!;
  }
  hm /= times.length;
  var total = 0.0, lagN = 0.0, lagD = 0.0;
  for (final t in times) {
    final delta = s.values[t]! - hm;
    total += delta * delta;
    final next = r.residual[t + 1];
    if (next != null) {
      lagN += r.residual[t]! * next;
      lagD += r.residual[t]! * r.residual[t]!;
    }
  }
  final unknowns = model.coefficients.length,
      dof = times.length - model.coefficients.length;
  final s2 = ss / dof, byIndex = <int, Harmonic>{};
  for (var k = 0; k < selected.length; k++) {
    final i = selected[k], ia = 2 * k + 1, ib = 2 * k + 2;
    final a = model.coefficients[ia], b = model.coefficients[ib];
    final (amp, phase) = amplitudePhase(a, b);
    final va = s2 * model.inverse[ia][ia],
        vb = s2 * model.inverse[ib][ib],
        cab = s2 * model.inverse[ia][ib];
    final ae = sqrt(a * a * va + b * b * vb + 2 * a * b * cab) / amp,
        pe =
            sqrt(b * b * va + a * a * vb - 2 * a * b * cab) /
            (amp * amp) *
            180 /
            3.141592653589793;
    final snr = (amp / ae) * (amp / ae), h = Harmonic(amp, phase, ae, pe, snr);
    r.harmonics[c[i].name] = h;
    byIndex[i] = h;
  }
  for (var i = 0; i < c.length; i++) {
    final co = c[i];
    if (status[i] != 'fitted') {
      constants.writeln(
        '${s.code},${co.name},${format(co.speed, 7)},${status[i]},,,,,,',
      );
      continue;
    }
    final h = byIndex[i]!;
    constants.writeln(
      '${s.code},${co.name},${format(co.speed, 7)},fitted,${format(h.amp, 4)},${format(h.phase, 2)},${format(h.ampError, 4)},${format(h.phaseError, 2)},${format(h.snr, 1)},${h.snr >= p.snr ? 'yes' : 'no'}',
    );
  }
  r.predictions = [
    for (var i = 0; i <= p.hours; i++)
      predict(model, c, (p.start + i).toDouble()),
  ];
  final ext = extrema(model, c, p), raw = ext.length;
  while (ext.length >= 2) {
    var best = 0, distance = (ext[0].height - ext[1].height).abs();
    for (var i = 1; i + 1 < ext.length; i++) {
      final d = (ext[i].height - ext[i + 1].height).abs();
      if (d < distance) {
        best = i;
        distance = d;
      }
    }
    if (distance >= p.minRange) break;
    ext.removeRange(best, best + 2);
  }
  for (var i = 0; i < ext.length; i++) {
    var best = i;
    for (var j = 0; j < ext.length; j++) {
      if (ext[j].high == ext[i].high &&
          extremaDate(p, ext[j]) == extremaDate(p, ext[i])) {
        if ((ext[i].high && ext[j].height > ext[best].height) ||
            (!ext[i].high && ext[j].height < ext[best].height))
          best = j;
      }
    }
    ext[i].label = ext[i].high
        ? (i == best ? 'HHW' : 'LHW')
        : (i == best ? 'LLW' : 'HLW');
  }
  r.extremes = ext;
  extremesOut.writeln(
    'station=${s.code} extremes=${ext.length} raw=$raw removed=${raw - ext.length}',
  );
  for (var i = 0; i < ext.length; i++) {
    final e = ext[i],
        change = i == 0 ? 'none' : format(ext[i].height - ext[i - 1].height, 3);
    extremesOut.writeln(
      '${datetime(p, e.minute)} ${e.label} ${format(e.height, 3)} change=$change',
    );
  }
  final highs = <double>[],
      lows = <double>[],
      dailyHigh = <double>[],
      dailyLow = <double>[];
  for (final e in ext) {
    (e.high ? highs : lows).add(e.height);
  }
  for (var hour = p.start; hour < p.start + p.hours; hour += 24) {
    final d = Day(hour);
    for (final e in ext) {
      if (extremaDate(p, e) != date(p, hour)) continue;
      if (e.high) {
        d.nHigh++;
        if (d.high == null || e.height > d.high!) d.high = e.height;
      } else {
        d.nLow++;
        if (d.low == null || e.height < d.low!) d.low = e.height;
      }
    }
    var hhw = 'none', llw = 'none', range = 'none';
    if (d.high != null) {
      hhw = format(d.high!, 3);
      dailyHigh.add(d.high!);
    }
    if (d.low != null) {
      llw = format(d.low!, 3);
      dailyLow.add(d.low!);
    }
    if (d.high != null && d.low != null) range = format(d.high! - d.low!, 3);
    r.days.add(d);
    extremesOut.writeln(
      'day date=${date(p, hour)} high_waters=${d.nHigh} low_waters=${d.nLow} hhw=$hhw llw=$llw range=$range',
    );
  }
  r.mhhw = mean(dailyHigh);
  r.mllw = mean(dailyLow);
  r.mhw = mean(highs);
  r.mlw = mean(lows);
  r.mtl = (r.mhw + r.mlw) / 2;
  r.dtl = (r.mhhw + r.mllw) / 2;
  r.mn = r.mhw - r.mlw;
  r.gt = r.mhhw - r.mllw;
  summary.writeln('[station ${s.code}] ${s.name}');
  summary.writeln(
    'record first=${datetime(p, first * 60)} last=${datetime(p, last * 60)} length=${last - first} usable=${times.length}',
  );
  summary.writeln(
    'fit constituents=${selected.length} unknowns=$unknowns dof=$dof mean_level=${format(model.coefficients[0], 4)}',
  );
  summary.writeln(
    'residual rms=${format(sqrt(ss / times.length), 4)} max_abs=${format(maxAbs, 4)} explained_percent=${format(100 * (1 - ss / total), 4)} lag1_autocorrelation=${format(lagN / lagD, 4)}',
  );
  final top = List.of(times)
    ..sort((a, b) {
      final d = r.residual[b]!.abs().compareTo(r.residual[a]!.abs());
      return d != 0 ? d : a.compareTo(b);
    });
  for (var i = 0; i < p.top; i++) {
    final t = top[i];
    summary.writeln(
      'top_residual rank=${i + 1} time=${datetime(p, t * 60)} observed=${format(s.values[t]!, 3)} fitted=${format(predict(model, c, t.toDouble()), 4)} residual=${format(r.residual[t]!, 4)}',
    );
  }
  final mid = first + (last - first) ~/ 2,
      train = [
        for (final t in times)
          if (t <= first + (last - first) ~/ 2) t,
      ],
      test = [
        for (final t in times)
          if (t > first + (last - first) ~/ 2) t,
      ];
  final (validationSelected, _) = selectConstituents(
    train.last - train.first,
    c,
    p.rayleigh,
  );
  final validation = fit(train, s.values, validationSelected, c);
  var valSS = 0.0, inSS = 0.0, testMean = 0.0;
  for (final t in test) {
    final e = s.values[t]! - predict(validation, c, t.toDouble());
    valSS += e * e;
    inSS += r.residual[t]! * r.residual[t]!;
    testMean += s.values[t]!;
  }
  testMean /= test.length;
  var testTotal = 0.0;
  for (final t in test) {
    final d = s.values[t]! - testMean;
    testTotal += d * d;
  }
  summary.writeln(
    'validation split=${datetime(p, mid * 60)} train=${train.length} test=${test.length} constituents=${validationSelected.length} rms=${format(sqrt(valSS / test.length), 4)} in_sample_rms=${format(sqrt(inSS / test.length), 4)} skill=${format(1 - valSS / testTotal, 4)}',
  );
  final m2 = r.harmonics['M2']!,
      s2h = r.harmonics['S2']!,
      k1 = r.harmonics['K1']!,
      o1 = r.harmonics['O1']!,
      m4 = r.harmonics['M4']!;
  final form = (k1.amp + o1.amp) / (m2.amp + s2h.amp),
      kind = form < 0.25
          ? 'semidiurnal'
          : form < 1.5
          ? 'mixed_semidiurnal'
          : form < 3
          ? 'mixed_diurnal'
          : 'diurnal';
  summary.writeln('form_number=${format(form, 4)} type=$kind');
  summary.writeln(
    'ranges spring=${format(2 * (m2.amp + s2h.amp), 3)} neap=${format(2 * (m2.amp - s2h.amp), 3)} mn=${format(r.mn, 3)} gt=${format(r.gt, 3)}',
  );
  final rise = <double>[], fall = <double>[];
  for (var i = 1; i < ext.length; i++) {
    if (!ext[i - 1].high && ext[i].high)
      rise.add((ext[i].minute - ext[i - 1].minute).toDouble());
    if (ext[i - 1].high && !ext[i].high)
      fall.add((ext[i].minute - ext[i - 1].minute).toDouble());
  }
  var phase = 2 * m2.phase - m4.phase;
  while (phase < 0) {
    phase += 360;
  }
  while (phase >= 360) {
    phase -= 360;
  }
  summary.writeln(
    'asymmetry rise_minutes=${format(mean(rise), 1)} fall_minutes=${format(mean(fall), 1)} m4_m2_ratio=${format(m4.amp / m2.amp, 4)} relative_phase=${format(phase, 2)} dominance=${phase < 180 ? 'flood' : 'ebb'}',
  );
  summary.writeln(
    'datums mhhw=${format(r.mhhw, 3)} mhw=${format(r.mhw, 3)} mtl=${format(r.mtl, 3)} dtl=${format(r.dtl, 3)} mlw=${format(r.mlw, 3)} mllw=${format(r.mllw, 3)}',
  );
  var ampSum = 0.0;
  for (final i in selected) {
    ampSum += byIndex[i]!.amp;
  }
  summary.writeln(
    'bounds hat=${format(model.coefficients[0] + ampSum, 3)} lat=${format(model.coefficients[0] - ampSum, 3)}',
  );
  var highest = -1, lowest = -1;
  for (var i = 0; i < ext.length; i++) {
    final e = ext[i];
    if (e.high && (highest < 0 || e.height > ext[highest].height)) highest = i;
    if (!e.high && (lowest < 0 || e.height < ext[lowest].height)) lowest = i;
  }
  summary.writeln(
    'window high_waters=${highs.length} low_waters=${lows.length} highest=${format(ext[highest].height, 3)} highest_time=${datetime(p, ext[highest].minute)} lowest=${format(ext[lowest].height, 3)} lowest_time=${datetime(p, ext[lowest].minute)}',
  );
  var widest = -1, narrowest = -1;
  for (var i = 0; i < r.days.length; i++) {
    final d = r.days[i];
    if (d.high == null || d.low == null) continue;
    if (widest < 0 ||
        d.high! - d.low! > r.days[widest].high! - r.days[widest].low!)
      widest = i;
    if (narrowest < 0 ||
        d.high! - d.low! < r.days[narrowest].high! - r.days[narrowest].low!)
      narrowest = i;
  }
  summary.writeln(
    'daily_range widest=${format(r.days[widest].high! - r.days[widest].low!, 3)} widest_date=${date(p, r.days[widest].hour)} narrowest=${format(r.days[narrowest].high! - r.days[narrowest].low!, 3)} narrowest_date=${date(p, r.days[narrowest].hour)}',
  );
  var above = 0, below = 0;
  for (final v in r.predictions) {
    if (v > r.mhhw) above++;
    if (v < r.mllw) below++;
  }
  summary.writeln(
    'exceedance above_mhhw=${format(100 * above / (p.hours + 1), 2)} below_mllw=${format(100 * below / (p.hours + 1), 2)}',
  );
  final dw =
          c.firstWhere((v) => v.name == 'S2').speed -
          c.firstWhere((v) => v.name == 'M2').speed,
      dg = s2h.phase - m2.phase;
  final a = (dw * p.start - dg) / 180,
      b = (dw * (p.start + p.hours) - dg) / 180;
  for (var q = min(a, b).ceil(); q <= max(a, b).floor(); q++) {
    final t = (dg + 180 * q) / dw;
    if (t < p.start || t > p.start + p.hours) continue;
    summary.writeln(
      '${q.isEven ? 'spring' : 'neap'} time=${datetime(p, (t * 60 + 0.5).floor())}',
    );
  }
  final events = <(int, int, int, int)>[];
  int sign(int t) => r.residual[t]! > p.surge
      ? 1
      : r.residual[t]! < -p.surge
      ? -1
      : 0;
  for (var i = 0; i < times.length;) {
    final t = times[i], sg = sign(times[i]);
    if (sg == 0) {
      i++;
      continue;
    }
    var j = i, peak = t;
    while (j + 1 < times.length &&
        times[j + 1] == times[j] + 1 &&
        sign(times[j + 1]) == sg) {
      j++;
      if ((sg == 1 && r.residual[times[j]]! > r.residual[peak]!) ||
          (sg == -1 && r.residual[times[j]]! < r.residual[peak]!))
        peak = times[j];
    }
    if (j - i + 1 >= p.surgeHours) events.add((t, times[j], peak, sg));
    i = j + 1;
  }
  summary.writeln(
    'surges count=${events.length} threshold=${format(p.surge, 3)} min_hours=${p.surgeHours}',
  );
  for (final (a, b, peak, sg) in events) {
    summary.writeln(
      'surge type=${sg > 0 ? 'positive' : 'negative'} start=${datetime(p, a * 60)} end=${datetime(p, b * 60)} hours=${b - a + 1} peak=${format(r.residual[peak]!, 4)} peak_time=${datetime(p, peak * 60)}',
    );
  }
  final weights = [0, 2, 1, 1, 2, 0, 1, 1, 0, 2, 0, 1, 1, 0, 1, 0, 0, 1, 0, 1],
      daily = <DailyMean>[];
  for (var day = first ~/ 24 * 24; day <= last; day += 24) {
    final noon = day + 12;
    if (noon - 19 < first || noon + 19 > last) continue;
    var sum = 0.0, filled = 0;
    for (var j = -19; j <= 19; j++) {
      final t = noon + j;
      var v = s.values[t] ?? 0;
      if (reason.containsKey(t)) {
        v = predict(model, c, t.toDouble());
        filled++;
      }
      sum += weights[j.abs()] * v;
    }
    daily.add(DailyMean(day, filled, sum / 30));
  }
  var xm = 0.0, vm = 0.0, imax = 0, imin = 0;
  for (var i = 0; i < daily.length; i++) {
    final d = daily[i];
    xm += (d.hour - daily[0].hour) / 24;
    vm += d.level;
    if (d.level > daily[imax].level) imax = i;
    if (d.level < daily[imin].level) imin = i;
  }
  xm /= daily.length;
  vm /= daily.length;
  var sxy = 0.0, sxx = 0.0;
  for (final d in daily) {
    final x = (d.hour - daily[0].hour) / 24 - xm;
    sxy += x * (d.level - vm);
    sxx += x * x;
  }
  summary.writeln(
    'daily_mean days=${daily.length} average=${format(vm, 4)} slope_mm_per_day=${format(1000 * (sxy / sxx), 3)} max=${format(daily[imax].level, 4)} max_date=${date(p, daily[imax].hour)} min=${format(daily[imin].level, 4)} min_date=${date(p, daily[imin].hour)}',
  );
  for (final d in daily) {
    summary.writeln(
      'daily_mean date=${date(p, d.hour)} level=${format(d.level, 4)} filled=${d.filled}',
    );
  }
  return r;
}

double lagMean(Result a, Result b, bool high) {
  final differences = <double>[];
  for (final e in a.extremes) {
    if (e.high != high) continue;
    var best = -1;
    for (var i = 0; i < b.extremes.length; i++) {
      final f = b.extremes[i];
      if (f.high == high &&
          (best < 0 ||
              (e.minute - f.minute).abs() <
                  (e.minute - b.extremes[best].minute).abs()))
        best = i;
    }
    differences.add((e.minute - b.extremes[best].minute).toDouble());
  }
  return mean(differences);
}

(double, int) correlation(Result a, Result b, int lag) {
  final x = <double>[], y = <double>[];
  for (final t in a.times) {
    final v = b.residual[t + lag];
    if (v != null) {
      x.add(a.residual[t]!);
      y.add(v);
    }
  }
  final mx = mean(x), my = mean(y);
  var sxy = 0.0, sxx = 0.0, syy = 0.0;
  for (var i = 0; i < x.length; i++) {
    final dx = x[i] - mx, dy = y[i] - my;
    sxy += dx * dy;
    sxx += dx * dx;
    syy += dy * dy;
  }
  return (sxy / sqrt(sxx * syy), x.length);
}

void main() {
  final (p, c, stations) = readInput();
  Directory('output').createSync(recursive: true);
  final cleaning = StringBuffer(),
      constants = StringBuffer(
        'station,constituent,speed,status,amplitude,phase,amplitude_error,phase_error,snr,significant\n',
      ),
      predictions = StringBuffer(),
      extremesOut = StringBuffer(),
      summary = StringBuffer(),
      results = <Result>[];
  var reference = 0, plot = 0;
  for (var i = 0; i < stations.length; i++) {
    final s = stations[i];
    results.add(
      processStation(s, c, p, cleaning, constants, extremesOut, summary),
    );
    if (s.code == p.reference) reference = i;
    if (s.code == p.plot) plot = i;
  }
  predictions.writeln(['time', ...stations.map((s) => s.code)].join(','));
  for (var i = 0; i <= p.hours; i++) {
    predictions.writeln(
      [
        datetime(p, (p.start + i) * 60),
        ...results.map((r) => format(r.predictions[i], 3)),
      ].join(','),
    );
  }
  summary.writeln('[comparison] reference=${p.reference}');
  final ref = results[reference];
  for (var i = 0; i < results.length; i++) {
    if (i == reference) continue;
    final r = results[i];
    summary.writeln(
      '${r.station.code} tide hw_lag_min=${format(lagMean(r, ref, true), 1)} lw_lag_min=${format(lagMean(r, ref, false), 1)} range_ratio=${format(r.gt / ref.gt, 4)} mtl_diff=${format(r.mtl - ref.mtl, 3)}',
    );
    for (final name in ['M2', 'S2', 'K1', 'O1']) {
      final h = r.harmonics[name]!, base = ref.harmonics[name]!;
      var phase = h.phase - base.phase;
      if (phase > 180) phase -= 360;
      if (phase <= -180) phase += 360;
      final speed = c.firstWhere((v) => v.name == name).speed;
      summary.writeln(
        '${r.station.code} $name amplitude_ratio=${format(h.amp / base.amp, 4)} phase_diff=${format(phase, 2)} time_lag_min=${format(phase / speed * 60, 1)}',
      );
    }
  }
  summary.writeln('[correlation] max_lag=${p.lag}');
  for (var i = 0; i < results.length; i++) {
    for (var j = i + 1; j < results.length; j++) {
      var bestLag = 0, bestPairs = 0, best = -double.maxFinite, lag0 = 0.0;
      for (var lag = -p.lag; lag <= p.lag; lag++) {
        final (rho, n) = correlation(results[i], results[j], lag);
        if (lag == 0) lag0 = rho;
        if (rho > best ||
            (rho == best &&
                (lag.abs() < bestLag.abs() ||
                    (lag.abs() == bestLag.abs() && lag < bestLag)))) {
          bestLag = lag;
          bestPairs = n;
          best = rho;
        }
      }
      summary.writeln(
        '${results[i].station.code}-${results[j].station.code} lag0=${format(lag0, 4)} best_lag=$bestLag best=${format(best, 4)} pairs=$bestPairs',
      );
    }
  }
  summary.writeln(
    '[plot] station=${p.plot} start=${datetime(p, p.start * 60)} hours=${p.plotWidth} step_cm=${p.zs}',
  );
  final r = results[plot], rows = (p.zt - p.zb) ~/ p.zs + 1;
  final cells = List.generate(rows, (_) => List.filled(p.plotWidth, ' '));
  final qz = ((p.zt - 100 * r.model.coefficients[0]) / p.zs + 0.5).floor();
  if (qz >= 0 && qz < rows) cells[qz] = List.filled(p.plotWidth, '-');
  final marks = List.filled(p.plotWidth, '');
  for (final e in r.extremes) {
    final col = (e.minute - 60 * p.start + 30) ~/ 60;
    if (col >= 0 && col < p.plotWidth) marks[col] = e.high ? 'H' : 'L';
  }
  for (var col = 0; col < p.plotWidth; col++) {
    final q = ((p.zt - 100 * r.predictions[col]) / p.zs + 0.5).floor();
    if (q < 0) {
      cells[0][col] = '^';
    } else if (q >= rows) {
      cells[rows - 1][col] = 'v';
    } else {
      cells[q][col] = marks[col].isEmpty ? '*' : marks[col];
    }
  }
  for (final s in plotLines(cells, p)) {
    summary.writeln(s);
  }
  writeLines('output/cleaning.txt', cleaning);
  writeLines('output/constituents.csv', constants);
  writeLines('output/predictions.csv', predictions);
  writeLines('output/extremes.txt', extremesOut);
  writeLines('output/summary.txt', summary);
}
