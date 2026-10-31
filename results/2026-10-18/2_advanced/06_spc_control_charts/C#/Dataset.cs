using System.Globalization;

record Constants(double A2, double A3, double B3, double B4, double D3, double D4, double D2, double C4);
sealed class Settings
{
    public string Characteristic = "";
    public int Lsl, Usl, Target, Size, Phase1, Passes, Span, Gap, Bin, Window, Step;
    public double CusumK, CusumH, Weight, EwmaL, CiZ;
    public List<int>[] Rules = Enumerable.Range(0, 7).Select(_ => new List<int>()).ToArray();
}
record Lot(int Number, long Inspected, long Defectives, long Defects);
record Input(Settings Settings, long[] Values, List<Lot> Lots);
static class Dataset
{
    static readonly Constants[] Table = [
        new(1.880,2.659,0,3.267,0,3.267,1.128,0.7979),
        new(1.023,1.954,0,2.568,0,2.574,1.693,0.8862),
        new(0.729,1.628,0,2.266,0,2.282,2.059,0.9213),
        new(0.577,1.427,0,2.089,0,2.114,2.326,0.9400),
        new(0.483,1.287,0.030,1.970,0,2.004,2.534,0.9515),
        new(0.419,1.182,0.118,1.882,0.076,1.924,2.704,0.9594),
        new(0.373,1.099,0.185,1.815,0.136,1.864,2.847,0.9650),
        new(0.337,1.032,0.239,1.761,0.184,1.816,2.970,0.9693),
        new(0.308,0.975,0.284,1.716,0.223,1.777,3.078,0.9727)
    ];
    public static Constants ControlConstants(int size) => Table[size - 2];
    public static Input Read()
    {
        Settings s = new();
        Dictionary<string, string> fields = new();
        string[] names = ["XBAR_R", "R", "XBAR_S", "S", "I", "MR", "STD"];
        foreach (string text in File.ReadLines("input/spec.txt"))
        {
            string[] parts = text.Split(' ');
            if (parts[0] == "rules") s.Rules[Array.IndexOf(names, parts[1])] = parts.Skip(2).Select(int.Parse).ToList();
            else fields[parts[0]] = parts[1];
        }
        int I(string key) => int.Parse(fields[key], CultureInfo.InvariantCulture);
        double D(string key) => double.Parse(fields[key], CultureInfo.InvariantCulture);
        s.Characteristic = fields["characteristic"];
        s.Lsl = I("lsl"); s.Usl = I("usl"); s.Target = I("target");
        s.Size = I("subgroup_size"); s.Phase1 = I("phase1_subgroups"); s.Passes = I("max_passes");
        s.Span = I("ma_span"); s.Gap = I("event_gap"); s.Bin = I("histogram_bin");
        s.Window = I("rolling_window"); s.Step = I("rolling_step"); s.CusumK = D("cusum_k");
        s.CusumH = D("cusum_h"); s.Weight = D("ewma_lambda"); s.EwmaL = D("ewma_l"); s.CiZ = D("ci_z");
        long[] values = File.ReadLines("input/measurements.csv").Skip(1).Select(row => long.Parse(row.Split(',')[2])).ToArray();
        List<Lot> lots = File.ReadLines("input/attributes.csv").Skip(1).Select(row => {
            long[] p = row.Split(',').Select(long.Parse).ToArray();
            return new Lot((int)p[0], p[1], p[2], p[3]);
        }).ToList();
        return new(s, values, lots);
    }
}
