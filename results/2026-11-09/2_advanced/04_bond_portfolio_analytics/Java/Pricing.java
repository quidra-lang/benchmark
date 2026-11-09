import java.util.ArrayList;
import java.util.List;
import java.util.function.DoubleUnaryOperator;

final class Bisection {
    static double solve(DoubleUnaryOperator function, double low, double high, double target) {
        for (int i = 0; i < 80; i++) { double middle = (low + high) / 2; if (function.applyAsDouble(middle) > target) low = middle; else high = middle; } return (low + high) / 2;
    }
}
record Risk(double macaulay, double modified, double convexity, double dv01) {}
final class YieldPricer {
    private final List<Double> flows;
    private final double fraction;
    private final int frequency;
    private final long outstanding;
    YieldPricer(List<Double> flows, double fraction, int frequency, long outstanding) { this.flows = flows; this.fraction = fraction; this.frequency = frequency; this.outstanding = outstanding; }
    private List<Double> values(double rate) {
        double first = 1 + fraction * rate / frequency, growth = 1 + rate / frequency, factor = 1; List<Double> values = new ArrayList<>();
        for (double cash : flows) { values.add(cash / (first * factor)); factor *= growth; } return values;
    }
    double dirty(double rate) { double total = 0; for (double value : values(rate)) total += value; return total * 100 / outstanding; }
    double solve(double target) { return Bisection.solve(this::dirty, 0, 1, target); }
    Risk measure(double rate) {
        List<Double> present = values(rate); double growth = 1 + rate / frequency, total = 0, weighted = 0, curvature = 0;
        for (int i = 0; i < present.size(); i++) { double years = (i + fraction) / frequency; total += present.get(i); weighted += years * present.get(i); curvature += years * (years + 1.0 / frequency) * present.get(i); }
        double macaulay = weighted / total;
        return new Risk(macaulay, macaulay / growth, curvature / (total * growth * growth), (dirty(rate - 0.0001) - dirty(rate + 0.0001)) / 2);
    }
}
