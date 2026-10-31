import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.*;

record Group(String text, int position) {
}

record Slot(String kind, boolean repeat) {
}

record Runway(String name, long heading) {
}

record TrendTime(String kind, long hour, long minute) {
}

record Temporary(String kind, Section state) {
}

record Component(long head, long cross) {
}

record RunwayWind(String name, Component mean, Component gust, boolean usable) {
}

record ParseError(int report, int position, String content) {
}

@FunctionalInterface interface ErrorSink {
    void add(int position, String reason, String text);
}

final class Station {
    String code, name;
    long elevation;
    List<Runway> runways = new ArrayList<>();
}

final class Value {
    String raw = "", kind = "", unit = "", qualifier = "", qualifier2 = "", runway = "", trend = "", amount = "", suffix = "", intensity = "", descriptor = "";
    long direction, speed, first, second, whole, num, meters, height, temp, dew, value, inches, hecto;
    long gust = -1, den = 1;
    boolean variable, calm, mixed, fractional, nsw, hasSecond;
    List<String> codes = new ArrayList<>();
}

final class Section {
    String context = "", category = "";
    Value modifier, wind, variation, visibility, temperature, pressure;
    List<Value> rvr = new ArrayList<>(), weather, cloud;
    boolean noTrend;
    long ceiling = -1;
}

final class Change {
    String kind;
    long time, start, end;
    List<Group> groups;
    List<TrendTime> times = new ArrayList<>();
    Section state;
}

final class Hour {
    Section prevailing;
    List<Temporary> temporary = new ArrayList<>();
}

final class Report {
    int number, bodyStart;
    String kind, modifier = "";
    Station station;
    long time, issueDay, start, end;
    Section main, base;
    List<Change> trends, changes;
    Map<Long, Hour> timeline = new LinkedHashMap<>();
    List<Long> slp = new ArrayList<>();
    List<Value> precise = new ArrayList<>();
    List<String> speciReasons;
    Long pressureAltitude, densityAltitude;
    List<RunwayWind> winds;
    String preferred = "none";
}

public class Main {
    static List<String> readLines(String name) throws IOException {
        return Files.readAllLines(Path.of("input", name), StandardCharsets.US_ASCII);
    }

    static ErrorSink recorder(List<ParseError> errors, int number) {
        return (position, reason, text) -> errors.add(new ParseError(number, position, reason + (text == null?"":" \""+text + "\"")));
    }

    static Report header(List<String> words, int number, Map<String, Station> stations, Calendar calendar, ErrorSink error) {
        String kind = words.get(0);
        if (!Set.of("METAR", "SPECI", "TAF").contains(kind)) {
            error.add(1, "rejected report, invalid type", kind);
            return null;
        }
        Report r = new Report();
        r.number = number;
        r.kind = kind;
        int i = 1;
        if (kind.equals("TAF") && i<words.size() && Set.of("AMD", "COR").contains(words.get(i))) r.modifier = words.get(i++);
        List<String> items = kind.equals("TAF")?List.of("station", "time", "validity"):List.of("station", "time");
        for (String item:items) {
            if (i == words.size()) {
                error.add(i + 1, "rejected report, missing "+item, null);
                return null;
            }
            String word = words.get(i);
            boolean ok = false;
            switch (item) {
                case "station": r.station = stations.get(word);
                ok = r.station != null;
                break;
                case "time": r.time = calendar.observation(word);
                ok = r.time >= 0;
                r.issueDay = r.time / 1440 + 1;
                break;
                case "validity":
                long[] period = calendar.period(word, r.issueDay, 1800);
                ok = period != null;
                if (ok) {
                    r.start = period[0];
                    r.end = period[1];
                }
                break;
            }
            if (!ok) {
                error.add(i + 1, "rejected report, invalid "+item, word);
                return null;
            }
            i++;
        }
        r.bodyStart = i;
        return r;
    }

    static List<Group> joinGroups(List<String> words, int start) {
        List<Group> result = new ArrayList<>();
        for (int i = start;i<words.size();i++) {
            int position = i + 1;
            String text = words.get(i);
            if (Groups.match("\\d", text) != null && i + 1<words.size() && Groups.match("\\d/\\d{1,2}SM", words.get(i + 1)) != null) text += " "+words.get(++i);
            result.add(new Group(text, position));
        }
        return result;
    }

