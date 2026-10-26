using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;

static class Dendrogram
{
    public static int[][] Children(List<Agglomerative.Merge> merges, int count)
    {
        int[] minimum = new int[2 * count - 1];
        for (int u = 0; u < count; u++) minimum[u] = u;
        int[][] children = new int[merges.Count][];
        for (int step = 0; step < merges.Count; step++)
        {
            Agglomerative.Merge merge = merges[step];
            children[step] = minimum[merge.A] < minimum[merge.B] ? [merge.A, merge.B] : [merge.B, merge.A];
            minimum[count + step] = Math.Min(minimum[merge.A], minimum[merge.B]);
        }
        return children;
    }

    public static int[] LeafOrder(int[][] children, int count)
    {
        List<int> order = [];
        Stack<int> pending = new();
        pending.Push(count + children.Length - 1);
        while (pending.Count > 0)
        {
            int node = pending.Pop();
            if (node < count) order.Add(node);
            else { pending.Push(children[node - count][1]); pending.Push(children[node - count][0]); }
        }
        return order.ToArray();
    }

    public static int Column(double height, double maximum, int width)
    {
        double position = Math.Floor(height / maximum * width);
        return position > width ? width + 1 : (int)position;
    }
    static void Mark(int[][] grid, int row, int column, int priority) => grid[row][column] = Math.Max(grid[row][column], priority);

    public static List<string> Rows(List<Agglomerative.Merge> merges, int[][] children, int[] order, string[] idents, string[] labels, double maximum, int[] cutColumns, int width)
    {
        int count = order.Length;
        int[][] grid = Enumerable.Range(0, count).Select(_ => new int[width + 1]).ToArray();
        int[] anchor = new int[2 * count - 1];
        for (int row = 0; row < count; row++) anchor[order[row]] = row;
        foreach (int x in cutColumns) if (x <= width) for (int row = 0; row < count; row++) Mark(grid, row, x, 1);
        int[] columns = merges.Select(merge => Column(merge.Height, maximum, width)).ToArray();
        for (int step = 0; step < children.Length; step++)
        {
            int upper = children[step][0], lower = children[step][1], x = columns[step];
            Mark(grid, anchor[upper], x, 4);
            Mark(grid, anchor[lower], x, 4);
            for (int row = anchor[upper] + 1; row < anchor[lower]; row++) Mark(grid, row, x, 3);
            foreach (int child in children[step])
            {
                int start = child < count ? 0 : columns[child - count] + 1;
                for (int position = start; position < x; position++) Mark(grid, anchor[child], position, 2);
            }
            anchor[count + step] = (anchor[upper] + anchor[lower]) / 2;
        }
        int idWidth = idents.Max(value => value.Length), labelWidth = labels.Max(value => value.Length);
        List<string> rows = [];
        for (int row = 0; row < count; row++)
        {
            int leaf = order[row];
            StringBuilder text = new(idents[leaf].PadRight(idWidth) + " " + labels[leaf].PadRight(labelWidth) + " ");
            foreach (int mark in grid[row]) text.Append(" :-|+"[mark]);
            rows.Add(text.ToString().TrimEnd());
        }
        StringBuilder scale = new(new string(' ', idWidth + labelWidth + 2));
        for (int x = 0; x <= width; x++) scale.Append(x % 10 == 0 ? '+' : '-');
        rows.Add(scale.ToString());
        return rows;
    }
}
