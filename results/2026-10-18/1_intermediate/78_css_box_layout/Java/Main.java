import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Comparator;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

public class Main {
    static final LinkedHashMap<String, String> INITIAL = new LinkedHashMap<>();

    static {
        String values = "display=block|position=static|box-sizing=content-box|width=auto|height=auto|"
                + "min-width=0|min-height=0|max-width=none|max-height=none|margin-top=0|"
                + "margin-right=0|margin-bottom=0|margin-left=0|padding-top=0|padding-right=0|"
                + "padding-bottom=0|padding-left=0|border-top=0|border-right=0|border-bottom=0|"
                + "border-left=0|top=auto|right=auto|bottom=auto|left=auto|"
                + "flex-direction=row|flex-wrap=nowrap|justify-content=start|align-items=stretch|align-self=auto|"
                + "row-gap=0|column-gap=0|order=0|flex-grow=0|flex-shrink=1|"
                + "flex-basis=auto|grid-template-columns=none|grid-template-rows=none|grid-column=auto|grid-row=auto";
        for (String entry : values.split("\\|")) {
            int p = entry.indexOf('=');
            INITIAL.put(entry.substring(0, p), entry.substring(p + 1));
        }
    }

    static class Element {
        String type, id, text;
        List<String> classes = new ArrayList<>();
        List<Element> children = new ArrayList<>();
        Map<String, String> style = new HashMap<>(INITIAL);
        Element parent, containing;
        int index, depth, cw, ch, rx, ry, x, y, intrinsic = -1;
        boolean displayed;
        List<String> lines = new ArrayList<>();
        String get(String property) {
            return style.get(property);
        }
        int number(String property) {
            return Integer.parseInt(get(property));
        }
        int hf() {
            return number("padding-left") + number("padding-right") + number("border-left") + number("border-right");
        }
        int vf() {
            return number("padding-top") + number("padding-bottom") + number("border-top") + number("border-bottom");
        }
        int hm() {
            return number("margin-left") + number("margin-right");
        }
        int vm() {
            return number("margin-top") + number("margin-bottom");
        }
        int bw() {
            return cw + hf();
        }
        int bh() {
            return ch + vf();
        }
        int cx() {
            return x + number("border-left") + number("padding-left");
        }
        int cy() {
            return y + number("border-top") + number("padding-top");
        }
    }

    record Declaration(String property, String value) { }

    record Rule(String[] selectors, List<Declaration> declarations) { }

    record Track(char kind, int value) { }

    static class GridItem {
        Element e;
        int row, column, rows, columns, aw, ax, width, contribution;
        boolean placed;
        GridItem(Element e) {
            this.e = e;
            int[] c = placement(e.get("grid-column")), r = placement(e.get("grid-row"));
            column = c[0];
            columns = c[1];
            row = r[0];
            rows = r[1];
        }
    }

    record Grid(List<GridItem> items, int columns, int rows) { }

    static class FlexItem {
        Element e;
        int base, hypothetical, size, cross, outer;
        long weight;
        boolean frozen;
        FlexItem(Element e) {
            this.e = e;
        }
    }
    static final List<Element> elements = new ArrayList<>();

    static int viewportWidth, viewportHeight;

    static boolean integer(String s) {
        if (s.isEmpty() || s.length() > 3) return false;
        for (int i = 0; i < s.length(); i++) if (s.charAt(i) < '0' || s.charAt(i) > '9') return false;
        return true;
    }

    static boolean positive(String s) {
        return integer(s) && Integer.parseInt(s) > 0;
    }

    static boolean signed(String s) {
        return integer(s) || s.startsWith("-") && integer(s.substring(1));
    }

    static boolean percentage(String s) {
        return s.endsWith("%") && integer(s.substring(0, s.length() - 1));
    }

    static boolean oneOf(String s, String values) {
        return Arrays.asList(values.split(" ")).contains(s);
    }

    static boolean known(String property) {
        return INITIAL.containsKey(property) || oneOf(property, "margin padding border gap");
    }

