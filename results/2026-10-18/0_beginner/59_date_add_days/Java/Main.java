import java.util.Locale;

public class Main {
    static String date(int y, int m, int d) {
        return String.format(Locale.ROOT, "%04d-%02d-%02d", y, m, d);
    }

    public static void main(String[] args) {
        int[] lengths = {31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31};
        int[][] cases = {
            {1999, 12, 25, 10}, {2000, 2, 27, 3}, {2021, 2, 20, 14}, {2023, 11, 15, 120},
            {2026, 10, 17, 1500}};
        for (int[] item : cases) {
            int year = item[0], month = item[1], day = item[2];
            String original = date(year, month, day);
            for (int i = 0; i < item[3]; i++) {
                int monthLength = lengths[month - 1]
                        + (month == 2 && year % 4 == 0 && (year % 100 != 0 || year % 400 == 0) ? 1 : 0);
                day++;
                if (day > monthLength) {
                    day = 1;
                    month++;
                    if (month > 12) {
                        month = 1;
                        year++;
                    }
                }
            }
            System.out.println(original + " + " + item[3] + " days = " + date(year, month, day));
        }
    }
}
