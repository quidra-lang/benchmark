import java.util.*;

record Fraction(long numerator, long denominator) {
    double value() {
        return (double)numerator / denominator;
    }
    public String toString() {
        long divisor = Metrics.gcd(numerator, denominator);
        return numerator / divisor + "/" + denominator / divisor + " " +
            Metrics.ratio(numerator, denominator);
    }
}
record RocPoint(double threshold, int tp, int fp) {}
record Confusion(int tp, int fp, int tn, int fn) {
    int correct() {
        return tp + tn;
    }
}
final class Metrics {
    static long gcd(long a, long b) {
        while (b != 0) {
            long old = b;
            b = a % b;
            a = old;
        }
        return a;
    }
    static String fixed(double value, int places) {
        String text = String.format(Locale.ROOT, "%." + places + "f", value);
        return text.startsWith("-") && Double.parseDouble(text) == 0 ? text.substring(1) : text;
    }
    static String ratio(long numerator, long denominator) {
        if (denominator == 0)
            return "-";
        long rounded = (20000 * numerator + denominator) / (2 * denominator);
        return rounded / 10000 + "." + String.format(Locale.ROOT, "%04d", rounded % 10000);
    }
    static Confusion confusion(double[] probabilities, int[] targets, double threshold) {
        int tp = 0, fp = 0, tn = 0, fn = 0;
        for (int i = 0; i < probabilities.length; i++) {
            if (probabilities[i] >= threshold) {
                if (targets[i] == 1)
                    tp++;
                else
                    fp++;
            } else if (targets[i] == 0)
                tn++;
            else
                fn++;
        }
        return new Confusion(tp, fp, tn, fn);
    }
    static List<Integer> order(double[] scores, boolean reverse) {
        List<Integer> order = new ArrayList<>();
        for (int i = 0; i < scores.length; i++)
            order.add(i);
        order.sort((a, b) -> {
            int compare = Double.compare(scores[a], scores[b]);
            if (reverse)
                compare = -compare;
            return compare != 0 ? compare : Integer.compare(a, b);
        });
        return order;
    }
    static Fraction auc(double[] scores, int[] targets) {
        List<Integer> order = order(scores, false);
        int positives = 0;
        for (int target : targets)
            positives += target;
        long ranks = 0;
        int start = 0;
        while (start < order.size()) {
            int end = start;
            while (end + 1 < order.size() && scores[order.get(end + 1)] == scores[order.get(start)])
                end++;
            for (int position = start; position <= end; position++)
                if (targets[order.get(position)] == 1)
                    ranks += start + end + 2;
            start = end + 1;
        }
        return new Fraction(ranks - (long)positives * (positives + 1),
                            2L * positives * (targets.length - positives));
    }
    static List<RocPoint> roc(double[] probabilities, int[] targets) {
        List<Integer> order = order(probabilities, true);
        List<RocPoint> points = new ArrayList<>();
        int tp = 0, fp = 0;
        for (int position = 0; position < order.size(); position++) {
            int i = order.get(position);
            if (targets[i] == 1)
                tp++;
            else
                fp++;
            if (position + 1 == order.size() || probabilities[order.get(position + 1)] != probabilities[i])
                points.add(new RocPoint(probabilities[i], tp, fp));
        }
        return points;
    }
}