    static Map<String, String> declaration(String property, String value) {
        String[] tokens = value.split(" ", -1);
        Map<String, String> result = new LinkedHashMap<>();
        if (oneOf(property, "margin padding border gap")) {
            boolean gap = property.equals("gap");
            if (tokens.length < 1 || tokens.length > (gap ? 2 : 4)) return null;
            for (String token : tokens) if (!integer(token) || property.equals("border") && !oneOf(token, "0 1")) return null;
            if (gap) {
                result.put("row-gap", tokens[0]);
                result.put("column-gap", tokens[tokens.length - 1]);
            } else {
                String[] sides = {"top", "right", "bottom", "left"};
                String[] expanded = {tokens[0], tokens.length > 1 ? tokens[1] : tokens[0], tokens.length > 2 ? tokens[2] : tokens[0], tokens.length > 3 ? tokens[3] : tokens.length > 1 ? tokens[1] : tokens[0]};
                for (int i = 0; i < 4; i++) result.put(property + "-" + sides[i], expanded[i]);
            }
            return result;
        }
        if (!INITIAL.containsKey(property)) return null;
        boolean valid;
        if (property.startsWith("grid-template-")) {
            valid = value.equals("none");
            if (!valid) {
                valid = true;
                for (String token : tokens) if (!integer(token) && !token.equals("auto") && !(token.endsWith("fr") && positive(token.substring(0, token.length() - 2)))) valid = false;
            }
        } else if (property.equals("grid-column") || property.equals("grid-row")) {
            valid = tokens.length == 1 && (value.equals("auto") || positive(value))
                    || tokens.length == 2 && tokens[0].equals("span") && positive(tokens[1])
                    || tokens.length == 3 && positive(tokens[0]) && tokens[1].equals("/") && positive(tokens[2]) && Integer.parseInt(tokens[0]) < Integer.parseInt(tokens[2])
                    || tokens.length == 4 && positive(tokens[0]) && tokens[1].equals("/") && tokens[2].equals("span") && positive(tokens[3]);
        } else {
            if (tokens.length != 1) return null;
            valid = switch (property) {
                case "display" -> oneOf(value, "block flex grid none");
                case "position" -> oneOf(value, "static relative absolute");
                case "box-sizing" -> oneOf(value, "content-box border-box");
                case "width", "height", "flex-basis" -> value.equals("auto") || integer(value) || percentage(value);
                case "min-width", "min-height" -> integer(value) || percentage(value);
                case "max-width", "max-height" -> value.equals("none") || integer(value) || percentage(value);
                case "top", "right", "bottom", "left" -> value.equals("auto") || signed(value);
                case "order" -> signed(value);
                case "flex-direction" -> oneOf(value, "row row-reverse column column-reverse");
                case "flex-wrap" -> oneOf(value, "nowrap wrap");
                case "justify-content" -> oneOf(value, "start end center space-between space-around space-evenly");
                case "align-items" -> oneOf(value, "stretch start end center");
                case "align-self" -> oneOf(value, "auto stretch start end center");
                default -> property.startsWith("border-") ? oneOf(value, "0 1") : integer(value);
            };
        }
        if (!valid) return null;
        result.put(property, value);
        return result;
    }

    static List<Element> flow(Element e, boolean sorted) {
        List<Element> result = new ArrayList<>();
        for (Element child : e.children) if (child.displayed && !child.get("position").equals("absolute")) result.add(child);
        if (sorted) result.sort(Comparator.comparingInt((Element a) -> a.number("order")).thenComparingInt(a -> a.index));
        return result;
    }

    static int resolve(Element e, String property, int reference, boolean horizontal) {
        String value = e.get(property);
        if (value.equals("auto") || value.equals("none")) return -1;
        int n;
        if (value.endsWith("%")) {
            if (reference < 0) return -1;
            n = (int)((long)reference * Integer.parseInt(value.substring(0, value.length() - 1)) / 100);
        } else n = Integer.parseInt(value);
        return e.get("box-sizing").equals("border-box") ? Math.max(0, n - (horizontal ? e.hf() : e.vf())) : n;
    }

    static int clamp(Element e, int value, int reference, boolean horizontal) {
        String axis = horizontal ? "width" : "height";
        int low = resolve(e, "min-" + axis, reference, horizontal), high = resolve(e, "max-" + axis, reference, horizontal);
        if (high >= 0) value = Math.min(value, high);
        return Math.max(value, Math.max(0, low));
    }

    static int[] distribute(int total, long[] weights) {
        int[] result = new int[weights.length];
        long sum = 0;
        for (long w : weights) sum += w;
        if (sum == 0) return result;
        int remaining = total;
        for (int i = 0; i < weights.length; i++) {
            result[i] = (int)((long)total * weights[i] / sum);
            remaining -= result[i];
        }
        for (int i = 0; i < weights.length && remaining > 0; i++) if (weights[i] > 0) {
            result[i]++;
            remaining--;
        }
        return result;
    }

