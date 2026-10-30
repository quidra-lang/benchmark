using System;
using System.Collections.Generic;
public static class Signals {
    public record Aspect(Layout.Signal signal, string aspect);
    public static List<Aspect> Aspects(Interlocking interlocking, Func<string, bool> occupied) {
        Layout layout = interlocking.layout;
        Dictionary<string, Interlocking.Route> cleared = new();
        foreach (Layout.Signal signal in layout.signals.Values)
            foreach (Interlocking.Route route in interlocking.routes.Values) {
                if (route.start != signal.name || route.state != "LOCKED")
                    continue;
                bool ready = true;
                foreach (Interlocking.Requirement requirement in route.requirements) {
                    Layout.Point point = layout.points[requirement.point];
                    if (!point.Detected() || point.position != requirement.position)
                        ready = false;
                }
                foreach (string name in route.sections)
                    if (occupied(name))
                        ready = false;
                foreach (string name in route.overlap)
                    if (occupied(name))
                        ready = false;
                if (ready) {
                    cleared[signal.name] = route;
                    break;
                }
            }
        List<Aspect> result = new();
        foreach (Layout.Signal signal in layout.signals.Values) {
            Interlocking.Route route = cleared.GetValueOrDefault(signal.name);
            string aspect = route == null ? "RED"
                            : layout.signals.ContainsKey(route.finish)
                                ? (cleared.ContainsKey(route.finish) ? "GREEN" : "YELLOW")
                            : layout.buffers.ContainsKey(route.finish) ? "YELLOW"
                                                                       : "GREEN";
            result.Add(new(signal, aspect));
        }
        return result;
    }
}
