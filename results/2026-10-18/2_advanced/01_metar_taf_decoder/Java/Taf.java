import java.util.*;

final class Taf {
    static final List<Slot> SLOTS = List.of(new Slot("wind", false), new Slot("visibility", false), new Slot("weather", true), new Slot("cloud", true));
    private static final Set<String> INDICATORS = Set.of("BECMG", "TEMPO", "PROB30", "PROB40");
    static boolean indicator(Group g) {
        return INDICATORS.contains(g.text()) || Groups.match("FM\\d{6}", g.text()) != null;
    }
    record Parts(List<Group> base, List<Change> changes) {
    }

    static Parts split(List<Group> body, Report r, Calendar calendar, ErrorSink error) {
        int i = 0;
        while (i<body.size() && !indicator(body.get(i))) i++;
        List<Group> base = body.subList(0, i);
        List<Change> changes = new ArrayList<>();
        while (i<body.size()) {
            Group g = body.get(i++);
            Change c = new Change();
            c.kind = g.text().startsWith("FM")?"FM":g.text();
            if ((c.kind.equals("PROB30") || c.kind.equals("PROB40")) && i<body.size() && body.get(i).text().equals("TEMPO")) {
                c.kind += " TEMPO";
                i++;
            }
            int end = i;
            while (end<body.size() && !indicator(body.get(end))) end++;
            if (c.kind.equals("FM")) {
                c.time = calendar.changeTime(g.text(), r.issueDay);
                if (c.time<r.start || c.time >= r.end) error.add(g.position(), "invalid period", g.text());
                else {
                    c.groups = body.subList(i, end);
                    changes.add(c);
                }
            } else if (i == end || Groups.match("\\d{4}/\\d{4}", body.get(i).text()) == null) {
                error.add(g.position(), "missing period", c.kind);
            } else {
                long[] period = calendar.period(body.get(i).text(), r.issueDay, 0);
                if (period == null || period[0]<r.start || period[1]>r.end) error.add(body.get(i).position(), "invalid period", body.get(i).text());
                else {
                    c.start = period[0];
                    c.end = period[1];
                    c.groups = body.subList(i + 1, end);
                    changes.add(c);
                }
            }
            i = end;
        }
        return new Parts(base, changes);
    }

    static Section state(Section s) {
        Section result = new Section();
        result.wind = s.wind;
        result.visibility = s.visibility;
        result.weather = s.weather;
        result.cloud = s.cloud;
        return result;
    }

    static Section overlay(Section s, Section c) {
        Section result = state(s);
        if (c.wind != null) result.wind = c.wind;
        if (c.visibility != null) result.visibility = c.visibility;
        if (c.weather != null) result.weather = c.weather;
        if (c.cloud != null) result.cloud = c.cloud;
        return result;
    }

    static void expand(Report r) {
        for (long h = r.start;h<r.end;h += 60) {
            Section p = state(r.base);
            for (Change c:r.changes) {
                if (c.kind.equals("FM") && c.time <= h) p = state(c.state);
                if (c.kind.equals("BECMG") && c.end <= h) p = overlay(p, c.state);
            }
            Main.derive(p);
            Hour hour = new Hour();
            hour.prevailing = p;
            for (Change c:r.changes) if (!c.kind.equals("FM") && !c.kind.equals("BECMG") && c.start <= h && h<c.end) {
                Section s = overlay(p, c.state);
                Main.derive(s);
                hour.temporary.add(new Temporary(c.kind, s));
            }
            r.timeline.put(h, hour);
        }
    }
}
