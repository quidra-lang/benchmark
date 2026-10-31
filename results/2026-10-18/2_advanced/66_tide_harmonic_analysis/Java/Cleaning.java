import java.util.*;
final class Cleaning {
    record Run(int first, int last, double value) {}
    record Spike(int time, double value, double residual, double median, double mad, double limit) {
    }
    record Gap(int first, int last, String cause) {}
    static final class Record {
        int first, last, numeric, tested;
        double prefitRms;
        double[] values = new double[10001];
        boolean[] candidate = new boolean[10001], usable = new boolean[10001];
        String[] reasons = new String[10001];
        List<Integer> candidates = new ArrayList<>(), times = new ArrayList<>();
        List<Run> runs = new ArrayList<>();
        List<Spike> spikes = new ArrayList<>();
        List<Gap> gaps = new ArrayList<>();
    }
    static double median(List<Double> values) {
        List<Double> sorted = new ArrayList<>(values);
        sorted.sort(Double::compare);
        int n = sorted.size();
        return n % 2 == 1 ? sorted.get(n / 2) : (sorted.get(n / 2 - 1) + sorted.get(n / 2)) / 2;
    }
    static Record prepare(Records.Station station, int minimumRun) {
        Record r = new Record();
        List<Integer> numeric = new ArrayList<>();
        for (var entry : station.values.entrySet())
            if (entry.getValue() != null) {
                numeric.add(entry.getKey());
                r.values[entry.getKey()] = entry.getValue() / 1000.0;
            }
        r.first = numeric.getFirst();
        r.last = numeric.getLast();
        r.numeric = numeric.size();
        for (int t = r.first; t <= r.last; t++) {
            if (!station.values.containsKey(t))
                r.reasons[t] = "absent";
            else if (station.values.get(t) == null)
                r.reasons[t] = "na";
        }
        int i = 0;
        while (i < numeric.size()) {
            int first = numeric.get(i), last = first;
            while (i + 1 < numeric.size() && numeric.get(i + 1) == last + 1 &&
                   station.values.get(numeric.get(i + 1)).equals(station.values.get(first))) {
                last = numeric.get(++i);
            }
            if (last - first + 1 >= minimumRun) {
                r.runs.add(new Run(first, last, r.values[first]));
                for (int t = first + 1; t <= last; t++)
                    r.reasons[t] = "flat";
            }
            i++;
        }
        for (int t : numeric)
            if (r.reasons[t] == null) {
                r.candidates.add(t);
                r.candidate[t] = true;
            }
        return r;
    }
    static void spikes(Record r, double[] residuals, Records.Settings s) {
        int width = s.integer("spike", 0), required = s.integer("spike", 1);
        for (int t : r.candidates) {
            List<Double> values = new ArrayList<>();
            for (int u = Math.max(r.first, t - width); u <= Math.min(r.last, t + width); u++)
                if (r.candidate[u])
                    values.add(residuals[u]);
            if (values.size() < required)
                continue;
            r.tested++;
            double center = median(values);
            List<Double> deviations = new ArrayList<>();
            for (double value : values)
                deviations.add(Math.abs(value - center));
            double mad = median(deviations),
                   limit = Math.max(s.real("spike", 2) * 1.4826 * mad, s.real("spike", 3));
            if (Math.abs(residuals[t] - center) > limit) {
                r.reasons[t] = "spike";
                r.spikes.add(new Spike(t, r.values[t], residuals[t], center, mad, limit));
            }
        }
        for (int t : r.candidates)
            if (r.reasons[t] == null) {
                r.usable[t] = true;
                r.times.add(t);
            }
        int t = r.first;
        while (t <= r.last) {
            if (r.reasons[t] == null) {
                t++;
                continue;
            }
            int first = t;
            String cause = r.reasons[t];
            while (t + 1 <= r.last && r.reasons[t + 1] != null) {
                t++;
                if (!cause.equals(r.reasons[t]))
                    cause = "mixed";
            }
            r.gaps.add(new Gap(first, t, cause));
            t++;
        }
    }
}