    static Section matchSection(List<Group> body, List<Slot> slots, String context, Station station, ErrorSink error) {
        Section s = new Section();
        s.context = context;
        int current = 0;
        for (Group g:body) {
            int found = current;
            Value value = null;
            while (found<slots.size()) {
                value = Metar.test(slots.get(found), g.text());
                if (value != null) break;
                found++;
            }
            if (found == slots.size()) {
                String reason = "unknown group";
                for (int i = 0;i<current;i++) if (Metar.test(slots.get(i), g.text()) != null) {
                    reason = "out of order group";
                    break;
                }
                error.add(g.position(), reason, g.text());
                continue;
            }
            Slot slot = slots.get(found);
            if (!Groups.valid(slot.kind(), value, s, station)) {
                error.add(g.position(), "invalid group", g.text());
                continue;
            }
            Groups.accept(s, slot.kind(), value);
            current = found + (slot.repeat()?0:1);
            if (slot.kind().equals("visibility") && value.kind.equals("cavok")) {
                for (int i = 0;i<slots.size();i++) if (slots.get(i).kind().equals("cloud")) {
                    current = i + 1;
                    break;
                }
            }
        }
        return s;
    }

    static void derive(Section s) {
        s.ceiling = -1;
        if (s.cloud != null) for (Value cloud:s.cloud) if (Set.of("BKN", "OVC", "VV").contains(cloud.amount)) {
            s.ceiling = cloud.height;
            break;
        }
        long[] v = s.visibility == null?null:Units.miles(s.visibility);
        long c = s.ceiling;
        if (c >= 0 && c<500 || v != null && v[0]<v[1]) s.category = "LIFR";
        else if (c >= 0 && c<1000 || v != null && v[0]<3 * v[1]) s.category = "IFR";
        else if (c >= 0 && c <= 3000 || v != null && v[0] <= 5 * v[1]) s.category = "MVFR";
        else s.category = "VFR";
    }

    static Component components(long direction, long heading, long speed) {
        long angle = direction - heading;
        return new Component(Math.floorDiv(speed * Units.cos(angle), 1000), Math.floorDiv(speed * Units.sin(angle), 1000));
    }

    static void runwayWinds(Report r, long crosswind, long tailwind) {
        Value wind = r.main.wind;
        if (wind == null || wind.variable || wind.calm) return;
        r.winds = new ArrayList<>();
        long best = Long.MIN_VALUE;
        for (Runway runway:r.station.runways) {
            Component mean = components(wind.direction, runway.heading(), wind.speed);
            Component gust = wind.gust<0?null:components(wind.direction, runway.heading(), wind.gust);
            Component deciding = gust == null?mean:gust;
            boolean usable = Math.abs(deciding.cross()) <= crosswind && -deciding.head() <= tailwind;
            r.winds.add(new RunwayWind(runway.name(), mean, gust, usable));
            if (usable && mean.head()>best) {
                best = mean.head();
                r.preferred = runway.name();
            }
        }
    }

    static List<String> windChanges(Value a, Value b, long alpha) {
        List<String> reasons = new ArrayList<>();
        if (a == null || b == null) return reasons;
        if (!a.variable && !a.calm && !b.variable && !b.calm && Math.max(a.speed, b.speed) >= 10) {
            long d = Math.abs(a.direction - b.direction) % 360;
            if (Math.min(d, 360 - d) >= alpha) reasons.add("wind shift");
        }
        if (Math.abs(a.speed - b.speed) >= 10) reasons.add("wind speed");
        return reasons;
    }

    static boolean weatherFlag(Section s, boolean freezing) {
        if (s.weather == null) return false;
        return s.weather.stream().anyMatch(w -> freezing ? w.descriptor.equals("FZ") && (w.codes.contains("DZ") || w.codes.contains("RA")) : w.descriptor.equals("TS"));
    }

