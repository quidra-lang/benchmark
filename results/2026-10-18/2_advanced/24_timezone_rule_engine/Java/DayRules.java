final class DayRules {
    static final String[] MONTHS = {"Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"};
    static final String[] WEEKDAYS = {"Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"};
    static final int[] COMMON_DAYS = {31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31};
    static final long DAY = 86400;
    static final long NEG_INFINITY = -(1L << 62);
    static final long POS_INFINITY = 1L << 62;

    static boolean leap(int year) { return year % 4 == 0 && year % 100 != 0 || year % 400 == 0; }
    static int daysInMonth(int year, int month) { return month == 2 && leap(year) ? 29 : COMMON_DAYS[month - 1]; }

    private static long daysBeforeYear(int year) {
        long previous = year - 1L;
        return previous * 365 + Math.floorDiv(previous, 4) - Math.floorDiv(previous, 100) + Math.floorDiv(previous, 400);
    }

    static long dayNumber(int year, int month, int day) {
        long number = daysBeforeYear(year) - daysBeforeYear(1970) + day - 1;
        for (int m = 1; m < month; m++) number += daysInMonth(year, m);
        return number;
    }

    static int weekday(long day) { return (int) Math.floorMod(day + 4, 7); }
    static long timeValue(int year, int month, int day, int hour, int minute, int second) { return dayNumber(year, month, day) * DAY + hour * 3600L + minute * 60L + second; }

    static int[] splitTime(long time) {
        long number = Math.floorDiv(time, DAY);
        int year = 1970 + (int) Math.floorDiv(number, 366);
        while (dayNumber(year, 1, 1) > number) year--;
        while (dayNumber(year + 1, 1, 1) <= number) year++;
        int month = 1, day = (int) (number - dayNumber(year, 1, 1) + 1);
        while (day > daysInMonth(year, month)) { day -= daysInMonth(year, month); month++; }
        long seconds = Math.floorMod(time, DAY);
        return new int[]{year, month, day, (int) (seconds / 3600), (int) (seconds / 60 % 60), (int) (seconds % 60)};
    }

    record DaySpec(String kind, int weekday, int day) {
        long value(int year, int month) {
            if (kind.equals("last")) {
                long last = dayNumber(year, month, daysInMonth(year, month));
                return last - Math.floorMod(DayRules.weekday(last) - weekday, 7);
            }
            long base = dayNumber(year, month, day);
            return switch (kind) {
                case "after" -> base + Math.floorMod(weekday - DayRules.weekday(base), 7);
                case "before" -> base - Math.floorMod(DayRules.weekday(base) - weekday, 7);
                default -> base;
            };
        }
    }
}
