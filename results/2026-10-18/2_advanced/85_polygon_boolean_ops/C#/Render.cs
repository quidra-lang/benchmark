static class Render
{
    public static (List<string> Lines, int[] Counts) Draw(Region region, (Rings A, Rings B)? operands, long[] v)
    {
        long x = v[0], y = v[1], cw = v[2], ch = v[3];
        int cols = (int)v[4], rows = (int)v[5];
        Rings all = region.SelectMany(p => p).ToList();
        List<string> lines = new();
        int[] counts = new int[4];
        for (int j = 0; j < rows; j++)
        {
            System.Text.StringBuilder line = new();
            for (int i = 0; i < cols; i++)
            {
                Point point = new(2 * x + (2 * i + 1) * cw, 2 * y + (2 * (rows - 1 - j) + 1) * ch, 2);
                bool a = operands is {
                } left && RingOps.Interior(point, left.A);
                bool b = operands is {
                } right && RingOps.Interior(point, right.B);
                char c;
                if (RingOps.Interior(point, all)) {
                    counts[0]++;
                    c = '#';
                }
                else if (a && b) {
                    counts[3]++;
                    c = '+';
                }
                else if (a) {
                    counts[1]++;
                    c = 'a';
                }
                else if (b) {
                    counts[2]++;
                    c = 'b';
                }
                else c = '.';
                line.Append(c);
            }
            lines.Add(line.ToString());
        }
        return (lines, counts);
    }
}
