import java.nio.file.*;
import java.nio.charset.StandardCharsets;
import java.util.*;
final class Interlocking {
    record Requirement(String point, String position) {}
    record PointLock(String route, String position) {}
    static List<String> names(String text) {
        return text.equals("-") ? List.of() : List.of(text.split(","));
    }
    static List<Requirement> requirements(String text) {
        List<Requirement> result = new ArrayList<>();
        for (String item : names(text)) {
            String[] f = item.split(":");
            result.add(new Requirement(f[0], f[1]));
        }
        return result;
    }
    static final class Route {
        String name, start, finish, direction, state;
        List<Requirement> points, flank, requirements;
        List<String> sections, overlap, conflicts;
        int approachTime, overlapCounter, requests, grants, uses, cancels, wait, maxwait,
            lockedSeconds;
        Integer releaseTime;
        Set<String> passed = new HashSet<>();
        boolean overlapLocked;
        Route(String[] f, Layout layout) {
            name = f[1];
            start = f[2];
            finish = f[3];
            points = Interlocking.requirements(f[4]);
            sections = names(f[5]);
            overlap = names(f[6]);
            flank = Interlocking.requirements(f[7]);
            conflicts = names(f[8]);
            approachTime = Integer.parseInt(f[9]);
            direction = layout.signals.get(start).direction;
            requirements = new ArrayList<>(points);
            requirements.addAll(flank);
        }
    }
    Layout layout;
    Map<String, Route> routes = new LinkedHashMap<>();
    Interlocking(Layout layout) throws Exception {
        this.layout = layout;
        for (String line :
             Files.readAllLines(Path.of("input/routes.txt"), StandardCharsets.US_ASCII)) {
            Route route = new Route(line.split(" "), layout);
            routes.put(route.name, route);
        }
    }
    void lock(Route route) {
        route.state = "LOCKED";
        route.releaseTime = null;
        route.passed.clear();
        route.overlapLocked = true;
        route.overlapCounter = 0;
        for (String name : route.sections)
            layout.sections.get(name).routeLock = route.name;
        for (String name : route.overlap)
            layout.sections.get(name).overlapLocks.add(route.name);
        for (Requirement requirement : route.requirements)
            layout.points.get(requirement.point())
                .locks.add(new PointLock(route.name, requirement.position()));
    }
    void unlockPoints(Route route, Set<String> sections) {
        for (Layout.Point point : layout.points.values())
            if (sections == null || sections.contains(point.common))
                point.locks.removeIf(lock -> lock.route().equals(route.name));
    }
    void unlockSection(Route route, String name) {
        Layout.Section section = layout.sections.get(name);
        if (Objects.equals(section.routeLock, route.name))
            section.routeLock = null;
        unlockPoints(route, Set.of(name));
    }
    void unlockOverlap(Route route) {
        for (String name : route.overlap)
            layout.sections.get(name).overlapLocks.remove(route.name);
        unlockPoints(route, new HashSet<>(route.overlap));
        route.overlapLocked = false;
    }
    void release(Route route) {
        for (String name : route.sections)
            if (Objects.equals(layout.sections.get(name).routeLock, route.name))
                layout.sections.get(name).routeLock = null;
        if (route.overlapLocked)
            unlockOverlap(route);
        unlockPoints(route, null);
        route.state = null;
        route.releaseTime = null;
    }
}
