using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;
public static class Resolution {
    public record Manoeuvre(string name, int amount) {}
    public static List<Manoeuvre> Manoeuvres(int maximum) {
        List<Manoeuvre> moves = new();
        moves.Add(new Manoeuvre("level_up", 10));
        moves.Add(new Manoeuvre("level_down", -10));
        moves.Add(new Manoeuvre("speed_down", 0));
        for (int delay = 60; delay <= maximum; delay += 60)
            moves.Add(new Manoeuvre("delay_" + delay, delay));
        return moves;
    }
    public static string[] Priority(FlightPlans.Plan a, FlightPlans.Plan b) {
        int comparison = (a.departure + a.delay).CompareTo(b.departure + b.delay);
        if (comparison == 0)
            comparison = string.CompareOrdinal(a.callsign, b.callsign);
        return comparison > 0 ? new string[] { a.callsign, b.callsign }
                              : new string[] { b.callsign, a.callsign };
    }
    public static FlightPlans.Plan Propose(FlightPlans.Plan plan, Manoeuvre manoeuvre,
                                           Dictionary<string, FlightPlans.AircraftType> types,
                                           FlightPlans.Settings settings) {
        FlightPlans.Plan changed = plan.Copy();
        if (manoeuvre.name.Equals("level_up") || manoeuvre.name.Equals("level_down")) {
            changed.offset += manoeuvre.amount;
            foreach (int level in changed.Levels())
                if (level < settings.levelMin || level > settings.levelMax)
                    return null;
        } else if (manoeuvre.name.Equals("speed_down")) {
            changed.speed = changed.speed * 9 / 10;
            if (changed.speed < types[changed.type].minimum)
                return null;
        } else
            changed.delay += manoeuvre.amount;
        return changed;
    }
}
