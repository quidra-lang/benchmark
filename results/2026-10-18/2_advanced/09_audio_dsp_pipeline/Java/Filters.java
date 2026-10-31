final class Filters {
    static Processed fir(long[] samples, long divisor, long[] taps) {
        ClipCounter clips = new ClipCounter(); long[] output = new long[samples.length];
        for (int n = 0; n < output.length; n++) { long total = 0; for (int k = 0; k < Math.min(taps.length, n + 1); k++) total += taps[k] * samples[n - k]; output[n] = clips.saturate(SignalMath.floorDiv(total, divisor)); } return new Processed(output, clips.count);
    }
    static Processed biquad(long[] samples, long[] coefficients) {
        long[] signal = samples; ClipCounter clips = new ClipCounter();
        for (int section = 0; section < coefficients.length; section += 5) {
            long u1 = 0, u2 = 0, v1 = 0, v2 = 0; long[] output = new long[signal.length];
            for (int j = 0; j < signal.length; j++) {
                long u = signal[j], value = coefficients[section] * u + coefficients[section + 1] * u1 + coefficients[section + 2] * u2 - coefficients[section + 3] * v1 - coefficients[section + 4] * v2;
                long v = clips.saturate(SignalMath.floorDiv(value, 16384)); output[j] = v; u2 = u1; u1 = u; v2 = v1; v1 = v;
            }
            signal = output;
        }
        return new Processed(signal, clips.count);
    }
    static long[] movingAverage(long[] samples, int width) {
        long[] output = new long[samples.length]; long total = 0;
        for (int j = 0; j < samples.length; j++) { total += samples[j]; if (j >= width) total -= samples[j - width]; output[j] = SignalMath.rdiv(total, width); } return output;
    }
    static Processed dcBlock(long[] samples, long numerator, long denominator) {
        ClipCounter clips = new ClipCounter(); long[] output = new long[samples.length]; long previousInput = 0, previousOutput = 0;
        for (int j = 0; j < samples.length; j++) { previousOutput = clips.saturate(samples[j] - previousInput + SignalMath.rdiv(numerator * previousOutput, denominator)); previousInput = samples[j]; output[j] = previousOutput; } return new Processed(output, clips.count);
    }
}
