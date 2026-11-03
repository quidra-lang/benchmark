import java.util.ArrayList;
import java.util.Arrays;
import java.util.Comparator;
import java.util.HashMap;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;

record Rational(long numerator, long denominator) implements Comparable<Rational> {
    Rational {
        if (denominator < 0) { numerator = -numerator; denominator = -denominator; }
        long first = Math.abs(numerator), second = denominator;
        while (second != 0) { long remainder = first % second; first = second; second = remainder; }
        numerator /= first; denominator /= first;
    }
    Rational(long value) { this(value, 1); }
    public int compareTo(Rational other) { return Long.compare(numerator * other.denominator, other.numerator * denominator); }
}
public class Main {
    static final String SYMBOLS = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz";
    static final List<String> ORIENTATIONS = List.of("none", "horizontal", "vertical", "falling", "rising");
    static final String CSV_HEADER = "image,label,class,flags,area,x0,y0,x1,y1,cx,cy,mean,variance,min,max,contrast,border,perimeter,chain,straight,diagonal,turns,compactness,runs,holes,hole_area,euler,parent,depth,var_x,var_y,cov_xy,hu1,orientation,anisotropy,extent,mirror_lr,mirror_tb,hull_area,solidity,feret2,width2,elongation,bays,bay_area,skeleton,endpoints,branches,neighbor,distance2,codes";
    static final List<Pixel> FOUR = List.of(new Pixel(1, 0), new Pixel(0, -1), new Pixel(-1, 0), new Pixel(0, 1));
    static final List<Pixel> EIGHT = List.of(new Pixel(1, 0), new Pixel(1, -1), new Pixel(0, -1), new Pixel(-1, -1), new Pixel(-1, 0), new Pixel(-1, 1), new Pixel(0, 1), new Pixel(1, 1));
    record Setting(String name, int connectivity, String threshold, String polarity, List<String> operations) {
        String method() { return threshold.equals("otsu") || threshold.equals("isodata") ? threshold : "fixed"; }
    }
    static final class Parameters {
        int otsuTop, sweepStep, bayMin;
        Rational isotropy = new Rational(0);
        final Map<String, List<Pixel>> elements = new HashMap<>();
        final Map<String, Setting> settings = new HashMap<>();
    }
    record Condition(String feature, String comparison, String text) {
        boolean holds(Region region) {
            int result = feature.equals("orientation") ? region.orientation.compareTo(text) : region.features.get(feature).compareTo(parseRational(text));
            return switch (comparison) { case "<" -> result < 0; case "<=" -> result <= 0; case ">" -> result > 0; case ">=" -> result >= 0; case "=" -> result == 0; case "!=" -> result != 0; default -> throw new IllegalArgumentException(); };
        }
        String words() { return feature + " " + comparison + " " + text; }
    }
    record Rule(String name, List<Condition> conditions) {
        boolean matches(Region region) { return conditions.stream().allMatch(condition -> condition.holds(region)); }
    }
    static final class Rules {
        final List<Condition> filters = new ArrayList<>();
        final List<Rule> classes = new ArrayList<>(), flags = new ArrayList<>();
        List<String> classNames() {
            List<String> names = new ArrayList<>();
            for (Rule rule : classes) if (!names.contains(rule.name())) names.add(rule.name());
            names.add("other"); return names;
        }
    }
    record Hole(int number, List<Pixel> pixels, int owner) {}
    static final class Region {
        final int number;
        final List<Pixel> pixels;
        final Map<String, Rational> features = new HashMap<>();
        List<Integer> codes = new ArrayList<>();
        Set<Pixel> skeleton = new HashSet<>();
        long hullDoubled, distance;
        Region parent;
        int depth, droppedBy = -1, neighbor = -1;
        final List<Region> children = new ArrayList<>();
        boolean kept;
        String className = "other", orientation = "none";
        final List<String> flags = new ArrayList<>();
        Region(int number, List<Pixel> pixels) { this.number = number; this.pixels = pixels; }
        void put(String name, long value) { features.put(name, new Rational(value)); }
        void put(String name, long numerator, long denominator) { features.put(name, new Rational(numerator, denominator)); }
        long integer(String name) { return features.get(name).numerator(); }
    }
    static Rational parseRational(String text) {
        String[] parts = text.split("/");
        return new Rational(Long.parseLong(parts[0]), parts.length == 1 ? 1 : Long.parseLong(parts[1]));
    }
    static Parameters readParameters(String path) throws Exception {
        Parameters result = new Parameters();
        for (String line : PgmReader.lines(path)) {
            List<String> words = List.of(line.split(" "));
            switch (words.getFirst()) {
                case "otsu_top" -> result.otsuTop = Integer.parseInt(words.get(1));
                case "sweep" -> result.sweepStep = Integer.parseInt(words.get(1));
                case "isotropy" -> result.isotropy = parseRational(words.get(1));
                case "bay_min" -> result.bayMin = Integer.parseInt(words.get(1));
                case "element" -> {
                    int ox = Integer.parseInt(words.get(4)), oy = Integer.parseInt(words.get(5)); List<Pixel> offsets = new ArrayList<>();
                    for (int y = 6; y < words.size(); y++) for (int x = 0; x < words.get(y).length(); x++) if (words.get(y).charAt(x) == '#') offsets.add(new Pixel(x - ox, y - 6 - oy));
                    result.elements.put(words.get(1), offsets);
                }
                case "image" -> result.settings.put(words.get(1), new Setting(words.get(1), Integer.parseInt(words.get(2)), words.get(3), words.get(4), words.subList(5, words.size())));
                default -> throw new IllegalArgumentException();
            }
        }
        return result;
    }
    static Rules readRules(String path) throws Exception {
        Rules result = new Rules();
        for (String line : PgmReader.lines(path)) {
            String[] words = line.split(" ");
            if (words[0].equals("filter")) result.filters.add(new Condition(words[1], words[2], words[3]));
            else {
                List<Condition> conditions = new ArrayList<>();
                for (int i = 2; i < words.length; i += 3) conditions.add(new Condition(words[i], words[i + 1], words[i + 2]));
                (words[0].equals("class") ? result.classes : result.flags).add(new Rule(words[1], conditions));
            }
        }
        return result;
    }
    static int count(boolean[][] mask) { int count = 0; for (boolean[] row : mask) for (boolean flag : row) if (flag) count++; return count; }
    static List<List<Pixel>> groups(int[][] labels, int count) {
        List<List<Pixel>> groups = new ArrayList<>(); for (int i = 0; i <= count; i++) groups.add(new ArrayList<>());
        for (int y = 0; y < labels.length; y++) for (int x = 0; x < labels[0].length; x++) groups.get(labels[y][x]).add(new Pixel(x, y));
        return groups;
    }
    static List<List<Pixel>> enclosed(boolean[][] mask, int connectivity) {
        int height = mask.length, width = mask[0].length; boolean[][] background = new boolean[height][width];
        for (int y = 0; y < height; y++) for (int x = 0; x < width; x++) background[y][x] = !mask[y][x];
        LabelResult result = Labeling.label(background, connectivity); List<List<Pixel>> enclosed = new ArrayList<>();
        for (List<Pixel> pixels : groups(result.labels(), result.count()).subList(1, result.count() + 1)) {
            boolean onEdge = pixels.stream().anyMatch(point -> point.x() == 0 || point.y() == 0 || point.x() == width - 1 || point.y() == height - 1);
            if (!onEdge) enclosed.add(pixels);
        }
        return enclosed;
    }
    static boolean[][] fill(boolean[][] mask, int connectivity) {
        boolean[][] filled = Arrays.stream(mask).map(boolean[]::clone).toArray(boolean[][]::new);
        for (List<Pixel> pixels : enclosed(mask, connectivity)) for (Pixel point : pixels) filled[point.y()][point.x()] = true;
        return filled;
    }
    static long cross(Pixel a, Pixel b, Pixel p) { return (long) (b.x() - a.x()) * (p.y() - a.y()) - (long) (b.y() - a.y()) * (p.x() - a.x()); }
    static long distance(Pixel a, Pixel b) { long dx = a.x() - b.x(), dy = a.y() - b.y(); return dx * dx + dy * dy; }
    static List<Pixel> halfHull(List<Pixel> points) {
        List<Pixel> chain = new ArrayList<>();
        for (Pixel point : points) { while (chain.size() >= 2 && cross(chain.get(chain.size() - 2), chain.getLast(), point) <= 0) chain.removeLast(); chain.add(point); }
        return chain;
    }
    static List<Pixel> hull(List<Pixel> pixels) {
        Set<Pixel> corners = new HashSet<>();
        for (Pixel point : pixels) { corners.add(point); corners.add(new Pixel(point.x() + 1, point.y())); corners.add(new Pixel(point.x(), point.y() + 1)); corners.add(new Pixel(point.x() + 1, point.y() + 1)); }
        List<Pixel> ordered = corners.stream().sorted(Comparator.comparingInt(Pixel::x).thenComparingInt(Pixel::y)).toList();
        List<Pixel> lower = halfHull(ordered), upper = halfHull(ordered.reversed());
        List<Pixel> hull = new ArrayList<>(lower.subList(0, lower.size() - 1)); hull.addAll(upper.subList(0, upper.size() - 1)); return hull;
    }
    static boolean containsCenter(List<Pixel> hull, int x, int y) {
        Pixel center = new Pixel(2 * x + 1, 2 * y + 1);
        for (int i = 0; i < hull.size(); i++) { Pixel a = hull.get(i), b = hull.get((i + 1) % hull.size()); if (cross(new Pixel(2 * a.x(), 2 * a.y()), new Pixel(2 * b.x(), 2 * b.y()), center) < 0) return false; }
        return true;
    }
    static String meanText(long total, int count) { return count == 0 ? "-" : Report.decimal(new Rational(total, count), 2); }
    static String orientationLine(List<Region> regions) {
        List<String> parts = new ArrayList<>(List.of("orientations"));
        for (String name : ORIENTATIONS) { parts.add(name); parts.add("" + regions.stream().filter(region -> region.orientation.equals(name)).count()); }
        return String.join(" ", parts);
    }
    static final class Analysis {
        final Image image;
        final Setting setting;
        final Parameters parameters;
        final int width, height, connectivity, complement, cutoff;
        final Histogram histogram;
        final OtsuResult otsu;
        final IsodataResult isodata;
        final boolean[][] initial, mask;
        final List<Integer> morphCounts = new ArrayList<>();
        final List<int[]> sweep = new ArrayList<>();
        final int[][] labels, holeOf;
        final int provisional, fourComponents, eightComponents, bitQuad;
        final List<Region> regions = new ArrayList<>();
        final List<Hole> holes = new ArrayList<>();
        Analysis(Image image, Setting setting, Parameters parameters) {
            this.image = image; this.setting = setting; this.parameters = parameters; width = image.width(); height = image.height(); connectivity = setting.connectivity(); complement = 12 - connectivity;
            histogram = new Histogram(image); otsu = Threshold.otsu(histogram); isodata = Threshold.isodata(histogram);
            cutoff = switch (setting.threshold()) { case "otsu" -> otsu.cutoff(); case "isodata" -> isodata.cutoff(); default -> Integer.parseInt(setting.threshold()); };
            initial = binarize(cutoff); boolean[][] current = initial;
            for (String operation : setting.operations()) { current = operation(current, operation); morphCounts.add(count(current)); }
            mask = current;
            for (int t = parameters.sweepStep; t < image.maxval(); t += parameters.sweepStep) { boolean[][] binary = binarize(t); sweep.add(new int[] {t, count(binary), Labeling.label(binary, connectivity).count()}); }
            LabelResult labeled = Labeling.label(mask, connectivity); labels = labeled.labels(); provisional = labeled.provisional();
            List<List<Pixel>> pixels = groups(labels, labeled.count()); for (int j = 1; j <= labeled.count(); j++) regions.add(new Region(j, pixels.get(j)));
            fourComponents = Labeling.label(mask, 4).count(); eightComponents = Labeling.label(mask, 8).count(); bitQuad = Labeling.bitQuad(mask, connectivity);
            holeOf = new int[height][width];
            for (List<Pixel> holePixels : enclosed(mask, complement)) {
                Pixel first = holePixels.getFirst(); Hole hole = new Hole(holes.size() + 1, holePixels, labels[first.y() - 1][first.x()]);
                holes.add(hole); for (Pixel point : holePixels) holeOf[point.y()][point.x()] = hole.number();
            }
            for (Region region : regions) {
                Pixel first = region.pixels.getFirst();
                if (first.y() >= 1 && holeOf[first.y() - 1][first.x()] > 0) {
                    int owner = holes.get(holeOf[first.y() - 1][first.x()] - 1).owner(); region.parent = regions.get(owner - 1); region.depth = region.parent.depth + 1; region.parent.children.add(region);
                }
            }
            for (Region region : regions) measure(region);
        }
        boolean[][] binarize(int threshold) {
            boolean[][] binary = new boolean[height][width];
            for (int y = 0; y < height; y++) for (int x = 0; x < width; x++) binary[y][x] = setting.polarity().equals("bright") ? image.pixels()[y][x] > threshold : image.pixels()[y][x] <= threshold;
            return binary;
        }
        boolean[][] operation(boolean[][] source, String operation) {
            if (operation.equals("fill")) return fill(source, complement);
            String[] words = operation.split(":"); List<Pixel> offsets = parameters.elements.get(words[1]);
            return switch (words[0]) { case "erode" -> Morphology.erode(source, offsets); case "dilate" -> Morphology.dilate(source, offsets); case "open" -> Morphology.opening(source, offsets); case "close" -> Morphology.closing(source, offsets); default -> throw new IllegalArgumentException(); };
        }
        int labelAt(int x, int y) { return x >= 0 && x < width && y >= 0 && y < height ? labels[y][x] : -1; }
        void measure(Region region) {
            long area = region.pixels.size(), sumI = 0, sumII = 0, sumX = 0, sumY = 0, sumXX = 0, sumYY = 0, sumXY = 0;
            int x0 = width, y0 = height, x1 = -1, y1 = -1, minimum = image.maxval(), maximum = 0, perimeter = 0, runs = 0;
            Set<Pixel> surrounding = new HashSet<>(); List<Pixel> neighbors = complement == 4 ? FOUR : EIGHT;
            for (Pixel point : region.pixels) {
                int x = point.x(), y = point.y(), value = image.pixels()[y][x];
                x0 = Math.min(x0, x); y0 = Math.min(y0, y); x1 = Math.max(x1, x); y1 = Math.max(y1, y); minimum = Math.min(minimum, value); maximum = Math.max(maximum, value);
                sumI += value; sumII += (long) value * value; sumX += x; sumY += y; sumXX += x * x; sumYY += y * y; sumXY += x * y;
                for (Pixel offset : EIGHT) if (labelAt(x + offset.x(), y + offset.y()) == 0) surrounding.add(new Pixel(x + offset.x(), y + offset.y()));
                for (Pixel offset : neighbors) if (labelAt(x + offset.x(), y + offset.y()) != region.number) { perimeter++; break; }
                if (labelAt(x - 1, y) != region.number) runs++;
            }
            region.put("area", area); region.put("x0", x0); region.put("y0", y0); region.put("x1", x1); region.put("y1", y1);
            region.put("width", x1 - x0 + 1); region.put("height", y1 - y0 + 1); region.put("border", x0 == 0 || y0 == 0 || x1 == width - 1 || y1 == height - 1 ? 1 : 0);
            region.put("mean", sumI, area); region.put("variance", area * sumII - sumI * sumI, area * area); region.put("min", minimum); region.put("max", maximum);
            long sumSurrounding = 0; for (Pixel point : surrounding) sumSurrounding += image.pixels()[point.y()][point.x()];
            if (surrounding.isEmpty()) region.put("contrast", 0); else region.put("contrast", sumI * surrounding.size() - sumSurrounding * area, area * surrounding.size());
            region.put("perimeter", perimeter); region.put("runs", runs); region.codes = chainCode(region);
            int straight = connectivity == 4 ? region.codes.size() : (int) region.codes.stream().filter(code -> code % 2 == 0).count(), diagonal = region.codes.size() - straight, turns = 0;
            for (int i = 0; i < region.codes.size(); i++) if (!region.codes.get(i).equals(region.codes.get((i + region.codes.size() - 1) % region.codes.size()))) turns++;
            region.put("chain", region.codes.size()); region.put("straight", straight); region.put("diagonal", diagonal); region.put("turns", turns);
            long length = 5L * straight + 7L * diagonal; region.put("compactness", length * length, 25 * area);
            int owned = 0, holeArea = 0; for (Hole hole : holes) if (hole.owner() == region.number) { owned++; holeArea += hole.pixels().size(); }
            region.put("holes", owned); region.put("hole_area", holeArea); region.put("euler", 1 - owned); region.put("depth", region.depth);
            long m20 = area * sumXX - sumX * sumX, m02 = area * sumYY - sumY * sumY, m11 = area * sumXY - sumX * sumY;
            region.put("cx", sumX, area); region.put("cy", sumY, area); region.put("var_x", m20, area * area); region.put("var_y", m02, area * area); region.put("cov_xy", m11, area * area); region.put("hu1", m20 + m02, area * area * area);
            Rational anisotropy = m20 + m02 == 0 ? new Rational(0) : new Rational(Math.abs(m20 - m02) + 2 * Math.abs(m11), m20 + m02); region.features.put("anisotropy", anisotropy);
            long u = m20 - m02, v = 2 * m11;
            if (anisotropy.compareTo(parameters.isotropy) > 0) region.orientation = Math.abs(v) >= Math.abs(u) ? (v > 0 ? "falling" : "rising") : (u > 0 ? "horizontal" : "vertical");
            region.put("extent", area, (long) (x1 - x0 + 1) * (y1 - y0 + 1)); int lr = 0, tb = 0;
            for (Pixel point : region.pixels) { if (labelAt(x0 + x1 - point.x(), point.y()) == region.number) lr++; if (labelAt(point.x(), y0 + y1 - point.y()) == region.number) tb++; }
            region.put("mirror_lr", lr, area); region.put("mirror_tb", tb, area); measureHull(region, x0, y0, x1, y1);
            region.skeleton = Morphology.thin(region.pixels); int endpoints = 0, branches = 0;
            for (Pixel point : region.skeleton) { int crossing = Morphology.crossing(region.skeleton, point); if (crossing == 1) endpoints++; if (crossing >= 3) branches++; }
            region.put("skeleton", region.skeleton.size()); region.put("endpoints", endpoints); region.put("branches", branches);
        }
        List<Integer> chainCode(Region region) {
            List<Pixel> directions = connectivity == 4 ? FOUR : EIGHT, visited = new ArrayList<>(List.of(region.pixels.getFirst())); List<Integer> codes = new ArrayList<>(); int heading = directions.size() - 1;
            while (true) {
                Pixel point = visited.getLast(); int start = connectivity == 4 ? (heading + 3) % 4 : (heading + (heading % 2 == 0 ? 7 : 6)) % 8, chosen = -1;
                for (int offset = 0; offset < directions.size(); offset++) { int direction = (start + offset) % directions.size(); Pixel delta = directions.get(direction); if (labelAt(point.x() + delta.x(), point.y() + delta.y()) == region.number) { chosen = direction; break; } }
                if (chosen < 0) return new ArrayList<>();
                Pixel delta = directions.get(chosen); visited.add(new Pixel(point.x() + delta.x(), point.y() + delta.y())); codes.add(chosen); heading = chosen;
                int moves = codes.size(); if (moves >= 2 && visited.get(moves).equals(visited.get(1)) && visited.get(moves - 1).equals(visited.getFirst())) return new ArrayList<>(codes.subList(0, moves - 1));
            }
        }
        void measureHull(Region region, int x0, int y0, int x1, int y1) {
            List<Pixel> hull = hull(region.pixels); long doubled = 0, feret = 0; Rational width2 = null;
            for (int i = 0; i < hull.size(); i++) {
                Pixel a = hull.get(i), b = hull.get((i + 1) % hull.size()); doubled += (long) a.x() * b.y() - (long) b.x() * a.y(); long reach = 0;
                for (Pixel point : hull) { reach = Math.max(reach, Math.abs(cross(a, b, point))); feret = Math.max(feret, distance(a, point)); }
                Rational trial = new Rational(reach * reach, distance(a, b)); if (width2 == null || trial.compareTo(width2) < 0) width2 = trial;
            }
            region.hullDoubled = Math.abs(doubled); region.put("solidity", 2L * region.pixels.size(), region.hullDoubled); region.put("feret2", feret); region.features.put("width2", width2); region.put("elongation", feret * width2.denominator(), width2.numerator());
            boolean[][] bayMask = new boolean[y1 - y0 + 1][x1 - x0 + 1];
            for (int y = y0; y <= y1; y++) for (int x = x0; x <= x1; x++) bayMask[y - y0][x - x0] = labels[y][x] == 0 && holeOf[y][x] == 0 && containsCenter(hull, x, y);
            LabelResult bays = Labeling.label(bayMask, complement); int[] sizes = new int[bays.count() + 1]; for (int[] row : bays.labels()) for (int label : row) sizes[label]++;
            int bayCount = 0, bayArea = 0; for (int j = 1; j < sizes.length; j++) { if (sizes[j] >= parameters.bayMin) bayCount++; bayArea += sizes[j]; }
            region.put("bays", bayCount); region.put("bay_area", bayArea);
        }
        List<Region> kept() { return regions.stream().filter(region -> region.kept).toList(); }
        void applyRules(Rules rules) {
            for (Region region : regions) {
                for (int i = 0; i < rules.filters.size(); i++) if (!rules.filters.get(i).holds(region)) { region.droppedBy = i; break; }
                if (region.droppedBy >= 0) continue;
                region.kept = true; for (Rule rule : rules.classes) if (rule.matches(region)) { region.className = rule.name(); break; }
                for (Rule rule : rules.flags) if (rule.matches(region)) region.flags.add(rule.name());
            }
            List<Region> kept = kept();
            for (Region region : kept) for (Region other : kept) if (other != region) {
                long dx = region.integer("x0") + region.integer("x1") - other.integer("x0") - other.integer("x1"), dy = region.integer("y0") + region.integer("y1") - other.integer("y0") - other.integer("y1"); long distance = dx * dx + dy * dy;
                if (region.neighbor < 0 || distance < region.distance) { region.neighbor = other.number; region.distance = distance; }
            }
        }
        String tree(Region region) { return region.children.isEmpty() ? "" + region.number : region.number + "(" + String.join(" ", region.children.stream().map(this::tree).toList()) + ")"; }
        List<String> thresholdLines() {
            List<String> lines = new ArrayList<>(List.of("image " + image.name() + " size " + width + " " + height + " maxval " + image.maxval(),
                "histogram pixels " + histogram.pixels + " min " + histogram.minimum + " max " + histogram.maximum + " mean " + meanText(histogram.total, histogram.pixels) + " median " + histogram.median + " mode " + histogram.mode + " levels " + histogram.levels));
            List<String> bins = new ArrayList<>(List.of("bins", "" + histogram.binWidth)); for (int bin : histogram.bins) bins.add("" + bin); lines.add(String.join(" ", bins));
            lines.add("otsu threshold " + otsu.cutoff() + " upper " + otsu.upper() + " candidates " + otsu.candidates().size());
            for (int i = 0; i < Math.min(parameters.otsuTop, otsu.candidates().size()); i++) {
                Candidate candidate = otsu.candidates().get(i); Split split = candidate.split(); Rational gap = new Rational(split.sumAbove() * split.below() - split.sumBelow() * split.above(), (long) split.below() * split.above());
                lines.add("rank " + (i + 1) + " t " + candidate.cutoff() + " below " + split.below() + " above " + split.above() + " mean_below " + meanText(split.sumBelow(), split.below()) + " mean_above " + meanText(split.sumAbove(), split.above()) + " gap " + Report.decimal(gap, 2));
            }
            lines.add("isodata threshold " + isodata.cutoff() + " iterations " + isodata.iterations()); lines.add("threshold " + cutoff + " " + setting.method() + " " + setting.polarity() + " foreground " + count(initial));
            for (int i = 0; i < morphCounts.size(); i++) lines.add("morph " + setting.operations().get(i) + " foreground " + morphCounts.get(i));
            for (int[] result : sweep) lines.add("sweep " + result[0] + " foreground " + result[1] + " regions " + result[2]); return lines;
        }
        char symbol(int x, int y, boolean skeletonOnly) {
            int label = labels[y][x]; if (label == 0) return holeOf[y][x] > 0 ? ':' : '.';
            Region region = regions.get(label - 1); if (skeletonOnly && !region.skeleton.contains(new Pixel(x, y))) return '+'; return region.kept ? SYMBOLS.charAt(label % 62) : '#';
        }
        List<String> mapLines() {
            String size = image.name() + " " + width + " " + height; List<String> lines = new ArrayList<>(List.of("morphology " + size));
            for (int y = 0; y < height; y++) { StringBuilder row = new StringBuilder(); for (int x = 0; x < width; x++) row.append(mask[y][x] ? (initial[y][x] ? '#' : '+') : (initial[y][x] ? '-' : '.')); lines.add(row.toString()); }
            for (boolean skeletonOnly : new boolean[] {false, true}) { lines.add((skeletonOnly ? "skeleton " : "labels ") + size); for (int y = 0; y < height; y++) { StringBuilder row = new StringBuilder(); for (int x = 0; x < width; x++) row.append(symbol(x, y, skeletonOnly)); lines.add(row.toString()); } }
            return lines;
        }
        String csv(Region region) {
            List<String> fields = new ArrayList<>();
            for (String field : CSV_HEADER.split(",")) fields.add(switch (field) {
                case "image" -> image.name(); case "label" -> "" + region.number; case "class" -> region.className; case "flags" -> region.flags.isEmpty() ? "-" : String.join("+", region.flags);
                case "parent" -> region.parent == null ? "-" : "" + region.parent.number; case "orientation" -> region.orientation; case "hull_area" -> Report.hullArea(region.hullDoubled);
                case "neighbor" -> region.neighbor < 0 ? "-" : "" + region.neighbor; case "distance2" -> region.neighbor < 0 ? "-" : Report.decimal(new Rational(region.distance, 4), 2);
                case "codes" -> region.codes.isEmpty() ? "-" : String.join("", region.codes.stream().map(Object::toString).toList());
                case "cx", "cy", "compactness", "var_x", "var_y", "cov_xy", "anisotropy", "extent", "mirror_lr", "mirror_tb", "solidity", "width2", "elongation" -> Report.decimal(region.features.get(field), 3);
                case "mean", "variance", "contrast" -> Report.decimal(region.features.get(field), 2); case "hu1" -> Report.decimal(region.features.get(field), 4); default -> "" + region.integer(field);
            });
            return String.join(",", fields);
        }
        String intensity(boolean foreground) {
            long total = 0; int count = 0; for (int y = 0; y < height; y++) for (int x = 0; x < width; x++) if (mask[y][x] == foreground) { total += image.pixels()[y][x]; count++; } return meanText(total, count);
        }
        List<String> summary(Rules rules) {
            List<Region> kept = kept(); int holePixels = holes.stream().mapToInt(hole -> hole.pixels().size()).sum();
            List<String> lines = new ArrayList<>(List.of("image " + image.name(), "threshold " + cutoff + " " + setting.method() + " " + setting.polarity() + " conn " + connectivity,
                "foreground " + count(initial) + " " + count(mask), "regions " + regions.size() + " provisional " + provisional + " kept " + kept.size() + " dropped " + (regions.size() - kept.size()),
                "connectivity four " + fourComponents + " eight " + eightComponents, "holes " + holes.size() + " hole_pixels " + holePixels + " euler " + (regions.size() - holes.size()) + " bitquad " + bitQuad));
            for (Hole hole : holes) {
                int x0 = width, y0 = height, x1 = -1, y1 = -1; for (Pixel point : hole.pixels()) { x0 = Math.min(x0, point.x()); y0 = Math.min(y0, point.y()); x1 = Math.max(x1, point.x()); y1 = Math.max(y1, point.y()); }
                lines.add("hole " + hole.number() + " owner " + hole.owner() + " area " + hole.pixels().size() + " box " + x0 + " " + y0 + " " + x1 + " " + y1);
            }
            lines.add("depth_max " + regions.stream().mapToInt(region -> region.depth).max().orElse(0)); List<String> trees = regions.stream().filter(region -> region.parent == null).map(this::tree).toList(); lines.add(trees.isEmpty() ? "tree" : "tree " + String.join(" ", trees));
            lines.add("intensity foreground " + intensity(true) + " background " + intensity(false));
            if (kept.isEmpty()) lines.add("area total 0 mean - largest - smallest -");
            else {
                Region largest = kept.getFirst(), smallest = largest; long total = 0;
                for (Region region : kept) { total += region.integer("area"); if (region.integer("area") > largest.integer("area")) largest = region; if (region.integer("area") < smallest.integer("area")) smallest = region; }
                lines.add("area total " + total + " mean " + meanText(total, kept.size()) + " largest " + largest.number + " " + largest.integer("area") + " smallest " + smallest.number + " " + smallest.integer("area"));
            }
            List<String> classes = new ArrayList<>(List.of("classes")); for (String name : rules.classNames()) { classes.add(name); classes.add("" + kept.stream().filter(region -> region.className.equals(name)).count()); } lines.add(String.join(" ", classes)); lines.add(orientationLine(kept));
            List<String> flags = new ArrayList<>(List.of("flags")); for (Rule rule : rules.flags) { flags.add(rule.name()); flags.add("" + kept.stream().filter(region -> region.flags.contains(rule.name())).count()); } lines.add(String.join(" ", flags)); return lines;
        }
    }
    static List<String> overall(List<Analysis> analyses, Rules rules) {
        List<Region> regions = new ArrayList<>(); int holeCount = 0; for (Analysis analysis : analyses) { regions.addAll(analysis.regions); holeCount += analysis.holes.size(); }
        List<Region> kept = regions.stream().filter(region -> region.kept).toList();
        List<String> lines = new ArrayList<>(List.of("overall", "images " + analyses.size(), "regions " + regions.size() + " kept " + kept.size() + " dropped " + (regions.size() - kept.size()), "holes " + holeCount + " euler " + (regions.size() - holeCount)));
        for (int i = 0; i < rules.filters.size(); i++) { int filter = i; lines.add("filter " + (i + 1) + " " + rules.filters.get(i).words() + " dropped " + regions.stream().filter(region -> region.droppedBy == filter).count()); }
        for (String name : rules.classNames()) { List<Region> members = kept.stream().filter(region -> region.className.equals(name)).toList(); long total = members.stream().mapToLong(region -> region.integer("area")).sum(); lines.add("class " + name + " count " + members.size() + " area " + total + " mean " + meanText(total, members.size())); }
        for (Rule rule : rules.flags) lines.add("flag " + rule.name() + " count " + kept.stream().filter(region -> region.flags.contains(rule.name())).count()); lines.add(orientationLine(kept));
        Region largest = null; String imageName = null;
        for (Analysis analysis : analyses) for (Region region : analysis.kept()) if (largest == null || region.integer("area") > largest.integer("area")) { largest = region; imageName = analysis.image.name(); }
        lines.add(largest == null ? "largest -" : "largest " + imageName + " " + largest.number + " " + largest.integer("area")); return lines;
    }
    public static void main(String[] args) throws Exception {
        Parameters parameters = readParameters("input/params.txt"); Rules rules = readRules("input/rules.txt"); List<Analysis> analyses = new ArrayList<>();
        for (Image image : PgmReader.read("input/images.txt")) { Analysis analysis = new Analysis(image, parameters.settings.get(image.name()), parameters); analysis.applyRules(rules); analyses.add(analysis); }
        List<String> thresholds = new ArrayList<>(), maps = new ArrayList<>(), rows = new ArrayList<>(List.of(CSV_HEADER)), summary = new ArrayList<>();
        for (Analysis analysis : analyses) { thresholds.addAll(analysis.thresholdLines()); maps.addAll(analysis.mapLines()); for (Region region : analysis.kept()) rows.add(analysis.csv(region)); summary.addAll(analysis.summary(rules)); }
        summary.addAll(overall(analyses, rules)); Map<String, List<String>> files = new LinkedHashMap<>(); files.put("thresholds.txt", thresholds); files.put("labels.txt", maps); files.put("regions.csv", rows); files.put("summary.txt", summary); Report.write(files);
    }
}