    static int[] placement(String value) {
        String[] t = value.split(" ");
        if (value.equals("auto")) return new int[]{0, 1};
        if (t[0].equals("span")) return new int[]{0, Integer.parseInt(t[1])};
        int start = Integer.parseInt(t[0]);
        return new int[]{start, t.length == 1 ? 1 : t.length == 3 ? Integer.parseInt(t[2]) - start : Integer.parseInt(t[3])};
    }

    static List<Track> tracks(String value, boolean columns) {
        List<Track> result = new ArrayList<>();
        if (value.equals("none")) {
            if (columns) result.add(new Track('a', 0));
            return result;
        }
        for (String token : value.split(" ")) result.add(token.equals("auto") ? new Track('a', 0) : token.endsWith("fr") ? new Track('f', Integer.parseInt(token.substring(0, token.length() - 2))) : new Track('n', Integer.parseInt(token)));
        return result;
    }

    static boolean overlaps(List<GridItem> items, GridItem item, int row, int column) {
        for (GridItem other : items) if (other.placed && row < other.row + other.rows && other.row < row + item.rows && column < other.column + other.columns && other.column < column + item.columns) return true;
        return false;
    }

    static Grid grid(Element e) {
        List<GridItem> items = new ArrayList<>();
        int nc = tracks(e.get("grid-template-columns"), true).size(), nr = tracks(e.get("grid-template-rows"), false).size();
        for (Element child : flow(e, true)) {
            GridItem item = new GridItem(child);
            items.add(item);
            nc = Math.max(nc, item.column == 0 ? item.columns : item.column + item.columns - 1);
        }
        for (GridItem item : items) if (item.row > 0 && item.column > 0) item.placed = true;
        int cr = 1, cc = 1;
        for (GridItem item : items) {
            if (item.placed) continue;
            if (item.row > 0) {
                int c = 1;
                while (c <= nc - item.columns + 1 && overlaps(items, item, item.row, c)) c++;
                item.column = c <= nc - item.columns + 1 ? c : 1;
            } else if (item.column > 0) {
                if (item.column < cc) cr++;
                int r = cr;
                while (overlaps(items, item, r, item.column)) r++;
                item.row = r;
                cr = r;
                cc = item.column + item.columns;
            } else {
                int r = cr, c = cc;
                while (true) {
                    if (c + item.columns - 1 > nc) {
                        r++;
                        c = 1;
                    } else if (overlaps(items, item, r, c)) c++;
                    else break;
                }
                item.row = r;
                item.column = c;
                cr = r;
                cc = c + item.columns;
            }
            item.placed = true;
        }
        for (GridItem item : items) nr = Math.max(nr, item.row + item.rows - 1);
        return new Grid(items, nc, nr);
    }

    static int[] trackSizes(Element e, Grid grid, boolean columns, int available, boolean intrinsic) {
        int count = columns ? grid.columns : grid.rows;
        List<Track> specs = tracks(e.get(columns ? "grid-template-columns" : "grid-template-rows"), columns);
        while (specs.size() < count) specs.add(new Track('a', 0));
        int[] sizes = new int[count];
        for (int i = 0; i < count; i++) {
            Track track = specs.get(i);
            if (track.kind == 'n') sizes[i] = track.value;
            else if (track.kind == 'a' || available < 0) {
                for (GridItem item : grid.items) if ((columns ? item.column : item.row) == i + 1 && (columns ? item.columns : item.rows) == 1) sizes[i] = Math.max(sizes[i], intrinsic ? contribution(item.e) : item.contribution);
            }
        }
        int gap = e.number(columns ? "column-gap" : "row-gap");
        int leftover = available - Arrays.stream(sizes).sum() - gap * Math.max(0, count - 1);
        if (available >= 0 && leftover > 0) {
            boolean fr = specs.stream().anyMatch(t -> t.kind == 'f');
            long[] weights = new long[count];
            for (int i = 0; i < count; i++) if (fr ? specs.get(i).kind == 'f' : specs.get(i).kind == 'a') weights[i] = fr ? specs.get(i).value : 1;
            int[] extra = distribute(leftover, weights);
            for (int i = 0; i < count; i++) sizes[i] += extra[i];
        }
        return sizes;
    }

    static int maxContent(Element e) {
        if (e.intrinsic >= 0) return e.intrinsic;
        int result = 0;
        if (e.text != null) result = e.text.length();
        else if (e.get("display").equals("flex") && e.get("flex-direction").startsWith("row")) {
            List<Element> children = flow(e, false);
            for (Element child : children) result += contribution(child);
            result += e.number("column-gap") * Math.max(0, children.size() - 1);
        } else if (e.get("display").equals("grid")) {
            Grid g = grid(e);
            result = Arrays.stream(trackSizes(e, g, true, -1, true)).sum() + e.number("column-gap") * (g.columns - 1);
        } else for (Element child : flow(e, false)) result = Math.max(result, contribution(child));
        e.intrinsic = result;
        return result;
    }

