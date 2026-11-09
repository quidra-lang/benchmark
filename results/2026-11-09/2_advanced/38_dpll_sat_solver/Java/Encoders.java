import java.util.*;
final class Encoders {
    static CnfIo.Formula queens(int n) {
        List<int[]> clauses = new ArrayList<>();
        for (int r = 0; r < n; r++) {
            int[] row = new int[n];
            for (int c = 1; c <= n; c++)
                row[c - 1] = r * n + c;
            clauses.add(row);
        }
        for (int a = 1; a <= n * n; a++)
            for (int b = a + 1; b <= n * n; b++) {
                int ar = (a - 1) / n, ac = (a - 1) % n, br = (b - 1) / n, bc = (b - 1) % n;
                if (ar == br || ac == bc || Math.abs(ar - br) == Math.abs(ac - bc))
                    clauses.add(new int[] {-a, -b});
            }
        return new CnfIo.Formula(n * n, clauses);
    }
    static CnfIo.Formula pigeon(int p, int h) {
        List<int[]> clauses = new ArrayList<>();
        for (int i = 0; i < p; i++) {
            int[] row = new int[h];
            for (int j = 1; j <= h; j++)
                row[j - 1] = i * h + j;
            clauses.add(row);
        }
        for (int i = 0; i < p; i++)
            for (int a = 1; a <= h; a++)
                for (int b = a + 1; b <= h; b++)
                    clauses.add(new int[] {-(i * h + a), -(i * h + b)});
        for (int j = 1; j <= h; j++)
            for (int a = 0; a < p; a++)
                for (int b = a + 1; b < p; b++)
                    clauses.add(new int[] {-(a * h + j), -(b * h + j)});
        return new CnfIo.Formula(p * h, clauses);
    }
    static CnfIo.Formula coloring(int vertices, List<int[]> edges, int k) {
        List<int[]> clauses = new ArrayList<>();
        for (int x = 0; x < vertices; x++) {
            int[] row = new int[k];
            for (int c = 1; c <= k; c++)
                row[c - 1] = x * k + c;
            clauses.add(row);
        }
        for (int x = 0; x < vertices; x++)
            for (int a = 1; a <= k; a++)
                for (int b = a + 1; b <= k; b++)
                    clauses.add(new int[] {-(x * k + a), -(x * k + b)});
        for (int[] edge : edges)
            for (int c = 1; c <= k; c++)
                clauses.add(new int[] {-((edge[0] - 1) * k + c), -((edge[1] - 1) * k + c)});
        return new CnfIo.Formula(vertices * k, clauses);
    }
    static int[] positions(boolean[] model, int rows, int width) {
        int[] positions = new int[rows];
        for (int r = 0; r < rows; r++)
            for (int c = 1; c <= width; c++)
                if (model[r * width + c])
                    positions[r] = c;
        return positions;
    }
}
