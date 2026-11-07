using System;
using System.Collections.Generic;
using System.Linq;

sealed record Center(string Id, long Minutes, long Efficiency, long Available, string Description);
sealed record Operation(string Item, int Number, string Center, long Setup, long Run)
{
    public long Minutes(long units) => Setup + units * Run;
}
static class Capacity
{
    public static SortedDictionary<string, Center> ReadCenters(List<string> errors)
    {
        SortedDictionary<string, Center> centers = new(StringComparer.Ordinal);
        foreach (Row row in Io.Rows("workcenters.csv"))
        {
            string[] f = row.Fields; long minutes = long.Parse(f[1]), efficiency = long.Parse(f[2]); string error = "";
            if (centers.ContainsKey(f[0])) error = "duplicate center " + f[0]; else if (efficiency < 50 || efficiency > 150) error = "bad efficiency " + efficiency;
            if (error.Length > 0) Io.Error(errors, "workcenters.csv", row.Line, error); else centers[f[0]] = new(f[0], minutes, efficiency, minutes * efficiency / 100, f[3]);
        }
        return centers;
    }
    public static SortedDictionary<string, List<Operation>> ReadRoutings(SortedDictionary<string, Item> items, SortedDictionary<string, Center> centers, Bom bom, List<string> errors)
    {
        SortedDictionary<string, List<Operation>> routes = new(StringComparer.Ordinal);
        foreach (Row row in Io.Rows("routings.csv"))
        {
            string[] f = row.Fields; int number = int.Parse(f[1]); long run = long.Parse(f[4]); string error = "";
            if (!items.ContainsKey(f[0])) error = "unknown item " + f[0];
            else if (!centers.ContainsKey(f[2])) error = "unknown center " + f[2];
            else if (!bom.Manufactured(f[0])) error = "purchased item " + f[0];
            else if (run < 1) error = "bad run time " + run;
            else if (routes.TryGetValue(f[0], out var existing) && existing.Any(o => o.Number == number)) error = $"duplicate {f[0]} operation {number}";
            if (error.Length > 0) Io.Error(errors, "routings.csv", row.Line, error);
            else { if (!routes.TryGetValue(f[0], out var operations)) routes[f[0]] = operations = []; operations.Add(new(f[0], number, f[2], long.Parse(f[3]), run)); }
        }
        foreach (var operations in routes.Values) operations.Sort((a, b) => a.Number.CompareTo(b.Number)); return routes;
    }
    public static int OperationWeek(int receipt, int lead, int index, int count) => Math.Max(receipt - lead + index * lead / count, 1);
    public static long[] Level(long[] loads, long available)
    {
        long[] leveled = new long[loads.Length]; long carry = 0;
        for (int week = loads.Length - 1; week > 1; week--) { long total = loads[week] + carry; leveled[week] = Math.Min(total, available); carry = total - leveled[week]; }
        leveled[1] = loads[1] + carry; return leveled;
    }
}