    static int contribution(Element e) {
        int w = resolve(e, "width", -1, true);
        return clamp(e, w < 0 ? maxContent(e) : w, -1, true) + e.hf() + e.hm();
    }

    static String align(Element parent, Element child) {
        return child.get("align-self").equals("auto") ? parent.get("align-items") : child.get("align-self");
    }

    static int offset(String align, int space) {
        return space <= 0 ? 0 : align.equals("end") ? space : align.equals("center") ? space / 2 : 0;
    }

    static void position(Element parent, Element child, int x, int y) {
        child.rx = parent.number("border-left") + parent.number("padding-left") + x;
        child.ry = parent.number("border-top") + parent.number("padding-top") + y;
    }

    static int layout(Element e, int widthReference, int heightReference, int forcedWidth, int forcedHeight) {
        int w = resolve(e, "width", widthReference, true);
        e.cw = forcedWidth >= 0 ? forcedWidth : clamp(e, w < 0 ? Math.max(0, widthReference - e.hm() - e.hf()) : w, widthReference, true);
        if (forcedHeight < 0) {
            int h = resolve(e, "height", heightReference, false);
            if (h >= 0) forcedHeight = clamp(e, h, heightReference, false);
        }
        int a;
        if (e.text != null) {
            e.lines = new ArrayList<>();
            String current = "";
            for (String word : e.text.split(" ")) {
                if (current.isEmpty()) current = word;
                else if (current.length() + 1 + word.length() <= e.cw) current += " " + word;
                else {
                    e.lines.add(current);
                    current = word;
                }
            }
            e.lines.add(current);
            a = e.lines.size();
        } else if (e.get("display").equals("flex")) a = flex(e, forcedHeight, heightReference);
        else if (e.get("display").equals("grid")) a = gridLayout(e, forcedHeight);
        else {
            a = 0;
            int previousBottom = 0;
            boolean first = true;
            for (Element child : flow(e, false)) {
                layout(child, e.cw, forcedHeight, -1, -1);
                int y = a + (first ? child.number("margin-top") : Math.max(previousBottom, child.number("margin-top")));
                position(e, child, child.number("margin-left"), y);
                a = y + child.bh();
                previousBottom = child.number("margin-bottom");
                first = false;
            }
            if (!first) a += previousBottom;
        }
        e.ch = forcedHeight >= 0 ? forcedHeight : clamp(e, a, heightReference, false);
        return a;
    }

