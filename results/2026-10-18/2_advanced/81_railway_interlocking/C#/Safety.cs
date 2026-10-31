using System;
using System.Collections.Generic;
using System.Linq;
public sealed class Safety {
    public static readonly List<string> PROPERTIES =
        new() { "OCCUPANCY", "POINT_MOTION", "CONFLICT", "SIGNAL_PASSING" };
    public Dictionary<string, int> checks = new(), violations = new();
    public List<string> records = new();
    public void Check(int time, string kind, string details) {
        checks[kind] = checks.GetValueOrDefault(kind, 0) + 1;
        if (details != null) {
            violations[kind] = violations.GetValueOrDefault(kind, 0) + 1;
            records.Add("VIOLATION " + time + " " + kind + " " + details);
        }
    }
    public void Inspect(int time, Layout layout, Dictionary<string, Interlocking.Route> routes) {
        foreach (Layout.Section section in layout.sections.Values)
            Check(time, "OCCUPANCY",
                  section.occupants.Count >= 2
                      ? section.name + " " + string.Join(",", section.occupants)
                      : null);
        foreach (Layout.Point point in layout.points.Values)
            if (point.moving) {
                string details = null;
                if (layout.sections[point.common].occupants.Count != 0)
                    details = point.name + " occupied";
                else if (point.locks.Any(pointLock => routes[pointLock.route].state == "USED" ||
                                                      routes[pointLock.route].state == "APPROACH"))
                    details = point.name + " locked";
                Check(time, "POINT_MOTION", details);
            }
        List<Interlocking.Route> locked =
            routes.Values.Where(route => route.state == "LOCKED" || route.state == "APPROACH")
                .ToList();
        for (int a = 0; a < locked.Count; a++)
            for (int b = a + 1; b < locked.Count; b++) {
                Interlocking.Route first = locked[a], second = locked[b];
                Check(time, "CONFLICT",
                      first.conflicts.Contains(second.name) || second.conflicts.Contains(first.name)
                          ? first.name + " " + second.name
                          : null);
            }
    }
    public List<string> Report() {
        List<string> lines = new();
        foreach (string kind in PROPERTIES) {
            int count = violations.GetValueOrDefault(kind, 0);
            lines.Add(kind + " " + (count > 0 ? "FAIL" : "OK") + " checks " +
                      checks.GetValueOrDefault(kind, 0) + " violations " + count);
        }
        lines.AddRange(records);
        lines.Add("RESULT " + (records.Count == 0 ? "SAFE" : "UNSAFE"));
        return lines;
    }
}
