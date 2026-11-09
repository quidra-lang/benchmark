using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;
public static class HeuristicMiner {
    public static Report.Fraction Dependency(Dictionary<Dfg.Pair, long> counts, string a,
                                             string b) {
        long forward = Dfg.Count(counts, a, b), reverse = Dfg.Count(counts, b, a);
        return new Report.Fraction(forward - reverse, forward + reverse + 1);
    }
    public static Report.Fraction Loop(long count) => new(count, count + 1);
    public static Report.Fraction
    Split(Dictionary<Dfg.Pair, long> counts, string a, string b,
          string c) => new(Dfg.Count(counts, b, c) + Dfg.Count(counts, c, b),
                           Dfg.Count(counts, a, b) + Dfg.Count(counts, a, c) + 1);
    public static Report.Fraction
    Join(Dictionary<Dfg.Pair, long> counts, string a, string b,
         string c) => new(Dfg.Count(counts, b, c) + Dfg.Count(counts, c, b),
                          Dfg.Count(counts, b, a) + Dfg.Count(counts, c, a) + 1);
}
