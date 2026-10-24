#nullable enable
using System.Collections.Generic;
using System.Linq;

static class Verification
{
    public static readonly string[] Categories = { "VFR", "MVFR", "IFR", "LIFR" };

    public static bool Covers(Report t, Report o)
    {
        long h = o.Time - o.Time % 60;
        return t.Time <= o.Time && t.Start <= h && h < t.End;
    }

    private static Report? Select(List<Report> tafs, Report o)
    {
        Report? selected = null;
        foreach (var t in tafs)
            if (Covers(t, o) && (selected == null || t.Time > selected.Time || t.Time == selected.Time && t.Number > selected.Number))
                selected = t;
        return selected;
    }

    public sealed record Choice(Report Observation, Hour Forecast, bool TemporaryHit);

    public sealed class Result
    {
        public long[,] Table = new long[4, 4], Buckets = new long[5, 2];
        public long[] Rows = new long[4], Columns = new long[4];
        public long Total, NoForecast, Hits, TemporaryHits, Expected;
        public List<Choice> Choices = new();

        public string HitRate => Units.Fraction(Hits, Total);
        public string TemporaryRate => Units.Fraction(TemporaryHits, Total);
        public string Skill => Units.Fraction(Total * Hits - Expected, Total * Total - Expected);
        public string Pod(int i) => Units.Fraction(Table[i, i], Columns[i]);
        public string Far(int i) => Units.Fraction(Rows[i] - Table[i, i], Rows[i]);
    }

    public static Result Analyze(List<Report> observations, List<Report> tafs)
    {
        var a = new Result();
        foreach (var o in observations)
        {
            long h = o.Time - o.Time % 60;
            string category = o.Main!.Category;
            foreach (var t in tafs)
                if (Covers(t, o))
                {
                    int bucket = (int)((h - t.Start) / 360);
                    a.Buckets[bucket, 1]++;
                    if (t.Timeline[h].Prevailing.Category == category) a.Buckets[bucket, 0]++;
                }
            var chosen = Select(tafs, o);
            if (chosen == null) { a.NoForecast++; continue; }
            var f = chosen.Timeline[h];
            string fc = f.Prevailing.Category;
            bool hit = fc == category;
            bool temporaryHit = hit || f.Temporary.Any(t => t.State.Category == category);
            a.Table[System.Array.IndexOf(Categories, fc), System.Array.IndexOf(Categories, category)]++;
            if (hit) a.Hits++;
            if (temporaryHit) a.TemporaryHits++;
            a.Choices.Add(new Choice(o, f, temporaryHit));
        }
        for (int i = 0; i < 4; i++)
            for (int j = 0; j < 4; j++)
            {
                a.Rows[i] += a.Table[i, j];
                a.Columns[j] += a.Table[i, j];
                a.Total += a.Table[i, j];
            }
        for (int i = 0; i < 4; i++) a.Expected += a.Rows[i] * a.Columns[i];
        return a;
    }
}
