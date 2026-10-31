record Row(string Id, double[] Values, string? Label, double? Target);
record Settings(string[] Scalings, int[] Ks, string[] Metrics, string[] Weightings, int Folds, int EditK, int[] Curve, double[] Bins, int Top);
record Input(string[] Features, List<Row> Train, List<Row> Test, Settings Settings);
static class Dataset
{
    static (string[] Features, List<Row> Rows) ReadRows(string name)
    {
        string[] lines = File.ReadAllLines(Path.Combine("input", name)); string[] header = lines[0].Split(',');
        List<Row> rows = [];
        foreach (string text in lines.Skip(1))
        {
            string[] fields = text.Split(',');
            double[] values = fields.Skip(1).Take(fields.Length - 3).Select(double.Parse).ToArray();
            rows.Add(new(fields[0], values, fields[^2].Length == 0 ? null : fields[^2], fields[^1].Length == 0 ? null : double.Parse(fields[^1])));
        }
        return (header[1..^2], rows);
    }
    public static Input Read()
    {
        var train = ReadRows("train.csv"); var test = ReadRows("test.csv");
        Dictionary<string, string[]> values = File.ReadLines("input/params.txt").Select(line => line.Split(' ')).ToDictionary(parts => parts[0], parts => parts.Skip(1).ToArray(), StringComparer.Ordinal);
        Settings settings = new(values["SCALINGS"], values["K_VALUES"].Select(int.Parse).ToArray(), values["METRICS"], values["WEIGHTINGS"], int.Parse(values["FOLDS"][0]), int.Parse(values["EDIT_K"][0]), values["CURVE"].Select(int.Parse).ToArray(), values["BINS"].Select(double.Parse).ToArray(), int.Parse(values["TOP"][0]));
        return new(train.Features, train.Rows, test.Rows, settings);
    }
}
