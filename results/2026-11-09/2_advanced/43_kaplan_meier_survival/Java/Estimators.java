import java.util.*;

final class Estimators {
    static int risk(List<Dataset.Subject> subjects, int time) {
        int result = 0;
        for (Dataset.Subject s : subjects)
            if (s.time() >= time)
                result++;
        return result;
    }
    static List<Integer> eventTimes(List<Dataset.Subject> subjects, boolean reverse) {
        SortedSet<Integer> result = new TreeSet<>();
        for (Dataset.Subject s : subjects)
            if (s.event() == (reverse ? 0 : 1))
                result.add(s.time());
        return new ArrayList<>(result);
    }
    static final class Row {
        int time, risk, events, censored;
        double survival = 1, se, lower = Double.NaN, upper = Double.NaN, hazard, hazardSe;
    }
    static List<Row> km(List<Dataset.Subject> subjects, boolean reverse) {
        List<Integer> times = eventTimes(subjects, reverse);
        List<Row> result = new ArrayList<>();
        double survival = 1, greenwood = 0, hazard = 0, variance = 0;
        for (int i = 0; i < times.size(); i++) {
            int time = times.get(i), n = risk(subjects, time), d = 0, censored = 0;
            for (Dataset.Subject s : subjects) {
                int event = reverse ? 1 - s.event() : s.event();
                if (s.time() == time && event == 1)
                    d++;
                if (event == 0 && s.time() >= time && (i + 1 == times.size() || s.time() < times.get(i + 1)))
                    censored++;
            }
            survival *= (double)(n - d) / n;
            hazard += (double)d / n;
            variance += (double)d / (n * n);
            Row r = new Row();
            r.time = time;
            r.risk = n;
            r.events = d;
            r.censored = censored;
            r.survival = survival;
            r.hazard = hazard;
            r.hazardSe = Math.sqrt(variance);
            if (n == d) {
                greenwood = Double.NaN;
                r.se = Double.NaN;
            } else {
                greenwood += (double)d / (n * (n - d));
                r.se = survival * Math.sqrt(greenwood);
                double log = Math.log(survival), omega = Numerics.Z * Math.sqrt(greenwood) / (-log);
                r.lower = Math.exp(log * Math.exp(omega));
                r.upper = Math.exp(log * Math.exp(-omega));
            }
            result.add(r);
        }
        return result;
    }
    static Row at(List<Row> rows, int time) {
        Row result = new Row();
        for (Row r : rows) {
            if (r.time > time)
                break;
            result = r;
        }
        return result;
    }
    static final class Life {
        int start, end, risk, events, withdrawn, exposed2;
        double q, survival, se, hazard;
    }
    static List<Life> life(List<Dataset.Subject> subjects, int width, int count) {
        List<Life> result = new ArrayList<>();
        double survival = 1, greenwood = 0;
        for (int i = 0; i < count; i++) {
            Life r = new Life();
            r.start = i * width;
            r.end = (i + 1) * width;
            r.risk = risk(subjects, r.start);
            for (Dataset.Subject s : subjects)
                if (s.time() >= r.start && s.time() < r.end) {
                    if (s.event() == 1)
                        r.events++;
                    else
                        r.withdrawn++;
                }
            int f = 2 * r.risk - r.withdrawn;
            r.exposed2 = f;
            r.q = (double)(2 * r.events) / f;
            survival *= (double)(f - 2 * r.events) / f;
            greenwood += (double)(4 * r.events) / (f * (f - 2 * r.events));
            r.survival = survival;
            r.se = survival * Math.sqrt(greenwood);
            r.hazard = (double)(2000 * r.events) / (width * (f - r.events));
            result.add(r);
        }
        return result;
    }
}
