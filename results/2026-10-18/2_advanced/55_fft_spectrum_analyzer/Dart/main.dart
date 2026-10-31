import 'dart:io';
import 'dart:math' hide pi;
part 'signal_io.dart';
part 'fft.dart';
part 'windows.dart';
part 'spectral.dart';
part 'report.dart';

double sum(List<double> v) {
  var s = 0.0;
  for (final x in v) {
    s += x;
  }
  return s;
}

double squares(List<double> v) {
  var s = 0.0;
  for (final x in v) {
    s += x * x;
  }
  return s;
}

double rms(List<double> v) => sqrt(squares(v) / v.length);
double log10(double v) => log(v) / ln10;
double db(double v) => 20 * log10(v);
int best(List<double> v, int lo, int hi) {
  var k = lo;
  for (var j = lo + 1; j <= hi; j++) {
    if (v[j] > v[k]) k = j;
  }
  return k;
}

int harmonicBin(List<double> a, double center, int d) {
  var k = -1;
  for (var j = 1; j + 1 < a.length; j++) {
    if ((j - center).abs() <= d && (k < 0 || a[j] > a[k])) k = j;
  }
  return k;
}

(List<double>, List<Object>) detrend(List<double> s, int fs) {
  final n = s.length, mu = sum(s) / n, center = (n - 1) / 2;
  var num = 0.0, den = 0.0, lo = s[0], hi = s[0];
  for (var i = 0; i < n; i++) {
    final t = i - center;
    num += t * (s[i] - mu);
    den += t * t;
    lo = min(lo, s[i]);
    hi = max(hi, s[i]);
  }
  final slope = num / den, d = List<double>.filled(n, 0);
  var peak = 0.0, cube = 0.0, four = 0.0;
  for (var i = 0; i < n; i++) {
    d[i] = s[i] - mu - slope * (i - center);
    peak = max(peak, d[i].abs());
    cube += d[i] * d[i] * d[i];
    four += d[i] * d[i] * d[i] * d[i];
  }
  final r = rms(d);
  return (
    d,
    [
      'mean',
      mu,
      'slope',
      slope * fs,
      'rms',
      r,
      'min',
      lo,
      'max',
      hi,
      'crest',
      peak / r,
      'skewness',
      cube / n / (r * r * r),
      'kurtosis',
      four / n / (r * r * r * r),
    ],
  );
}

double bandwidth(List<double> a, int k) {
  final limit = a[k] / sqrt(2);
  var left = 0.0, right = (a.length - 1).toDouble();
  for (var j = k + 1; j < a.length; j++) {
    if (a[j] <= limit) {
      right = j - 1 + (a[j - 1] - limit) / (a[j - 1] - a[j]);
      break;
    }
  }
  for (var j = k - 1; j >= 0; j--) {
    if (a[j] <= limit) {
      left = j + 1 - (a[j + 1] - limit) / (a[j + 1] - a[j]);
      break;
    }
  }
  return right - left;
}

(int, double) correlationLag(List<double> v, int limit) {
  final q = v.length;
  double at(int k) => v[k % q];
  var chosen = -limit;
  for (var lag = -limit + 1; lag <= limit; lag++) {
    final v1 = at(lag), v2 = at(chosen);
    if (v1 > v2 ||
        (v1 == v2 &&
            (lag.abs() < chosen.abs() ||
                (lag.abs() == chosen.abs() && lag < chosen))))
      chosen = lag;
  }
  final (position, _) = interpolate(
    [at(chosen - 1), at(chosen), at(chosen + 1)],
    1,
    false,
  );
  return (chosen, chosen + position - 1);
}

