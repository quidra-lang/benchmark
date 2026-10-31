import java.util.*;

final class Verification {
    static final List<String> CATEGORIES = List.of("VFR", "MVFR", "IFR", "LIFR");
    static boolean covers(Report t, Report o) {
        long h = o.time - o.time % 60;
        return t.time <= o.time && t.start <= h && h<t.end;
    }

    static Report select(List<Report> tafs, Report o) {
        Report selected = null;
        for (Report t:tafs) if (covers(t, o) && (selected == null || t.time>selected.time || t.time == selected.time && t.number>selected.number)) selected = t;
        return selected;
    }
    record Choice(Report observation, Hour forecast, boolean temporaryHit) {
    }
    static final class Result {
        final long[][] table = new long[4][4], buckets = new long[5][2];
        final long[] rows = new long[4], columns = new long[4];
        long total, noForecast, hits, temporaryHits, expected;
        final List<Choice> choices = new ArrayList<>();
        String hitRate() {
            return Units.fraction(hits, total);
        }
        String temporaryRate() {
            return Units.fraction(temporaryHits, total);
        }
        String skill() {
            return Units.fraction(total * hits - expected, total * total - expected);
        }
        String pod(int i) {
            return Units.fraction(table[i][i], columns[i]);
        }
        String far(int i) {
            return Units.fraction(rows[i] - table[i][i], rows[i]);
        }
    }

    static Result analyze(List<Report> obs, List<Report> tafs) {
        Result a = new Result();
        for (Report o:obs) {
            long h = o.time - o.time % 60;
            String category = o.main.category;
            for (Report t:tafs) if (covers(t, o)) {
                int bucket = (int)((h - t.start) / 360);
                a.buckets[bucket][1]++;
                if (t.timeline.get(h).prevailing.category.equals(category)) a.buckets[bucket][0]++;
            }
            Report chosen = select(tafs, o);
            if (chosen == null) {
                a.noForecast++;
                continue;
            }
            Hour f = chosen.timeline.get(h);
            String fc = f.prevailing.category;
            boolean hit = fc.equals(category);
            boolean temporaryHit = hit || f.temporary.stream().anyMatch(t -> t.state().category.equals(category));
            a.table[CATEGORIES.indexOf(fc)][CATEGORIES.indexOf(category)]++;
            if (hit) a.hits++;
            if (temporaryHit) a.temporaryHits++;
            a.choices.add(new Choice(o, f, temporaryHit));
        }
        for (int i = 0;i<4;i++) for (int j = 0;j<4;j++) {
            a.rows[i] += a.table[i][j];
            a.columns[j] += a.table[i][j];
            a.total += a.table[i][j];
        }
        for (int i = 0;i<4;i++) a.expected += a.rows[i] * a.columns[i];
        return a;
    }
}
