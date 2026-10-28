using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public static class Encoders {
    public static CnfIo.Formula Queens(int n) {
        List<int[]> clauses = new();
        for (int r = 0; r < n; r++) {
            int[] row = new int[n];
            for (int c = 1; c <= n; c++)
                row[c - 1] = r * n + c;
            clauses.Add(row);
        }
        for (int a = 1; a <= n * n; a++)
            for (int b = a + 1; b <= n * n; b++) {
                int ar = (a - 1) / n, ac = (a - 1) % n, br = (b - 1) / n, bc = (b - 1) % n;
                if (ar == br || ac == bc || Math.Abs(ar - br) == Math.Abs(ac - bc))
                    clauses.Add(new int[] { -a, -b });
            }
        return new CnfIo.Formula(n * n, clauses);
    }
    public static CnfIo.Formula Pigeon(int p, int h) {
        List<int[]> clauses = new();
        for (int i = 0; i < p; i++) {
            int[] row = new int[h];
            for (int j = 1; j <= h; j++)
                row[j - 1] = i * h + j;
            clauses.Add(row);
        }
        for (int i = 0; i < p; i++)
            for (int a = 1; a <= h; a++)
                for (int b = a + 1; b <= h; b++)
                    clauses.Add(new int[] { -(i * h + a), -(i * h + b) });
        for (int j = 1; j <= h; j++)
            for (int a = 0; a < p; a++)
                for (int b = a + 1; b < p; b++)
                    clauses.Add(new int[] { -(a * h + j), -(b * h + j) });
        return new CnfIo.Formula(p * h, clauses);
    }
    public static CnfIo.Formula Coloring(int vertices, List<int[]> edges, int k) {
        List<int[]> clauses = new();
        for (int x = 0; x < vertices; x++) {
            int[] row = new int[k];
            for (int c = 1; c <= k; c++)
                row[c - 1] = x * k + c;
            clauses.Add(row);
        }
        for (int x = 0; x < vertices; x++)
            for (int a = 1; a <= k; a++)
                for (int b = a + 1; b <= k; b++)
                    clauses.Add(new int[] { -(x * k + a), -(x * k + b) });
        foreach (int[] edge in edges)
            for (int c = 1; c <= k; c++)
                clauses.Add(new int[] { -((edge[0] - 1) * k + c), -((edge[1] - 1) * k + c) });
        return new CnfIo.Formula(vertices * k, clauses);
    }
    public static int[] Positions(bool[] model, int rows, int width) {
        int[] positions = new int[rows];
        for (int r = 0; r < rows; r++)
            for (int c = 1; c <= width; c++)
                if (model[r * width + c])
                    positions[r] = c;
        return positions;
    }
}
