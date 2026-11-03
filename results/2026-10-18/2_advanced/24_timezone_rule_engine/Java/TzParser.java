import java.util.*;

final class TzParser {
    static final class FieldError extends RuntimeException { FieldError(String message) { super(message); } }
    record Time(long value, char type) {}
    record Until(String yearText, String monthText, String dayText, long time, char type, long value) {}

    static String content(String raw) { int comment = raw.indexOf('#'); return (comment < 0 ? raw : raw.substring(0, comment)).replaceFirst(" +$", ""); }
    static boolean continuation(String content) { return content.startsWith(" "); }
    static String[] fields(String content) { return content.stripLeading().split(" +"); }
    static boolean number(String text, int low, int high) { return text.length() >= low && text.length() <= high && text.matches("[0-9]+"); }

    static Long hms(String text, int maxParts) {
        String[] parts = text.split(":", -1);
        if (parts.length > maxParts || !number(parts[0], 1, 2)) return null;
        long value = Long.parseLong(parts[0]) * 3600;
        for (int i = 1; i < parts.length; i++) {
            if (!number(parts[i], 2, 2) || Integer.parseInt(parts[i]) > 59) return null;
            value += Long.parseLong(parts[i]) * (i == 1 ? 60 : 1);
        }
        return value;
    }

    static int year(String text) {
        if (!number(text, 4, 4)) throw new FieldError("bad year");
        int value = Integer.parseInt(text);
        if (value < 1800 || value > 2099) throw new FieldError("bad year");
        return value;
    }

    static int toYear(String text, int from) {
        if (text.equals("only")) return from;
        if (text.equals("max")) return 2099;
        if (!number(text, 4, 4)) throw new FieldError("bad year");
        int value = Integer.parseInt(text);
        if (value < from || value > 2099) throw new FieldError("bad year");
        return value;
    }

    static int month(String text) {
        int index = Arrays.asList(DayRules.MONTHS).indexOf(text);
        if (index < 0) throw new FieldError("bad month");
        return index + 1;
    }

    static int weekday(String text) {
        int index = Arrays.asList(DayRules.WEEKDAYS).indexOf(text);
        if (index < 0) throw new FieldError("bad day spec");
        return index;
    }

    static int dayOfMonth(String text, int month) {
        if (!number(text, 1, 2) || text.charAt(0) == '0' || Integer.parseInt(text) > DayRules.COMMON_DAYS[month - 1]) throw new FieldError("bad day spec");
        return Integer.parseInt(text);
    }

    static DayRules.DaySpec day(String text, int month) {
        if (text.startsWith("last")) return new DayRules.DaySpec("last", weekday(text.substring(4)), 0);
        for (String operator : new String[]{">=", "<="}) {
            int index = text.indexOf(operator);
            if (index >= 0) return new DayRules.DaySpec(operator.equals(">=") ? "after" : "before", weekday(text.substring(0, index)), dayOfMonth(text.substring(index + 2), month));
        }
        return new DayRules.DaySpec("day", 0, dayOfMonth(text, month));
    }

    static Time time(String text) {
        char type = 'w';
        if (!text.isEmpty() && "wsu".indexOf(text.charAt(text.length() - 1)) >= 0) { type = text.charAt(text.length() - 1); text = text.substring(0, text.length() - 1); }
        Long value = hms(text, 3);
        if (value == null || value > 86400) throw new FieldError("bad time");
        return new Time(value, type);
    }

    static long save(String text) {
        Long value = hms(text, 2);
        if (value == null || value > 7200) throw new FieldError("bad save");
        return value;
    }

    static String letter(String text) {
        if (text.equals("-")) return "";
        if (!text.matches("[A-Z]{1,5}")) throw new FieldError("bad letter");
        return text;
    }

    static long offset(String text) {
        int sign = 1;
        if (text.startsWith("-")) { sign = -1; text = text.substring(1); }
        Long value = hms(text, 3);
        if (value == null || value >= 57600) throw new FieldError("bad offset");
        return sign * value;
    }

    static void checkFormat(String text, boolean ruleSet) {
        int placeholders = (text.length() - text.replace("%s", "").length()) / 2;
        long percentages = text.chars().filter(c -> c == '%').count();
        long slashes = text.chars().filter(c -> c == '/').count();
        boolean valid = text.matches("[A-Za-z0-9+/%-]+") && percentages == placeholders && placeholders <= 1 && slashes <= 1
            && !(placeholders > 0 && slashes > 0) && (ruleSet || placeholders == 0);
        if (slashes == 1 && (text.startsWith("/") || text.endsWith("/"))) valid = false;
        if (!valid) throw new FieldError("bad format");
    }

    static Until until(String[] fields) {
        int year = year(fields[0]);
        String monthText = fields.length > 1 ? fields[1] : "Jan";
        int month = month(monthText);
        String dayText = fields.length > 2 ? fields[2] : "1";
        DayRules.DaySpec day = day(dayText, month);
        Time time = fields.length > 3 ? time(fields[3]) : new Time(0, 'w');
        return new Until(fields[0], monthText, dayText, time.value, time.type, day.value(year, month) * DayRules.DAY + time.value);
    }
}
