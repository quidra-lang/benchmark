import java.util.*;
final class Safety {
    static final List<String> PROPERTIES =
        List.of("OCCUPANCY", "POINT_MOTION", "CONFLICT", "SIGNAL_PASSING");
    Map<String, Integer> checks = new HashMap<>(), violations = new HashMap<>();
    List<String> records = new ArrayList<>();
    void check(int time, String kind, String details) {
        checks.merge(kind, 1, Integer::sum);
        if (details != null) {
            violations.merge(kind, 1, Integer::sum);
            records.add("VIOLATION " + time + " " + kind + " " + details);
        }
    }
    void inspect(int time, Layout layout, Map<String, Interlocking.Route> routes) {
        for (Layout.Section section : layout.sections.values())
            check(time, "OCCUPANCY",
                  section.occupants.size() >= 2
                      ? section.name + " " + String.join(",", section.occupants)
                      : null);
        for (Layout.Point point : layout.points.values())
            if (point.moving) {
                String details = null;
                if (!layout.sections.get(point.common).occupants.isEmpty())
                    details = point.name + " occupied";
                else
                    for (Interlocking.PointLock lock : point.locks)
                        if (Set.of("USED", "APPROACH").contains(routes.get(lock.route()).state)) {
                            details = point.name + " locked";
                            break;
                        }
                check(time, "POINT_MOTION", details);
            }
        List<Interlocking.Route> locked = new ArrayList<>();
        for (Interlocking.Route route : routes.values())
            if (route.state != null && Set.of("LOCKED", "APPROACH").contains(route.state))
                locked.add(route);
        for (int a = 0; a < locked.size(); a++)
            for (int b = a + 1; b < locked.size(); b++) {
                Interlocking.Route first = locked.get(a), second = locked.get(b);
                check(time, "CONFLICT",
                      first.conflicts.contains(second.name) || second.conflicts.contains(first.name)
                          ? first.name + " " + second.name
                          : null);
            }
    }
    List<String> report() {
        List<String> lines = new ArrayList<>();
        for (String kind : PROPERTIES) {
            int count = violations.getOrDefault(kind, 0);
            lines.add(kind + " " + (count > 0 ? "FAIL" : "OK") + " checks " +
                      checks.getOrDefault(kind, 0) + " violations " + count);
        }
        lines.addAll(records);
        lines.add("RESULT " + (records.isEmpty() ? "SAFE" : "UNSAFE"));
        return lines;
    }
}
