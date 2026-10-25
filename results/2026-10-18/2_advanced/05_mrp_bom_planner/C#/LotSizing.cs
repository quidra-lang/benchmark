using System;

static class LotSizing
{
    public static long Size(Item item, int week, long projected, long[] receipts, long[] gross, int horizon)
    {
        long quantity = item.Safety - projected;
        if (item.Rule == "LFL") return quantity;
        if (item.Rule == "FOQ") return (quantity + item.First - 1) / item.First * item.First;
        if (item.Rule == "MIN") return (Math.Max(quantity, item.First) + item.Second - 1) / item.Second * item.Second;
        int end = (int)Math.Min(week + item.First - 1, horizon);
        for (int later = week + 1; later <= end; later++) { projected += receipts[later] - gross[later]; quantity = Math.Max(quantity, item.Safety - projected); }
        return quantity;
    }
}
