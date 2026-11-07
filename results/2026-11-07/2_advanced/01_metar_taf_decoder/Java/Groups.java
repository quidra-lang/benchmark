import java.util.*;
import java.util.regex.*;

final class Groups {
    static final Map<String, String> DESCRIPTORS = Map.of("MI", "shallow", "BC", "patches", "PR", "partial",
    "DR", "low drifting", "BL", "blowing", "SH", "showers", "TS", "thunderstorm", "FZ", "freezing");
    static final Map<String, String> PHENOMENA = table(
    "DZ|drizzle|RA|rain|SN|snow|SG|snow grains|IC|ice crystals|PL|ice pellets|GR|hail|GS|small hail|UP|unknown precipitation|BR|mist|FG|fog|FU|smoke|VA|volcanic ash|DU|dust|SA|sand|HZ|haze|PY|spray|PO|dust whirls|SQ|squalls|FC|funnel cloud|SS|sandstorm|DS|duststorm");
    static final Set<String> PRECIPITATION = Set.of("DZ", "RA", "SN", "SG", "IC", "PL", "GR", "GS", "UP");
    static final Map<String, String> AMOUNTS = Map.of("FEW", "few", "SCT", "scattered", "BKN", "broken", "OVC", "overcast");
    static final Map<String, String> CLEAR = Map.of("SKC", "sky clear", "CLR", "clear below 12000 ft", "NSC", "no significant cloud");
    static final Map<String, String> INTENSITIES = Map.of("-", "light", "+", "heavy", "VC", "nearby");
    private static Map<String, String> table(String data) {
        Map<String, String> result = new HashMap<>();
        String[] p = data.split("\\|");
        for (int i = 0; i<p.length; i += 2) result.put(p[i], p[i + 1]);
        return result;
    }

    static long number(String s) {
        return s == null || s.isEmpty() ? 0 : Long.parseLong(s);
    }

    static String[] match(String pattern, String text) {
        Matcher m = Pattern.compile(pattern).matcher(text);
        if (!m.matches()) return null;
        String[] result = new String[m.groupCount() + 1];
        for (int i = 0; i<result.length; i++) result[i] = m.group(i);
        return result;
    }

    static Value format(String kind, String text) {
        Value v = new Value();
        v.raw = text;
        String[] m;
        switch (kind) {
            case "modifier": return text.equals("AUTO") || text.equals("COR") ? v : null;
            case "wind":
            m = match("(\\d{3}|VRB)(\\d{2,3})(?:G(\\d{2,3}))?(KT|MPS)", text);
            if (m == null) return null;
            v.variable = m[1].equals("VRB");
            v.calm = m[1].equals("000");
            v.direction = v.variable ? 0 : number(m[1]);
            v.speed = number(m[2]);
            v.gust = m[3] == null ? -1 : number(m[3]);
            v.unit = m[4];
            break;
            case "variation":
            m = match("(\\d{3})V(\\d{3})", text);
            if (m == null) return null;
            v.first = number(m[1]);
            v.second = number(m[2]);
            break;
            case "visibility":
            if (text.equals("CAVOK")) {
                v.kind = "cavok";
                v.meters = 10000;
                v.qualifier = "P";
                break;
            }
            if (match("\\d{4}", text) != null) {
                v.kind = "meter";
                v.meters = number(text);
                if (v.meters == 9999) {
                    v.meters = 10000;
                    v.qualifier = "P";
                }
                break;
            }
            v.kind = "mile";
            m = match("(\\d) (\\d)/(\\d{1,2})SM", text);
            if (m != null) {
                v.whole = number(m[1]);
                v.num = number(m[2]);
                v.den = number(m[3]);
                v.mixed = true;
                v.fractional = true;
                break;
            }
            m = match("([MP]?)(?:(\\d{1,2})|(\\d)/(\\d{1,2}))SM", text);
            if (m == null) return null;
            v.qualifier = m[1];
            v.whole = number(m[2]);
            v.fractional = m[3] != null;
            if (v.fractional) {
                v.num = number(m[3]);
                v.den = number(m[4]);
            }
            break;
            case "rvr":
            m = match("R(\\d{2}[LCR]?)/([MP]?)(\\d{4})(?:V([MP]?)(\\d{4}))?(FT)?([UDN])?", text);
            if (m == null) return null;
            v.runway = m[1];
            v.qualifier = m[2];
            v.first = number(m[3]);
            v.hasSecond = m[5] != null;
            v.qualifier2 = m[4] == null?"":m[4];
            v.second = number(m[5]);
            v.unit = m[6] == null?"m":"ft";
            v.trend = m[7] == null?"":m[7];
            break;
            case "weather":
            if (text.equals("NSW")) {
                v.nsw = true;
                break;
            }
            String body = text;
            if (body.startsWith("VC")) {
                v.intensity = "VC";
                body = body.substring(2);
            }
            else if (body.startsWith("-") || body.startsWith("+")) {
                v.intensity = body.substring(0, 1);
                body = body.substring(1);
            }
            if (body.isEmpty() || body.length() % 2 != 0) return null;
            for (int i = 0; i<body.length(); i += 2) {
                String code = body.substring(i, i + 2);
                if (!DESCRIPTORS.containsKey(code) && !PHENOMENA.containsKey(code)) return null;
                v.codes.add(code);
            }
            if (DESCRIPTORS.containsKey(v.codes.get(0))) v.descriptor = v.codes.remove(0);
            break;
            case "cloud":
            if (CLEAR.containsKey(text)) {
                v.amount = text;
                break;
            }
            m = match("(FEW|SCT|BKN|OVC)(\\d{3})(CB|TCU)?", text);
            if (m != null) {
                v.amount = m[1];
                v.height = number(m[2]) * 100;
                v.suffix = m[3] == null?"":m[3];
                break;
            }
            m = match("VV(\\d{3})", text);
            if (m == null) return null;
            v.amount = "VV";
            v.height = number(m[1]) * 100;
            break;
            case "temperature":
            m = match("(M?)(\\d{2})/(M?)(\\d{2})", text);
            if (m == null) return null;
            v.temp = number(m[2]) * (m[1].isEmpty()?1:-1);
            v.dew = number(m[4]) * (m[3].isEmpty()?1:-1);
            break;
            case "pressure":
            m = match("([AQ])(\\d{4})", text);
            if (m == null) return null;
            v.unit = m[1];
            v.value = number(m[2]);
            break;
            case "noTrend": return text.equals("NOSIG")?v:null;
            default: return null;
        }
        return v;
    }

