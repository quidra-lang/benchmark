import java.nio.file.*;
import java.nio.charset.StandardCharsets;
import java.util.*;
final class Report {
    static String path(List<Integer> path) {
        return String.join(",", path.stream().map(Object::toString).toList());
    }
    static String attribute(Decision.Attribute attribute) {
        return "path " + path(attribute.path()) + " origin " + attribute.origin() + " med " +
            attribute.med() + " comm " + Policy.communityText(attribute.communities());
    }
    static String route(Decision.Route route) {
        if (route == null)
            return "NONE";
        String comm = Policy.communityText(route.communities());
        if (route.local())
            return "LOCAL origin " + route.origin() + " comm " + comm;
        return "next " + route.neighbor() + " path " + path(route.path()) + " link " +
            route.link().name + " lp " + route.localPref() + " med " + route.med() + " origin " +
            route.origin() + " comm " + comm;
    }
    static void write(String name, List<String> lines) throws Exception {
        Files.createDirectories(Path.of("output"));
        Files.writeString(Path.of("output", name),
                          String.join("\n", lines) + (lines.isEmpty() ? "" : "\n"),
                          StandardCharsets.US_ASCII);
    }
}