    static int flex(Element e, int k, int heightReference) {
        boolean horizontal = e.get("flex-direction").startsWith("row"), reverse = e.get("flex-direction").endsWith("reverse");
        int reference = horizontal ? e.cw : k, gap = e.number(horizontal ? "column-gap" : "row-gap");
        List<FlexItem> items = new ArrayList<>();
        for (Element child : flow(e, true)) {
            FlexItem item = new FlexItem(child);
            items.add(item);
            item.outer = horizontal ? child.hm() + child.hf() : child.vm() + child.vf();
            if (!horizontal) {
                int r = Math.max(0, e.cw - child.hm() - child.hf()), width = resolve(child, "width", e.cw, true);
                item.cross = clamp(child, width >= 0 ? width : align(e, child).equals("stretch") ? r : Math.min(maxContent(child), r), e.cw, true);
            }
            item.base = resolve(child, "flex-basis", reference, horizontal);
            if (item.base < 0) item.base = resolve(child, horizontal ? "width" : "height", reference, horizontal);
            if (item.base < 0) item.base = horizontal ? maxContent(child) : layout(child, e.cw, k, item.cross, -1);
            item.hypothetical = clamp(child, item.base, reference, horizontal);
        }
        int length = reference;
        if (length < 0) {
            length = gap * Math.max(0, items.size() - 1);
            for (FlexItem item : items) length += item.hypothetical + item.outer;
            length = clamp(e, length, heightReference, false);
        }
        List<List<FlexItem>> lines = new ArrayList<>();
        int occupied = 0;
        for (FlexItem item : items) {
            if (lines.isEmpty() || horizontal && e.get("flex-wrap").equals("wrap") && occupied + gap + item.hypothetical + item.outer > length) {
                lines.add(new ArrayList<>());
                occupied = 0;
            }
            List<FlexItem> line = lines.get(lines.size() - 1);
            if (!line.isEmpty()) occupied += gap;
            occupied += item.hypothetical + item.outer;
            line.add(item);
        }
        int crossStart = 0;
        for (List<FlexItem> line : lines) {
            int total = gap * (line.size() - 1);
            for (FlexItem item : line) total += item.hypothetical + item.outer;
            boolean grow = total < length;
            for (FlexItem item : line) {
                item.weight = grow ? item.e.number("flex-grow") : (long)item.e.number("flex-shrink") * item.base;
                item.size = item.hypothetical;
                item.frozen = item.weight == 0 || (grow ? item.base > item.hypothetical : item.base < item.hypothetical);
            }
            while (true) {
                int free = length - gap * (line.size() - 1), remaining = 0;
                long[] weights = new long[line.size()];
                for (int i = 0; i < line.size(); i++) {
                    FlexItem item = line.get(i);
                    free -= (item.frozen ? item.size : item.base) + item.outer;
                    if (!item.frozen) {
                        weights[i] = item.weight;
                        remaining++;
                    }
                }
                if (remaining == 0) break;
                int[] shares = distribute(Math.max(0, grow ? free : -free), weights), violations = new int[line.size()];
                int violation = 0;
                for (int i = 0; i < line.size(); i++) {
                    FlexItem item = line.get(i);
                    if (!item.frozen) {
                        int tentative = item.base + (grow ? shares[i] : -shares[i]);
                        item.size = clamp(item.e, tentative, reference, horizontal);
                        violations[i] = item.size - tentative;
                        violation += violations[i];
                    }
                }
                for (int i = 0; i < line.size(); i++) if (violation == 0 || violation > 0 && violations[i] > 0 || violation < 0 && violations[i] < 0) line.get(i).frozen = true;
            }
            int lc = horizontal ? 0 : e.cw;
            if (horizontal) {
                for (FlexItem item : line) {
                    layout(item.e, e.cw, k, item.size, -1);
                    item.cross = item.e.ch;
                    lc = Math.max(lc, item.cross + item.e.vf() + item.e.vm());
                }
                if (lines.size() == 1) lc = k >= 0 ? k : clamp(e, lc, heightReference, false);
            }
            int used = gap * (line.size() - 1);
            for (FlexItem item : line) used += item.size + item.outer;
            int space = length - used;
            int[] before = new int[line.size() + 1];
            if (space > 0) {
                String justify = e.get("justify-content");
                if (justify.equals("end")) before[0] = space;
                else if (justify.equals("center")) before[0] = space / 2;
                else if (justify.startsWith("space-")) {
                    long[] weights = new long[before.length];
                    Arrays.fill(weights, 1);
                    if (justify.equals("space-between")) {
                        weights[0] = 0;
                        weights[weights.length - 1] = 0;
                    } else if (justify.equals("space-around")) for (int i = 1; i < weights.length - 1; i++) weights[i] = 2;
                    before = distribute(space, weights);
                }
            }
            int cursor = 0;
            for (int i = 0; i < line.size(); i++) {
                FlexItem item = line.get(i);
                Element child = item.e;
                String alignment = align(e, child);
                if (horizontal) {
                    if (alignment.equals("stretch") && child.get("height").equals("auto")) {
                        item.cross = clamp(child, Math.max(0, lc - child.vm() - child.vf()), k, false);
                        layout(child, e.cw, k, item.size, item.cross);
                    } else layout(child, e.cw, k, item.size, -1);
                } else layout(child, e.cw, k, item.cross, item.size);
                int cross = crossStart + offset(alignment, lc - item.cross - (horizontal ? child.vf() + child.vm() : child.hf() + child.hm())) + child.number(horizontal ? "margin-top" : "margin-left");
                cursor += before[i];
                int main = reverse ? length - cursor - child.number(horizontal ? "margin-right" : "margin-bottom") - item.size - (horizontal ? child.hf() : child.vf()) : cursor + child.number(horizontal ? "margin-left" : "margin-top");
                position(e, child, horizontal ? main : cross, horizontal ? cross : main);
                cursor += item.size + item.outer + gap;
            }
            crossStart += lc + e.number("row-gap");
        }
        return horizontal ? lines.isEmpty() ? 0 : crossStart - e.number("row-gap") : length;
    }

    static int prefix(int[] sizes, int count, int gap) {
        int result = count * gap;
        for (int i = 0; i < count; i++) result += sizes[i];
        return result;
    }

    static int area(int[] sizes, int start, int span, int gap) {
        int result = gap * (span - 1);
        for (int i = start - 1; i < start - 1 + span; i++) result += sizes[i];
        return result;
    }