    static boolean valid(String kind, Value v, Section s, Station station) {
        switch (kind) {
            case "wind":
            if (v.variable) {
                if (v.speed<1) return false;
            }
            else if (v.direction>360 || v.direction % 10 != 0 || (v.direction == 0) != (v.speed == 0)) return false;
            return v.gust<0 || !v.calm && v.gust>v.speed;
            case "variation":
            return v.first >= 10 && v.first <= 360 && v.first % 10 == 0 && v.second >= 10 && v.second <= 360
 && v.second % 10 == 0 && v.first != v.second && s.wind != null && !s.wind.variable && !s.wind.calm;
            case "visibility":
            if (!v.kind.equals("mile")) return true;
            if (!v.fractional) return v.whole >= 1;
            return (v.den == 2 || v.den == 4 || v.den == 8 || v.den == 16) && v.num >= 1 && v.num<v.den && (!v.mixed || v.whole >= 1);
            case "rvr":
            return station.runways.stream().anyMatch(r -> r.name().equals(v.runway)) && (!v.hasSecond || v.first<v.second);
            case "weather":
            List<Value> accepted = s.weather == null?List.of():s.weather;
            if (accepted.size() >= 3 || accepted.stream().anyMatch(w -> w.nsw)) return false;
            if (v.nsw) return accepted.isEmpty() && (s.context.equals("trend") || s.context.equals("change"));
            if (!v.codes.stream().allMatch(PHENOMENA::containsKey) || new HashSet<>(v.codes).size() != v.codes.size()) return false;
            if (v.codes.isEmpty() && !v.descriptor.equals("TS") && !v.descriptor.equals("SH")) return false;
            if ((v.intensity.equals("-") || v.intensity.equals("+")) && v.codes.stream().noneMatch(PRECIPITATION::contains)) return false;
            return v.codes.size()<2 || v.codes.stream().allMatch(PRECIPITATION::contains);
            case "cloud":
            if (s.cloud == null || s.cloud.isEmpty()) return true;
            Value last = s.cloud.get(s.cloud.size() - 1);
            return AMOUNTS.containsKey(v.amount) && AMOUNTS.containsKey(last.amount) && v.height>last.height;
            case "temperature": return v.dew <= v.temp;
            case "pressure": return v.unit.equals("A") ? v.value >= 2500 && v.value <= 3150 : v.value >= 850 && v.value <= 1070;
            default: return true;
        }
    }

    static void accept(Section s, String kind, Value v) {
        switch (kind) {
            case "modifier": s.modifier = v;
            break;
            case "wind":
            if (v.unit.equals("MPS")) {
                v.speed = Units.knots(v.speed);
                if (v.gust >= 0) v.gust = Units.knots(v.gust);
            }
            s.wind = v;
            break;
            case "variation": s.variation = v;
            break;
            case "visibility":
            s.visibility = v;
            if (v.kind.equals("cavok")) {
                s.weather = new ArrayList<>();
                s.cloud = new ArrayList<>();
            }
            break;
            case "rvr": s.rvr.add(v);
            break;
            case "weather": if (s.weather == null) s.weather = new ArrayList<>();
            s.weather.add(v);
            break;
            case "cloud": if (s.cloud == null) s.cloud = new ArrayList<>();
            s.cloud.add(v);
            break;
            case "temperature": s.temperature = v;
            break;
            case "pressure":
            v.inches = v.unit.equals("A")?v.value:Units.inHg(v.value);
            v.hecto = v.unit.equals("Q")?v.value:Units.hPa(v.value);
            s.pressure = v;
            break;
            case "noTrend": s.noTrend = true;
            break;
        }
    }
}
