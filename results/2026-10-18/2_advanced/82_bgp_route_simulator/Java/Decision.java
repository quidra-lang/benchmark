import java.util.*;
import java.util.function.ToLongFunction;
final class Decision {
    record
        Attribute(List<Integer> path, String origin, int med, List<Policy.Community> communities) {
        Attribute {
            path = List.copyOf(path);
            communities = List.copyOf(communities);
        }
    }
    record Route(List<Integer> path, String origin, int med, List<Policy.Community> communities,
                 Integer localPref, Topology.Link link) {
        Route {
            path = List.copyOf(path);
            communities = List.copyOf(communities);
        }
        boolean local() { return link == null; }
        int neighbor() { return path.getFirst(); }
        static Route originated(String origin, List<Policy.Community> communities) {
            return new Route(List.of(), origin, 0, communities, null, null);
        }
    }
    record Selection(Route route, String reason) {}
    static Selection best(List<Route> candidates, Map<Integer, Long> routerIds) {
        List<Route> remaining = new ArrayList<>(candidates);
        if (remaining.size() == 1)
            return new Selection(remaining.getFirst(), "ONLY");
        for (String reason : List.of("LOCALPREF", "ASPATH", "ORIGIN", "MED", "ROUTERID", "LINK")) {
            if (reason.equals("MED")) {
                Map<Integer, Integer> minimum = new HashMap<>();
                for (Route route : remaining)
                    minimum.merge(route.neighbor(), route.med(), Math::min);
                remaining.removeIf(route -> route.med() != minimum.get(route.neighbor()));
            } else {
                ToLongFunction<Route> key = switch (reason) {
                    case "LOCALPREF" -> route -> - ((long)route.localPref());
                    case "ASPATH" -> route -> route.path().size();
                    case "ORIGIN" ->
                        route
                            -> route.origin().equals("IGP")   ? 0
                               : route.origin().equals("EGP") ? 1
                                                              : 2;
                    case "ROUTERID" -> route -> routerIds.get(route.neighbor());
                    default -> route -> route.link().number;
                };
                long minimum = remaining.stream().mapToLong(key).min().orElseThrow();
                remaining.removeIf(route -> key.applyAsLong(route) != minimum);
            }
            if (remaining.size() == 1)
                return new Selection(remaining.getFirst(), reason);
        }
        throw new IllegalStateException();
    }
}
