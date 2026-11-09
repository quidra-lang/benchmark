using System;
using System.Collections.Generic;

static class Resolver
{
    public sealed record Period(long Start, long Offset, bool Dst, string Abbreviation)
    {
        public bool SameState(Period other) => Offset == other.Offset && Dst == other.Dst && Abbreviation == other.Abbreviation;
    }

    public sealed class Timeline
    {
        public List<Period> Periods { get; }
        public Timeline(List<Period> periods) { Periods = periods; }

        public int IndexAt(long time)
        {
            int low = 0, high = Periods.Count;
            while (low < high) { int middle = (low + high) / 2; if (Periods[middle].Start <= time) low = middle + 1; else high = middle; }
            return low - 1;
        }

        public Period PeriodAt(long time) => Periods[IndexAt(time)];
        public long EndOf(int index) => index + 1 < Periods.Count ? Periods[index + 1].Start : DayRules.PositiveInfinity;
        public int NearbyFirst(long local) => IndexAt(local - 57600);
        public int NearbyLast(long local) => IndexAt(local + 57600);

        public List<int> Candidates(long local)
        {
            var found = new List<int>();
            for (int index = NearbyFirst(local); index <= NearbyLast(local); index++)
            {
                Period period = Periods[index];
                long time = local - period.Offset;
                if (period.Start <= time && time < EndOf(index)) found.Add(index);
            }
            return found;
        }

        public int SkippingTransition(long local)
        {
            for (int index = Math.Max(1, NearbyFirst(local)); index <= NearbyLast(local); index++)
            {
                long start = Periods[index].Start;
                if (start + Periods[index - 1].Offset <= local && local < start + Periods[index].Offset) return index;
            }
            throw new InvalidOperationException();
        }
    }
}
