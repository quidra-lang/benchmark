import java.time.LocalDate;

record Fraction(long numerator, long denominator) { double value() { return (double) numerator / denominator; } }
final class Daycount {
    static Fraction between(String convention, int start, int end) {
        if (convention.equals("ACT/360")) return new Fraction(end - start, 360);
        if (convention.equals("ACT/365F")) return new Fraction(end - start, 365);
        if (convention.equals("ACT/ACT")) {
            long numerator = 0; int year = Dates.civil(start).getYear();
            while (start < end) { int boundary = Math.min(end, Dates.dayNumber(year + 1, 1, 1)); numerator += (long) (boundary - start) * (Dates.leap(year) ? 365 : 366); start = boundary; year++; }
            return new Fraction(numerator, 133590);
        }
        LocalDate first = Dates.civil(start), last = Dates.civil(end); int d1 = first.getDayOfMonth(), d2 = last.getDayOfMonth();
        if (convention.equals("30E/360")) { d1 = Math.min(d1, 30); d2 = Math.min(d2, 30); }
        else {
            boolean february = first.getMonthValue() == 2 && d1 == first.lengthOfMonth();
            if (february && last.getMonthValue() == 2 && d2 == last.lengthOfMonth()) d2 = 30;
            if (february) d1 = 30;
            if (d2 == 31 && d1 >= 30) d2 = 30;
            if (d1 == 31) d1 = 30;
        }
        return new Fraction(360 * (last.getYear() - first.getYear()) + 30 * (last.getMonthValue() - first.getMonthValue()) + d2 - d1, 360);
    }
}
