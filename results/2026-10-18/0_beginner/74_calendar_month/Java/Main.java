import java.util.ArrayList;
import java.util.List;
import java.util.Locale;

public class Main {
    public static void main(String[] args) {
        String[] names = {"January","February","March","April","May","June",
            "July","August","September","October","November","December"};
        int[][] months = {{2024,2},{2026,8},{2026,11}};
        int[] offsets = {0,3,2,5,0,3,5,1,4,6,2,4};
        for (int index = 0; index < months.length; index++) {
            if (index > 0) System.out.println();
            int year = months[index][0], month = months[index][1];
            int y = month < 3 ? year - 1 : year;
            int weekday = (y + y / 4 - y / 100 + y / 400 + offsets[month - 1] + 1) % 7;
            int[] lengths = {31,28,31,30,31,30,31,31,30,31,30,31};
            if (year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)) lengths[1] = 29;
            System.out.println(names[month - 1] + " " + year);
            System.out.println("Su Mo Tu We Th Fr Sa");
            List<String> week = new ArrayList<>(java.util.Collections.nCopies(weekday, "  "));
            for (int day = 1; day <= lengths[month - 1]; day++) {
                week.add(String.format(Locale.ROOT,"%2d",day));
                if (week.size() == 7) {
                    System.out.println(String.join(" ",week));
                    week.clear();
                }
            }
            if (!week.isEmpty()) System.out.println(String.join(" ",week));
        }
    }
}
