import java.util.Locale;

final class Units {
    private static final long[] SINE = {
        0, 174, 342, 500, 643, 766, 866, 940, 985, 1000
    };
    static long sin(long angle) {
        long y = Math.floorMod(angle, 360);
        if (y <= 90) return SINE[(int)y / 10];
        if (y <= 180) return SINE[(int)(180 - y) / 10];
        if (y <= 270) return -SINE[(int)(y - 180) / 10];
        return -SINE[(int)(360 - y) / 10];
    }

    static long cos(long angle) {
        return sin(angle + 90);
    }

    static long knots(long v) {
        return (v * 1944 + 500) / 1000;
    }

    static long inHg(long v) {
        return (v * 2953 + 500) / 1000;
    }

    static long hPa(long v) {
        return (v * 33864 + 50000) / 100000;
    }

    static String pad(long v, int width) {
        return String.format(Locale.ROOT, "%0" + width + "d", v);
    }

    static long days(long y, long m) {
        if (m == 2) return y % 4 == 0 && (y % 100 != 0 || y % 400 == 0) ? 29 : 28;
        return m == 4 || m == 6 || m == 9 || m == 11 ? 30 : 31;
    }

    static long[] miles(Value v) {
        return v.kind.equals("mile") ? new long[]{
            v.whole * v.den + v.num, v.den
        }
        : new long[]{
            v.meters * 1000, 1609344
        };
    }

    static long meters(Value v) {
        if (!v.kind.equals("mile")) return v.meters;
        long[] f = miles(v);
        return 1609344 * f[0] / (1000 * f[1]);
    }

    static long compareVisibility(Value a, Value b) {
        long[] x = miles(a), y = miles(b);
        return x[0] * y[1] - y[0] * x[1];
    }

    static String fraction(long n, long d) {
        if (d == 0) return "undefined";
        long a = Math.abs(n), b = d;
        while (b != 0) {
            long r = a % b;
            a = b;
            b = r;
        }
        return n / a + "/" + d / a;
    }
}

final class Calendar {
    final long year, month, days, nextYear, nextMonth, nextDays;
    Calendar(long year, long month) {
        this.year = year;
        this.month = month;
        days = Units.days(year, month);
        nextYear = month == 12 ? year + 1 : year;
        nextMonth = month == 12 ? 1 : month + 1;
        nextDays = Units.days(nextYear, nextMonth);
    }
    long observation(String word) {
        String[] m = Groups.match("(\\d{2})(\\d{2})(\\d{2})Z", word);
        if (m == null) return -1;
        long d = Groups.number(m[1]), h = Groups.number(m[2]), n = Groups.number(m[3]);
        return d < 1 || d > days || h > 23 || n > 59 ? -1 : ((d - 1) * 24 + h) * 60 + n;
    }
    long dayTime(long d, long h, long m, long issueDay) {
        boolean next = d < issueDay;
        if (d < 1 || d > (next ? nextDays : days)) return -1;
        return (next ? days * 1440 : 0) + ((d - 1) * 24 + h) * 60 + m;
    }
    long[] period(String word, long issueDay, long maximum) {
        String[] m = Groups.match("(\\d{2})(\\d{2})/(\\d{2})(\\d{2})", word);
        if (m == null) return null;
        long h = Groups.number(m[2]), k = Groups.number(m[4]);
        if (h > 23 || k < 1 || k > 24) return null;
        long s = dayTime(Groups.number(m[1]), h, 0, issueDay);
        long e = dayTime(Groups.number(m[3]), k, 0, issueDay);
        return s < 0 || e <= s || maximum > 0 && e - s > maximum ? null : new long[]{
            s, e
        };
    }
    long changeTime(String word, long issueDay) {
        String[] m = Groups.match("FM(\\d{2})(\\d{2})(\\d{2})", word);
        if (m == null) return -1;
        long h = Groups.number(m[2]), n = Groups.number(m[3]);
        return h > 23 || n > 59 ? -1 : dayTime(Groups.number(m[1]), h, n, issueDay);
    }
    String stamp(long time) {
        boolean next = time >= days * 1440;
        if (next) time -= days * 1440;
        return String.format(Locale.ROOT, "%04d-%02d-%02dT%02d:%02dZ", next ? nextYear : year,
        next ? nextMonth : month, time / 1440 + 1, time % 1440 / 60, time % 60);
    }
}