    static int gridLayout(Element e, int k) {
        Grid g = grid(e);
        int cg = e.number("column-gap"), rg = e.number("row-gap");
        int[] columns = trackSizes(e, g, true, e.cw, true);
        for (GridItem item : g.items) {
            item.aw = area(columns, item.column, item.columns, cg);
            item.ax = prefix(columns, item.column - 1, cg);
            int width = resolve(item.e, "width", item.aw, true);
            item.width = clamp(item.e, width < 0 ? Math.max(0, item.aw - item.e.hm() - item.e.hf()) : width, item.aw, true);
            layout(item.e, item.aw, -1, item.width, -1);
            item.contribution = item.e.bh() + item.e.vm();
        }
        int[] rows = trackSizes(e, g, false, k, false);
        for (GridItem item : g.items) {
            int ah = area(rows, item.row, item.rows, rg), ay = prefix(rows, item.row - 1, rg);
            String alignment = align(e, item.e);
            int fh = alignment.equals("stretch") && item.e.get("height").equals("auto") ? clamp(item.e, Math.max(0, ah - item.e.vm() - item.e.vf()), ah, false) : -1;
            layout(item.e, item.aw, ah, item.width, fh);
            position(e, item.e, item.ax + item.e.number("margin-left"), ay + offset(alignment, ah - item.e.bh() - item.e.vm()) + item.e.number("margin-top"));
        }
        return Arrays.stream(rows).sum() + rg * Math.max(0, g.rows - 1);
    }

    static void relayout() {
        for (Element e : elements) {
            e.displayed = !e.get("display").equals("none") && (e.parent == null || e.parent.displayed);
            e.intrinsic = -1;
            e.containing = null;
        }
        Element root = elements.get(0);
        if (root.displayed && !root.get("position").equals("absolute")) {
            layout(root, viewportWidth, viewportHeight, -1, -1);
            root.rx = root.number("margin-left");
            root.ry = root.number("margin-top");
        }
        for (Element e : elements) if (e.displayed && e.get("position").equals("absolute")) {
            Element cb = e.parent;
            while (cb != null && cb.get("position").equals("static")) cb = cb.parent;
            e.containing = cb;
            int width = cb == null ? viewportWidth : cb.cw + cb.number("padding-left") + cb.number("padding-right"), height = cb == null ? viewportHeight : cb.ch + cb.number("padding-top") + cb.number("padding-bottom");
            int left = e.get("left").equals("auto") ? 0 : e.number("left"), right = e.get("right").equals("auto") ? 0 : e.number("right"), top = e.get("top").equals("auto") ? 0 : e.number("top"), bottom = e.get("bottom").equals("auto") ? 0 : e.number("bottom");
            int w = resolve(e, "width", width, true);
            if (e.get("width").equals("auto")) {
                int r = Math.max(0, width - left - right - e.hm() - e.hf());
                w = !e.get("left").equals("auto") && !e.get("right").equals("auto") ? r : Math.min(maxContent(e), r);
            }
            int h = e.get("height").equals("auto") && !e.get("top").equals("auto") && !e.get("bottom").equals("auto") ? clamp(e, Math.max(0, height - top - bottom - e.vm() - e.vf()), height, false) : -1;
            layout(e, width, height, clamp(e, w, width, true), h);
            e.rx = !e.get("left").equals("auto") ? left + e.number("margin-left") : !e.get("right").equals("auto") ? width - right - e.number("margin-right") - e.bw() : e.number("margin-left");
            e.ry = !e.get("top").equals("auto") ? top + e.number("margin-top") : !e.get("bottom").equals("auto") ? height - bottom - e.number("margin-bottom") - e.bh() : e.number("margin-top");
        }
        for (Element e : elements) if (e.displayed) {
            Element ref = e.get("position").equals("absolute") ? e.containing : e.parent;
            e.x = e.rx + (ref == null ? 0 : ref.x + (e.get("position").equals("absolute") ? ref.number("border-left") : 0));
            e.y = e.ry + (ref == null ? 0 : ref.y + (e.get("position").equals("absolute") ? ref.number("border-top") : 0));
            if (e.get("position").equals("relative")) {
                e.x += !e.get("left").equals("auto") ? e.number("left") : !e.get("right").equals("auto") ? -e.number("right") : 0;
                e.y += !e.get("top").equals("auto") ? e.number("top") : !e.get("bottom").equals("auto") ? -e.number("bottom") : 0;
            }
        }
    }

    static int[][] snapshot() {
        int[][] result = new int[elements.size()][5];
        for (Element e : elements) result[e.index] = new int[]{e.displayed ? 1 : 0, e.x, e.y, e.bw(), e.bh()};
        return result;
    }

