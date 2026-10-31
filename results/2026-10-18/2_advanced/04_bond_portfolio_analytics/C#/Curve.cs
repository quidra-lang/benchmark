using System;
using System.Collections.Generic;
using System.Linq;

readonly record struct Flow(int Days, double Amount);
readonly record struct Pillar(int Maturity, int Coupon, int Frequency);
sealed class ZeroCurve(int[] days, double[] rates)
{
    public int[] Days { get; } = days;
    public double[] Rates { get; } = rates;
    public double Zero(int day)
    {
        if (day <= Days[0]) return Rates[0]; if (day >= Days[^1]) return Rates[^1];
        int index = 1; while (Days[index] < day) index++; if (Days[index] == day) return Rates[index];
        return Rates[index - 1] + (Rates[index] - Rates[index - 1]) * ((double)(day - Days[index - 1]) / (Days[index] - Days[index - 1]));
    }
    public double Discount(int day, double spread = 0)
    {
        double rate = Zero(day) + spread, growth = 1; for (int i = 0; i < day / 365; i++) growth *= 1 + rate;
        return 1 / (growth * (1 + rate * (day % 365) / 365));
    }
    public double PresentValue(List<Flow> flows, double spread = 0) { double total = 0; foreach (Flow flow in flows) total += flow.Amount * Discount(flow.Days, spread); return total; }
    public double Forward(int start, int end) => (Discount(start) / Discount(end) - 1) * 365 / (end - start);
    public ZeroCurve Shifted(double[] deltas) => new(Days, Rates.Select((rate, i) => rate + deltas[i]).ToArray());
    public double Spread(List<Flow> flows, double target) => Bisection.Solve(spread => PresentValue(flows, spread), -0.5, 0.5, target);
    public static ZeroCurve Bootstrap(int settlement, List<Pillar> pillars)
    {
        List<int> days = []; List<double> rates = [];
        foreach (Pillar pillar in pillars)
        {
            List<int> dates = Schedule.Build(settlement, pillar.Maturity, pillar.Frequency, false, false); List<Flow> flows = [];
            for (int i = 1; i < dates.Count; i++) { Fraction fraction = Daycount.Between("30/360", dates[i - 1], dates[i]); double cash = pillar.Coupon * (double)fraction.Numerator / (10000 * fraction.Denominator); if (i + 1 == dates.Count) cash += 1; flows.Add(new(dates[i] - settlement, cash)); }
            days.Add(pillar.Maturity - settlement);
            double rate = Bisection.Solve(trial => new ZeroCurve(days.ToArray(), rates.Append(trial).ToArray()).PresentValue(flows), 0, 1, 1); rates.Add(rate);
        }
        return new(days.ToArray(), rates.ToArray());
    }
}
