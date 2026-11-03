part of 'main.dart';

int channelValue(Channel c) {
  if (!c.sounding) return 0;
  final level = waveValue(c.instrument!, c.mode, c.phase, c.register);
  c.phase += c.increment;
  if (c.phase >= 65536) {
    c.phase -= 65536;
    if (c.instrument!.wave == 'NOISE')
      c.register = clockRegister(c.register, c.mode);
  }
  return (2 * level - 15) * c.amplitude;
}

int mixTick(
  List<Channel> channels,
  int count,
  int gain,
  List<bool> muted,
  List<int> samples,
  List<List<int>> lanes,
) {
  var clipped = 0;
  for (var i = 0; i < count; i++) {
    var total = 0;
    for (var k = 0; k < channels.length; k++) {
      final value = channelValue(channels[k]);
      lanes[k].add(value);
      if (!muted[k]) total += value;
    }
    var sample = 128 + floorDiv(gain * total, 4096);
    if (sample < 0 || sample > 255) {
      clipped++;
      sample = clamp(sample, 0, 255);
    }
    samples.add(sample);
  }
  return clipped;
}

void fadeOut(List<int> samples, int fade) {
  final n = samples.length, length = math.min(samples.length, fade);
  for (var i = n - length; i < n; i++) {
    samples[i] = 128 + floorDiv((samples[i] - 128) * (n - 1 - i), length);
  }
}