    static String changes(int[][] old) {
        List<String> changed = new ArrayList<>();
        int[][] now = snapshot();
        for (Element e : elements) if (old[e.index][0] != now[e.index][0] || e.displayed && !Arrays.equals(old[e.index], now[e.index])) changed.add(e.id);
        return changed.isEmpty() ? "no change" : String.join(" ", changed);
    }

    static String rectangle(String name, int x, int y, int w, int h) {
        return name + " " + x + " " + y + " " + w + " " + h + "\n";
    }

    static void render(StringBuilder out) {
        char[][] screen = new char[viewportHeight][viewportWidth];
        for (char[] row : screen) Arrays.fill(row, '.');
        for (Element e : elements) if (e.displayed) {
            for (int y = Math.max(0, e.y); y < Math.min(viewportHeight, e.y + e.bh()); y++) for (int x = Math.max(0, e.x); x < Math.min(viewportWidth, e.x + e.bw()); x++) {
                boolean horizontal = e.number("border-top") == 1 && y == e.y || e.number("border-bottom") == 1 && y == e.y + e.bh() - 1, vertical = e.number("border-left") == 1 && x == e.x || e.number("border-right") == 1 && x == e.x + e.bw() - 1;
                screen[y][x] = horizontal ? vertical ? '+' : '-' : vertical ? '|' : ' ';
            }
            if (e.text != null) for (int i = 0; i < e.lines.size(); i++) {
                int y = e.cy() + i;
                if (y < 0 || y >= viewportHeight) continue;
                String line = e.lines.get(i);
                for (int j = 0; j < line.length(); j++) {
                    int x = e.cx() + j;
                    if (x >= 0 && x < viewportWidth) screen[y][x] = line.charAt(j);
                }
            }
        }
        String edge = "#".repeat(viewportWidth + 2);
        out.append("render ").append(viewportWidth).append('x').append(viewportHeight).append('\n').append(edge).append('\n');
        for (char[] row : screen) out.append('#').append(row).append("#\n");
        out.append(edge).append('\n');
    }

    static void command(String line, StringBuilder out) {
        String[] t = line.split(" ");
        Element e = t.length > 1 ? elements.stream().filter(a -> a.id.equals(t[1])).findFirst().orElse(null) : null;
        switch (t[0]) {
            case "LAYOUT" -> {
                out.append("layout ").append(viewportWidth).append('x').append(viewportHeight).append('\n');
                for (Element a : elements) out.append("  ".repeat(a.depth)).append(a.displayed ? rectangle(a.id, a.x, a.y, a.bw(), a.bh()) : a.id + " none\n");
            }
            case "BOX" -> {
                if (e == null) out.append("error: unknown element ").append(t[1]).append('\n');
                else if (!e.displayed) out.append("box ").append(e.id).append(": none\n");
                else {
                    out.append("box ").append(e.id).append('\n');
                    out.append(rectangle("margin", e.x - e.number("margin-left"), e.y - e.number("margin-top"), e.bw() + e.hm(), e.bh() + e.vm()));
                    out.append(rectangle("border", e.x, e.y, e.bw(), e.bh()));
                    out.append(rectangle("padding", e.x + e.number("border-left"), e.y + e.number("border-top"), e.cw + e.number("padding-left") + e.number("padding-right"), e.ch + e.number("padding-top") + e.number("padding-bottom")));
                    out.append(rectangle("content", e.cx(), e.cy(), e.cw, e.ch));
                }
            }
            case "RENDER" -> render(out);
            case "HIT" -> {
                int x = Integer.parseInt(t[1]), y = Integer.parseInt(t[2]);
                if (x >= viewportWidth || y >= viewportHeight) out.append("error: point ").append(x).append(' ').append(y).append(" outside viewport\n");
                else {
                    Element hit = null;
                    for (Element a : elements) if (a.displayed && x >= a.x && x < a.x + a.bw() && y >= a.y && y < a.y + a.bh()) hit = a;
                    List<String> path = new ArrayList<>();
                    for (; hit != null; hit = hit.parent) path.add(0, hit.id);
                    out.append("hit ").append(x).append(' ').append(y).append(": ").append(path.isEmpty() ? "none" : String.join(" > ", path)).append('\n');
                }
            }
            case "SET" -> {
                String value = line.substring(t[0].length() + t[1].length() + t[2].length() + 3);
                if (e == null) out.append("error: unknown element ").append(t[1]).append('\n');
                else if (!known(t[2])) out.append("error: unknown property ").append(t[2]).append('\n');
                else {
                    Map<String, String> values = declaration(t[2], value);
                    if (values == null) out.append("error: invalid value for ").append(t[2]).append(": ").append(value).append('\n');
                    else {
                        int[][] old = snapshot();
                        e.style.putAll(values);
                        relayout();
                        out.append("set ").append(e.id).append(' ').append(t[2]).append(' ').append(value).append(": ").append(changes(old)).append('\n');
                    }
                }
            }
            case "VIEWPORT" -> {
                int w = Integer.parseInt(t[1]), h = Integer.parseInt(t[2]);
                if (w < 1 || w > 80 || h < 1 || h > 40) out.append("error: invalid viewport ").append(w).append(' ').append(h).append('\n');
                else {
                    int[][] old = snapshot();
                    viewportWidth = w;
                    viewportHeight = h;
                    relayout();
                    out.append("viewport ").append(w).append(' ').append(h).append(": ").append(changes(old)).append('\n');
                }
            }
            case "OVERFLOW" -> {
                List<String> list = new ArrayList<>();
                for (Element a : elements) if (a.displayed) {
                    boolean overflow = a.text != null && (a.lines.size() > a.ch || a.lines.stream().anyMatch(s -> s.length() > a.cw));
                    if (a.text == null) for (Element child : flow(a, false)) if (child.x - child.number("margin-left") < a.cx() || child.y - child.number("margin-top") < a.cy() || child.x + child.bw() + child.number("margin-right") > a.cx() + a.cw || child.y + child.bh() + child.number("margin-bottom") > a.cy() + a.ch) overflow = true;
                    if (overflow) list.add(a.id);
                }
                out.append("overflow: ").append(list.isEmpty() ? "none" : String.join(" ", list)).append('\n');
            }
            default -> out.append("error: unknown command ").append(t[0]).append('\n');
        }
    }

