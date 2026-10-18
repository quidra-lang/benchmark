import java.util.*;
import java.math.*;

public class Main {
    static String date(int y, int m, int d) { return String.format(Locale.ROOT,"%04d-%02d-%02d",y,m,d); }
    public static void main(String[] args) {
        for (int[] item : new int[][]{{1999,12,25,10},{2000,2,27,3},{2021,2,20,14},{2023,11,15,120},{2026,10,17,1500}}) {
            int year = item[0], month = item[1], day = item[2]; String original = date(year,month,day);
            for (int i = 0; i < item[3]; i++) {
                int[] lengths = {31,28,31,30,31,30,31,31,30,31,30,31};
                if (year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)) lengths[1] = 29;
                day++; if (day > lengths[month - 1]) { day = 1; month++; if (month > 12) { month = 1; year++; } }
            }
            System.out.println(original + " + " + item[3] + " days = " + date(year,month,day));
        }
    }
}
