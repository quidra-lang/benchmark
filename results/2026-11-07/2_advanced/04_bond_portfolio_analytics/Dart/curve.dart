import 'daycount.dart';
import 'schedule.dart';
import 'pricing.dart';
class ZeroCurve {
  final List<int> days;
  final List<double> rates;
  ZeroCurve(this.days, this.rates);
  double zero(int day) {
    if (day <= days.first) return rates.first;
    if (day >= days.last) return rates.last;
    var index = 1; while (days[index] < day) index++;
    final low = days[index - 1];
    return rates[index - 1] + (rates[index] - rates[index - 1]) * ((day - low) / (days[index] - low));
  }
  double discount(int day, [double spread = 0.0]) {
    final rate = zero(day) + spread; var growth = 1.0;
    for (var year = 0; year < day ~/ 365; year++) growth *= 1 + rate;
    return 1 / (growth * (1 + rate * (day % 365) / 365));
  }
  double forward(int start, int end) => (discount(start) / discount(end) - 1) * 365 / (end - start);
  ZeroCurve shifted(List<double> deltas) => ZeroCurve(List.of(days), [for (var index = 0; index < rates.length; index++) rates[index] + deltas[index]]);
  double presentValue(List<(int, double)> flows, [double spread = 0.0]) { var total = 0.0; for (final (day, flow) in flows) total += flow * discount(day, spread); return total; }
}
ZeroCurve bootstrap(int settlement, List<(int, int, int)> pillars) {
  final curve = ZeroCurve([], []);
  for (final (maturity, coupon, frequency) in pillars) {
    final dates = couponSchedule(settlement, maturity, frequency, false, false), flows = <(int, double)>[];
    for (var index = 1; index < dates.length; index++) {
      final (n, m) = yearFraction('30/360', dates[index - 1], dates[index]);
      var flow = coupon * n / (10000 * m);
      if (index == dates.length - 1) flow += 1;
      flows.add((dates[index] - settlement, flow));
    }
    curve.days.add(maturity - settlement); curve.rates.add(0.0);
    final last = curve.rates.length - 1;
    final rate = bisection((trial) { curve.rates[last] = trial; return curve.presentValue(flows); }, 0.0, 1.0, 1.0);
    curve.rates[last] = rate;
  }
  return curve;
}
double zSpread(ZeroCurve curve, List<(int, double)> flows, int target) => bisection((spread) => curve.presentValue(flows, spread), -0.5, 0.5, target.toDouble());
