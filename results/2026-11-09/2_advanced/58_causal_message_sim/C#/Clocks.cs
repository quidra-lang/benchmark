using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public static class Clocks {
    public static void Advance(Processes.State p, Program.Event sender) {
        if (sender == null)
            p.lamport++;
        else {
            p.lamport = Math.Max(p.lamport, sender.lamport) + 1;
            for (int i = 0; i < p.vector.Length; i++)
                p.vector[i] = Math.Max(p.vector[i], sender.vector[i]);
        }
        p.vector[p.index]++;
    }
    public static bool LessEqual(int[] a, int[] b) {
        for (int i = 0; i < a.Length; i++)
            if (a[i] > b[i])
                return false;
        return true;
    }
    public static bool Before(int[] a, int[] b) {
        return !a.SequenceEqual(b) && LessEqual(a, b);
    }
    public static string Relation(int[] a, int[] b) {
        return Before(a, b) ? "->" : Before(b, a) ? "<-" : "||";
    }
    public static bool Deliverable(Program.Packet c, Processes.State p) {
        int[] stamp = c.message.stamp;
        for (int i = 0; i < stamp.Length; i++)
            if (i == c.source ? stamp[i] != p.broadcast[i] + 1 : stamp[i] > p.broadcast[i])
                return false;
        return true;
    }
    public static int[] Missing(Program.Packet c, Processes.State p) {
        List<int> list = new();
        for (int i = 0; i < p.broadcast.Length; i++)
            if (c.message.stamp[i] > p.broadcast[i] + (i == c.source ? 1 : 0))
                list.Add(i);
        int[] values = new int[list.Count];
        for (int i = 0; i < values.Length; i++)
            values[i] = list[i];
        return values;
    }
    public static string Vector(int[] values) {
        List<string> s = new();
        foreach (int value in values)
            s.Add(Convert.ToString(value));
        return string.Join(",", s);
    }
}