    static List<String> speciCheck(Report previous, Report r) {
        if (previous == null) return List.of("no previous report");
        Section a = previous.main, b = r.main;
        List<String> reasons = new ArrayList<>();
        if (!a.category.equals(b.category)) reasons.add("category "+a.category + " to "+b.category);
        reasons.addAll(windChanges(a.wind, b.wind, 45));
        for (boolean freezing:new boolean[]{
            false, true
        }) if (weatherFlag(a, freezing) != weatherFlag(b, freezing)) {
            reasons.add((freezing?"freezing precipitation":"thunderstorm") + " "+(weatherFlag(b, freezing)?"began":"ended"));
        }
        return reasons.isEmpty()?List.of("no criteria met"):reasons;
    }

    static void decodeObservation(Report r, List<Group> body, long crosswind, long tailwind, ErrorSink error) {
        Metar.Parts p = Metar.split(body);
        r.main = matchSection(p.main(), Metar.MAIN_SLOTS, "main", r.station, error);
        derive(r.main);
        r.trends = Metar.trends(p.trends(), error);
        for (Change trend:r.trends) trend.state = matchSection(trend.groups, Taf.SLOTS, "trend", r.station, error);
        Metar.remarks(r, p.remarks());
        if (r.main.pressure != null) {
            r.pressureAltitude = r.station.elevation + (2992 - r.main.pressure.inches) * 10;
            if (r.main.temperature != null) r.densityAltitude = r.pressureAltitude + Math.floorDiv(120 * (1000 * r.main.temperature.temp - 15000 + 2 * r.pressureAltitude), 1000);
        }
        runwayWinds(r, crosswind, tailwind);
    }

    static void decodeForecast(Report r, List<Group> body, Calendar c, ErrorSink error) {
        Taf.Parts parts = Taf.split(body, r, c, error);
        r.base = matchSection(parts.base(), Taf.SLOTS, "base", r.station, error);
        r.changes = parts.changes();
        for (Change change:r.changes) change.state = matchSection(change.groups, Taf.SLOTS, "change", r.station, error);
        Taf.expand(r);
    }

    static String windPhrase(Value w) {
        if (w.calm) return "calm";
        return (w.variable?"variable":Units.pad(w.direction, 3) + " degrees") + " at "+w.speed + " KT"+(w.gust<0?"":" gusting "+w.gust + " KT");
    }

    static String windCode(Value w) {
        if (w.calm) return "00000KT";
        return (w.variable?"VRB":Units.pad(w.direction, 3)) + Units.pad(w.speed, 2) + (w.gust<0?"":"G"+Units.pad(w.gust, 2)) + "KT";
    }

    static String mileNumber(Value v) {
        if (!v.fractional) return Long.toString(v.whole);
        return (v.whole == 0?"":v.whole + " ") + v.num + "/"+v.den;
    }

    static String qualifier(String q) {
        return q.equals("M")?"less than ":q.equals("P")?"more than ":"";
    }

    static String visibilityPhrase(Value v) {
        if (v.kind.equals("cavok")) return "10 km or more (CAVOK)";
        if (v.kind.equals("meter")) return v.qualifier.equals("P")?"10 km or more":v.meters + " m";
        return qualifier(v.qualifier) + mileNumber(v) + " SM";
    }

    static String visibilityCode(Value v) {
        return v.kind.equals("mile")?v.qualifier + mileNumber(v) + "SM":v.raw;
    }

    static String weatherPhrase(Value w) {
        if (w.nsw) return "no significant weather";
        List<String> p = new ArrayList<>();
        if (!w.intensity.isEmpty()) p.add(Groups.INTENSITIES.get(w.intensity));
        if (!w.descriptor.isEmpty()) p.add(Groups.DESCRIPTORS.get(w.descriptor));
        if (!w.codes.isEmpty()) p.add(String.join(" and ", w.codes.stream().map(Groups.PHENOMENA::get).toList()));
        return String.join(" ", p);
    }

    static String cloudPhrase(Value c) {
        if (Groups.CLEAR.containsKey(c.amount)) return Groups.CLEAR.get(c.amount);
        if (c.amount.equals("VV")) return "vertical visibility "+c.height + " ft";
        return Groups.AMOUNTS.get(c.amount) + " at "+c.height + " ft"+(c.suffix.isEmpty()?"":c.suffix.equals("CB")?" cumulonimbus":" towering cumulus");
    }

