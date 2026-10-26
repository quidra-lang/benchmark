import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.Map;

record DateResult(Long seconds, String error) {}
final class Dates {
    static final List<String> WEEKDAYS = List.of("mon", "tue", "wed", "thu", "fri", "sat", "sun"), MONTHS = List.of("jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec");
    static final int[] MONTH_DAYS = {31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31};
    static final Map<String, Integer> ZONES = Map.ofEntries(Map.entry("ut", 0), Map.entry("gmt", 0), Map.entry("z", 0), Map.entry("est", -300), Map.entry("edt", -240), Map.entry("cst", -360), Map.entry("cdt", -300), Map.entry("mst", -420), Map.entry("mdt", -360), Map.entry("pst", -480), Map.entry("pdt", -420));
    static boolean leap(int year) { return year % 4 == 0 && year % 100 != 0 || year % 400 == 0; }
    static int monthDays(int year, int month) { return month == 2 && leap(year) ? 29 : MONTH_DAYS[month - 1]; }
    static int yearDays(int year) { return leap(year) ? 366 : 365; }
    static int epochDays(int year, int month, int day) {
        int days = day - 1; for (int current = 1970; current < year; current++) days += yearDays(current); for (int current = 1; current < month; current++) days += monthDays(year, current); return days;
    }
    static boolean digits(String text, int... lengths) {
        boolean length = false; for (int candidate : lengths) if (text.length() == candidate) length = true;
        return length && text.chars().allMatch(letter -> letter >= '0' && letter <= '9');
    }
    static boolean numericZone(String text) { return text.length() == 5 && (text.charAt(0) == '+' || text.charAt(0) == '-') && digits(text.substring(1), 4); }
    static DateResult failure(String text) { return new DateResult(null, text); }
    static DateResult parse(String value) {
        String text = Headers.removeComments(value); if (text == null) return failure("bad Date syntax");
        List<String> tokens = new ArrayList<>(Headers.words(text.replace(",", " , "))); int weekday = -1;
        if (tokens.size() >= 3 && WEEKDAYS.contains(Headers.lower(tokens.getFirst())) && tokens.get(1).equals(",")) { weekday = WEEKDAYS.indexOf(Headers.lower(tokens.getFirst())); tokens = tokens.subList(2, tokens.size()); }
        if (tokens.size() != 5) return failure("bad Date syntax");
        String dayText = tokens.get(0), monthText = Headers.lower(tokens.get(1)), yearText = tokens.get(2), zone = tokens.get(4); String[] time = tokens.get(3).split(":", -1);
        boolean validTime = time.length == 2 || time.length == 3; for (String piece : time) validTime &= digits(piece, 2);
        if (!digits(dayText, 1, 2) || !MONTHS.contains(monthText) || !digits(yearText, 2, 4) || !validTime || !(numericZone(zone) || ZONES.containsKey(Headers.lower(zone)))) return failure("bad Date syntax");
        int day = Integer.parseInt(dayText), month = MONTHS.indexOf(monthText) + 1, year = Integer.parseInt(yearText);
        if (yearText.length() == 2) year += year < 50 ? 2000 : 1900;
        int hour = Integer.parseInt(time[0]), minute = Integer.parseInt(time[1]), second = time.length == 3 ? Integer.parseInt(time[2]) : 0, offset;
        if (numericZone(zone)) {
            int hours = Integer.parseInt(zone.substring(1, 3)), minutes = Integer.parseInt(zone.substring(3));
            if (hours > 23 || minutes > 59) return failure("Date out of range");
            offset = (hours * 60 + minutes) * (zone.charAt(0) == '-' ? -1 : 1);
        } else offset = ZONES.get(Headers.lower(zone));
        if (year < 1970 || year > 2099 || day < 1 || day > monthDays(year, month) || hour > 23 || minute > 59 || second > 59) return failure("Date out of range");
        int days = epochDays(year, month, day); long seconds = days * 86400L + hour * 3600 + minute * 60 + second - offset * 60;
        if (seconds < 0) return failure("Date out of range");
        if (weekday >= 0 && (days + 3) % 7 != weekday) return failure("Date weekday mismatch");
        return new DateResult(seconds, null);
    }
    static String format(long seconds) {
        int days = (int) (seconds / 86400), rest = (int) (seconds % 86400), year = 1970, month = 1;
        while (days >= yearDays(year)) { days -= yearDays(year); year++; }
        while (days >= monthDays(year, month)) { days -= monthDays(year, month); month++; }
        return String.format(Locale.ROOT, "%04d-%02d-%02d %02d:%02d:%02d", year, month, days + 1, rest / 3600, rest % 3600 / 60, rest % 60);
    }
}
