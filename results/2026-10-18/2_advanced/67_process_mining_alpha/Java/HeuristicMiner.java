import java.util.*;
final class HeuristicMiner {
    static Report.Fraction dependency(Map<Dfg.Pair, Long> counts, String a, String b) {
        long forward = Dfg.count(counts, a, b), reverse = Dfg.count(counts, b, a);
        return new Report.Fraction(forward - reverse, forward + reverse + 1);
    }
    static Report.Fraction loop(long count) { return new Report.Fraction(count, count + 1); }
    static Report.Fraction split(Map<Dfg.Pair, Long> counts, String a, String b, String c) {
        return new Report.Fraction(Dfg.count(counts, b, c) + Dfg.count(counts, c, b),
                                   Dfg.count(counts, a, b) + Dfg.count(counts, a, c) + 1);
    }
    static Report.Fraction join(Map<Dfg.Pair, Long> counts, String a, String b, String c) {
        return new Report.Fraction(Dfg.count(counts, b, c) + Dfg.count(counts, c, b),
                                   Dfg.count(counts, b, a) + Dfg.count(counts, c, a) + 1);
    }
}
