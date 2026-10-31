import java.util.ArrayList;
import java.util.List;

record Flow(int days, double amount) {}
record Pillar(int maturity, int coupon, int frequency) {}
final class ZeroCurve {
    final int[] days;
    final double[] rates;
    ZeroCurve(int[] days, double[] rates) { this.days = days; this.rates = rates; }
    double zero(int day) {
        if (day <= days[0]) return rates[0]; if (day >= days[days.length - 1]) return rates[rates.length - 1];
        int index = 1; while (days[index] < day) index++; if (days[index] == day) return rates[index];
        return rates[index - 1] + (rates[index] - rates[index - 1]) * ((double) (day - days[index - 1]) / (days[index] - days[index - 1]));
    }
    double discount(int day, double spread) {
        double rate = zero(day) + spread, growth = 1; for (int i = 0; i < day / 365; i++) growth *= 1 + rate; return 1 / (growth * (1 + rate * (day % 365) / 365));
    }
    double presentValue(List<Flow> flows, double spread) { double total = 0; for (Flow flow : flows) total += flow.amount() * discount(flow.days(), spread); return total; }
    double forward(int start, int end) { return (discount(start, 0) / discount(end, 0) - 1) * 365 / (end - start); }
    ZeroCurve shifted(double[] deltas) { double[] shifted = new double[rates.length]; for (int i = 0; i < rates.length; i++) shifted[i] = rates[i] + deltas[i]; return new ZeroCurve(days, shifted); }
    double spread(List<Flow> flows, double target) { return Bisection.solve(spread -> presentValue(flows, spread), -0.5, 0.5, target); }
    static ZeroCurve bootstrap(int settlement, List<Pillar> pillars) {
        List<Integer> days = new ArrayList<>(); List<Double> rates = new ArrayList<>();
        for (Pillar pillar : pillars) {
            List<Integer> dates = Schedule.build(settlement, pillar.maturity(), pillar.frequency(), false, false); List<Flow> flows = new ArrayList<>();
            for (int i = 1; i < dates.size(); i++) { Fraction fraction = Daycount.between("30/360", dates.get(i - 1), dates.get(i)); double cash = pillar.coupon() * (double) fraction.numerator() / (10000 * fraction.denominator()); if (i + 1 == dates.size()) cash += 1; flows.add(new Flow(dates.get(i) - settlement, cash)); }
            days.add(pillar.maturity() - settlement);
            double rate = Bisection.solve(trial -> {
                int[] ds = days.stream().mapToInt(Integer::intValue).toArray(); double[] rs = new double[rates.size() + 1]; for (int i = 0; i < rates.size(); i++) rs[i] = rates.get(i); rs[rates.size()] = trial;
                return new ZeroCurve(ds, rs).presentValue(flows, 0);
            }, 0, 1, 1);
            rates.add(rate);
        }
        return new ZeroCurve(days.stream().mapToInt(Integer::intValue).toArray(), rates.stream().mapToDouble(Double::doubleValue).toArray());
    }
}
