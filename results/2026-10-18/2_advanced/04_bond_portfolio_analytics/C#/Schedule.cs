using System;
using System.Collections.Generic;

static class Schedule
{
    public static List<int> Build(int issue, int maturity, int frequency, bool eom, bool longStub)
    {
        DateOnly anchor = Dates.Civil(maturity); bool endMonth = eom && anchor.Day == Dates.MonthLength(anchor.Year, anchor.Month);
        List<int> dates = []; int boundary = maturity;
        while (boundary > issue)
        {
            dates.Add(boundary); int index = anchor.Year * 12 + anchor.Month - 1 - 12 / frequency * dates.Count;
            int year = index / 12, month = index % 12 + 1, length = Dates.MonthLength(year, month);
            boundary = Dates.DayNumber(year, month, endMonth ? length : Math.Min(anchor.Day, length));
        }
        if (longStub && boundary != issue && dates.Count >= 2) dates.RemoveAt(dates.Count - 1);
        dates.Add(issue); dates.Reverse(); return dates;
    }
}
