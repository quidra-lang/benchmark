import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Comparator;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.StringJoiner;
import java.util.stream.Collectors;

record Pen(int width, String color, int on, int off) {}
record Brush(List<String> colors, String axis, String rule) {}
final class Styles {
    final Map<String, Color> colors = new HashMap<>();
    final Map<String, Pen> pens = new HashMap<>();
    final Map<String, Brush> brushes = new HashMap<>();
}
final class Font {
    final int width, height;
    final Map<Character, List<Point>> glyphs = new HashMap<>();
    Font(int width, int height) { this.width = width; this.height = height; }
}
final class Node {
    boolean repeat;
    int line, count, dx, dy;
    String keyword = "";
    String[] arguments = new String[0];
    final List<Node> body = new ArrayList<>();
}
final class Block {
    final String name, mode;
    final int opacity;
    int endLine;
    final List<Node> body = new ArrayList<>();
    Block(String name, int opacity, String mode) { this.name = name; this.opacity = opacity; this.mode = mode; }
}
final class Scene {
    int width, height;
    String background;
    final List<Block> layers = new ArrayList<>();
    final Map<String, Block> symbols = new HashMap<>();
}
record Probe(String kind, int[] values) {}
record PathCommand(char letter, int[] values) {}
final class Subpath {
    final List<Point> points = new ArrayList<>();
    boolean closed;
    Subpath(Point point) { points.add(point); }
}
final class Execution {
    final int sequence, layer;
    final Node command;
    String kind = "", error = "";
    int pixels;
    Rect box;
    Execution(int sequence, int layer, Node command) { this.sequence = sequence; this.layer = layer; this.command = command; }
}
record Form(int count, int first) {}
final class Raster {
    static final Set<String> PEN_COMMANDS = Set.of("LINE","RECT","CIRCLE","ELLIPSE","POLYLINE","POLYGON","PATH");
    static final Set<String> BRUSH_COMMANDS = Set.of("FILLRECT","FILLCIRCLE","FILLELLIPSE","FILLPOLYGON","FILLPATH","FLOOD","TEXT");
    static final Set<String> STATE_COMMANDS = Set.of("TRANSLATE","SCALE","ROTATE","SAVE","RESTORE","CLIP","NOCLIP","USE");
    static final List<String> ERROR_NAMES = List.of("unknown_command","bad_arguments","unknown_style","unknown_symbol","unknown_glyph","bad_value","stack_empty");
    static final Map<String, Form> FORMS = Map.ofEntries(Map.entry("LINE",new Form(5,1)),Map.entry("RECT",new Form(5,1)),Map.entry("FILLRECT",new Form(5,1)),Map.entry("CIRCLE",new Form(4,1)),Map.entry("FILLCIRCLE",new Form(4,1)),Map.entry("ELLIPSE",new Form(5,1)),Map.entry("FILLELLIPSE",new Form(5,1)),Map.entry("FLOOD",new Form(3,1)),Map.entry("ERASE",new Form(4,0)),Map.entry("TRANSLATE",new Form(2,0)),Map.entry("SCALE",new Form(2,0)),Map.entry("ROTATE",new Form(1,0)),Map.entry("SAVE",new Form(0,0)),Map.entry("RESTORE",new Form(0,0)),Map.entry("NOCLIP",new Form(0,0)),Map.entry("CLIP",new Form(4,0)),Map.entry("USE",new Form(3,1)));
    static final Map<Character, Integer> PATH_ARITIES = Map.of('M',2,'L',2,'H',1,'V',1,'Q',4,'C',6,'Z',0);
    static String line(Object... values) { StringJoiner joiner = new StringJoiner(" "); for (Object value : values) joiner.add(value.toString()); return joiner.toString(); }
    static String[] words(String text) { String trimmed = text.strip(); return trimmed.isEmpty() ? new String[0] : trimmed.split(" +"); }
    static boolean integerWord(String text) { return text.matches("-?[0-9]+"); }
    static List<PathCommand> parsePath(String[] words, int first) {
        List<PathCommand> result = new ArrayList<>();
        for (int i = first; i < words.length;) {
            if (words[i].length() != 1) return null; char letter = words[i].charAt(0), upper = Character.toUpperCase(letter); Integer arity = PATH_ARITIES.get(upper); if (arity == null || letter != upper && letter != Character.toLowerCase(upper)) return null;
            if ((result.isEmpty() || Character.toUpperCase(result.getLast().letter()) == 'Z') && upper != 'M') return null;
            if (i + arity >= words.length) return null; int[] values = new int[arity]; for (int j = 0; j < arity; j++) { if (!integerWord(words[i + j + 1])) return null; values[j] = Integer.parseInt(words[i + j + 1]); } result.add(new PathCommand(letter,values)); i += arity + 1;
        }
        return result.isEmpty() ? null : result;
    }
    static boolean validForm(String keyword, String[] a) {
        Form form = FORMS.get(keyword); if (form != null) return a.length == form.count() && Arrays.stream(a).skip(form.first()).allMatch(Raster::integerWord);
        if (keyword.equals("TEXT")) return a.length == 5 && integerWord(a[1]) && integerWord(a[2]);
        if (Set.of("POLYLINE","POLYGON","FILLPOLYGON").contains(keyword)) return a.length >= 2 && Arrays.stream(a).skip(1).allMatch(Raster::integerWord) && a.length == 2 + 2 * Integer.parseInt(a[1]);
        return a.length >= 2 && integerWord(a[1]) && parsePath(a,2) != null;
    }
    static Set<Point> rectPixels(Rect rect) { Set<Point> pixels = new HashSet<>(); for (int y = rect.y0(); y <= rect.y1(); y++) for (int x = rect.x0(); x <= rect.x1(); x++) pixels.add(new Point(x,y)); return pixels; }
    static Rect bounds(Set<Point> pixels) { if (pixels.isEmpty()) return null; return new Rect(pixels.stream().mapToInt(Point::x).min().orElseThrow(),pixels.stream().mapToInt(Point::y).min().orElseThrow(),pixels.stream().mapToInt(Point::x).max().orElseThrow(),pixels.stream().mapToInt(Point::y).max().orElseThrow()); }
    static String boxText(Rect box) { return box == null ? "none" : line(box.x0(),box.y0(),box.x1(),box.y1()); }
    static List<Segment> segments(List<Point> points, boolean closed) { List<Segment> edges = new ArrayList<>(); for (int i = 1; i < points.size(); i++) edges.add(new Segment(points.get(i - 1),points.get(i))); if (closed && !points.isEmpty()) edges.add(new Segment(points.getLast(),points.getFirst())); return edges; }
    static List<String> read(String name) throws IOException { return Files.readAllLines(Path.of("input",name),StandardCharsets.US_ASCII); }
    static void write(String name, List<String> lines) throws IOException { Files.writeString(Path.of("output",name),String.join("\n",lines) + (lines.isEmpty() ? "" : "\n"),StandardCharsets.US_ASCII); }
}
record Matrix(int a, int b, int c, int d, int e, int f) {}
record SavedState(Matrix matrix, Rect clip) {}
final class DrawingState {
    final Rect screen;
    Rect clip;
    Matrix matrix = new Matrix(1,0,0,1,0,0);
    List<SavedState> stack = new ArrayList<>();
    DrawingState(Rect screen) { this.screen = screen; clip = screen; }
    DrawingState copy() { DrawingState copy = new DrawingState(screen); copy.clip = clip; copy.matrix = matrix; copy.stack = new ArrayList<>(stack); return copy; }
    Point transform(int x, int y) { return new Point(matrix.a() * x + matrix.b() * y + matrix.e(),matrix.c() * x + matrix.d() * y + matrix.f()); }
    Rect deviceRect(int x0, int y0, int x1, int y1) { Point a = transform(x0,y0), b = transform(x1,y1); return new Rect(Math.min(a.x(),b.x()),Math.min(a.y(),b.y()),Math.max(a.x(),b.x()),Math.max(a.y(),b.y())); }
    Point radii(int rx, int ry) { return new Point(Math.abs(matrix.a()) * rx + Math.abs(matrix.b()) * ry,Math.abs(matrix.c()) * rx + Math.abs(matrix.d()) * ry); }
    void translate(int dx, int dy) { Matrix m = matrix; matrix = new Matrix(m.a(),m.b(),m.c(),m.d(),m.e() + m.a() * dx + m.b() * dy,m.f() + m.c() * dx + m.d() * dy); }
    void scale(int sx, int sy) { Matrix m = matrix; matrix = new Matrix(m.a() * sx,m.b() * sy,m.c() * sx,m.d() * sy,m.e(),m.f()); }
    void rotate(int turns) { for (int q = Math.floorMod(turns,4); q > 0; q--) { Matrix m = matrix; matrix = new Matrix(m.b(),-m.a(),m.d(),-m.c(),m.e(),m.f()); } }
}
record Shape(Point center, Set<Point> points) {}
final class Renderer {
    final Scene scene;
    final Styles styles;
    final Font font;
    final Rect screen;
    DrawingState state;
    Layer layer;
    final List<Layer> layers = new ArrayList<>();
    final List<Execution> executions = new ArrayList<>();
    Renderer(Scene scene, Styles styles, Font font) { this.scene = scene; this.styles = styles; this.font = font; screen = new Rect(0,0,scene.width - 1,scene.height - 1); state = new DrawingState(screen); }
    void run() { for (Block block : scene.layers) { layer = new Layer(scene.width,scene.height,block.opacity,block.mode); layers.add(layer); state = new DrawingState(screen); executeBody(block.body); } }
    void executeBody(List<Node> body) {
        for (Node node : body) if (node.repeat) { DrawingState saved = state.copy(); for (int k = 0; k < node.count; k++) { state = saved.copy(); state.translate(k * node.dx,k * node.dy); executeBody(node.body); } state = saved; } else execute(node);
    }
    String check(Node command) {
        String k = command.keyword; String[] a = command.arguments;
        if (!Raster.PEN_COMMANDS.contains(k) && !Raster.BRUSH_COMMANDS.contains(k) && !Raster.STATE_COMMANDS.contains(k) && !k.equals("ERASE")) return "unknown_command";
        if (!Raster.validForm(k,a)) return "bad_arguments";
        if (Raster.PEN_COMMANDS.contains(k) && !styles.pens.containsKey(a[0]) || Raster.BRUSH_COMMANDS.contains(k) && !styles.brushes.containsKey(a[0])) return "unknown_style";
        if (k.equals("USE")) { Block symbol = scene.symbols.get(a[0]); if (symbol == null || symbol.endLine >= command.line) return "unknown_symbol"; }
        if (k.equals("TEXT")) for (char c : a[4].toCharArray()) if (c != '_' && !font.glyphs.containsKey(c)) return "unknown_glyph";
        if (k.equals("RESTORE") && state.stack.isEmpty()) return "stack_empty";
        boolean valid = switch (k) {
            case "CIRCLE","FILLCIRCLE" -> Integer.parseInt(a[3]) >= 1;
            case "ELLIPSE","FILLELLIPSE" -> Integer.parseInt(a[3]) >= 1 && Integer.parseInt(a[4]) >= 1;
            case "POLYLINE" -> Integer.parseInt(a[1]) >= 2;
            case "POLYGON","FILLPOLYGON" -> Integer.parseInt(a[1]) >= 3;
            case "PATH","FILLPATH" -> Integer.parseInt(a[1]) >= 1 && Integer.parseInt(a[1]) <= 32;
            case "FLOOD" -> state.clip.contains(state.transform(Integer.parseInt(a[1]),Integer.parseInt(a[2])));
            case "TEXT" -> Set.of("left","center","right").contains(a[3]);
            case "SCALE" -> Integer.parseInt(a[0]) != 0 && Integer.parseInt(a[1]) != 0;
            case "CLIP" -> !state.deviceRect(Integer.parseInt(a[0]),Integer.parseInt(a[1]),Integer.parseInt(a[2]),Integer.parseInt(a[3])).intersect(state.clip).empty();
            default -> true;
        };
        return valid ? "" : "bad_value";
    }
    void applyState(Node command) {
        String[] a = command.arguments;
        switch (command.keyword) {
            case "TRANSLATE" -> state.translate(Integer.parseInt(a[0]),Integer.parseInt(a[1]));
            case "SCALE" -> state.scale(Integer.parseInt(a[0]),Integer.parseInt(a[1]));
            case "ROTATE" -> state.rotate(Integer.parseInt(a[0]));
            case "SAVE" -> state.stack.add(new SavedState(state.matrix,state.clip));
            case "RESTORE" -> { SavedState saved = state.stack.removeLast(); state.matrix = saved.matrix(); state.clip = saved.clip(); }
            case "CLIP" -> state.clip = state.deviceRect(Integer.parseInt(a[0]),Integer.parseInt(a[1]),Integer.parseInt(a[2]),Integer.parseInt(a[3])).intersect(state.clip);
            case "NOCLIP" -> state.clip = screen;
            case "USE" -> { DrawingState saved = state.copy(); state.translate(Integer.parseInt(a[1]),Integer.parseInt(a[2])); executeBody(scene.symbols.get(a[0]).body); state = saved; }
            default -> throw new IllegalArgumentException(command.keyword);
        }
    }
    Set<Point> expand(Iterable<Point> points, int width) { Set<Point> pixels = new HashSet<>(); for (Point p : points) for (Point pixel : Primitives.expandSquare(p,width)) if (state.clip.contains(pixel)) pixels.add(pixel); return pixels; }
    Set<Point> stroke(Pen pen, List<Segment> edges) {
        List<Point> points = new ArrayList<>(); for (Segment edge : edges) { Segment clipped = Clipping.clipSegment(edge.start(),edge.end(),state.clip); if (clipped != null) points.addAll(Primitives.bresenham(clipped.start(),clipped.end())); }
        if (pen.off() > 0) { List<Point> kept = new ArrayList<>(); for (int i = 0; i < points.size(); i++) if (i % (pen.on() + pen.off()) < pen.on()) kept.add(points.get(i)); points = kept; } return expand(points,pen.width());
    }
    List<Point> vertices(String[] a) { List<Point> points = new ArrayList<>(); for (int i = 2; i < a.length; i += 2) points.add(state.transform(Integer.parseInt(a[i]),Integer.parseInt(a[i + 1]))); return points; }
    Shape shape(String keyword, String[] a) {
        Point center = state.transform(Integer.parseInt(a[1]),Integer.parseInt(a[2])); boolean circle = keyword.equals("CIRCLE") || keyword.equals("FILLCIRCLE"); Point radii = state.radii(Integer.parseInt(a[3]),Integer.parseInt(a[circle ? 3 : 4])); return new Shape(center,circle && radii.x() == radii.y() ? Primitives.circle(radii.x()) : Primitives.ellipse(radii.x(),radii.y()));
    }
    List<Subpath> subpaths(String[] a) {
        List<Subpath> paths = new ArrayList<>(); Point current = new Point(0,0), start = new Point(0,0); int divisions = Integer.parseInt(a[1]);
        for (PathCommand command : Raster.parsePath(a,2)) {
            char kind = Character.toUpperCase(command.letter()); if (kind == 'Z') { paths.getLast().closed = true; current = start; continue; }
            boolean relative = Character.isLowerCase(command.letter()); int ox = relative ? current.x() : 0, oy = relative ? current.y() : 0; List<Point> user = new ArrayList<>();
            if (kind == 'H') user.add(new Point(command.values()[0] + ox,current.y())); else if (kind == 'V') user.add(new Point(current.x(),command.values()[0] + oy)); else for (int i = 0; i < command.values().length; i += 2) user.add(new Point(command.values()[i] + ox,command.values()[i + 1] + oy));
            List<Point> device = user.stream().map(p -> state.transform(p.x(),p.y())).toList();
            if (kind == 'M') { paths.add(new Subpath(device.getFirst())); start = user.getFirst(); } else if (kind == 'L' || kind == 'H' || kind == 'V') paths.getLast().points.add(device.getFirst()); else { List<Point> controls = new ArrayList<>(); controls.add(paths.getLast().points.getLast()); controls.addAll(device); paths.getLast().points.addAll(Primitives.bezier(controls,divisions).subList(1,divisions + 1)); } current = user.getLast();
        }
        return paths;
    }
    Set<Point> textCoverage(String[] a) {
        int x = Integer.parseInt(a[1]), y = Integer.parseInt(a[2]), advance = font.width + 1, extent = a[4].length() * advance - 1, left = a[3].equals("left") ? x : a[3].equals("center") ? x - extent / 2 : x - extent + 1; Set<Point> pixels = new HashSet<>();
        for (int i = 0; i < a[4].length(); i++) if (a[4].charAt(i) != '_') for (Point dot : font.glyphs.get(a[4].charAt(i))) { Rect rect = state.deviceRect(left + i * advance + dot.x(),y + dot.y(),left + i * advance + dot.x() + 1,y + dot.y() + 1); pixels.addAll(Raster.rectPixels(new Rect(rect.x0(),rect.y0(),rect.x1() - 1,rect.y1() - 1).intersect(state.clip))); } return pixels;
    }
    Set<Point> coverage(Node command) {
        String k = command.keyword; String[] a = command.arguments;
        if (k.equals("ERASE")) { Set<Point> pixels = new HashSet<>(); for (Point p : Raster.rectPixels(state.deviceRect(Integer.parseInt(a[0]),Integer.parseInt(a[1]),Integer.parseInt(a[2]),Integer.parseInt(a[3])).intersect(state.clip))) if (layer.erase(p)) pixels.add(p); return pixels; }
        if (Set.of("CIRCLE","ELLIPSE","FILLCIRCLE","FILLELLIPSE").contains(k)) { Shape shape = shape(k,a); if (Raster.BRUSH_COMMANDS.contains(k)) return Fill.shape(shape.center(),shape.points(),state.clip); return expand(shape.points().stream().map(p -> new Point(shape.center().x() + p.x(),shape.center().y() + p.y())).toList(),styles.pens.get(a[0]).width()); }
        if (k.equals("FILLRECT")) return Raster.rectPixels(state.deviceRect(Integer.parseInt(a[1]),Integer.parseInt(a[2]),Integer.parseInt(a[3]),Integer.parseInt(a[4])).intersect(state.clip));
        if (k.equals("FLOOD")) return Fill.flood(layer,state.transform(Integer.parseInt(a[1]),Integer.parseInt(a[2])),state.clip); if (k.equals("TEXT")) return textCoverage(a);
        if (k.equals("FILLPOLYGON")) return Fill.polygons(List.of(Clipping.clipPolygon(vertices(a),state.clip)),styles.brushes.get(a[0]).rule(),state.clip);
        if (k.equals("FILLPATH")) return Fill.polygons(subpaths(a).stream().map(p -> Clipping.clipPolygon(p.points,state.clip)).toList(),styles.brushes.get(a[0]).rule(),state.clip);
        List<Segment> edges;
        if (k.equals("LINE")) edges = List.of(new Segment(state.transform(Integer.parseInt(a[1]),Integer.parseInt(a[2])),state.transform(Integer.parseInt(a[3]),Integer.parseInt(a[4]))));
        else if (k.equals("RECT")) { Rect r = state.deviceRect(Integer.parseInt(a[1]),Integer.parseInt(a[2]),Integer.parseInt(a[3]),Integer.parseInt(a[4])); edges = Raster.segments(List.of(new Point(r.x0(),r.y0()),new Point(r.x1(),r.y0()),new Point(r.x1(),r.y1()),new Point(r.x0(),r.y1())),true); }
        else if (k.equals("POLYGON") || k.equals("POLYLINE")) edges = Raster.segments(vertices(a),k.equals("POLYGON")); else { edges = new ArrayList<>(); for (Subpath path : subpaths(a)) edges.addAll(Raster.segments(path.points,path.closed)); } return stroke(styles.pens.get(a[0]),edges);
    }
    void execute(Node command) {
        Execution execution = new Execution(executions.size() + 1,layers.size(),command); executions.add(execution); String error = check(command);
        if (!error.isEmpty()) { execution.kind = "error"; execution.error = error; return; }
        if (Raster.STATE_COMMANDS.contains(command.keyword)) { execution.kind = "state"; applyState(command); return; }
        Set<Point> pixels = coverage(command); execution.kind = "drawing"; execution.pixels = pixels.size(); execution.box = Raster.bounds(pixels); if (command.keyword.equals("ERASE")) return;
        if (Raster.PEN_COMMANDS.contains(command.keyword)) { Color color = styles.colors.get(styles.pens.get(command.arguments[0]).color()); for (Point p : pixels) layer.paint(p,color,command.line); }
        else {
            Brush brush = styles.brushes.get(command.arguments[0]); Color first = styles.colors.get(brush.colors().getFirst());
            for (Point p : pixels) {
                Color color = first;
                if (!brush.axis().isEmpty()) { Rect box = execution.box; Color second = styles.colors.get(brush.colors().get(1)); int offset = brush.axis().equals("x") ? p.x() - box.x0() : p.y() - box.y0(), length = brush.axis().equals("x") ? box.x1() - box.x0() : box.y1() - box.y0(); if (length > 0) { int[] values = new int[4]; for (int c = 0; c < 4; c++) values[c] = first.component(c) + Canvas.round((second.component(c) - first.component(c)) * offset,length); color = new Color(values[0],values[1],values[2],values[3]); } }
                layer.paint(p,color,command.line);
            }
        }
    }
}
final class KeywordTally {
    int executed, errors, pixels;
}
public class Main {
    static Styles readStyles() throws IOException {
        Styles styles = new Styles();
        for (String text : Raster.read("styles.txt")) {
            if (text.isEmpty() || text.charAt(0) == '#') continue; String[] p = Raster.words(text);
            switch (p[0]) {
                case "color" -> styles.colors.put(p[1],new Color(Integer.parseInt(p[2]),Integer.parseInt(p[3]),Integer.parseInt(p[4]),Integer.parseInt(p[5])));
                case "pen" -> styles.pens.put(p[1],new Pen(Integer.parseInt(p[2]),p[3],Integer.parseInt(p[4]),Integer.parseInt(p[5])));
                case "brush" -> styles.brushes.put(p[1],new Brush(List.of(p[2]),"",p[3]));
                case "gradient" -> styles.brushes.put(p[1],new Brush(List.of(p[2],p[3]),p[4],p[5]));
                default -> throw new IllegalArgumentException(p[0]);
            }
        }
        return styles;
    }
    static Font readFont() throws IOException {
        List<String> input = Raster.read("font.txt"); String[] header = Raster.words(input.getFirst()); Font font = new Font(Integer.parseInt(header[1]),Integer.parseInt(header[2]));
        for (int i = 1; i < input.size(); i += font.height + 1) { List<Point> dots = new ArrayList<>(); for (int y = 0; y < font.height; y++) for (int x = 0; x < font.width; x++) if (input.get(i + y + 1).charAt(x) == '#') dots.add(new Point(x,y)); font.glyphs.put(Raster.words(input.get(i))[1].charAt(0),dots); } return font;
    }
    static Scene readScene() throws IOException {
        Scene scene = new Scene(); List<String> input = Raster.read("scene.txt"); Block block = null; ArrayDeque<List<Node>> bodies = new ArrayDeque<>();
        for (int i = 0; i < input.size(); i++) {
            String[] p = Raster.words(input.get(i)); if (p.length == 0 || p[0].charAt(0) == '#') continue;
            switch (p[0]) {
                case "CANVAS" -> { scene.width = Integer.parseInt(p[1]); scene.height = Integer.parseInt(p[2]); scene.background = p[3]; }
                case "LAYER" -> { block = new Block(p[1],Integer.parseInt(p[2]),p[3]); scene.layers.add(block); bodies.clear(); bodies.addLast(block.body); }
                case "SYMBOL" -> { block = new Block(p[1],0,""); scene.symbols.put(block.name,block); bodies.clear(); bodies.addLast(block.body); }
                case "END" -> { block.endLine = i + 1; bodies.clear(); }
                case "REPEAT" -> { Node node = new Node(); node.repeat = true; node.line = i + 1; node.count = Integer.parseInt(p[1]); node.dx = Integer.parseInt(p[2]); node.dy = Integer.parseInt(p[3]); bodies.getLast().add(node); bodies.addLast(node.body); }
                case "ENDREPEAT" -> bodies.removeLast();
                default -> { Node node = new Node(); node.line = i + 1; node.keyword = p[0]; node.arguments = Arrays.copyOfRange(p,1,p.length); bodies.getLast().add(node); }
            }
        }
        return scene;
    }
    static List<Probe> readProbes() throws IOException {
        List<String> input = Raster.read("probes.txt"); List<Probe> probes = new ArrayList<>(); for (int i = 1; i <= Integer.parseInt(input.getFirst()); i++) { String[] p = Raster.words(input.get(i)); probes.add(new Probe(p[0],Arrays.stream(p).skip(1).mapToInt(Integer::parseInt).toArray())); } return probes;
    }
    static List<String> commandLines(List<Execution> executions) {
        List<String> lines = new ArrayList<>(); for (Execution execution : executions) { String head = Raster.line("cmd",execution.sequence,"line",execution.command.line,execution.command.keyword); lines.add(head + (execution.kind.equals("error") ? " error " + execution.error : execution.kind.equals("drawing") ? " pixels " + execution.pixels + " box " + Raster.boxText(execution.box) : " ok")); } return lines;
    }
    static <T extends Comparable<? super T>> List<Map.Entry<T, Integer>> ranked(Map<T, Integer> counts) { return counts.entrySet().stream().sorted(Map.Entry.<T, Integer>comparingByValue().reversed().thenComparing(Map.Entry.comparingByKey())).toList(); }
    static List<String> layerLines(Scene scene, List<Layer> layers, List<Execution> executions) {
        int[] visible = new int[layers.size()];
        for (int y = 0; y < scene.height; y++) for (int x = 0; x < scene.width; x++) { boolean covered = false; for (int i = layers.size() - 1; i >= 0; i--) { int alpha = layers.get(i).alphaAt(new Point(x,y)); if (alpha > 0 && !covered) visible[i]++; if (alpha == 255) covered = true; } }
        List<String> lines = new ArrayList<>(List.of("layers " + layers.size()));
        for (int i = 0; i < layers.size(); i++) {
            Block block = scene.layers.get(i); Layer layer = layers.get(i); int commands = 0, errors = 0; for (Execution execution : executions) if (execution.layer == i + 1) { commands++; if (execution.kind.equals("error")) errors++; }
            Set<Point> painted = new HashSet<>(); Map<Color, Integer> counts = new HashMap<>();
            for (int y = 0; y < scene.height; y++) for (int x = 0; x < scene.width; x++) { Point point = new Point(x,y); Color color = layer.colorAt(point); if (color != null) { painted.add(point); counts.merge(color,1,Integer::sum); } }
            lines.add(Raster.line("layer",i + 1,block.name,"opacity",block.opacity,"mode",block.mode,"commands",commands,"errors",errors,"pixels",painted.size(),"box",Raster.boxText(Raster.bounds(painted)),"visible",visible[i],"colors",counts.size()));
            for (Map.Entry<Color, Integer> color : ranked(counts).stream().limit(5).toList()) lines.add(Raster.line("color",color.getKey(),"pixels",color.getValue()));
        }
        return lines;
    }
    static List<String> summaryLines(Scene scene, Styles styles, List<Execution> executions, Rgb[][] image) {
        Map<String, Integer> kinds = new HashMap<>(), errors = new HashMap<>(), uses = new HashMap<>(); for (String name : scene.symbols.keySet()) uses.put(name,0); Map<String, KeywordTally> keywords = new HashMap<>(); Set<String> usedPens = new HashSet<>(), usedBrushes = new HashSet<>(), usedColors = new HashSet<>(List.of(scene.background)); int painted = 0, erased = 0;
        for (Execution execution : executions) {
            Node command = execution.command; kinds.merge(execution.kind,1,Integer::sum); KeywordTally tally = keywords.computeIfAbsent(command.keyword,_ -> new KeywordTally()); tally.executed++;
            if (execution.kind.equals("error")) { errors.merge(execution.error,1,Integer::sum); tally.errors++; }
            else if (execution.kind.equals("drawing")) { tally.pixels += execution.pixels; if (command.keyword.equals("ERASE")) erased += execution.pixels; else painted += execution.pixels; if (Raster.PEN_COMMANDS.contains(command.keyword)) usedPens.add(command.arguments[0]); else if (Raster.BRUSH_COMMANDS.contains(command.keyword)) usedBrushes.add(command.arguments[0]); }
            else if (command.keyword.equals("USE")) uses.merge(command.arguments[0],1,Integer::sum);
        }
        for (String name : usedPens) usedColors.add(styles.pens.get(name).color()); for (String name : usedBrushes) usedColors.addAll(styles.brushes.get(name).colors());
        Color background = styles.colors.get(scene.background); List<String> lines = new ArrayList<>(List.of(Raster.line("canvas",scene.width,scene.height),Raster.line("background",background.r(),background.g(),background.b()),"layers " + scene.layers.size(),"symbols " + scene.symbols.size(),"commands " + executions.size(),"drawing " + kinds.getOrDefault("drawing",0),"state " + kinds.getOrDefault("state",0),"errors " + kinds.getOrDefault("error",0)));
        for (String error : Raster.ERROR_NAMES) lines.add(Raster.line("error",error,errors.getOrDefault(error,0))); lines.add("painted " + painted); lines.add("erased " + erased); Map<Rgb, Integer> counts = new HashMap<>();
        for (Rgb[] row : image) for (Rgb color : row) counts.merge(color,1,Integer::sum); lines.add("colors " + counts.size()); int rank = 0; for (Map.Entry<Rgb, Integer> color : ranked(counts).stream().limit(8).toList()) lines.add(Raster.line("top",++rank,color.getKey(),"pixels",color.getValue()));
        for (String name : uses.keySet().stream().sorted().toList()) lines.add(Raster.line("symbol",name,"uses",uses.get(name))); for (String keyword : keywords.keySet().stream().sorted().toList()) { KeywordTally tally = keywords.get(keyword); lines.add(Raster.line("keyword",keyword,"executed",tally.executed,"errors",tally.errors,"pixels",tally.pixels)); }
        List<String> unused = new ArrayList<>(); for (String name : styles.colors.keySet().stream().sorted().toList()) if (!usedColors.contains(name)) unused.add("unused color " + name); for (String name : styles.pens.keySet().stream().sorted().toList()) if (!usedPens.contains(name)) unused.add("unused pen " + name); for (String name : styles.brushes.keySet().stream().sorted().toList()) if (!usedBrushes.contains(name)) unused.add("unused brush " + name); for (String name : uses.keySet().stream().sorted().toList()) if (uses.get(name) == 0) unused.add("unused symbol " + name); lines.add("unused " + unused.size()); lines.addAll(unused); return lines;
    }
    static List<String> probeLines(List<Probe> probes, Rgb[][] image, List<Layer> layers) {
        List<String> lines = new ArrayList<>();
        for (int i = 0; i < probes.size(); i++) {
            Probe probe = probes.get(i); int[] v = probe.values();
            if (probe.kind().equals("point")) { Point point = new Point(v[0],v[1]); List<String> stack = new ArrayList<>(); for (int j = 0; j < layers.size(); j++) if (layers.get(j).alphaAt(point) > 0) stack.add((j + 1) + ":" + layers.get(j).lineAt(point)); lines.add(Raster.line("point",i + 1,point.x(),point.y(),"rgb",image[point.y()][point.x()],"layers",stack.size(),"stack",stack.isEmpty() ? "none" : String.join(" ",stack))); }
            else {
                int[] totals = new int[3], cover = new int[layers.size()]; Set<Rgb> colors = new HashSet<>(); int count = (v[2] - v[0] + 1) * (v[3] - v[1] + 1);
                for (int y = v[1]; y <= v[3]; y++) for (int x = v[0]; x <= v[2]; x++) { Rgb color = image[y][x]; colors.add(color); for (int c = 0; c < 3; c++) totals[c] += color.component(c); for (int j = 0; j < layers.size(); j++) if (layers.get(j).alphaAt(new Point(x,y)) > 0) cover[j]++; }
                String covers = Arrays.stream(cover).mapToObj(Integer::toString).collect(Collectors.joining(" ")); lines.add(Raster.line("area",i + 1,v[0],v[1],v[2],v[3],"pixels",count,"mean",totals[0] / count,totals[1] / count,totals[2] / count,"colors",colors.size(),"cover",covers));
            }
        }
        return lines;
    }
    public static void main(String[] args) throws IOException {
        Styles styles = readStyles(); Font font = readFont(); Scene scene = readScene(); List<Probe> probes = readProbes(); Renderer renderer = new Renderer(scene,styles,font); renderer.run(); Rgb[][] image = Canvas.composite(renderer.layers,styles.colors.get(scene.background),scene.width,scene.height);
        Files.createDirectories(Path.of("output")); PpmWriter.writePpm("output/image.ppm",image); PpmWriter.writePreview("output/preview.txt",image); Raster.write("commands.txt",commandLines(renderer.executions)); Raster.write("layers.txt",layerLines(scene,renderer.layers,renderer.executions)); Raster.write("summary.txt",summaryLines(scene,styles,renderer.executions,image)); Raster.write("probes.txt",probeLines(probes,image,renderer.layers));
    }
}
