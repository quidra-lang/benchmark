using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;
public static class Evaluation {
    public static readonly string[] REGIONS = { "nonocc", "all", "disc" };
    public record Regions(List<int> nonocc, List<int> all, List<int> disc, List<int> occluded) {
        public List<int> At(int i) { return i == 0 ? nonocc : i == 1 ? all : disc; }
    }
    public record Metrics(int pixels, int valid, int bad1, int bad2, long error, int exact) {
        public string Mae() { return valid == 0 ? "-" : Refinement.Two(error, valid); }
    }
    public static Regions ComputeRegions(int[] truth, int w, int h) {
        List<int> all = new(), visible = new(), hidden = new(), disc = new();
        for (int p = 0; p < truth.Length; p++)
            if (truth[p] != 0) {
                all.Add(p);
                int x = p % w, y = p / w, g = truth[p], target = x - g;
                bool occluded = target < 0;
                for (int x2 = 0; x2 < w && !occluded; x2++)
                    if (truth[y * w + x2] > g && x2 - truth[y * w + x2] == target)
                        occluded = true;
                if (occluded)
                    hidden.Add(p);
                else
                    visible.Add(p);
            }
        foreach (int p in visible) {
            int x = p % w, y = p / w;
            bool edge = false;
            for (int yy = Math.Max(0, y - 1); yy <= Math.Min(h - 1, y + 1); yy++)
                for (int xx = Math.Max(0, x - 1); xx <= Math.Min(w - 1, x + 1); xx++) {
                    int q = yy * w + xx;
                    if (q != p && truth[q] != 0 && Math.Abs(truth[q] - truth[p]) >= 2)
                        edge = true;
                }
            if (edge)
                disc.Add(p);
        }
        return new Regions(visible, all, disc, hidden);
    }
    public static Metrics Evaluate(int[] image, int[] truth, List<int> region) {
        int valid = 0, bad1 = 0, bad2 = 0, exact = 0;
        long error = 0;
        foreach (int p in region)
            if (image[p] == 0) {
                bad1++;
                bad2++;
            } else {
                valid++;
                int e = Math.Abs(image[p] - truth[p]);
                error += e;
                if (e > 1)
                    bad1++;
                if (e > 2)
                    bad2++;
                if (e == 0)
                    exact++;
            }
        return new Metrics(region.Count, valid, bad1, bad2, error, exact);
    }
    public static long Gcd(long a, long b) {
        while (b != 0) {
            long t = a % b;
            a = b;
            b = t;
        }
        return a;
    }
    public static string Ratio(long a, long b) {
        if (b == 0)
            return "0/1 0.00";
        long divisor = Gcd(a, b);
        return a / divisor + "/" + b / divisor + " " + Refinement.Two(100 * a, b);
    }
}
