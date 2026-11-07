import java.util.*;
final class Resolution {
    record Manoeuvre(String name, int amount) {}
    static List<Manoeuvre> manoeuvres(int maximum) {
        List<Manoeuvre> moves = new ArrayList<>();
        moves.add(new Manoeuvre("level_up", 10));
        moves.add(new Manoeuvre("level_down", -10));
        moves.add(new Manoeuvre("speed_down", 0));
        for (int delay = 60; delay <= maximum; delay += 60)
            moves.add(new Manoeuvre("delay_" + delay, delay));
        return moves;
    }
    static String[] priority(FlightPlans.Plan a, FlightPlans.Plan b) {
        int comparison = Long.compare(a.departure + a.delay, b.departure + b.delay);
        if (comparison == 0)
            comparison = a.callsign.compareTo(b.callsign);
        return comparison > 0 ? new String[] {a.callsign, b.callsign}
                              : new String[] {b.callsign, a.callsign};
    }
    static FlightPlans.Plan propose(FlightPlans.Plan plan, Manoeuvre manoeuvre,
                                    Map<String, FlightPlans.AircraftType> types,
                                    FlightPlans.Settings settings) {
        FlightPlans.Plan changed = plan.copy();
        if (manoeuvre.name().equals("level_up") || manoeuvre.name().equals("level_down")) {
            changed.offset += manoeuvre.amount();
            for (int level : changed.levels())
                if (level < settings.levelMin() || level > settings.levelMax())
                    return null;
        } else if (manoeuvre.name().equals("speed_down")) {
            changed.speed = changed.speed * 9 / 10;
            if (changed.speed < types.get(changed.type).minimum())
                return null;
        } else
            changed.delay += manoeuvre.amount();
        return changed;
    }
}