    static String summary(Section s) {
        List<String> p = new ArrayList<>();
        if (s.wind != null) p.add("wind "+windPhrase(s.wind));
        if (s.visibility != null) p.add("visibility "+visibilityPhrase(s.visibility));
        if (s.weather != null && !s.weather.isEmpty()) p.add("weather "+String.join(", ", s.weather.stream().map(Main::weatherPhrase).toList()));
        if (s.cloud != null && !s.cloud.isEmpty()) p.add("cloud "+String.join(", ", s.cloud.stream().map(Main::cloudPhrase).toList()));
        return p.isEmpty()?"no conditions":String.join("; ", p);
    }

    static String tokens(Section s) {
        List<String> p = new ArrayList<>();
        if (s.wind != null) p.add(windCode(s.wind));
        if (s.visibility != null) p.add(visibilityCode(s.visibility));
        if (s.weather != null) for (Value w:s.weather) if (!w.nsw) p.add(w.raw);
        if (s.cloud != null) for (Value cloud:s.cloud) p.add(cloud.raw);
        p.add(s.category);
        return String.join(" ", p);
    }

    static String tenth(long v) {
        return (v<0?"-":"") + Math.abs(v) / 10 + "."+Math.abs(v) % 10;
    }

    static String pressurePhrase(Value p) {
        String a = p.inches / 100 + "."+Units.pad(p.inches % 100, 2) + " inHg", q = p.hecto + " hPa";
        return p.unit.equals("A")?a + " ("+q + ")":q + " ("+a + ")";
    }

    static String rvrPhrase(Value v) {
        String a = qualifier(v.qualifier) + v.first;
        if (v.hasSecond) a = "between "+a + " and "+qualifier(v.qualifier2) + v.second;
        String trend = switch (v.trend) {
            case "U" -> ", rising";
            case "D" -> ", falling";
            case "N" -> ", no change";
            default -> "";
        };
        return "runway "+v.runway + " "+a + " "+v.unit + trend;
    }

    static String componentPhrase(Component c) {
        String p = (c.head()<0?"tailwind "+(-c.head()):"headwind "+c.head()) + " KT";
        return p + (c.cross() == 0?", crosswind 0 KT":", crosswind "+Math.abs(c.cross()) + " KT from "+(c.cross()>0?"right":"left"));
    }

    static String altitude(Long value) {
        return value == null?"not available":value + " ft";
    }

