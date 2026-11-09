import java.time.LocalDate;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;

final class Schedule {
    static List<Integer> build(int issue, int maturity, int frequency, boolean eom, boolean longStub) {
        LocalDate anchor = Dates.civil(maturity); boolean endMonth = eom && anchor.getDayOfMonth() == anchor.lengthOfMonth();
        List<Integer> dates = new ArrayList<>(); int boundary = maturity;
        while (boundary > issue) {
            dates.add(boundary); int index = anchor.getYear() * 12 + anchor.getMonthValue() - 1 - 12 / frequency * dates.size();
            int year = index / 12, month = index % 12 + 1, length = Dates.monthLength(year, month);
            boundary = Dates.dayNumber(year, month, endMonth ? length : Math.min(anchor.getDayOfMonth(), length));
        }
        if (longStub && boundary != issue && dates.size() >= 2) dates.removeLast();
        dates.add(issue); Collections.reverse(dates); return dates;
    }
}
