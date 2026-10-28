part of 'main.dart';

class Peak {
  final int time, r, peakI, peakF, slope;
  int thresholdI = 0, thresholdF = 0;
  String? category;
  Peak(this.time, this.r, this.peakI, this.peakF, this.slope);
}

class Levels {
  int spki, npki, spkf, npkf;
  Levels(this.spki, this.npki, this.spkf, this.npkf);
  Levels copy() => Levels(spki, npki, spkf, npkf);
}

List<Peak> findPeaks(Signals s) {
  final peaks = <Peak>[];
  for (var time = 0; time < s.integrated.length; time++) {
    final value = s.integrated[time];
    if (value <= 0) continue;
    var valid = true;
    for (var j = math.max(0, time - 20); j < time; j++) {
      if (s.integrated[j] >= value) {
        valid = false;
        break;
      }
    }
    if (!valid) continue;
    for (var j = time + 1; j < math.min(s.integrated.length, time + 21); j++) {
      if (s.integrated[j] > value) {
        valid = false;
        break;
      }
    }
    if (!valid) continue;
    var r = math.max(0, time - 30), slope = 0;
    for (var j = r + 1; j <= time; j++) {
      if (s.bandpass[j].abs() > s.bandpass[r].abs()) r = j;
    }
    for (var j = math.max(0, time - 29); j <= time; j++) {
      slope = math.max(slope, s.derivative[j].abs());
    }
    peaks.add(Peak(time, r, value, s.bandpass[r].abs(), slope));
  }
  return peaks;
}

Levels initialLevels(Signals s) {
  final integrated = s.integrated.take(400).toList(),
      band = s.bandpass.take(400).map((v) => v.abs()).toList();
  return Levels(
    integrated.reduce(math.max) ~/ 3,
    sum(integrated) ~/ 800,
    band.reduce(math.max) ~/ 3,
    sum(band) ~/ 800,
  );
}

int widthMS(List<int> band, int r) {
  final peak = band[r].abs();
  int? first;
  var last = -1;
  for (var j = math.max(0, r - 25); j < math.min(band.length, r + 26); j++) {
    if (4 * band[j].abs() >= peak) {
      first ??= j;
      last = j;
    }
  }
  return 5 * (last - first! + 1);
}
