import java.io.*;
import java.util.*;

public class Main {
    static final String[] FIELD_NAMES = {"minute", "hour", "day-of-month", "month", "day-of-week"};
    static final int[] MINIMUM = {0, 0, 1, 1, 0}, MAXIMUM = {59, 23, 31, 12, 7};
    static final String[] MONTHS = {"January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"};
    static final String[] WEEKDAYS = {"Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"};
    static final int[] MONTH_DAYS = {31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31};

    static final class CommandError extends RuntimeException {
        CommandError(String message) { super(message); }
    }
    static String format(String pattern, Object... values) { return String.format(Locale.ROOT, pattern, values); }
    static boolean digits(String text, int minimum, int maximum) {
        return text.length() >= minimum && text.length() <= maximum && text.chars().allMatch(c -> c >= '0' && c <= '9');
    }
    static int integer(String text) { return Integer.parseInt(text); }
    static boolean leap(int year) { return year % 4 == 0 && (year % 100 != 0 || year % 400 == 0); }
    static int monthLength(int year, int month) { return month == 2 && leap(year) ? 29 : MONTH_DAYS[month - 1]; }
    record Date(int year, int month, int day) {
        int number() {
            int result = day - 1;
            for (int y = 2000; y < year; y++) result += leap(y) ? 366 : 365;
            for (int m = 1; m < month; m++) result += monthLength(year, m);
            return result;
        }
        int weekday() { return (number() + 6) % 7; }
        static Date fromNumber(int number) {
            int year = 2000, month = 1;
            while (number >= (leap(year) ? 366 : 365)) { number -= leap(year) ? 366 : 365; year++; }
            while (number >= monthLength(year, month)) { number -= monthLength(year, month); month++; }
            return new Date(year, month, number + 1);
        }
        @Override public String toString() { return format("%04d-%02d-%02d %s", year, month, day, WEEKDAYS[weekday()].substring(0, 3)); }
    }
    static boolean pattern(String text, String pattern) {
        if (text.length() != pattern.length()) return false;
        for (int i = 0; i < pattern.length(); i++) {
            char value = text.charAt(i), required = pattern.charAt(i);
            if (required == '#' ? value < '0' || value > '9' : value != required) return false;
        }
        return true;
    }
    static Date readDate(String text, String reason) {
        if (!pattern(text, "####-##-##")) throw new CommandError(reason);
        Date date = new Date(integer(text.substring(0, 4)), integer(text.substring(5, 7)), integer(text.substring(8)));
        if (date.year() < 2001 || date.year() > 2098 || date.month() < 1 || date.month() > 12 || date.day() < 1 || date.day() > monthLength(date.year(), date.month())) throw new CommandError(reason);
        return date;
    }
    static int readDatetime(String[] words, int at) {
        Date date = readDate(words[at], "invalid datetime");
        String time = words[at + 1];
        if (!pattern(time, "##:##")) throw new CommandError("invalid datetime");
        int hour = integer(time.substring(0, 2)), minute = integer(time.substring(3));
        if (hour > 23 || minute > 59) throw new CommandError("invalid datetime");
        return date.number() * 1440 + hour * 60 + minute;
    }
    static Date readMonth(String text) {
        if (!pattern(text, "####-##")) throw new CommandError("invalid month");
        Date date = new Date(integer(text.substring(0, 4)), integer(text.substring(5)), 1);
        if (date.year() < 2001 || date.year() > 2098 || date.month() < 1 || date.month() > 12) throw new CommandError("invalid month");
        return date;
    }
    static String datetimeText(int time) {
        Date date = Date.fromNumber(time / 1440);
        return format("%04d-%02d-%02d %02d:%02d %s", date.year(), date.month(), date.day(), time % 1440 / 60, time % 60, WEEKDAYS[date.weekday()].substring(0, 3));
    }
    static String span(int minutes) { return format("%dd%02dh%02dm", minutes / 1440, minutes % 1440 / 60, minutes % 60); }
    static int positive(String text, int width, int maximum, String reason) {
        if (!digits(text, 1, width) || text.charAt(0) == '0' || integer(text) > maximum) throw new CommandError(reason);
        return integer(text);
    }
    record Window(int low, int high) {
        static Window read(String[] words, int at) {
            int low = readDatetime(words, at), high = readDatetime(words, at + 2);
            if (low > high) throw new CommandError("invalid window");
            if (high - low > 44640) throw new CommandError("window too long");
            return new Window(low, high);
        }
    }

