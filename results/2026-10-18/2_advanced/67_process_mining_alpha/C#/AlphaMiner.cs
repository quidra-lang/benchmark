using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;
public static class AlphaMiner {
    public record Candidate(int left, int right) {}
    public static Candidate Extend(Candidate pair, int activity, int side, string[][] relation) {
        int mask = 1 << activity, group = side == 0 ? pair.left : pair.right,
            other = side == 0 ? pair.right : pair.left;
        if ((group & mask) != 0 || relation[activity][activity] != "#")
            return null;
        for (int i = 0; i < relation.Length; i++) {
            if ((group & (1 << i)) != 0 && relation[activity][i] != "#")
                return null;
            if ((other & (1 << i)) != 0 &&
                (side == 0 ? relation[activity][i] : relation[i][activity]) != "->")
                return null;
        }
        return side == 0 ? new Candidate(group | mask, other) : new Candidate(other, group | mask);
    }
    public static int CompareMask(int a, int b) {
        while (a != 0 && b != 0) {
            int first = System.Numerics.BitOperations.TrailingZeroCount((uint)a),
                second = System.Numerics.BitOperations.TrailingZeroCount((uint)b);
            if (first != second)
                return first.CompareTo(second);
            a &= a - 1;
            b &= b - 1;
        }
        return a == b ? 0 : a == 0 ? -1 : 1;
    }
    public static int Compare(Candidate a, Candidate b) {
        int order = CompareMask(a.left, b.left);
        return order != 0 ? order : CompareMask(a.right, b.right);
    }
    public static Dictionary<Dfg.Pair, long> Triangles(List<Dfg.Trace> log) {
        Dictionary<Dfg.Pair, long> result = new();
        foreach (Dfg.Trace trace in log)
            for (int i = 2; i < trace.activities.Count; i++) {
                string a = trace.activities[i - 2], b = trace.activities[i - 1],
                       c = trace.activities[i];
                if (a == c && a != b)
                    result.AddCount(new Dfg.Pair(a, b), trace.weight);
            }
        return result;
    }
    public static string Plus(Dictionary<Dfg.Pair, long> counts,
                              Dictionary<Dfg.Pair, long> triangles, string a, string b) {
        bool forward = Dfg.Count(counts, a, b) > 0, reverse = Dfg.Count(counts, b, a) > 0,
             loop = a != b && Dfg.Count(triangles, a, b) > 0 && Dfg.Count(triangles, b, a) > 0;
        return forward && (!reverse || loop)   ? "->"
               : reverse && (!forward || loop) ? "<-"
               : forward && reverse            ? "||"
                                               : "#";
    }
}
