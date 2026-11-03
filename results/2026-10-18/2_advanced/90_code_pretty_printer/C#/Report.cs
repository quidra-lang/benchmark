using System;
using System.Collections.Generic;
using System.Linq;
static class Report {
    public static void Tree(Document document, int depth, IReadOnlyDictionary<int, string> modes, List<string> output) {
        string prefix = new(' ', depth * 2);
        switch (document) {
            case Document.Concat c: foreach (Document part in c.Children) Tree(part, depth, modes, output);
            break;
            case Document.Text t: output.Add(prefix + $"text \"{t.Value}\"");
            break;
            case Document.Suffix s: output.Add(prefix + $"suffix \"{s.Value}\"");
            break;
            case Document.IfBreak b: output.Add(prefix + $"if_break \"{b.Broken}\" \"{b.Flat}\"");
            break;
            case Document.Group g: output.Add(prefix + $"group {modes[g.Id]}");
            Tree(g.Child, depth + 1, modes, output);
            break;
            case Document.Nest n: output.Add(prefix + $"nest {n.Amount}");
            Tree(n.Child, depth + 1, modes, output);
            break;
            case Document.Align a: output.Add(prefix + "align");
            Tree(a.Child, depth + 1, modes, output);
            break;
            case Document.Line: output.Add(prefix + "line");
            break;
            case Document.Softline: output.Add(prefix + "softline");
            break;
            case Document.Hardline: output.Add(prefix + "hardline");
            break;
            case Document.BreakParent: output.Add(prefix + "break_parent");
            break;
        }
    }
    public static List<string> Diff(IReadOnlyList<string> a, IReadOnlyList<string> b) {
        int n = a.Count, m = b.Count;
        int[,] lcs = new int[n + 1, m + 1];
        for (int x = n - 1; x >= 0; x--) for (int y = m - 1; y >= 0; y--) lcs[x, y] = a[x] == b[y] ? lcs[x + 1, y + 1] + 1 : Math.Max(lcs[x + 1, y], lcs[x, y + 1]);
        int i = 0, j = 0, deleted = 0, inserted = 0;
        List<List<string>> hunks = new();
        while (i < n || j < m) {
            if (i < n && j < m && a[i] == b[j]) {
                i++;
                j++;
                continue;
            }
            int i0 = i, j0 = j, d = 0, e = 0;
            List<string> lines = new();
            while (i < n || j < m) {
                if (i < n && j < m && a[i] == b[j]) break;
                if (j == m || i < n && lcs[i + 1, j] >= lcs[i, j + 1]) {
                    lines.Add("-" + a[i++]);
                    d++;
                } else {
                    lines.Add("+" + b[j++]);
                    e++;
                }
            }
            deleted += d;
            inserted += e;
            hunks.Add(new() {
                $"@@ -{(d > 0 ? i0 + 1 : i0)},{d} +{(e > 0 ? j0 + 1 : j0)},{e} @@"
            });
            hunks[^1].AddRange(lines);
        }
        List<string> result = new() {
            $"hunks={hunks.Count} deleted={deleted} inserted={inserted}"
        };
        result.AddRange(hunks.SelectMany(x => x));
        return result;
    }
}
