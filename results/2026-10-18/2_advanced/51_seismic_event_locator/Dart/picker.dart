part of 'main.dart';

class Pick {
  final Station station;
  final int sample, duration, amplitude;
  final double ratio;
  final bool clipped;
  bool assigned = false;
  String state = 'unassociated';
  int event = 0;
  double firstResidual = 0, residual = 0;
  double get time => sample / 100;
  Pick(
    this.station,
    this.sample,
    this.duration,
    this.ratio,
    this.amplitude,
    this.clipped,
  );
}

int floorDiv(int a, int b) => a ~/ b - (a < 0 && a % b != 0 ? 1 : 0);
List<Pick> detectStation(Station station, Params p) {
  final n = station.samples.length,
      total = station.samples.fold(0, (a, b) => a + b),
      mean = floorDiv(total, n);
  final d = [for (final v in station.samples) v - mean],
      energy = [for (final v in d) v * v],
      prefix = List.filled(n + 1, 0);
  for (var i = 0; i < n; i++) {
    prefix[i + 1] = prefix[i] + energy[i];
    station.peak = max(station.peak, d[i].abs());
    if (station.samples[i].abs() >= p.integer('clip_level')) {
      station.clippedSamples++;
    }
  }
  station.mean = mean;
  station.noise = median([for (final v in d) v.abs().toDouble()]);
  final sw = p.integer('sta_window'), lw = p.integer('lta_window');
  var on = false, beginning = 0, peakRatio = 0.0;
  void finish(int end) {
    station.triggers++;
    final duration = end - beginning;
    if (duration < p.integer('min_duration')) {
      station.shortTriggers++;
      return;
    }
    var position = beginning;
    while (position - 1 >= beginning - sw + 1 &&
        energy[position - 1] >= p.integer('noise_level')) {
      position--;
    }
    var amplitude = 0, clipped = false;
    for (
      var j = position;
      j < min(position + p.integer('amplitude_window'), n);
      j++
    ) {
      amplitude = max(amplitude, d[j].abs());
      if (station.samples[j].abs() >= p.integer('clip_level')) {
        clipped = true;
      }
    }
    station.picks.add(
      Pick(
        station,
        station.start + position,
        duration,
        peakRatio,
        amplitude,
        clipped,
      ),
    );
  }

  for (var i = sw + lw - 1; i < n; i++) {
    final sta = prefix[i + 1] - prefix[i - sw + 1],
        lta = prefix[i - sw + 1] - prefix[i - sw - lw + 1],
        numerator = sta * lw,
        denominator = lta * sw;
    if (!on) {
      if (numerator * p.integer('trigger_on', 1) >=
          p.integer('trigger_on') * denominator) {
        on = true;
        beginning = i;
        peakRatio = numerator / denominator;
      }
    } else if (numerator * p.integer('trigger_off', 1) <
        p.integer('trigger_off') * denominator) {
      finish(i);
      on = false;
    } else {
      peakRatio = max(peakRatio, numerator / denominator);
    }
  }
  if (on) {
    finish(n);
  }
  return station.picks;
}