    enum SpecialKind { LAST, LAST_WORKDAY, BEFORE_LAST, NEAREST, NTH_WEEKDAY, LAST_WEEKDAY }
    record Special(SpecialKind kind, int value, int occurrence) {
        @Override public String toString() {
            return switch (kind) {
                case LAST -> "L"; case LAST_WORKDAY -> "LW"; case BEFORE_LAST -> "L-" + value;
                case NEAREST -> value + "W"; case NTH_WEEKDAY -> value + "#" + occurrence; case LAST_WEEKDAY -> value + "L";
            };
        }
        String phrase() {
            return switch (kind) {
                case LAST -> "the last day"; case LAST_WORKDAY -> "the last weekday";
                case BEFORE_LAST -> value + (value == 1 ? " day" : " days") + " before the last day";
                case NEAREST -> "the weekday nearest day " + value;
                case NTH_WEEKDAY -> "the " + List.of("1st", "2nd", "3rd", "4th", "5th").get(occurrence - 1) + " " + WEEKDAYS[value];
                case LAST_WEEKDAY -> "the last " + WEEKDAYS[value];
            };
        }
    }
    static int readValue(String text, int index) {
        List<String> names = switch (index) {
            case 3 -> List.of("JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC");
            case 4 -> List.of("SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"); default -> List.of();
        };
        int named = names.indexOf(text);
        if (named >= 0) return named + (index == 3 ? 1 : 0);
        if (!digits(text, 1, 2)) throw new CommandError("invalid value");
        int value = integer(text);
        if (value < MINIMUM[index] || value > MAXIMUM[index]) throw new CommandError("out of range");
        return value;
    }
    static int specialNumber(String text, int maximum, int width) {
        if (!digits(text, 1, width)) throw new CommandError("invalid value");
        int value = integer(text);
        if (value < 1 || value > maximum) throw new CommandError("out of range");
        return value;
    }
    static String wordList(List<String> parts, boolean either) {
        if (parts.size() < 2) return String.join("", parts);
        return String.join(", ", parts.subList(0, parts.size() - 1)) + (either ? " or " : " and ") + parts.getLast();
    }
    record Field(int index, List<Integer> values, List<Special> specials, boolean restricted) {
        Field { values = List.copyOf(values); specials = List.copyOf(specials); }
        boolean contains(int value) { return Collections.binarySearch(values, value) >= 0; }
        static Field parse(String text, int index) {
            TreeSet<Integer> values = new TreeSet<>();
            List<Special> specials = new ArrayList<>();
            try {
                for (String item : text.split(",", -1)) {
                    if (item.isEmpty()) throw new CommandError("empty item");
                    Special special = null;
                    if (index == 2 && (item.startsWith("L") || item.endsWith("W"))) {
                        if (item.equals("L")) special = new Special(SpecialKind.LAST, 0, 0);
                        else if (item.equals("LW")) special = new Special(SpecialKind.LAST_WORKDAY, 0, 0);
                        else if (item.startsWith("L-")) special = new Special(SpecialKind.BEFORE_LAST, specialNumber(item.substring(2), 30, 2), 0);
                        else if (item.endsWith("W")) special = new Special(SpecialKind.NEAREST, specialNumber(item.substring(0, item.length() - 1), 31, 2), 0);
                        else throw new CommandError("invalid value");
                    } else if (index == 4 && item.contains("#")) {
                        int at = item.indexOf('#');
                        int weekday = readValue(item.substring(0, at), index);
                        int occurrence = specialNumber(item.substring(at + 1), 5, 1);
                        special = new Special(SpecialKind.NTH_WEEKDAY, weekday % 7, occurrence);
                    } else if (index == 4 && item.length() >= 2 && item.endsWith("L")) {
                        special = new Special(SpecialKind.LAST_WEEKDAY, readValue(item.substring(0, item.length() - 1), index) % 7, 0);
                    }
                    if (special != null) {
                        if (!specials.contains(special)) specials.add(special);
                        continue;
                    }
                    int slash = item.indexOf('/');
                    String base = slash < 0 ? item : item.substring(0, slash);
                    int first, last;
                    if (base.equals("*")) { first = MINIMUM[index]; last = MAXIMUM[index]; }
                    else {
                        int dash = base.indexOf('-');
                        if (dash >= 0) {
                            first = readValue(base.substring(0, dash), index);
                            last = readValue(base.substring(dash + 1), index);
                            if (first > last) throw new CommandError("invalid range");
                        } else { first = readValue(base, index); last = slash < 0 ? first : MAXIMUM[index]; }
                    }
                    int step = 1;
                    if (slash >= 0) {
                        String part = item.substring(slash + 1);
                        if (!digits(part, 1, 2) || integer(part) == 0) throw new CommandError("invalid step");
                        step = integer(part);
                    }
                    for (int value = first; value <= last; value += step) values.add(index == 4 ? value % 7 : value);
                }
            } catch (CommandError error) { throw new CommandError(FIELD_NAMES[index] + " " + error.getMessage()); }
            return new Field(index, new ArrayList<>(values), specials, text.charAt(0) != '*');
        }
        int stepped() {
            if (values.size() < 2 || values.getFirst() != 0 || values.get(1) < 2) return 0;
            int step = values.get(1);
            if (values.size() != MAXIMUM[index] / step + 1) return 0;
            for (int i = 0; i < values.size(); i++) if (values.get(i) != i * step) return 0;
            return step;
        }
        String valueName(int value) { return index == 3 ? MONTHS[value - 1] : index == 4 ? WEEKDAYS[value] : Integer.toString(value); }
        String valueList(boolean either) {
            List<String> parts = new ArrayList<>();
            for (int first = 0; first < values.size();) {
                int last = first;
                while (last + 1 < values.size() && values.get(last + 1) == values.get(last) + 1) last++;
                if (last - first >= 2) parts.add(valueName(values.get(first)) + " through " + valueName(values.get(last)));
                else for (int i = first; i <= last; i++) parts.add(valueName(values.get(i)));
                first = last + 1;
            }
            return wordList(parts, either);
        }
        String dayPhrase(boolean either) {
            List<String> parts = new ArrayList<>();
            if (!values.isEmpty()) parts.add(index == 4 ? valueList(either) : (values.size() == 1 ? "day " : "days ") + valueList(false));
            for (Special special : specials) parts.add(special.phrase());
            return wordList(parts, either) + (index == 2 || !specials.isEmpty() ? " of the month" : "");
        }
    }
    record DayMatch(boolean dom, boolean dow, boolean condition) {}
    record Cron(List<Field> fields, List<Integer> daily, String text, String expanded) {
        Cron { fields = List.copyOf(fields); daily = List.copyOf(daily); }
        static Cron parse(String[] input) {
            String text = String.join(" ", input);
            String[] words = input;
            if (words.length == 1 && words[0].startsWith("@")) {
                String expansion = switch (words[0]) {
                    case "@yearly", "@annually" -> "0 0 1 1 *"; case "@monthly" -> "0 0 1 * *"; case "@weekly" -> "0 0 * * 0";
                    case "@daily", "@midnight" -> "0 0 * * *"; case "@hourly" -> "0 * * * *"; default -> throw new CommandError("unknown macro");
                };
                words = expansion.split(" ");
            }
            if (words.length != 5) throw new CommandError("field count");
            List<Field> fields = new ArrayList<>();
            for (int i = 0; i < 5; i++) fields.add(Field.parse(words[i], i));
            List<Integer> daily = new ArrayList<>();
            for (int hour : fields.get(1).values()) for (int minute : fields.get(0).values()) daily.add(hour * 60 + minute);
            return new Cron(fields, daily, text, String.join(" ", words));
        }
        boolean orRule() { return fields.get(2).restricted() && fields.get(4).restricted(); }
        static int nearest(Date date, int day) {
            int weekday = (date.number() - date.day() + day + 6) % 7;
            return weekday == 6 ? day == 1 ? 3 : day - 1 : weekday == 0 ? day == monthLength(date.year(), date.month()) ? day - 2 : day + 1 : day;
        }
        DayMatch matchDay(Date date) {
            int last = monthLength(date.year(), date.month()), day = date.day(), weekday = date.weekday();
            boolean dom = fields.get(2).contains(day), dow = fields.get(4).contains(weekday);
            for (Special special : fields.get(2).specials()) {
                dom |= switch (special.kind()) {
                    case LAST -> day == last; case LAST_WORKDAY -> day == nearest(date, last); case BEFORE_LAST -> day == last - special.value();
                    case NEAREST -> special.value() <= last && day == nearest(date, special.value()); default -> false;
                };
            }
            for (Special special : fields.get(4).specials()) {
                dow |= weekday == special.value() && (special.kind() == SpecialKind.NTH_WEEKDAY ? (day - 1) / 7 + 1 == special.occurrence() : day + 7 > last);
            }
            return new DayMatch(dom, dow, orRule() ? dom || dow : dom && dow);
        }
        boolean scheduled(Date date) { return fields.get(3).contains(date.month()) && matchDay(date).condition(); }
        List<Integer> fires(int low, int high, Set<Integer> holidays, boolean reverse, int limit) {
            List<Integer> result = new ArrayList<>();
            int first = low / 1440, last = high / 1440, step = reverse ? -1 : 1;
            for (int day = reverse ? last : first; day >= first && day <= last; day += step) {
                if (holidays.contains(day) || !scheduled(Date.fromNumber(day))) continue;
                for (int i = reverse ? daily.size() - 1 : 0; i >= 0 && i < daily.size(); i += step) {
                    int time = day * 1440 + daily.get(i);
                    if (time < low || time > high) continue;
                    result.add(time);
                    if (limit > 0 && result.size() == limit) return result;
                }
            }
            return result;
        }
        String description() {
            Field minute = fields.get(0), hour = fields.get(1), dom = fields.get(2), month = fields.get(3), dow = fields.get(4);
            String text;
            if (daily.size() <= 4) text = "At " + wordList(daily.stream().map(t -> format("%02d:%02d", t / 60, t % 60)).toList(), false);
            else {
                int ms = minute.stepped(), hs = hour.stepped();
                text = minute.values().size() == 60 ? "Every minute" : ms > 0 ? "Every " + ms + " minutes"
                    : "At " + (minute.values().size() == 1 ? "minute " : "minutes ") + minute.valueList(false);
                if (hour.values().size() == 24) { if (text.startsWith("At minute")) text += " of every hour"; }
                else if (hs > 0) text += ", every " + hs + " hours";
                else if (hour.values().getLast() - hour.values().getFirst() + 1 == hour.values().size()) text += format(", between %02d:00 and %02d:59", hour.values().getFirst(), hour.values().getLast());
                else text += ", during hours " + hour.valueList(false);
            }
            boolean dFull = dom.values().size() == 31, wFull = dow.values().size() == 7;
            if (orRule()) { if (!dFull && !wFull) text += ", on " + dom.dayPhrase(false) + " or on " + dow.dayPhrase(false); }
            else if (!dFull && !wFull) text += ", on " + dom.dayPhrase(false) + " if it is " + dow.dayPhrase(true);
            else if (!dFull) text += ", on " + dom.dayPhrase(false);
            else if (!wFull) text += ", on " + dow.dayPhrase(false);
            if (month.values().size() != 12) text += ", in " + month.valueList(false);
            return text;
        }
    }