    static List<String> observationLines(Report r, Calendar calendar) {
        Section s = r.main;
        List<String> lines = new ArrayList<>();
        lines.add("time: "+calendar.stamp(r.time));
        if (s.modifier != null) lines.add("modifier: "+(s.modifier.raw.equals("AUTO")?"automated":"corrected"));
        String wind = s.wind == null?"not reported":windPhrase(s.wind);
        if (s.variation != null) wind += ", varying between "+Units.pad(s.variation.first, 3) + " and "+Units.pad(s.variation.second, 3) + " degrees";
        lines.add("wind: "+wind);
        lines.add("visibility: "+(s.visibility == null?"not reported":visibilityPhrase(s.visibility)));
        for (Value v:s.rvr) lines.add("runway visual range: "+rvrPhrase(v));
        if (s.weather != null) for (Value w:s.weather) lines.add("weather: "+weatherPhrase(w));
        if (s.visibility != null && s.visibility.kind.equals("cavok")) lines.add("cloud: no significant cloud");
        else if (s.cloud == null) lines.add("cloud: not reported");
        else for (Value cloud:s.cloud) lines.add("cloud: "+cloudPhrase(cloud));
        Value t = s.temperature;
        lines.add("temperature: "+(t == null?"not reported":t.temp + " C, dew point "+t.dew + " C, spread "+(t.temp - t.dew) + " C"));
        lines.add("altimeter: "+(s.pressure == null?"not reported":pressurePhrase(s.pressure)));
        if (s.noTrend) lines.add("trend: no significant change");
        for (Change trend:r.trends) {
            String phrase = trend.kind.equals("BECMG")?"becoming":"temporarily";
            for (TrendTime time:trend.times) phrase += " "+(switch (time.kind()) {
                case "FM" -> "from";
                case "TL" -> "until";
                default -> "at";
            }) + " "+Units.pad(time.hour(), 2) + ":"+Units.pad(time.minute(), 2) + "Z";
            lines.add("trend: "+phrase + ": "+summary(trend.state));
        }
        for (long p:r.slp) lines.add("sea level pressure: "+tenth(p) + " hPa");
        for (Value p:r.precise) lines.add("precise temperature: "+tenth(p.temp) + " C, dew point "+tenth(p.dew) + " C");
        lines.add("ceiling: "+(s.ceiling<0?"none":s.ceiling + " ft"));
        lines.add("flight category: "+s.category);
        lines.add("pressure altitude: "+altitude(r.pressureAltitude));
        lines.add("density altitude: "+altitude(r.densityAltitude));
        if (r.winds == null) lines.add("runway wind: not computed");
        else {
            List<String> usable = new ArrayList<>();
            for (RunwayWind rw:r.winds) {
                lines.add("runway "+rw.name() + ": "+componentPhrase(rw.mean()) + (rw.gust() == null?"":"; gusts "+componentPhrase(rw.gust())));
                if (rw.usable()) usable.add(rw.name());
            }
            lines.add("usable runways: "+(usable.isEmpty()?"none":String.join(" ", usable)));
            lines.add("preferred runway: "+r.preferred);
        }
        if (r.kind.equals("SPECI")) lines.add("speci check: "+String.join(", ", r.speciReasons));
        return lines;
    }

    static List<String> forecastLines(Report r, Calendar c) {
        List<String> lines = new ArrayList<>();
        lines.add("issued: "+c.stamp(r.time));
        if (!r.modifier.isEmpty()) lines.add("modifier: "+(r.modifier.equals("AMD")?"amended":"corrected"));
        lines.add("valid: "+c.stamp(r.start) + " to "+c.stamp(r.end));
        lines.add("base: "+summary(r.base));
        for (Change change:r.changes) lines.add(change.kind + " "+(change.kind.equals("FM")?c.stamp(change.time):c.stamp(change.start) + " to "+c.stamp(change.end)) + ": "+summary(change.state));
        return lines;
    }

    static String decodedBlock(Report r, Calendar c) {
        List<String> lines = new ArrayList<>();
        lines.add("REPORT "+r.number + ": "+r.kind + " "+r.station.code + " ("+r.station.name + ")");
        for (String line:r.kind.equals("TAF")?forecastLines(r, c):observationLines(r, c)) lines.add("  "+line);
        return String.join("\n", lines);
    }

    static String counts(long[] counts) {
        List<String> parts = new ArrayList<>();
        for (int i = 0;i<4;i++) parts.add(Verification.CATEGORIES.get(i) + " "+counts[i]);
        return String.join(", ", parts);
    }

    static String timelineBlock(Report r, Calendar c) {
        List<String> lines = new ArrayList<>();
        lines.add("TAF "+r.station.code + " issued "+c.stamp(r.time) + " valid "+c.stamp(r.start) + " to "+c.stamp(r.end));
        long[] counts = new long[4];
        for (var entry:r.timeline.entrySet()) {
            Hour h = entry.getValue();
            String line = c.stamp(entry.getKey()) + " "+tokens(h.prevailing);
            counts[Verification.CATEGORIES.indexOf(h.prevailing.category)]++;
            for (Temporary t:h.temporary) line += " | "+t.kind() + " "+tokens(t.state());
            lines.add(line);
        }
        lines.add("summary: "+counts(counts));
        return String.join("\n", lines);
    }

    static String categoryLine(Report r, Calendar c) {
        Section s = r.main;
        return String.join(",", r.station.code, c.stamp(r.time), s.ceiling<0?"NONE":Long.toString(s.ceiling),
        s.visibility == null?"NONE":s.visibility.qualifier + Units.meters(s.visibility), s.category);
    }