    public static void main(String[] args) throws Exception {
        BufferedReader reader = new BufferedReader(new InputStreamReader(System.in));
        String[] dimensions = reader.readLine().split(" ");
        viewportWidth = Integer.parseInt(dimensions[0]);
        viewportHeight = Integer.parseInt(dimensions[1]);
        List<Rule> rules = new ArrayList<>();
        String line;
        while (!(line = reader.readLine()).equals("---")) {
            int brace = line.indexOf(" { ");
            List<Declaration> declarations = new ArrayList<>();
            for (String raw : line.substring(brace + 3, line.length() - 2).split("; ")) {
                int colon = raw.indexOf(": ");
                Map<String, String> values = declaration(raw.substring(0, colon), raw.substring(colon + 2));
                if (values != null) for (Map.Entry<String, String> entry : values.entrySet()) declarations.add(new Declaration(entry.getKey(), entry.getValue()));
            }
            rules.add(new Rule(line.substring(0, brace).split(", "), declarations));
        }
        Element[] ancestors = new Element[11];
        while (!(line = reader.readLine()).equals("===")) {
            int spaces = 0;
            while (line.charAt(spaces) == ' ') spaces++;
            Element e = new Element();
            e.depth = spaces / 2;
            e.index = elements.size();
            String body = line.substring(spaces);
            int end = body.indexOf(' ');
            String head = end < 0 ? body : body.substring(0, end);
            if (end >= 0) e.text = body.substring(end + 2, body.length() - 1);
            String[] parts = head.split("[#.]");
            e.type = parts[0];
            e.id = parts[1];
            for (int i = 2; i < parts.length; i++) e.classes.add(parts[i]);
            if (e.depth > 0) {
                e.parent = ancestors[e.depth - 1];
                e.parent.children.add(e);
            }
            ancestors[e.depth] = e;
            elements.add(e);
            Map<String, Integer> scores = new HashMap<>();
            for (Rule rule : rules) {
                int score = -1;
                for (String selector : rule.selectors) {
                    if (selector.startsWith("#") && selector.substring(1).equals(e.id)) score = Math.max(score, 2);
                    else if (selector.startsWith(".") && e.classes.contains(selector.substring(1))) score = Math.max(score, 1);
                    else if (selector.equals(e.type)) score = Math.max(score, 0);
                }
                if (score >= 0) for (Declaration d : rule.declarations) if (score >= scores.getOrDefault(d.property, -1)) {
                    e.style.put(d.property, d.value);
                    scores.put(d.property, score);
                }
            }
        }
        relayout();
        while (!(line = reader.readLine()).equals("END")) {
            StringBuilder out = new StringBuilder();
            command(line, out);
            System.out.print(out);
        }
    }
}