String check(double error) => error <= 1e-6 ? 'ok' : 'failed';
String yes(bool value) => value ? 'yes' : 'no';
void main() {
  final (fs, s1, s2, p) = readInput();
  final n = s1.length;
  final (x, stats1) = detrend(s1, fs);
  final (y, stats2) = detrend(s2, fs);
  final m = p.m, kmax = m ~/ 2;
  double frequency(int k) => k * fs / m;
  final w = window(p.mainWindow, m), fig = figures(w, fs);
  final (u, mainFFT, a) = amplitude(x, w);
  final amax = a[best(a, 0, kmax)],
      floor = median(a.sublist(1, kmax)),
      peaks = rankedPeaks(
        a,
        p.peakCount,
        (k) => db(a[k] / amax) >= p.threshold,
      ),
      positions = peaks.map((k) => interpolate(a, k, true).$1).toList(),
      wr = welch(x, y, fs, p.l, p.welchWindow),
      labels = <String>[];
  for (var rank = 0; rank < peaks.length; rank++) {
    final k = peaks[rank], q = positions[rank];
    var label = 'other';
    for (var h = 1; h <= 10; h++) {
      if ((q - h * p.fundamental * m / fs).abs() <= p.width) {
        label = 'h$h';
        break;
      }
    }
    if (label == 'other') {
      final fq = q * fs / m, j = (fq / p.notch + .5).floor();
      if (j >= 1 && (fq - j * p.notch).abs() <= p.notchWidth) label = 'mains';
    }
    if (label == 'other') {
      outer:
      for (var pr = 0; pr < peaks.length; pr++) {
        final kp = peaks[pr];
        if (pr == rank || a[kp] <= a[k]) continue;
        for (var rr = 0; rr < peaks.length; rr++) {
          final kr = peaks[rr];
          if (rr != rank &&
              rr != pr &&
              a[kp] > a[kr] &&
              (q + positions[rr] - 2 * positions[pr]).abs() <= 1) {
            label = 'sideband${pr + 1}';
            break outer;
          }
        }
      }
    }
    labels.add(label);
  }
  writeCSV('spectrum.csv', 'frequency,amplitude', [
    for (var k = 0; k < a.length; k++) [frequency(k), a[k]],
  ]);
  final peakLines = [
    fields([
      'length',
      m,
      'window',
      p.mainWindow,
      'resolution',
      fs / m,
      'threshold_db',
      p.threshold,
    ]),
    fields([
      'max_amplitude',
      amax,
      'noise_floor',
      floor,
      'noise_floor_db',
      db(floor),
    ]),
    fields(['peaks', peaks.length]),
  ];
  for (var rank = 0; rank < peaks.length; rank++) {
    final k = peaks[rank];
    final (q, v) = interpolate(a, k, true);
    peakLines.add(
      '${rank + 1} ${fields(['bin', k, 'frequency', frequency(k), 'refined', q * fs / m, 'amplitude', v, 'level_db', db(a[k] / amax), 'phase', mainFFT[k].phase * 180 / pi, 'bandwidth', bandwidth(a, k) * fs / m, 'snr_db', db(a[k] / floor), 'coherence', wr.coherence[(2 * k * p.l + m) ~/ (2 * m)], 'label', labels[rank]])}',
    );
  }
  writeLines('peaks.txt', peakLines);
  writeCSV('welch_psd.csv', 'frequency,psd_db', [
    for (var k = 0; k < wr.psd.length; k++)
      [k * fs / p.l, 10 * log10(wr.psd[k])],
  ]);
  final report = [
        '[signal]',
        fields(['sample_rate', fs, 'samples', n, 'duration', n / fs]),
        'channel=1 ${fields(stats1)}',
        'channel=2 ${fields(stats2)}',
        '[levels]',
      ],
      blocks = n ~/ p.block,
      levelLines = <String>[];
  var loudest = 0, maxRMS = -1.0;
  for (var g = 0; g < blocks; g++) {
    final lo = g * p.block,
        hi = (g + 1) * p.block,
        r1 = rms(x.sublist(lo, hi)),
        r2 = rms(y.sublist(lo, hi));
    var peak = 0.0;
    for (var i = lo; i < hi; i++) {
      peak = max(peak, x[i].abs());
    }
    if (r1 > maxRMS) {
      loudest = g;
      maxRMS = r1;
    }
    levelLines.add(
      fields([
        'block',
        g,
        'time',
        lo / fs,
        'rms1',
        r1,
        'rms2',
        r2,
        'peak1',
        peak,
      ]),
    );
  }
  report.add(
    fields(['block_length', p.block, 'blocks', blocks, 'loudest', loudest]),
  );
  report.addAll(levelLines);
  report.add('[windows]');
  for (final name in windowNames) {
    final ww = window(name, m), f = figures(ww, fs);
    final (_, _, aw) = amplitude(x, ww);
    final kb = harmonicBin(aw, p.fundamental * m / fs, p.width);
    final (_, av) = interpolate(aw, kb, true);
    report.add(
      fields([
        'name',
        name,
        'coherent_gain',
        f.gain,
        'enbw_bins',
        f.enbw,
        'enbw_hz',
        f.hz,
        'scalloping_db',
        f.scalloping,
        'fundamental_bin',
        kb,
        'bin_amplitude',
        aw[kb],
        'refined_amplitude',
        av,
        'floor_db',
        db(median(aw.sublist(1, kmax))),
      ]),
    );
  }
  final harmonicBins = <int>[],
      harmonicPositions = <double>[],
      harmonicValues = <double>[];
  for (var h = 1; h <= 10; h++) {
    final kh = harmonicBin(a, h * p.fundamental * m / fs, p.width);
    final (q, v) = interpolate(a, kh, true);
    harmonicBins.add(kh);
    harmonicPositions.add(q);
    harmonicValues.add(v);
  }
  final pw = List.filled(a.length, 0.0);
  var power = 0.0, weighted = 0.0, logPower = 0.0, fundamentalPower = 0.0;
  for (var k = 1; k < kmax; k++) {
    pw[k] = a[k] * a[k] / 2;
    power += pw[k];
    weighted += frequency(k) * pw[k];
    logPower += log(pw[k]);
    if ((k - harmonicBins[0]).abs() <= p.width) fundamentalPower += pw[k];
  }
  final ptot = power / fig.enbw,
      p1 = fundamentalPower / fig.enbw,
      centroid = weighted / power;
  var spread = 0.0, run = 0.0, rolloff = 0.0, rolled = false;
  for (var k = 1; k < kmax; k++) {
    final d = frequency(k) - centroid;
    spread += d * d * pw[k];
    run += pw[k];
    if (!rolled && run >= .85 * power) {
      rolloff = frequency(k);
      rolled = true;
    }
  }
  final method = pow2(m) == m ? 'radix2' : 'bluestein',
      size = pow2(m) == m ? m : pow2(2 * m - 1);
  report.addAll([
    '[main]',
    fields([
      'length',
      m,
      'window',
      p.mainWindow,
      'method',
      method,
      'transform_size',
      size,
      'resolution',
      fs / m,
    ]),
    fields([
      'total_power',
      ptot,
      'centroid',
      centroid,
      'spread',
      sqrt(spread / power),
      'rolloff',
      rolloff,
      'flatness_db',
      10 * log10(exp(logPower / (kmax - 1)) / (power / (kmax - 1))),
    ]),
    '[bands]',
  ]);
  final bands = p.bands;
  for (var eta = 0; eta + 1 < bands.length; eta++) {
    var s = 0.0;
    for (var k = 1; k < kmax; k++) {
      if (bands[eta] * m <= k * fs && k * fs < bands[eta + 1] * m) s += pw[k];
    }
    s /= fig.enbw;
    report.add(
      fields([
        'range',
        '${bands[eta]}-${bands[eta + 1]}',
        'power',
        s,
        'percent',
        100 * s / ptot,
      ]),
    );
  }
  report.add('[third_octave]');
  for (var b = p.t1; b <= p.t2; b++) {
    final center = 1000 * pow(2, b / 3),
        lo = 1000 * pow(2, (2 * b - 1) / 6),
        hi = 1000 * pow(2, (2 * b + 1) / 6);
    var count = 0, s = 0.0;
    for (var k = 1; k < kmax; k++) {
      if (lo <= frequency(k) && frequency(k) < hi) {
        count++;
        s += pw[k];
      }
    }
    report.add(
      fields([
        'band',
        b,
        'center',
        center.toDouble(),
        'lower',
        lo.toDouble(),
        'upper',
        hi.toDouble(),
        'bins',
        count,
        'level_db',
        10 * log10(s / fig.enbw),
      ]),
    );
  }
  report.addAll([
    '[harmonics]',
    fields(['fundamental', p.fundamental, 'search', p.width]),
  ]);
  var n3 = 0;
  for (var h = 1; h <= 10; h++) {
    final level = db(harmonicValues[h - 1] / harmonicValues[0]);
    if (h >= 3 && level >= -30) n3++;
    report.add(
      fields([
        'h',
        h,
        'target',
        h * p.fundamental,
        'bin',
        harmonicBins[h - 1],
        'refined',
        harmonicPositions[h - 1] * fs / m,
        'amplitude',
        harmonicValues[h - 1],
        'level_db',
        level,
      ]),
    );
  }
  final thd = sqrt(squares(harmonicValues.sublist(1))) / harmonicValues[0],
      thdn = sqrt((ptot - p1) / p1);
  report.addAll([
    fields(['thd_percent', 100 * thd, 'thd_db', db(thd)]),
    fields(['thdn_percent', 100 * thdn, 'thdn_db', db(thdn)]),
  ]);
  final (frames, packingError) = frameTransforms(
    x,
    window(p.spectrogramWindow, p.f),
    p.hop,
  );
  final nt = frames.length,
      g = frames.map((f) => f.map((z) => z.magnitude).toList()).toList();
  var gmax = 0.0;
  for (final frame in g) {
    for (final v in frame) {
      gmax = max(gmax, v);
    }
  }
  final flux = List.filled(nt, 0.0);
  for (var t = 1; t < nt; t++) {
    for (var k = 0; k < g[t].length; k++) {
      flux[t] += max(0.0, g[t][k] - g[t - 1][k]);
    }
  }
  final theta = p.onset * median(flux.sublist(1)), onsets = <int>[];
  for (var t = 1; t < nt; t++) {
    if (flux[t] > theta &&
        flux[t] > flux[t - 1] &&
        (t == nt - 1 || flux[t] > flux[t + 1]))
      onsets.add(t);
  }
  final kappa = List.filled(p.f ~/ 2 + 1, 0.0);
  for (var k = 0; k < kappa.length; k++) {
    var s2 = 0.0, s4 = 0.0;
    for (var t = 0; t < nt; t++) {
      final v = g[t][k];
      s2 += v * v;
      s4 += v * v * v * v;
    }
    kappa[k] = nt * s4 / (s2 * s2) - 2;
  }
  final kk = best(kappa, 1, p.f ~/ 2 - 1),
      sg = [
        fields([
          'frames',
          nt,
          'bins',
          p.f ~/ 2 + 1,
          'frame_length',
          p.f,
          'hop',
          p.hop,
          'window',
          p.spectrogramWindow,
          'band_db',
          p.shadeBand,
          'max_db',
          db(gmax),
        ]),
        ...shadeLines(g, fs, p.f, p.shadeBand, gmax),
        'track',
      ];
  for (var t = 0; t < nt; t++) {
    final kd = best(g[t], 1, p.f ~/ 2 - 1);
    sg.add(
      fields([
        'frame',
        t,
        'time',
        t * p.hop / fs,
        'frequency',
        kd * fs / p.f,
        'level_db',
        db(g[t][kd] / gmax),
      ]),
    );
  }
  sg.add(fields(['onsets', onsets.length, 'threshold', theta]));
  for (final t in onsets) {
    sg.add(fields(['frame', t, 'time', t * p.hop / fs, 'flux', flux[t]]));
  }
  sg.add(
    'kurtosis ${fields(['bin', kk, 'frequency', kk * fs / p.f, 'value', kappa[kk]])}',
  );
  writeLines('spectrogram.txt', sg);
  final xf = transform(realComplex(x, n)),
      bp = zeros(n),
      nf = zeros(n),
      ze = zeros(n);
  var kept = 0, removed = 0;
  for (var k = 0; k < n; k++) {
    final gk = min(k, n - k) * fs, z = xf[k];
    if (p.b1 * n <= gk && gk <= p.b2 * n) {
      bp[k] = z;
      kept++;
    }
    final jk = (2 * gk + p.notch * n) ~/ (2 * p.notch * n);
    if (jk >= 1 && (gk - jk * p.notch * n).abs() <= p.notchWidth * n) {
      removed++;
    } else {
      nf[k] = z;
    }
    if (k >= 1 && k <= (n - 1) ~/ 2 && p.e1 * n <= k * fs && k * fs <= p.e2 * n)
      ze[k] = z.scale(2);
  }
  final bandpassed = realParts(transform(bp, true)),
      notched = realParts(transform(nf, true)),
      analytic = transform(ze, true),
      envelope = analytic.map((z) => z.magnitude).toList(),
      em = sum(envelope) / n,
      centered = envelope.map((v) => v - em).toList(),
      ev = transform(realComplex(centered, n)),
      be = ev.map((z) => 2 * z.magnitude / n).toList(),
      ke = best(be, 1, (p.e2 - p.e1) * n ~/ (2 * fs));
  final (qe, envAmplitude) = interpolate(be, ke, true);
  final depth = envAmplitude / em, nu = List.filled(n - 1, 0.0);
  for (var i = 1; i < n; i++) {
    var dp = analytic[i].phase - analytic[i - 1].phase;
    if (dp <= -pi) dp += 2 * pi;
    if (dp > pi) dp -= 2 * pi;
    nu[i - 1] = dp * fs / (2 * pi);
  }
  final nuMean = sum(nu) / (n - 1);
  var nuVar = 0.0;
  for (final v in nu) {
    nuVar += (v - nuMean) * (v - nuMean);
  }
  final h = p.fir, sm = convolution(y, h), dc = sum(h);
  var firGain = const Complex(0);
  for (var j = 0; j < h.length; j++) {
    firGain = firGain + rot(2 * pi * p.fundamental * j / fs).scale(h[j]);
  }
  writeCSV('filtered.csv', 'index,bandpass,notched,smoothed,envelope', [
    for (var i = 0; i < n; i++)
      [i, bandpassed[i], notched[i], sm[i], envelope[i]],
  ]);
  final lam1 = (fs + p.p2 - 1) ~/ p.p2, lam2 = fs ~/ p.p1;
  var hpsBin = -1, hpsMax = double.negativeInfinity;
  for (var k = 1; 5 * k <= kmax; k++) {
    if (p.p1 * m <= k * fs && k * fs <= p.p2 * m) {
      var s = 0.0;
      for (var r = 1; r <= 5; r++) {
        s += log(a[r * k]);
      }
      if (s > hpsMax) {
        hpsMax = s;
        hpsBin = k;
      }
    }
  }
  final q = pow2(2 * n - 1), bf = radix(realComplex(bandpassed, q));
  for (var k = 0; k < q; k++) {
    final v = bf[k].magnitude;
    bf[k] = Complex(v * v);
  }
  final rho = realParts(radix(bf, true)), lag = best(rho, lam1, lam2);
  final (tau, rhoStar) = interpolate(rho, lag, false);
  var crossings = 0;
  for (var i = 1; i < n; i++) {
    if (bandpassed[i - 1] < 0 && bandpassed[i] >= 0) crossings++;
  }
  report.addAll([
    '[pitch]',
    fields(['range', '${p.p1}-${p.p2}', 'lags', '$lam1-$lam2']),
    'hps ${fields(['bin', hpsBin, 'order', 5, 'frequency', frequency(hpsBin)])}',
    'autocorrelation ${fields(['lag', lag, 'period', tau, 'frequency', fs / tau, 'strength', rhoStar / rho[0]])}',
    'zero_crossing ${fields(['count', crossings, 'frequency', crossings * fs / n])}',
    '[zoom]',
  ]);
  final dz = (p.z2 - p.z1) / (p.j - 1),
      zoomFFT = chirpZ(u, fs, p.z1, p.z2, p.j),
      zm = zoomFFT.map((z) => 2 * z.magnitude / fig.s1).toList();
  report.add(fields(['band', '${p.z1}-${p.z2}', 'points', p.j, 'step', dz]));
  final zoomPeaks = rankedPeaks(zm, 3);
  for (var rank = 0; rank < zoomPeaks.length; rank++) {
    final (qz, v) = interpolate(zm, zoomPeaks[rank], true);
    report.add(
      fields(['peak', rank + 1, 'frequency', p.z1 + qz * dz, 'amplitude', v]),
    );
  }
  final integrated = sum(wr.psd) * fs / p.l, variance = rms(x) * rms(x);
  report.addAll([
    '[welch]',
    fields([
      'segment_length',
      p.l,
      'segments',
      wr.segments,
      'window',
      p.welchWindow,
      'resolution',
      fs / p.l,
    ]),
    fields([
      'integrated_power',
      integrated,
      'variance',
      variance,
      'ratio',
      integrated / variance,
    ]),
  ]);
  final welchPeaks = rankedPeaks(wr.psd, 5);
  for (var rank = 0; rank < welchPeaks.length; rank++) {
    final k = welchPeaks[rank];
    report.add(
      fields([
        'peak',
        rank + 1,
        'frequency',
        k * fs / p.l,
        'psd_db',
        10 * log10(wr.psd[k]),
        'coherence',
        wr.coherence[k],
        'gain',
        wr.transfer[k].magnitude,
        'phase',
        wr.transfer[k].phase * 180 / pi,
      ]),
    );
  }
  report.addAll([
    '[filter]',
    fields([
      'bandpass',
      '${p.b1}-${p.b2}',
      'bins_kept',
      kept,
      'rms',
      rms(bandpassed),
      'energy_ratio',
      squares(bandpassed) / squares(x),
    ]),
    fields([
      'notch',
      p.notch,
      'width',
      p.notchWidth,
      'bins_removed',
      removed,
      'rms',
      rms(notched),
    ]),
    fields([
      'fir_taps',
      h.length,
      'dc_gain',
      dc,
      'gain_at_fundamental_db',
      db(firGain.magnitude),
      'rms',
      rms(sm.sublist(0, n)),
    ]),
    '[envelope]',
    fields([
      'band',
      '${p.e1}-${p.e2}',
      'mean',
      em,
      'bin',
      ke,
      'frequency',
      qe * fs / n,
      'amplitude',
      envAmplitude,
      'depth',
      depth,
    ]),
    'instantaneous_frequency ${fields(['mean', nuMean, 'std', sqrt(nuVar / (n - 1))])}',
  ]);
  final fx = radix(realComplex(x, q)),
      fy = radix(realComplex(y, q)),
      cxy = zeros(q),
      phat = zeros(q);
  for (var k = 0; k < q; k++) {
    cxy[k] = fx[k].conjugate * fy[k];
    phat[k] = cxy[k].scale(1 / cxy[k].magnitude);
  }
  final r = realParts(radix(cxy, true)), rp = realParts(radix(phat, true));
  final (ell, refined) = correlationLag(r, p.maxLag);
  final (plag, prefined) = correlationLag(rp, p.maxLag);
  report.addAll([
    '[correlation]',
    fields([
      'max_lag',
      p.maxLag,
      'lag',
      ell,
      'refined_lag',
      refined,
      'delay_ms',
      1000 * refined / fs,
      'coefficient',
      r[ell % q] / sqrt(squares(x) * squares(y)),
    ]),
    fields([
      'phat_lag',
      plag,
      'refined_lag',
      prefined,
      'delay_ms',
      1000 * prefined / fs,
    ]),
  ]);
  final back = transform(mainFFT, true);
  var inverseError = 0.0;
  for (var i = 0; i < m; i++) {
    inverseError = max(inverseError, (back[i] - Complex(u[i])).magnitude);
  }
  var fftEnergy = 0.0;
  for (final z in mainFFT) {
    final v = z.magnitude;
    fftEnergy += v * v;
  }
  final parseval = (squares(u) - fftEnergy / m).abs() / squares(u);
  var firError = 0.0;
  for (var i = 0; i < sm.length; i++) {
    var direct = 0.0;
    for (var j = 0; j < n; j++) {
      final hj = i - j;
      if (hj >= 0 && hj < h.length) direct += y[j] * h[hj];
    }
    firError = max(firError, (sm[i] - direct).abs());
  }
  var spotError = 0.0;
  for (final k in peaks) {
    var z = const Complex(0);
    for (var j = 0; j < m; j++) {
      z = z + rot(2 * pi * (k * j % m) / m).scale(u[j]);
    }
    spotError = max(spotError, (z - mainFFT[k]).magnitude);
  }
  report.addAll([
    '[checks]',
    fields(['inverse_roundtrip', check(inverseError)]),
    fields(['parseval', check(parseval)]),
    fields([
      'real_packing',
      check(max(wr.error, packingError)),
      'transforms',
      2 * wr.segments + nt,
    ]),
    fields(['fir_fft_vs_direct', check(firError)]),
    fields(['dft_spot_check', check(spotError), 'bins', peaks.length]),
    '[diagnosis]',
  ]);
  final ratio = harmonicValues[1] / harmonicValues[0];
  var electrical = false;
  Object electricalLevel = 'none';
  for (var rank = 0; rank < labels.length; rank++) {
    if (labels[rank] == 'mains') {
      final level = db(a[peaks[rank]] / amax);
      electrical = level >= -20;
      electricalLevel = level;
      break;
    }
  }
  var findings = 0;
  for (final v in [
    ratio >= .5,
    n3 >= 3,
    depth >= .2,
    electrical,
    onsets.isNotEmpty,
  ]) {
    if (v) findings++;
  }
  final status = findings == 0
      ? 'normal'
      : findings == 1
      ? 'warning'
      : 'alarm';
  report.addAll([
    fields(['misalignment', yes(ratio >= .5), 'ratio', ratio]),
    fields(['looseness', yes(n3 >= 3), 'harmonics', n3]),
    fields(['bearing', yes(depth >= .2), 'depth', depth]),
    fields(['electrical', yes(electrical), 'level_db', electricalLevel]),
    fields(['transient', yes(onsets.isNotEmpty), 'onsets', onsets.length]),
    fields(['status', status, 'findings', findings]),
  ]);
  writeLines('report.txt', report);
}
