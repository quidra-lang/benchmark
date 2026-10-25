record Compressed(long[] samples, long minGain, long reduced) {}
final class Dynamics {
    static long[] envelope(long[] samples, long attack, long release) {
        long[] levels = new long[samples.length]; long level = 0;
        for (int j = 0; j < samples.length; j++) { long magnitude = Math.min(Math.abs(samples[j]), 32767), coefficient = magnitude > level ? attack : release; level += SignalMath.rdiv((magnitude - level) * coefficient, 32768); levels[j] = level; } return levels;
    }
    static Processed normalize(long[] samples, long target) {
        long peak = SignalMath.peak(samples); long[] output = samples.clone();
        if (peak > 0) for (int j = 0; j < samples.length; j++) output[j] = SignalMath.rdiv(samples[j] * target, peak); return new Processed(output, peak);
    }
    static Processed gate(long[] samples, long threshold, int hold) {
        long[] output = new long[samples.length]; int last = -20001; long muted = 0;
        for (int j = 0; j < samples.length; j++) { if (Math.abs(samples[j]) >= threshold) last = j; boolean open = j - last <= hold; output[j] = open ? samples[j] : 0; if (!open) muted++; } return new Processed(output, muted);
    }
    static Compressed compress(long[] samples, long threshold, long ratioNumerator, long ratioDenominator, long attack, long release) {
        long[] levels = envelope(samples, attack, release), output = new long[samples.length]; long gain = 32768, minimum = 32768, reduced = 0;
        for (int j = 0; j < samples.length; j++) {
            long e = levels[j], target = 32768;
            if (e > threshold) { long desired = threshold + SignalMath.rdiv((e - threshold) * ratioDenominator, ratioNumerator); target = SignalMath.rdiv(desired * 32768, e); }
            gain = target < gain ? target : gain + SignalMath.rdiv((target - gain) * release, 32768); minimum = Math.min(minimum, gain); if (gain < 32768) reduced++; output[j] = SignalMath.rdiv(samples[j] * gain, 32768);
        }
        return new Compressed(output, minimum, reduced);
    }
}