    static long strength(Value w) {
        return w.gust<0?w.speed:w.gust;
    }

    static List<String> extremeLines(List<Report> obs, Calendar c) {
        Report[] selected = new Report[5];
        for (Report o:obs) {
            Section s = o.main;
            if (s.temperature != null) {
                if (selected[0] == null || s.temperature.temp<selected[0].main.temperature.temp) selected[0] = o;
                if (selected[1] == null || s.temperature.temp>selected[1].main.temperature.temp) selected[1] = o;
            }
            if (s.wind != null && (selected[2] == null || strength(s.wind)>strength(selected[2].main.wind))) selected[2] = o;
            if (s.ceiling >= 0 && (selected[3] == null || s.ceiling<selected[3].main.ceiling)) selected[3] = o;
            if (s.visibility != null && (selected[4] == null || Units.compareVisibility(s.visibility, selected[4].main.visibility)<0)) selected[4] = o;
        }
        String[] labels = {
            "lowest temperature", "highest temperature", "strongest wind", "lowest ceiling", "lowest visibility"
        };
        List<String> lines = new ArrayList<>();
        for (int i = 0;i<5;i++) {
            Report o = selected[i];
            String value = "not available";
            if (o != null) {
                Section s = o.main;
                value = switch (i) {
                    case 0, 1 -> s.temperature.temp + " C";
                    case 2 -> windPhrase(s.wind);
                    case 3 -> s.ceiling + " ft";
                    default -> visibilityPhrase(s.visibility);
                };
                value += " at "+c.stamp(o.time);
            }
            lines.add(labels[i] + ": "+value);
        }
        return lines;
    }

    static String tableRow(String label, List<String> values) {
        StringBuilder s = new StringBuilder(String.format(Locale.ROOT, "%-8s", label));
        for (String v:values) s.append(String.format(Locale.ROOT, "%6s", v));
        return s.toString();
    }

    static String verificationBlock(Station station, List<Report> obs, List<Report> tafs, Calendar c) {
        Verification.Result a = Verification.analyze(obs, tafs);
        long metars = 0;
        long[] counts = new long[4];
        for (Report o:obs) {
            if (o.kind.equals("METAR")) metars++;
            counts[Verification.CATEGORIES.indexOf(o.main.category)]++;
        }
        List<String> lines = new ArrayList<>(List.of("station "+station.code + " ("+station.name + ")", "reports: METAR "+metars + ", SPECI "+(obs.size() - metars), "observed categories: "+counts(counts)));
        lines.addAll(extremeLines(obs, c));
        lines.add("verified: "+a.total);
        lines.add("no forecast: "+a.noForecast);
        List<String> head = new ArrayList<>(Verification.CATEGORIES);
        head.add("total");
        lines.add(tableRow("forecast", head));
        for (int i = 0;i<4;i++) {
            List<String> values = new ArrayList<>();
            for (long n:a.table[i]) values.add(Long.toString(n));
            values.add(Long.toString(a.rows[i]));
            lines.add(tableRow(Verification.CATEGORIES.get(i), values));
        }
        List<String> totals = new ArrayList<>();
        for (long n:a.columns) totals.add(Long.toString(n));
        totals.add(Long.toString(a.total));
        lines.add(tableRow("total", totals));
        lines.add("hit rate: "+a.hitRate());
        lines.add("hit rate with temporary groups: "+a.temporaryRate());
        lines.add("heidke skill score: "+a.skill());
        for (int i = 0;i<4;i++) lines.add(Verification.CATEGORIES.get(i) + ": pod "+a.pod(i) + ", far "+a.far(i));
        for (int i = 0;i<5;i++) lines.add("hours "+i * 6 + "-"+(i * 6 + 5) + ": "+Units.fraction(a.buckets[i][0], a.buckets[i][1]));
        for (Verification.Choice choice:a.choices) {
            Section observed = choice.observation().main, forecast = choice.forecast().prevailing;
            List<String> reasons = new ArrayList<>();
            if (!choice.temporaryHit()) reasons.add("category "+observed.category + ", forecast "+forecast.category);
            if (!windChanges(forecast.wind, observed.wind, 60).isEmpty()) reasons.add("wind "+windCode(observed.wind) + ", forecast "+windCode(forecast.wind));
            if (!reasons.isEmpty()) lines.add("amendment "+c.stamp(choice.observation().time) + ": "+String.join("; ", reasons));
        }
        return String.join("\n", lines);
    }

