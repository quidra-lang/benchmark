import java.util.*;
final class AlphaMiner {
    record Candidate(int left, int right) {}
    static Candidate extend(Candidate pair, int activity, int side, String[][] relation) {
        int mask = 1 << activity, group = side == 0 ? pair.left() : pair.right(),
            other = side == 0 ? pair.right() : pair.left();
        if ((group & mask) != 0 || !relation[activity][activity].equals("#"))
            return null;
        for (int i = 0; i < relation.length; i++) {
            if ((group & (1 << i)) != 0 && !relation[activity][i].equals("#"))
                return null;
            if ((other & (1 << i)) != 0 &&
                !(side == 0 ? relation[activity][i] : relation[i][activity]).equals("->"))
                return null;
        }
        return side == 0 ? new Candidate(group | mask, other) : new Candidate(other, group | mask);
    }
    static int compareMask(int a, int b) {
        while (a != 0 && b != 0) {
            int first = Integer.numberOfTrailingZeros(a), second = Integer.numberOfTrailingZeros(b);
            if (first != second)
                return Integer.compare(first, second);
            a &= a - 1;
            b &= b - 1;
        }
        return a == b ? 0 : a == 0 ? -1 : 1;
    }
    static int compare(Candidate a, Candidate b) {
        int order = compareMask(a.left(), b.left());
        return order != 0 ? order : compareMask(a.right(), b.right());
    }
    static Map<Dfg.Pair, Long> triangles(List<Dfg.Trace> log) {
        Map<Dfg.Pair, Long> result = new HashMap<>();
        for (Dfg.Trace trace : log)
            for (int i = 2; i < trace.activities().size(); i++) {
                String a = trace.activities().get(i - 2), b = trace.activities().get(i - 1),
                       c = trace.activities().get(i);
                if (a.equals(c) && !a.equals(b))
                    result.merge(new Dfg.Pair(a, b), trace.weight(), Long::sum);
            }
        return result;
    }
    static String plus(Map<Dfg.Pair, Long> counts, Map<Dfg.Pair, Long> triangles, String a,
                       String b) {
        boolean forward = Dfg.count(counts, a, b) > 0, reverse = Dfg.count(counts, b, a) > 0,
                loop = !a.equals(b) && Dfg.count(triangles, a, b) > 0 &&
                       Dfg.count(triangles, b, a) > 0;
        return forward && (!reverse || loop) ? "->"
        : reverse && (!forward || loop)      ? "<-"
        : forward && reverse                 ? "||"
                                             : "#";
    }
}
