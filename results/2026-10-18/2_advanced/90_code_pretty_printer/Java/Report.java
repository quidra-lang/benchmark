import java.util.*;
final class Report {
    static void tree(Doc doc, int depth, List<String> lines) {
        String prefix = "  ".repeat(depth);
        switch (doc) {
        case DocBuilder.Text text -> lines.add(prefix + "text \"" + text.value() + "\"");
        case DocBuilder.Suffix suffix -> lines.add(prefix + "suffix \"" + suffix.value() + "\"");
        case DocBuilder.IfBreak conditional ->
            lines.add(prefix + "if_break \"" + conditional.broken() + "\" \"" + conditional.flat() +
                      "\"");
        case DocBuilder.Concat concat -> {
            for (Doc child : concat.items())
                tree(child, depth, lines);
        }
        case DocBuilder.Group group -> {
            lines.add(prefix + "group " + group.mode);
            tree(group.child, depth + 1, lines);
        }
        case DocBuilder.Nest nest -> {
            lines.add(prefix + "nest " + nest.amount());
            tree(nest.child(), depth + 1, lines);
        }
        case DocBuilder.Align align -> {
            lines.add(prefix + "align");
            tree(align.child(), depth + 1, lines);
        }
        case DocBuilder.Break marker -> lines.add(prefix + marker.name().toLowerCase(Locale.ROOT));
        }
    }
    static List<String> tree(Doc doc) {
        List<String> lines = new ArrayList<>();
        tree(doc, 0, lines);
        return lines;
    }
    static final class Hunk {
        int oldStart, newStart, deletes, inserts;
        List<String> lines = new ArrayList<>();
        Hunk(int oldStart, int newStart) {
            this.oldStart = oldStart;
            this.newStart = newStart;
        }
    }
    static List<String> diff(List<String> original, List<String> formatted) {
        int n = original.size(), m = formatted.size();
        int[][] table = new int[n + 1][m + 1];
        for (int i = n - 1; i >= 0; i--)
            for (int j = m - 1; j >= 0; j--)
                table[i][j] = original.get(i).equals(formatted.get(j))
                                  ? table[i + 1][j + 1] + 1
                                  : Math.max(table[i + 1][j], table[i][j + 1]);
        int i = 0, j = 0, deleted = 0, inserted = 0;
        List<Hunk> hunks = new ArrayList<>();
        Hunk current = null;
        while (i < n || j < m) {
            if (i < n && j < m && original.get(i).equals(formatted.get(j))) {
                if (current != null) {
                    hunks.add(current);
                    current = null;
                }
                i++;
                j++;
                continue;
            }
            if (current == null)
                current = new Hunk(i, j);
            if (j == m || i < n && table[i + 1][j] >= table[i][j + 1]) {
                current.deletes++;
                deleted++;
                current.lines.add("-" + original.get(i++));
            } else {
                current.inserts++;
                inserted++;
                current.lines.add("+" + formatted.get(j++));
            }
        }
        if (current != null)
            hunks.add(current);
        List<String> result = new ArrayList<>();
        result.add("hunks=" + hunks.size() + " deleted=" + deleted + " inserted=" + inserted);
        for (Hunk hunk : hunks) {
            result.add("@@ -" + (hunk.oldStart + (hunk.deletes > 0 ? 1 : 0)) + "," + hunk.deletes +
                       " +" + (hunk.newStart + (hunk.inserts > 0 ? 1 : 0)) + "," + hunk.inserts +
                       " @@");
            result.addAll(hunk.lines);
        }
        return result;
    }
}