    static String text(List<String> lines, String separator) {
        return lines.isEmpty()?"":String.join(separator, lines) + "\n";
    }

    public static void main(String[] args) throws IOException {
        Map<String, Station> stations = new HashMap<>();
        for (String line:readLines("stations.txt")) {
            String[] p = line.split(" ", 4);
            Station s = new Station();
            s.code = p[0];
            s.elevation = Groups.number(p[1]);
            s.name = p[3];
            for (String entry:p[2].split(",")) {
                String[] r = entry.split("/");
                s.runways.add(new Runway(r[0], Groups.number(r[1])));
            }
            stations.put(s.code, s);
        }
        Map<String, List<String>> settings = new HashMap<>();
        for (String line:readLines("params.txt")) {
            List<String> p = List.of(line.split(" "));
            settings.put(p.get(0), p.subList(1, p.size()));
        }
        Calendar c = new Calendar(Groups.number(settings.get("YEAR").get(0)), Groups.number(settings.get("MONTH").get(0)));
        long crosswind = Groups.number(settings.get("CROSSWIND_LIMIT").get(0)), tailwind = Groups.number(settings.get("TAILWIND_LIMIT").get(0));
        List<List<String>> raw = new ArrayList<>();
        for (String line:readLines("reports.txt")) {
            List<String> words = List.of(line.stripLeading().split(" "));
            if (line.startsWith(" ")) raw.get(raw.size() - 1).addAll(words);
            else raw.add(new ArrayList<>(words));
        }
        List<Report> reports = new ArrayList<>(), obs = new ArrayList<>(), tafs = new ArrayList<>();
        List<ParseError> errors = new ArrayList<>();
        Map<String, Report> previous = new HashMap<>();
        for (int i = 0;i<raw.size();i++) {
            ErrorSink error = recorder(errors, i + 1);
            Report r = header(raw.get(i), i + 1, stations, c, error);
            if (r == null) continue;
            List<Group> body = joinGroups(raw.get(i), r.bodyStart);
            if (r.kind.equals("TAF")) {
                decodeForecast(r, body, c, error);
                tafs.add(r);
            }
            else {
                decodeObservation(r, body, crosswind, tailwind, error);
                if (r.kind.equals("SPECI")) r.speciReasons = speciCheck(previous.get(r.station.code), r);
                previous.put(r.station.code, r);
                obs.add(r);
            }
            reports.add(r);
        }
        List<String> decoded = new ArrayList<>(), timelines = new ArrayList<>(), verified = new ArrayList<>(), csv = new ArrayList<>(List.of("station,time,ceiling,visibility,category"));
        for (Report r:reports) decoded.add(decodedBlock(r, c));
        for (Report r:obs) csv.add(categoryLine(r, c));
        for (Report r:tafs) timelines.add(timelineBlock(r, c));
        for (String code:settings.get("VERIFY")) verified.add(verificationBlock(stations.get(code), obs.stream().filter(r -> r.station.code.equals(code)).toList(), tafs.stream().filter(r -> r.station.code.equals(code)).toList(), c));
        errors.sort(Comparator.comparingInt(ParseError::report).thenComparingInt(ParseError::position));
        List<String> errorLines = errors.stream().map(e -> "report "+e.report() + " word "+e.position() + ": "+e.content()).toList();
        Map<String, String> outputs = Map.of("decoded.txt", text(decoded, "\n\n"), "categories.csv", text(csv, "\n"), "taf_timeline.txt", text(timelines, "\n\n"), "verification.txt", text(verified, "\n\n"), "errors.txt", text(errorLines, "\n"));
        Files.createDirectories(Path.of("output"));
        for (var e:outputs.entrySet()) Files.writeString(Path.of("output", e.getKey()), e.getValue(), StandardCharsets.US_ASCII);
    }
}
