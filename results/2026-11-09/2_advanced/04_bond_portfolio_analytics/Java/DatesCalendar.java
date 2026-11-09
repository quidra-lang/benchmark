import java.time.DateTimeException;
import java.time.LocalDate;
import java.time.format.DateTimeFormatter;
import java.util.HashSet;
import java.util.Set;

final class Dates {
    private static final long EPOCH = LocalDate.of(2000, 1, 1).toEpochDay();
    static boolean leap(int year) { return year % 4 == 0 && (year % 100 != 0 || year % 400 == 0); }
    static int monthLength(int year, int month) { return LocalDate.of(year, month, 1).lengthOfMonth(); }
    static int dayNumber(int year, int month, int day) { return (int) (LocalDate.of(year, month, day).toEpochDay() - EPOCH); }
    static LocalDate civil(int day) { return LocalDate.ofEpochDay(day + EPOCH); }
    static boolean valid(String text) {
        try { LocalDate date = LocalDate.parse(text, DateTimeFormatter.ISO_LOCAL_DATE); return date.getYear() >= 2001 && date.getYear() <= 2099; }
        catch (DateTimeException error) { return false; }
    }
    static int parse(String text) { return (int) (LocalDate.parse(text, DateTimeFormatter.ISO_LOCAL_DATE).toEpochDay() - EPOCH); }
    static String format(int day) { return civil(day).format(DateTimeFormatter.ISO_LOCAL_DATE); }
}
final class Calendar {
    final Set<Integer> holidays = new HashSet<>();
    boolean business(int day) { return (day + 5) % 7 < 5 && !holidays.contains(day); }
    int move(int day, int count) {
        int step = count < 0 ? -1 : 1; if (count < 0) count = -count;
        while (count > 0) { day += step; if (business(day)) count--; } return day;
    }
    int adjust(int day, String rule) {
        if (rule.equals("UNADJUSTED")) return day;
        int following = day; while (!business(following)) following++;
        if (rule.equals("FOLLOWING") || rule.equals("MODIFIED_FOLLOWING") && Dates.civil(following).getMonthValue() == Dates.civil(day).getMonthValue()) return following;
        while (!business(day)) day--; return day;
    }
}
