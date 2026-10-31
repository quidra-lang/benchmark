import java.util.*;

final class Metar {
    static final List<Slot> MAIN_SLOTS = List.of(new Slot("modifier", false), new Slot("wind", false),
    new Slot("variation", false), new Slot("visibility", false), new Slot("rvr", true), new Slot("weather", true),
    new Slot("cloud", true), new Slot("temperature", false), new Slot("pressure", false), new Slot("noTrend", false));
    static Value test(Slot slot, String text) {
        return Groups.format(slot.kind(), text);
    }

    static boolean isTrend(Group g) {
        return g.text().equals("BECMG") || g.text().equals("TEMPO");
    }
    record Parts(List<Group> main, List<Group> trends, List<Group> remarks) {
    }

    static Parts split(List<Group> body) {
        int end = body.size();
        for (int i = 0;i<body.size();i++) if (body.get(i).text().equals("RMK")) {
            end = i;
            break;
        }
        int start = end;
        for (int i = 0;i<end;i++) if (isTrend(body.get(i))) {
            start = i;
            break;
        }
        return new Parts(body.subList(0, start), body.subList(start, end),
        end<body.size()?body.subList(end + 1, body.size()):List.of());
    }

    static List<Change> trends(List<Group> body, ErrorSink error) {
        List<Change> result = new ArrayList<>();
        for (int i = 0;i<body.size();) {
            int end = i + 1;
            while (end<body.size() && !isTrend(body.get(end))) end++;
            Change c = new Change();
            c.kind = body.get(i).text();
            int cursor = i + 1;
            boolean invalid = false;
            while (cursor<end) {
                String[] m = Groups.match("(FM|TL|AT)(\\d{2})(\\d{2})", body.get(cursor).text());
                if (m == null || !c.times.isEmpty() && !(c.times.size() == 1 && c.times.get(0).kind().equals("FM") && m[1].equals("TL"))) break;
                long h = Groups.number(m[2]), n = Groups.number(m[3]);
                if (h>23 || n>59) {
                    error.add(body.get(cursor).position(), "invalid period", body.get(cursor).text());
                    invalid = true;
                    break;
                }
                c.times.add(new TrendTime(m[1], h, n));
                cursor++;
            }
            if (!invalid) {
                c.groups = body.subList(cursor, end);
                result.add(c);
            }
            i = end;
        }
        return result;
    }

    static void remarks(Report r, List<Group> body) {
        for (Group g:body) {
            String[] m = Groups.match("SLP(\\d{3})", g.text());
            if (m != null) {
                long n = Groups.number(m[1]);
                r.slp.add(n + (n >= 500?9000:10000));
                continue;
            }
            m = Groups.match("T([01])(\\d{3})([01])(\\d{3})", g.text());
            if (m != null) {
                Value v = new Value();
                v.temp = Groups.number(m[2]) * (m[1].equals("1")?-1:1);
                v.dew = Groups.number(m[4]) * (m[3].equals("1")?-1:1);
                r.precise.add(v);
            }
        }
    }
}
