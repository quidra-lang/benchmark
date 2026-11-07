import java.util.ArrayList;
import java.util.List;

record Split(int below, long sumBelow, int above, long sumAbove) {}
record Candidate(int cutoff, Split split, long numerator, long denominator) {
    Candidate(int cutoff, Split split) {
        this(cutoff, split, split.sumBelow() * split.sumBelow() * split.above() + split.sumAbove() * split.sumAbove() * split.below(), (long) split.below() * split.above());
    }
}
record OtsuResult(int cutoff, int upper, List<Candidate> candidates) {}
record IsodataResult(int cutoff, int iterations) {}
final class Histogram {
    final int maxval, pixels, minimum, maximum, levels, median, mode, binWidth;
    final long total;
    final int[] counts, belowCounts, bins;
    final long[] belowSums;
    Histogram(Image image) {
        maxval = image.maxval(); pixels = image.width() * image.height(); counts = new int[maxval + 1];
        for (int[] row : image.pixels()) for (int value : row) counts[value]++;
        belowCounts = new int[counts.length]; belowSums = new long[counts.length];
        int count = 0, first = -1, last = -1, distinct = 0, middle = -1, most = 0; long sum = 0;
        for (int value = 0; value < counts.length; value++) {
            count += counts[value]; sum += (long) value * counts[value]; belowCounts[value] = count; belowSums[value] = sum;
            if (counts[value] > 0) { if (first < 0) first = value; last = value; distinct++; }
            if (middle < 0 && 2 * count >= pixels) middle = value;
            if (counts[value] > counts[most]) most = value;
        }
        total = sum; minimum = first; maximum = last; levels = distinct; median = middle; mode = most; binWidth = (maxval + 8) / 8;
        bins = new int[maxval / binWidth + 1];
        for (int value = 0; value <= maxval; value++) bins[value / binWidth] += counts[value];
    }
    Split split(int cutoff) { return new Split(belowCounts[cutoff], belowSums[cutoff], pixels - belowCounts[cutoff], total - belowSums[cutoff]); }
}
final class Threshold {
    static int compareScores(Candidate first, Candidate second) {
        long firstQ = first.numerator() / first.denominator(), secondQ = second.numerator() / second.denominator();
        if (firstQ != secondQ) return Long.compare(firstQ, secondQ);
        long left = (first.numerator() % first.denominator()) * second.denominator();
        long right = (second.numerator() % second.denominator()) * first.denominator();
        return Long.compare(left, right);
    }
    static OtsuResult otsu(Histogram histogram) {
        List<Candidate> candidates = new ArrayList<>();
        for (int cutoff = 0; cutoff < histogram.maxval; cutoff++) {
            Split split = histogram.split(cutoff);
            if (histogram.counts[cutoff] > 0 && split.above() > 0) candidates.add(new Candidate(cutoff, split));
        }
        candidates.sort((first, second) -> { int comparison = compareScores(second, first); return comparison != 0 ? comparison : Integer.compare(first.cutoff(), second.cutoff()); });
        if (candidates.isEmpty()) return new OtsuResult(histogram.minimum, histogram.minimum, candidates);
        int best = candidates.getFirst().cutoff(), following = best + 1;
        while (histogram.counts[following] == 0) following++;
        return new OtsuResult(best, following - 1, candidates);
    }
    static IsodataResult isodata(Histogram histogram) {
        int cutoff = (int) (histogram.total / histogram.pixels), iterations = 0;
        while (true) {
            Split split = histogram.split(cutoff);
            if (split.below() == 0 || split.above() == 0) break;
            int following = (int) ((split.sumBelow() * split.above() + split.sumAbove() * split.below()) / (2L * split.below() * split.above()));
            iterations++;
            if (following == cutoff) break;
            cutoff = following;
            if (iterations == 100) break;
        }
        return new IsodataResult(cutoff, iterations);
    }
}
