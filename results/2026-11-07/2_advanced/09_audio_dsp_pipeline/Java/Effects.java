import java.util.Arrays;
import java.util.List;

final class Effects {
    static Processed gain(long[] samples, long numerator, long denominator) {
        ClipCounter clips = new ClipCounter(); long[] output = new long[samples.length];
        for (int j = 0; j < samples.length; j++) output[j] = clips.saturate(SignalMath.rdiv(samples[j] * numerator, denominator)); return new Processed(output, clips.count);
    }
    static Processed mix(List<long[]> tracks, List<Long> weights, long denominator) {
        ClipCounter clips = new ClipCounter(); int length = tracks.stream().mapToInt(track -> track.length).max().orElseThrow(); long[] output = new long[length];
        for (int j = 0; j < length; j++) { long total = 0; for (int k = 0; k < tracks.size(); k++) if (j < tracks.get(k).length) total += weights.get(k) * tracks.get(k)[j]; output[j] = clips.saturate(SignalMath.rdiv(total, denominator)); } return new Processed(output, clips.count);
    }
    static long[] delay(long[] samples, int count) { long[] output = new long[samples.length + count]; System.arraycopy(samples, 0, output, count, samples.length); return output; }
    static Processed echo(long[] samples, int delay, long numerator, long denominator, int tail) {
        long[] output = Arrays.copyOf(samples, samples.length + tail); ClipCounter clips = new ClipCounter();
        for (int j = delay; j < output.length; j++) output[j] = clips.saturate(output[j] + SignalMath.rdiv(numerator * output[j - delay], denominator)); return new Processed(output, clips.count);
    }
    static long resampledLength(int length, int oldRate, int newRate) { return (length - 1L) * newRate / oldRate + 1; }
    static long[] resample(long[] samples, int oldRate, int newRate) {
        long[] output = new long[(int)resampledLength(samples.length, oldRate, newRate)];
        for (int j = 0; j < output.length; j++) { int position = j * oldRate / newRate, fraction = j * oldRate % newRate; long value = samples[position]; if (fraction > 0) value += SignalMath.rdiv((samples[position + 1] - value) * fraction, newRate); output[j] = value; } return output;
    }
    static long[] fade(long[] samples, int fadeIn, int fadeOut) {
        long[] output = samples.clone(); int length = samples.length;
        for (int j = 0; j < fadeIn; j++) output[j] = SignalMath.rdiv(output[j] * j, fadeIn);
        for (int j = length - fadeOut; j < length; j++) output[j] = SignalMath.rdiv(output[j] * (length - 1 - j), fadeOut); return output;
    }
}
