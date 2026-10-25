import java.util.List;

record Center(int chart, double value, double fraction) {}
record LotPoint(double value, double lcl, double ucl, double z, String status) {}
final class AttributeCharts {
    static Center centerLine(int chart, List<Lot> lots, List<Integer> numbers) {
        long defectives = 0, defects = 0, inspected = 0;
        for (int number : numbers) {
            Lot lot = lots.get(number - 1);
            defectives += lot.defectives(); defects += lot.defects(); inspected += lot.inspected();
        }
        double fraction = (double)defectives / inspected;
        double value = switch (chart) { case 0 -> fraction; case 1 -> (double)defectives / numbers.size(); case 2 -> (double)defects / numbers.size(); default -> (double)defects / inspected; };
        return new Center(chart, value, fraction);
    }
    static LotPoint point(Lot lot, Center center) {
        double cl = center.value(), value, sigma;
        switch (center.chart()) {
            case 0 -> { value = (double)lot.defectives() / lot.inspected(); sigma = Math.sqrt(cl * (1 - cl) / lot.inspected()); }
            case 1 -> { value = lot.defectives(); sigma = Math.sqrt(cl * (1 - center.fraction())); }
            case 2 -> { value = lot.defects(); sigma = Math.sqrt(cl); }
            default -> { value = (double)lot.defects() / lot.inspected(); sigma = Math.sqrt(cl / lot.inspected()); }
        }
        double lcl = Math.max(0, cl - 3 * sigma), ucl = cl + 3 * sigma;
        return new LotPoint(value, lcl, ucl, (value - cl) / sigma, value > ucl ? "high" : value < lcl ? "low" : "ok");
    }
}
