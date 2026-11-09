#nullable enable
using System.Collections.Generic;

static class Metar
{
    public static readonly List<Slot> MainSlots = new()
    {
        new("modifier", false), new("wind", false), new("variation", false), new("visibility", false),
        new("rvr", true), new("weather", true), new("cloud", true), new("temperature", false),
        new("pressure", false), new("noTrend", false)
    };

    public static Value? Test(Slot slot, string text) => Groups.Format(slot.Kind, text);
    private static bool IsTrend(Group g) => g.Text is "BECMG" or "TEMPO";

    public static (List<Group> Main, List<Group> Trends, List<Group> Remarks) Split(List<Group> body)
    {
        int end = body.FindIndex(g => g.Text == "RMK");
        if (end < 0) end = body.Count;
        int start = body.FindIndex(0, end, IsTrend);
        if (start < 0) start = end;
        return (body.GetRange(0, start), body.GetRange(start, end - start),
            end == body.Count ? new() : body.GetRange(end + 1, body.Count - end - 1));
    }

    public static List<Change> Trends(List<Group> body, ErrorSink error)
    {
        var result = new List<Change>();
        for (int i = 0; i < body.Count;)
        {
            int end = i + 1;
            while (end < body.Count && !IsTrend(body[end])) end++;
            var c = new Change { Kind = body[i].Text };
            int cursor = i + 1;
            bool invalid = false;
            while (cursor < end)
            {
                var m = Groups.Match(@"(FM|TL|AT)(\d{2})(\d{2})", body[cursor].Text);
                if (m == null || c.Times.Count > 0 && !(c.Times.Count == 1 && c.Times[0].Kind == "FM" && m[1] == "TL")) break;
                long h = Groups.Number(m[2]), n = Groups.Number(m[3]);
                if (h > 23 || n > 59)
                {
                    error(body[cursor].Position, "invalid period", body[cursor].Text);
                    invalid = true;
                    break;
                }
                c.Times.Add(new TrendTime(m[1], h, n));
                cursor++;
            }
            if (!invalid)
            {
                c.Groups = body.GetRange(cursor, end - cursor);
                result.Add(c);
            }
            i = end;
        }
        return result;
    }

    public static void Remarks(Report r, List<Group> body)
    {
        foreach (var g in body)
        {
            var m = Groups.Match(@"SLP(\d{3})", g.Text);
            if (m != null)
            {
                long n = Groups.Number(m[1]);
                r.Slp.Add(n + (n >= 500 ? 9000 : 10000));
                continue;
            }
            m = Groups.Match(@"T([01])(\d{3})([01])(\d{3})", g.Text);
            if (m != null)
                r.Precise.Add(new Value
                {
                    Temp = Groups.Number(m[2]) * (m[1] == "1" ? -1 : 1),
                    Dew = Groups.Number(m[4]) * (m[3] == "1" ? -1 : 1)
                });
        }
    }
}
