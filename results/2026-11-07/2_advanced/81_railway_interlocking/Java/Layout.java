import java.nio.file.*;
import java.nio.charset.StandardCharsets;
import java.util.*;
final class Layout {
    record Key(String section, String end) {}
    record Beyond(String kind, String name) {}
    record Buffer(String name, String section, String end, int row, int column) {}
    record Boundary(String name, String section, String end) {}
    record Label(int row, int column, String text) {}
    static final class Section {
        String name, routeLock;
        int length, row, first, last, occupiedSeconds, lockedSeconds;
        boolean failed;
        List<String> occupants = new ArrayList<>();
        Set<String> trains = new HashSet<>(), overlapLocks = new HashSet<>();
        Section(String name, int length, int row, int first, int last) {
            this.name = name;
            this.length = length;
            this.row = row;
            this.first = first;
            this.last = last;
        }
    }
    static final class Point {
        String name, side, common, normal, reverse, position = "N", target;
        int row, column, throwsCount, lockedSeconds, movingSeconds;
        Integer completion;
        boolean moving, failed;
        Set<Interlocking.PointLock> locks = new HashSet<>();
        Point(String[] f) {
            name = f[1];
            side = f[2];
            common = f[3];
            normal = f[4];
            reverse = f[5];
            row = Integer.parseInt(f[6]);
            column = Integer.parseInt(f[7]);
        }
        boolean detected() { return !moving && !failed; }
    }
    static final class Signal {
        String name, section, direction, aspect = "RED";
        int row, column, passes;
        Map<String, Integer> seconds = new HashMap<>();
        Signal(String[] f) {
            name = f[1];
            section = f[2];
            direction = f[3];
            row = Integer.parseInt(f[4]);
            column = Integer.parseInt(f[5]);
        }
    }
    Map<String, Section> sections = new LinkedHashMap<>();
    Map<String, Point> points = new LinkedHashMap<>();
    Map<String, Signal> signals = new LinkedHashMap<>();
    Map<String, Buffer> buffers = new LinkedHashMap<>();
    Map<String, Boundary> boundaries = new LinkedHashMap<>();
    List<Label> labels = new ArrayList<>();
    Map<Key, Beyond> ends = new HashMap<>();
    Map<Key, Signal> signalsAt = new HashMap<>();
    Layout() throws Exception {
        for (String line :
             Files.readAllLines(Path.of("input/layout.txt"), StandardCharsets.US_ASCII)) {
            String[] f = line.split(" ");
            switch (f[0]) {
            case "SECTION":
                sections.put(f[1], new Section(f[1], Integer.parseInt(f[2]), Integer.parseInt(f[3]),
                                               Integer.parseInt(f[4]), Integer.parseInt(f[5])));
                break;
            case "JOINT":
                ends.put(new Key(f[1], "R"), new Beyond("section", f[2]));
                ends.put(new Key(f[2], "L"), new Beyond("section", f[1]));
                break;
            case "POINT": {
                Point p = new Point(f);
                points.put(p.name, p);
                ends.put(new Key(p.common, p.side), new Beyond("point", p.name));
                String other = p.side.equals("R") ? "L" : "R";
                ends.put(new Key(p.normal, other), new Beyond("point", p.name));
                ends.put(new Key(p.reverse, other), new Beyond("point", p.name));
                break;
            }
            case "SIGNAL": {
                Signal signal = new Signal(f);
                signals.put(signal.name, signal);
                signalsAt.put(new Key(signal.section, signal.direction), signal);
                break;
            }
            case "BUFFER":
                buffers.put(f[1], new Buffer(f[1], f[2], f[3], Integer.parseInt(f[4]),
                                             Integer.parseInt(f[5])));
                ends.put(new Key(f[2], f[3]), new Beyond("buffer", f[1]));
                break;
            case "BOUNDARY":
                boundaries.put(f[1], new Boundary(f[1], f[2], f[3]));
                ends.put(new Key(f[2], f[3]), new Beyond("boundary", f[1]));
                break;
            case "LABEL":
                labels.add(new Label(Integer.parseInt(f[1]), Integer.parseInt(f[2]), f[3]));
                break;
            }
        }
    }
    Beyond beyond(String section, String direction) {
        Beyond beyond = ends.get(new Key(section, direction.equals("UP") ? "R" : "L"));
        if (!beyond.kind().equals("point"))
            return beyond;
        Point point = points.get(beyond.name());
        String branch = point.position.equals("N") ? point.normal : point.reverse;
        if (point.moving || !section.equals(point.common) && !section.equals(branch))
            return new Beyond("impassable", null);
        return new Beyond("section", section.equals(point.common) ? branch : point.common);
    }
}
