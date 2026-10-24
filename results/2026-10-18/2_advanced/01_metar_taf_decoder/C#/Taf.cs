#nullable enable
using System;
using System.Collections.Generic;

static class Taf
{
    public static readonly List<Slot> Slots = new()
    {
        new("wind", false), new("visibility", false), new("weather", true), new("cloud", true)
    };

    private static bool Indicator(Group g) => g.Text is "BECMG" or "TEMPO" or "PROB30" or "PROB40"
        || Groups.Match(@"FM\d{6}", g.Text) != null;

    public static (List<Group> Base, List<Change> Changes) Split(List<Group> body, Report r, Calendar calendar, ErrorSink error)
    {
        int i = 0;
        while (i < body.Count && !Indicator(body[i])) i++;
        var baseGroups = body.GetRange(0, i);
        var changes = new List<Change>();
        while (i < body.Count)
        {
            var g = body[i++];
            var c = new Change { Kind = g.Text.StartsWith("FM", StringComparison.Ordinal) ? "FM" : g.Text };
            if ((c.Kind is "PROB30" or "PROB40") && i < body.Count && body[i].Text == "TEMPO")
            {
                c.Kind += " TEMPO";
                i++;
            }
            int end = i;
            while (end < body.Count && !Indicator(body[end])) end++;
            if (c.Kind == "FM")
            {
                c.Time = calendar.ChangeTime(g.Text, r.IssueDay);
                if (c.Time < r.Start || c.Time >= r.End) error(g.Position, "invalid period", g.Text);
                else
                {
                    c.Groups = body.GetRange(i, end - i);
                    changes.Add(c);
                }
            }
            else if (i == end || Groups.Match(@"\d{4}/\d{4}", body[i].Text) == null)
                error(g.Position, "missing period", c.Kind);
            else
            {
                var period = calendar.Period(body[i].Text, r.IssueDay);
                if (period == null || period.Value.Start < r.Start || period.Value.End > r.End)
                    error(body[i].Position, "invalid period", body[i].Text);
                else
                {
                    c.Start = period.Value.Start;
                    c.End = period.Value.End;
                    c.Groups = body.GetRange(i + 1, end - i - 1);
                    changes.Add(c);
                }
            }
            i = end;
        }
        return (baseGroups, changes);
    }

    private static Section State(Section s) => new()
    {
        Wind = s.Wind, Visibility = s.Visibility, Weather = s.Weather, Cloud = s.Cloud
    };

    private static Section Overlay(Section s, Section c) => new()
    {
        Wind = c.Wind ?? s.Wind,
        Visibility = c.Visibility ?? s.Visibility,
        Weather = c.Weather ?? s.Weather,
        Cloud = c.Cloud ?? s.Cloud
    };

    public static void Expand(Report r)
    {
        for (long h = r.Start; h < r.End; h += 60)
        {
            Section p = State(r.Base!);
            foreach (var c in r.Changes)
            {
                if (c.Kind == "FM" && c.Time <= h) p = State(c.State!);
                if (c.Kind == "BECMG" && c.End <= h) p = Overlay(p, c.State!);
            }
            Program.Derive(p);
            var hour = new Hour { Prevailing = p };
            foreach (var c in r.Changes)
                if (c.Kind is not ("FM" or "BECMG") && c.Start <= h && h < c.End)
                {
                    Section s = Overlay(p, c.State!);
                    Program.Derive(s);
                    hour.Temporary.Add(new Temporary(c.Kind, s));
                }
            r.Timeline[h] = hour;
        }
    }
}
