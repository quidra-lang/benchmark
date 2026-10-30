using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
public sealed class FmIndex {
    public readonly record struct Interval(int lower, int upper) {
        public bool Empty() => lower >= upper;
    }
    public readonly record struct Location(int position, int steps);
    public int size, interval, sampleCount;
    public string bwt;
    public int[] c = new int[6], samples;
    public int[][] checkpoints;
    public FmIndex(string text, int[] suffixes, int interval, int sampleInterval) {
        size = text.Length;
        this.interval = interval;
        StringBuilder builder = new();
        int[] frequencies = new int[6];
        foreach (int position in suffixes)
            builder.Append(text[position == 0 ? size - 1 : position - 1]);
        bwt = builder.ToString();
        foreach (char symbol in text)
            frequencies[SuffixArray.SYMBOLS.IndexOf(symbol)]++;
        int total = 0;
        for (int i = 0; i < 6; i++) {
            c[i] = total;
            total += frequencies[i];
        }
        checkpoints = new int [size / interval + 1][];
        for (int i = 0; i < checkpoints.Length; i++)
            checkpoints[i] = new int[6];
        int[] counts = new int[6];
        for (int i = 0; i < size; i++) {
            counts[SuffixArray.SYMBOLS.IndexOf(bwt[i])]++;
            if ((i + 1) % interval == 0)
                checkpoints[(i + 1) / interval] = counts.ToArray();
        }
        samples = new int[size];
        Array.Fill(samples, -1);
        if (sampleInterval > 0)
            for (int row = 0; row < size; row++)
                if (suffixes[row] % sampleInterval == 0) {
                    samples[row] = suffixes[row];
                    sampleCount++;
                }
    }
    public int Occurrence(char symbol, int position) {
        int checkpoint = position / interval, start = checkpoint * interval,
            count = checkpoints[checkpoint][SuffixArray.SYMBOLS.IndexOf(symbol)];
        for (int i = start; i < position; i++)
            if (bwt[i] == symbol)
                count++;
        return count;
    }
    public int Lf(int row) {
        char symbol = bwt[row];
        return c[SuffixArray.SYMBOLS.IndexOf(symbol)] + Occurrence(symbol, row);
    }
    public Interval Extend(int lower, int upper, char b) {
        if (b == 'N')
            return new(0, 0);
        int start = c[SuffixArray.SYMBOLS.IndexOf(b)];
        return new(start + Occurrence(b, lower), start + Occurrence(b, upper));
    }
    public Location Locate(int row) {
        int steps = 0;
        while (samples[row] < 0) {
            row = Lf(row);
            steps++;
        }
        return new(samples[row] + steps, steps);
    }
    public string Inverse() {
        char[] result = new char[size];
        result[^1] = '$';
        int row = 0;
        for (int i = size - 2; i >= 0; i--) {
            result[i] = bwt[row];
            row = Lf(row);
        }
        return new string(result);
    }
    public Interval Backward(string sequence) {
        Interval range = new(0, size);
        for (int i = sequence.Length - 1; i >= 0; i--) {
            range = Extend(range.lower, range.upper, sequence[i]);
            if (range.Empty())
                break;
        }
        return range;
    }
}
