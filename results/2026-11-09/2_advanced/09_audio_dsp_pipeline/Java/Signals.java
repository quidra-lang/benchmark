import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;

record Signal(String name, int rate, long[] samples, String origin, List<Signal> ingredients) {
    Signal { ingredients = List.copyOf(ingredients); }
}
record Processed(long[] samples, long count) {}
final class ClipCounter {
    long count;
    long saturate(long value) { long limited = Math.clamp(value, -32768, 32767); if (limited != value) count++; return limited; }
}
final class SignalMath {
    static long floorDiv(long numerator, long denominator) { return Math.floorDiv(numerator, denominator); }
    static long rdiv(long numerator, long denominator) { return floorDiv(2 * numerator + denominator, 2 * denominator); }
    static long peak(long[] samples) { long peak = 0; for (long sample : samples) peak = Math.max(peak, Math.abs(sample)); return peak; }
}
final class Signals {
    static List<Signal> read() throws IOException {
        List<String> lines = Files.readAllLines(Path.of("input/signals.txt")); List<Signal> signals = new ArrayList<>(); int index = 0;
        while (index < lines.size()) {
            String[] header = lines.get(index++).split(" "); int rate = Integer.parseInt(header[2]), count = Integer.parseInt(header[3]); long[] samples = new long[count]; int position = 0;
            while (position < count) for (String value : lines.get(index++).split(" ")) samples[position++] = Long.parseLong(value);
            signals.add(new Signal(header[1], rate, samples, "input", List.of()));
        }
        return signals;
    }
    static List<String> format(Signal signal) {
        List<String> lines = new ArrayList<>(List.of("SIGNAL " + signal.name() + " " + signal.rate() + " " + signal.samples().length));
        for (int start = 0; start < signal.samples().length; start += 16) lines.add(String.join(" ", Arrays.stream(signal.samples(), start, Math.min(start + 16, signal.samples().length)).mapToObj(Long::toString).toList())); return lines;
    }
    static long[] impulse(int count, int position, long amplitude) { long[] samples = new long[count]; samples[position] = amplitude; return samples; }
    static long[] step(int count, int position, long amplitude) { long[] samples = new long[count]; Arrays.fill(samples, position, count, amplitude); return samples; }
    static long[] noise(int count, long seed) {
        long[] samples = new long[count]; for (int j = 0; j < count; j++) { seed = 48271 * seed % 2147483647; samples[j] = seed % 65536 - 32768; } return samples;
    }
}
