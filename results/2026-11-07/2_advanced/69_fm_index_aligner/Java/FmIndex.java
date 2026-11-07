import java.util.*;
final class FmIndex {
    record Interval(int lower, int upper) {
        boolean empty() { return lower >= upper; }
    }
    record Location(int position, int steps) {}
    int size, interval;
    String bwt;
    int[] c = new int[6], samples;
    int[][] checkpoints;
    int sampleCount;
    FmIndex(String text, int[] suffixes, int interval, int sampleInterval) {
        this.size = text.length();
        this.interval = interval;
        StringBuilder bwt = new StringBuilder();
        int[] frequencies = new int[6];
        for (int position : suffixes)
            bwt.append(text.charAt(position == 0 ? size - 1 : position - 1));
        this.bwt = bwt.toString();
        for (char value : text.toCharArray())
            frequencies[SuffixArray.SYMBOLS.indexOf(value)]++;
        int total = 0;
        for (int i = 0; i < 6; i++) {
            c[i] = total;
            total += frequencies[i];
        }
        checkpoints = new int[size / interval + 1][6];
        int[] counts = new int[6];
        for (int i = 0; i < size; i++) {
            counts[SuffixArray.SYMBOLS.indexOf(this.bwt.charAt(i))]++;
            if ((i + 1) % interval == 0)
                checkpoints[(i + 1) / interval] = counts.clone();
        }
        samples = new int[size];
        Arrays.fill(samples, -1);
        if (sampleInterval > 0)
            for (int row = 0; row < size; row++)
                if (suffixes[row] % sampleInterval == 0) {
                    samples[row] = suffixes[row];
                    sampleCount++;
                }
    }
    int occurrence(char symbol, int position) {
        int checkpoint = position / interval, start = checkpoint * interval;
        int count = checkpoints[checkpoint][SuffixArray.SYMBOLS.indexOf(symbol)];
        for (int i = start; i < position; i++)
            if (bwt.charAt(i) == symbol)
                count++;
        return count;
    }
    int lf(int row) {
        char symbol = bwt.charAt(row);
        return c[SuffixArray.SYMBOLS.indexOf(symbol)] + occurrence(symbol, row);
    }
    Interval extend(int lower, int upper, char base) {
        if (base == 'N')
            return new Interval(0, 0);
        int start = c[SuffixArray.SYMBOLS.indexOf(base)];
        return new Interval(start + occurrence(base, lower), start + occurrence(base, upper));
    }
    Location locate(int row) {
        int steps = 0;
        while (samples[row] < 0) {
            row = lf(row);
            steps++;
        }
        return new Location(samples[row] + steps, steps);
    }
    String inverse() {
        char[] result = new char[size];
        result[size - 1] = '$';
        int row = 0;
        for (int i = size - 2; i >= 0; i--) {
            result[i] = bwt.charAt(row);
            row = lf(row);
        }
        return new String(result);
    }
    Interval backward(String sequence) {
        Interval interval = new Interval(0, size);
        for (int i = sequence.length() - 1; i >= 0; i--) {
            interval = extend(interval.lower(), interval.upper(), sequence.charAt(i));
            if (interval.empty())
                break;
        }
        return interval;
    }
}
