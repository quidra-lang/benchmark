import java.util.*;
import java.util.function.*;
final class Signals {
    record Aspect(Layout.Signal signal, String aspect) {}
    static List<Aspect> aspects(Interlocking interlocking, Predicate<String> occupied) {
        Layout layout = interlocking.layout;
        Map<String, Interlocking.Route> cleared = new HashMap<>();
        for (Layout.Signal signal : layout.signals.values())
            for (Interlocking.Route route : interlocking.routes.values()) {
                if (!route.start.equals(signal.name) || !Objects.equals(route.state, "LOCKED"))
                    continue;
                boolean ready = true;
                for (Interlocking.Requirement r : route.requirements) {
                    Layout.Point point = layout.points.get(r.point());
                    if (!point.detected() || !point.position.equals(r.position()))
                        ready = false;
                }
                for (String name : route.sections)
                    if (occupied.test(name))
                        ready = false;
                for (String name : route.overlap)
                    if (occupied.test(name))
                        ready = false;
                if (ready) {
                    cleared.put(signal.name, route);
                    break;
                }
            }
        List<Aspect> result = new ArrayList<>();
        for (Layout.Signal signal : layout.signals.values()) {
            Interlocking.Route route = cleared.get(signal.name);
            String aspect = route == null ? "RED"
                            : layout.signals.containsKey(route.finish)
                                ? (cleared.containsKey(route.finish) ? "GREEN" : "YELLOW")
                            : layout.buffers.containsKey(route.finish) ? "YELLOW"
                                                                       : "GREEN";
            result.add(new Aspect(signal, aspect));
        }
        return result;
    }
}