    enum Policy { ALLOW, FORBID, REPLACE }
    static final class Job {
        final Cron cron;
        boolean enabled = true;
        int duration = 1;
        Policy policy = Policy.ALLOW;
        Job(Cron cron) { this.cron = cron; }
    }
    record NamedJob(String id, Job job) {}
    static final class Scheduler {
        final TreeMap<String, Job> jobs = new TreeMap<>();
        final TreeSet<Integer> holidays = new TreeSet<>();
        Job job(String id) {
            Job result = jobs.get(id);
            if (result == null) throw new CommandError("unknown job");
            return result;
        }
        void newId(String id) {
            if (id.isEmpty() || id.length() > 16 || id.charAt(0) < 'a' || id.charAt(0) > 'z' || !id.chars().allMatch(c -> c >= 'a' && c <= 'z' || c >= '0' && c <= '9' || c == '_')) throw new CommandError("invalid id");
            if (jobs.containsKey(id)) throw new CommandError("duplicate job");
        }
        List<NamedJob> enabled() { return jobs.entrySet().stream().filter(e -> e.getValue().enabled).map(e -> new NamedJob(e.getKey(), e.getValue())).toList(); }
        List<String> timeline(Window window, boolean conflicts) {
            List<NamedJob> enabled = enabled();
            long[] masks = new long[window.high() - window.low() + 1];
            for (int i = 0; i < enabled.size(); i++) {
                for (int time : enabled.get(i).job().cron.fires(window.low(), window.high(), holidays, false, 0)) masks[time - window.low()] |= 1L << i;
            }
            int total = 0, peak = 0;
            for (long mask : masks) {
                int count = Long.bitCount(mask);
                if (!conflicts) total += count;
                else if (count >= 2) { total++; peak = Math.max(peak, count); }
            }
            List<String> rows = new ArrayList<>();
            rows.add(conflicts ? "CONFLICTS " + total + " peak " + peak : "TIMELINE " + total);
            for (int i = 0; i < masks.length && rows.size() < 101; i++) {
                long mask = masks[i];
                if (conflicts) {
                    if (Long.bitCount(mask) < 2) continue;
                    List<String> ids = new ArrayList<>();
                    for (int j = 0; j < enabled.size(); j++) if ((mask & (1L << j)) != 0) ids.add(enabled.get(j).id());
                    rows.add(datetimeText(window.low() + i) + " " + ids.size() + " " + String.join(" ", ids));
                } else {
                    for (int j = 0; j < enabled.size() && rows.size() < 101; j++) if ((mask & (1L << j)) != 0) rows.add(datetimeText(window.low() + i) + " " + enabled.get(j).id());
                }
            }
            if (total > 100) rows.add("... " + (total - 100) + " more");
            return rows;
        }
        List<String> simulate(Window window) {
            List<NamedJob> enabled = enabled();
            int[] events = new int[window.high() - window.low() + 1441];
            List<String> rows = new ArrayList<>();
            for (NamedJob entry : enabled) {
                Job job = entry.job();
                int started = 0, skipped = 0, replaced = 0, busy = 0, lastEnd = -1;
                for (int time : job.cron.fires(window.low(), window.high(), holidays, false, 0)) {
                    if (lastEnd > time && job.policy == Policy.FORBID) { skipped++; continue; }
                    if (lastEnd > time && job.policy == Policy.REPLACE) {
                        events[lastEnd - window.low()]++; events[time - window.low()]--;
                        busy -= lastEnd - time; replaced++;
                    }
                    lastEnd = time + job.duration;
                    events[time - window.low()]++; events[lastEnd - window.low()]--;
                    started++; busy += job.duration;
                }
                rows.add(format("%s %s started %d skipped %d replaced %d busy %d", entry.id(), job.policy, started, skipped, replaced, busy));
            }
            int running = 0, peak = 0, at = 0;
            for (int i = 0; i < events.length; i++) { running += events[i]; if (running > peak) { peak = running; at = window.low() + i; } }
            rows.addFirst("SIMULATE " + enabled.size() + " peak " + peak + (peak == 0 ? "" : " at " + datetimeText(at)));
            return rows;
        }
        List<String> execute(String[] words) {
            String command = words[0];
            int expected = switch (command) {
                case "JOB" -> -3; case "VALIDATE" -> -2; case "LIST", "HOLIDAYS" -> 1;
                case "REMOVE", "ENABLE", "DISABLE", "DESCRIBE", "WEEK", "EXCLUDE", "INCLUDE" -> 2;
                case "RENAME", "EXPAND", "CALENDAR" -> 3; case "RUNTIME", "MATCH", "GAP" -> 4;
                case "NEXT", "PREV", "TIMELINE", "CONFLICTS", "SIMULATE" -> 5; case "COUNT" -> 6; case "OVERLAP" -> 7;
                default -> throw new CommandError("unknown command");
            };
            if (expected < 0 ? words.length < -expected : words.length != expected) throw new CommandError("wrong arguments");
            Job job = switch (command) {
                case "REMOVE", "RENAME", "ENABLE", "DISABLE", "RUNTIME", "EXPAND", "DESCRIBE", "MATCH", "NEXT", "PREV", "COUNT", "GAP", "OVERLAP", "CALENDAR" -> job(words[1]);
                default -> null;
            };
            switch (command) {
                case "JOB" -> {
                    newId(words[1]); Cron cron = Cron.parse(Arrays.copyOfRange(words, 2, words.length));
                    jobs.put(words[1], new Job(cron)); return List.of("JOB " + words[1] + " added");
                }
                case "VALIDATE" -> {
                    Cron cron = Cron.parse(Arrays.copyOfRange(words, 1, words.length));
                    return List.of("VALID " + cron.expanded() + " " + (cron.orRule() ? "OR" : "AND") + " " + cron.daily().size());
                }
                case "REMOVE" -> { jobs.remove(words[1]); return List.of("REMOVE " + words[1]); }
                case "RENAME" -> { newId(words[2]); jobs.remove(words[1]); jobs.put(words[2], job); return List.of("RENAME " + words[1] + " " + words[2]); }
                case "ENABLE", "DISABLE" -> {
                    boolean desired = command.equals("ENABLE");
                    if (job.enabled == desired) throw new CommandError(desired ? "already enabled" : "already disabled");
                    job.enabled = desired; return List.of(command + " " + words[1]);
                }
                case "RUNTIME" -> {
                    int duration = positive(words[2], 4, 1440, "invalid duration");
                    Policy policy = switch (words[3]) { case "ALLOW" -> Policy.ALLOW; case "FORBID" -> Policy.FORBID; case "REPLACE" -> Policy.REPLACE; default -> throw new CommandError("invalid policy"); };
                    job.duration = duration; job.policy = policy;
                    return List.of("RUNTIME " + words[1] + " " + duration + " " + policy);
                }
                case "LIST" -> {
                    List<String> rows = new ArrayList<>(); rows.add("LIST " + jobs.size());
                    jobs.forEach((id, item) -> rows.add(id + " " + (item.enabled ? "on" : "off") + " " + item.duration + " " + item.policy + " " + item.cron.text()));
                    return rows;
                }
                case "EXPAND" -> {
                    int index = Arrays.asList(FIELD_NAMES).indexOf(words[2]);
                    if (index < 0) throw new CommandError("invalid field");
                    Field field = job.cron.fields().get(index);
                    List<String> parts = new ArrayList<>(); parts.add("EXPAND " + words[1] + " " + words[2] + " " + field.values().size());
                    for (int value : field.values()) parts.add(Integer.toString(value));
                    for (Special item : field.specials()) parts.add(item.toString());
                    return List.of(String.join(" ", parts));
                }
                case "DESCRIBE" -> { return List.of("DESCRIBE " + words[1] + " " + job.cron.description()); }
                case "MATCH" -> {
                    int time = readDatetime(words, 2); Date date = Date.fromNumber(time / 1440); DayMatch match = job.cron.matchDay(date);
                    List<String> reasons = new ArrayList<>();
                    if (!job.cron.fields().get(0).contains(time % 60)) reasons.add("minute");
                    if (!job.cron.fields().get(1).contains(time % 1440 / 60)) reasons.add("hour");
                    if (!match.condition() && !match.dom()) reasons.add("day-of-month");
                    if (!job.cron.fields().get(3).contains(date.month())) reasons.add("month");
                    if (!match.condition() && !match.dow()) reasons.add("day-of-week");
                    if (holidays.contains(time / 1440)) reasons.add("excluded");
                    return List.of("MATCH " + words[1] + " " + datetimeText(time) + " " + (reasons.isEmpty() ? "yes" : "no " + String.join(" ", reasons)));
                }
                case "NEXT", "PREV" -> {
                    int base = readDatetime(words, 2), limit = positive(words[4], 2, 50, "invalid count"); boolean reverse = command.equals("PREV");
                    List<Integer> times = job.cron.fires(reverse ? base - 527040 : base + 1, reverse ? base - 1 : base + 527040, holidays, reverse, limit);
                    List<String> rows = new ArrayList<>(); rows.add(command + " " + words[1] + " " + times.size());
                    for (int time : times) rows.add(datetimeText(time) + (reverse ? " -" : " +") + span(Math.abs(time - base)));
                    if (times.size() < limit) rows.add("NONE"); return rows;
                }
                case "COUNT" -> {
                    Window window = Window.read(words, 2); List<Integer> times = job.cron.fires(window.low(), window.high(), holidays, false, 0);
                    int days = 0, previous = -1;
                    for (int time : times) if (time / 1440 != previous) { previous = time / 1440; days++; }
                    return List.of("COUNT " + words[1] + " runs " + times.size() + " days " + days);
                }
                case "GAP" -> {
                    int base = readDatetime(words, 2); List<Integer> times = job.cron.fires(base, base + 44640, holidays, false, 0);
                    if (times.size() < 2) return List.of("GAP " + words[1] + " runs " + times.size() + " none");
                    TreeMap<Integer, Integer> histogram = new TreeMap<>(); int longest = 0, first = 0;
                    for (int i = 0; i + 1 < times.size(); i++) {
                        int gap = times.get(i + 1) - times.get(i); histogram.merge(gap, 1, Integer::sum);
                        if (gap > longest) { longest = gap; first = i; }
                    }
                    List<String> rows = new ArrayList<>();
                    rows.add(format("GAP %s runs %d shortest %s longest %s from %s to %s", words[1], times.size(), span(histogram.firstKey()), span(longest), datetimeText(times.get(first)), datetimeText(times.get(first + 1))));
                    histogram.forEach((gap, count) -> rows.add(span(gap) + " " + count)); return rows;
                }
                case "OVERLAP" -> {
                    Job otherJob = job(words[2]); Window window = Window.read(words, 3);
                    Set<Integer> other = new HashSet<>(otherJob.cron.fires(window.low(), window.high(), holidays, false, 0));
                    List<Integer> times = job.cron.fires(window.low(), window.high(), holidays, false, 0).stream().filter(other::contains).toList();
                    return List.of("OVERLAP " + words[1] + " " + words[2] + " " + times.size() + (times.isEmpty() ? "" : " first " + datetimeText(times.getFirst()) + " last " + datetimeText(times.getLast())));
                }
                case "TIMELINE", "CONFLICTS", "SIMULATE" -> {
                    Window window = Window.read(words, 1); return command.equals("SIMULATE") ? simulate(window) : timeline(window, command.equals("CONFLICTS"));
                }
                case "WEEK" -> {
                    int first = readDate(words[1], "invalid date").number(); int[][] counts = new int[7][24]; int total = 0;
                    for (NamedJob entry : enabled()) for (int time : entry.job().cron.fires(first * 1440, (first + 7) * 1440 - 1, holidays, false, 0)) { counts[time / 1440 - first][time % 1440 / 60]++; total++; }
                    List<String> rows = new ArrayList<>(); rows.add("WEEK " + words[1] + " " + total);
                    for (int d = 0; d < 7; d++) {
                        StringBuilder heat = new StringBuilder(); int dayTotal = 0;
                        for (int count : counts[d]) { heat.append(count == 0 ? '.' : count >= 10 ? '+' : (char) ('0' + count)); dayTotal += count; }
                        rows.add(Date.fromNumber(first + d) + " " + heat + " " + dayTotal);
                    }
                    return rows;
                }
                case "CALENDAR" -> {
                    Date first = readMonth(words[2]); List<String> cells = new ArrayList<>(Collections.nCopies(first.weekday(), "...")); int days = 0;
                    for (int day = 1; day <= monthLength(first.year(), first.month()); day++) {
                        Date date = new Date(first.year(), first.month(), day);
                        char mark = !job.cron.scheduled(date) ? '-' : holidays.contains(date.number()) ? 'x' : '*';
                        if (mark == '*') days++;
                        cells.add(format("%02d%c", day, mark));
                    }
                    while (cells.size() % 7 != 0) cells.add("...");
                    List<String> rows = new ArrayList<>(List.of("CALENDAR " + words[1] + " " + words[2] + " days " + days + " runs " + days * job.cron.daily().size(), "Sun Mon Tue Wed Thu Fri Sat"));
                    for (int i = 0; i < cells.size(); i += 7) rows.add(String.join(" ", cells.subList(i, i + 7))); return rows;
                }
                case "EXCLUDE", "INCLUDE" -> {
                    Date date = readDate(words[1], "invalid date");
                    if (command.equals("EXCLUDE")) { if (!holidays.add(date.number())) throw new CommandError("already excluded"); }
                    else if (!holidays.remove(date.number())) throw new CommandError("not excluded");
                    return List.of(command + " " + date + " holidays " + holidays.size());
                }
                case "HOLIDAYS" -> {
                    List<String> rows = new ArrayList<>(); rows.add("HOLIDAYS " + holidays.size());
                    for (int day : holidays) rows.add(Date.fromNumber(day).toString()); return rows;
                }
            }
            throw new IllegalStateException();
        }
    }

    public static void main(String[] args) throws IOException {
        BufferedReader input = new BufferedReader(new InputStreamReader(System.in));
        BufferedWriter output = new BufferedWriter(new OutputStreamWriter(System.out));
        String first = input.readLine(); if (first == null) return;
        int count = integer(first); Scheduler scheduler = new Scheduler();
        for (int i = 0; i < count; i++) {
            String[] words = input.readLine().trim().split(" +");
            try { for (String row : scheduler.execute(words)) { output.write(row); output.write('\n'); } }
            catch (CommandError error) { output.write("ERROR " + error.getMessage() + "\n"); }
        }
        output.flush();
    }
}
