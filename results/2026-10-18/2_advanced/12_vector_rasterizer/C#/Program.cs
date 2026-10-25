global using System;
global using System.Collections.Generic;
global using System.IO;
global using System.Linq;
using System.Globalization;
using System.Text;

sealed record Pen(int Width, string Color, int On, int Off);
sealed record Brush(string[] Colors, string Axis, string Rule);
sealed class Styles
{
    public Dictionary<string, Color> Colors = [];
    public Dictionary<string, Pen> Pens = [];
    public Dictionary<string, Brush> Brushes = [];
}
sealed class Font(int width, int height)
{
    public int Width = width, Height = height;
    public Dictionary<char, List<Point>> Glyphs = [];
}
sealed class Node
{
    public bool Repeat;
    public int Line, Count, Dx, Dy;
    public string Keyword = "";
    public string[] Arguments = [];
    public List<Node> Body = [];
}
sealed class Block(string name, int opacity = 0, string mode = "")
{
    public string Name = name, Mode = mode;
    public int Opacity = opacity, EndLine;
    public List<Node> Body = [];
}
sealed class Scene
{
    public int Width, Height;
    public string Background = "";
    public List<Block> Layers = [];
    public Dictionary<string, Block> Symbols = [];
}
sealed record Probe(string Kind, int[] Values);
sealed record PathCommand(char Letter, int[] Values);
sealed class Subpath(Point start)
{
    public List<Point> Points = [start];
    public bool Closed;
}
sealed class Execution(int sequence, int layer, Node command)
{
    public int Sequence = sequence, Layer = layer, Pixels;
    public Node Command = command;
    public string Kind = "", Error = "";
    public Rect? Box;
}
static class Raster
{
    public static readonly HashSet<string> PenCommands = ["LINE","RECT","CIRCLE","ELLIPSE","POLYLINE","POLYGON","PATH"];
    public static readonly HashSet<string> BrushCommands = ["FILLRECT","FILLCIRCLE","FILLELLIPSE","FILLPOLYGON","FILLPATH","FLOOD","TEXT"];
    public static readonly HashSet<string> StateCommands = ["TRANSLATE","SCALE","ROTATE","SAVE","RESTORE","CLIP","NOCLIP","USE"];
    public static readonly string[] ErrorNames = ["unknown_command","bad_arguments","unknown_style","unknown_symbol","unknown_glyph","bad_value","stack_empty"];
    static readonly Dictionary<string, (int Count, int First)> Forms = new()
    {
        ["LINE"] = (5,1),["RECT"] = (5,1),["FILLRECT"] = (5,1),["CIRCLE"] = (4,1),["FILLCIRCLE"] = (4,1),["ELLIPSE"] = (5,1),["FILLELLIPSE"] = (5,1),["FLOOD"] = (3,1),["ERASE"] = (4,0),["TRANSLATE"] = (2,0),["SCALE"] = (2,0),["ROTATE"] = (1,0),["SAVE"] = (0,0),["RESTORE"] = (0,0),["NOCLIP"] = (0,0),["CLIP"] = (4,0),["USE"] = (3,1)
    };
    static readonly Dictionary<char, int> PathArities = new() { ['M'] = 2,['L'] = 2,['H'] = 1,['V'] = 1,['Q'] = 4,['C'] = 6,['Z'] = 0 };
    public static string[] Words(string text) => text.Split(' ',StringSplitOptions.RemoveEmptyEntries);
    public static bool IntegerWord(string text) { int first = text.Length > 0 && text[0] == '-' ? 1 : 0; return first < text.Length && text.Skip(first).All(c => c >= '0' && c <= '9'); }
    public static List<PathCommand>? ParsePath(string[] words, int first)
    {
        List<PathCommand> result = [];
        for (int i = first; i < words.Length;)
        {
            if (words[i].Length != 1) return null; char letter = words[i][0], upper = char.ToUpperInvariant(letter); if (!PathArities.TryGetValue(upper,out int arity) || letter != upper && letter != char.ToLowerInvariant(upper)) return null;
            if ((result.Count == 0 || char.ToUpperInvariant(result[^1].Letter) == 'Z') && upper != 'M') return null;
            if (i + arity >= words.Length || !words.Skip(i + 1).Take(arity).All(IntegerWord)) return null; result.Add(new(letter,words.Skip(i + 1).Take(arity).Select(int.Parse).ToArray())); i += arity + 1;
        }
        return result.Count == 0 ? null : result;
    }
    public static bool ValidForm(string keyword, string[] a)
    {
        if (Forms.TryGetValue(keyword,out var form)) return a.Length == form.Count && a.Skip(form.First).All(IntegerWord);
        if (keyword == "TEXT") return a.Length == 5 && IntegerWord(a[1]) && IntegerWord(a[2]);
        if (keyword is "POLYLINE" or "POLYGON" or "FILLPOLYGON") return a.Length >= 2 && a.Skip(1).All(IntegerWord) && a.Length == 2 + 2 * int.Parse(a[1]);
        return a.Length >= 2 && IntegerWord(a[1]) && ParsePath(a,2) is not null;
    }
    public static IEnumerable<Point> RectPixels(Rect rect) { for (int y = rect.Y0; y <= rect.Y1; y++) for (int x = rect.X0; x <= rect.X1; x++) yield return new(x,y); }
    public static Rect? Bounds(IEnumerable<Point> values)
    {
        Point[] pixels = values.ToArray(); if (pixels.Length == 0) return null; return new(pixels.Min(p => p.X),pixels.Min(p => p.Y),pixels.Max(p => p.X),pixels.Max(p => p.Y));
    }
    public static string BoxText(Rect? box) => box is Rect b ? $"{b.X0} {b.Y0} {b.X1} {b.Y1}" : "none";
    public static List<Segment> Segments(List<Point> points, bool closed)
    {
        List<Segment> edges = []; for (int i = 1; i < points.Count; i++) edges.Add(new(points[i - 1],points[i])); if (closed && points.Count > 0) edges.Add(new(points[^1],points[0])); return edges;
    }
    public static string[] Read(string name) => File.ReadAllLines(Path.Combine("input",name));
    public static void Write(string name, List<string> lines) => File.WriteAllText(Path.Combine("output",name),string.Concat(lines.Select(line => line + "\n")),new UTF8Encoding(false));
}
readonly record struct Matrix(int A, int B, int C, int D, int E, int F);
sealed class DrawingState(Rect screen)
{
    public Rect Screen = screen, Clip = screen;
    public Matrix Matrix = new(1,0,0,1,0,0);
    public List<(Matrix Matrix, Rect Clip)> Stack = [];
    public DrawingState Copy() => new(Screen) { Matrix = Matrix,Clip = Clip,Stack = [..Stack] };
    public Point Transform(int x, int y) => new(Matrix.A * x + Matrix.B * y + Matrix.E,Matrix.C * x + Matrix.D * y + Matrix.F);
    public Rect DeviceRect(int x0, int y0, int x1, int y1) { Point a = Transform(x0,y0), b = Transform(x1,y1); return new(Math.Min(a.X,b.X),Math.Min(a.Y,b.Y),Math.Max(a.X,b.X),Math.Max(a.Y,b.Y)); }
    public Point Radii(int rx, int ry) => new(Math.Abs(Matrix.A) * rx + Math.Abs(Matrix.B) * ry,Math.Abs(Matrix.C) * rx + Math.Abs(Matrix.D) * ry);
    public void Translate(int dx, int dy) { Matrix m = Matrix; Matrix = m with { E = m.E + m.A * dx + m.B * dy,F = m.F + m.C * dx + m.D * dy }; }
    public void Scale(int sx, int sy) { Matrix m = Matrix; Matrix = m with { A = m.A * sx,C = m.C * sx,B = m.B * sy,D = m.D * sy }; }
    public void Rotate(int turns) { for (int q = (turns % 4 + 4) % 4; q > 0; q--) { Matrix m = Matrix; Matrix = new(m.B,-m.A,m.D,-m.C,m.E,m.F); } }
}
sealed class Renderer
{
    readonly Scene scene;
    readonly Styles styles;
    readonly Font font;
    readonly Rect screen;
    DrawingState state;
    Layer layer = null!;
    public List<Layer> Layers = [];
    public List<Execution> Executions = [];
    public Renderer(Scene scene, Styles styles, Font font) { this.scene = scene; this.styles = styles; this.font = font; screen = new(0,0,scene.Width - 1,scene.Height - 1); state = new(screen); }
    public void Run() { foreach (Block block in scene.Layers) { layer = new(scene.Width,scene.Height,block.Opacity,block.Mode); Layers.Add(layer); state = new(screen); ExecuteBody(block.Body); } }
    void ExecuteBody(List<Node> body)
    {
        foreach (Node node in body) if (node.Repeat) { DrawingState saved = state.Copy(); for (int k = 0; k < node.Count; k++) { state = saved.Copy(); state.Translate(k * node.Dx,k * node.Dy); ExecuteBody(node.Body); } state = saved; } else Execute(node);
    }
    string Check(Node command)
    {
        string k = command.Keyword; string[] a = command.Arguments;
        if (!Raster.PenCommands.Contains(k) && !Raster.BrushCommands.Contains(k) && !Raster.StateCommands.Contains(k) && k != "ERASE") return "unknown_command";
        if (!Raster.ValidForm(k,a)) return "bad_arguments";
        if (Raster.PenCommands.Contains(k) && !styles.Pens.ContainsKey(a[0]) || Raster.BrushCommands.Contains(k) && !styles.Brushes.ContainsKey(a[0])) return "unknown_style";
        if (k == "USE" && (!scene.Symbols.TryGetValue(a[0],out Block? symbol) || symbol.EndLine >= command.Line)) return "unknown_symbol";
        if (k == "TEXT" && a[4].Any(c => c != '_' && !font.Glyphs.ContainsKey(c))) return "unknown_glyph";
        if (k == "RESTORE" && state.Stack.Count == 0) return "stack_empty";
        int N(int i) => int.Parse(a[i]);
        bool valid = k switch
        {
            "CIRCLE" or "FILLCIRCLE" => N(3) >= 1,
            "ELLIPSE" or "FILLELLIPSE" => N(3) >= 1 && N(4) >= 1,
            "POLYLINE" => N(1) >= 2,
            "POLYGON" or "FILLPOLYGON" => N(1) >= 3,
            "PATH" or "FILLPATH" => N(1) >= 1 && N(1) <= 32,
            "FLOOD" => state.Clip.Contains(state.Transform(N(1),N(2))),
            "TEXT" => a[3] is "left" or "center" or "right",
            "SCALE" => N(0) != 0 && N(1) != 0,
            "CLIP" => !state.DeviceRect(N(0),N(1),N(2),N(3)).Intersect(state.Clip).Empty,
            _ => true
        };
        return valid ? "" : "bad_value";
    }
    void ApplyState(Node command)
    {
        string[] a = command.Arguments; int N(int i) => int.Parse(a[i]);
        switch (command.Keyword)
        {
            case "TRANSLATE": state.Translate(N(0),N(1)); break;
            case "SCALE": state.Scale(N(0),N(1)); break;
            case "ROTATE": state.Rotate(N(0)); break;
            case "SAVE": state.Stack.Add((state.Matrix,state.Clip)); break;
            case "RESTORE": { var saved = state.Stack[^1]; state.Stack.RemoveAt(state.Stack.Count - 1); state.Matrix = saved.Matrix; state.Clip = saved.Clip; break; }
            case "CLIP": state.Clip = state.DeviceRect(N(0),N(1),N(2),N(3)).Intersect(state.Clip); break;
            case "NOCLIP": state.Clip = screen; break;
            case "USE": { DrawingState saved = state.Copy(); state.Translate(N(1),N(2)); ExecuteBody(scene.Symbols[a[0]].Body); state = saved; break; }
        }
    }
    HashSet<Point> Expand(IEnumerable<Point> points, int width) => points.SelectMany(p => Primitives.ExpandSquare(p,width)).Where(state.Clip.Contains).ToHashSet();
    HashSet<Point> Stroke(Pen pen, List<Segment> edges)
    {
        List<Point> points = []; foreach (Segment edge in edges) if (Clipping.ClipSegment(edge.Start,edge.End,state.Clip) is Segment clipped) points.AddRange(Primitives.Bresenham(clipped.Start,clipped.End));
        if (pen.Off > 0) points = points.Where((_,i) => i % (pen.On + pen.Off) < pen.On).ToList(); return Expand(points,pen.Width);
    }
    List<Point> Vertices(string[] a) { List<Point> points = []; for (int i = 2; i < a.Length; i += 2) points.Add(state.Transform(int.Parse(a[i]),int.Parse(a[i + 1]))); return points; }
    (Point Center, HashSet<Point> Points) Shape(string keyword, string[] a)
    {
        Point center = state.Transform(int.Parse(a[1]),int.Parse(a[2])); bool circle = keyword is "CIRCLE" or "FILLCIRCLE"; Point radii = state.Radii(int.Parse(a[3]),int.Parse(a[circle ? 3 : 4])); return (center,circle && radii.X == radii.Y ? Primitives.Circle(radii.X) : Primitives.Ellipse(radii.X,radii.Y));
    }
    List<Subpath> Subpaths(string[] a)
    {
        List<Subpath> paths = []; Point current = new(0,0), start = new(0,0); int divisions = int.Parse(a[1]);
        foreach (PathCommand command in Raster.ParsePath(a,2)!)
        {
            char kind = char.ToUpperInvariant(command.Letter); if (kind == 'Z') { paths[^1].Closed = true; current = start; continue; }
            bool relative = char.IsLower(command.Letter); int ox = relative ? current.X : 0, oy = relative ? current.Y : 0; List<Point> user = [];
            if (kind == 'H') user.Add(new(command.Values[0] + ox,current.Y)); else if (kind == 'V') user.Add(new(current.X,command.Values[0] + oy)); else for (int i = 0; i < command.Values.Length; i += 2) user.Add(new(command.Values[i] + ox,command.Values[i + 1] + oy));
            List<Point> device = user.Select(p => state.Transform(p.X,p.Y)).ToList();
            if (kind == 'M') { paths.Add(new(device[0])); start = user[0]; } else if (kind is 'L' or 'H' or 'V') paths[^1].Points.Add(device[0]); else { List<Point> controls = [paths[^1].Points[^1],..device]; paths[^1].Points.AddRange(Primitives.Bezier(controls,divisions).Skip(1)); } current = user[^1];
        }
        return paths;
    }
    HashSet<Point> TextCoverage(string[] a)
    {
        int x = int.Parse(a[1]), y = int.Parse(a[2]), advance = font.Width + 1, extent = a[4].Length * advance - 1; int left = a[3] == "left" ? x : a[3] == "center" ? x - extent / 2 : x - extent + 1; HashSet<Point> pixels = [];
        for (int i = 0; i < a[4].Length; i++) if (a[4][i] != '_') foreach (Point dot in font.Glyphs[a[4][i]]) { Rect rect = state.DeviceRect(left + i * advance + dot.X,y + dot.Y,left + i * advance + dot.X + 1,y + dot.Y + 1); rect = rect with { X1 = rect.X1 - 1,Y1 = rect.Y1 - 1 }; pixels.UnionWith(Raster.RectPixels(rect.Intersect(state.Clip))); } return pixels;
    }
    HashSet<Point> Coverage(Node command)
    {
        string k = command.Keyword; string[] a = command.Arguments; int N(int i) => int.Parse(a[i]);
        if (k == "ERASE") return Raster.RectPixels(state.DeviceRect(N(0),N(1),N(2),N(3)).Intersect(state.Clip)).Where(layer.Erase).ToHashSet();
        if (k is "CIRCLE" or "ELLIPSE" or "FILLCIRCLE" or "FILLELLIPSE") { var shape = Shape(k,a); return Raster.BrushCommands.Contains(k) ? Fill.Shape(shape.Center,shape.Points,state.Clip) : Expand(shape.Points.Select(p => new Point(shape.Center.X + p.X,shape.Center.Y + p.Y)),styles.Pens[a[0]].Width); }
        if (k == "FILLRECT") return Raster.RectPixels(state.DeviceRect(N(1),N(2),N(3),N(4)).Intersect(state.Clip)).ToHashSet();
        if (k == "FLOOD") return Fill.Flood(layer,state.Transform(N(1),N(2)),state.Clip); if (k == "TEXT") return TextCoverage(a);
        if (k == "FILLPOLYGON") return Fill.Polygons([Clipping.ClipPolygon(Vertices(a),state.Clip)],styles.Brushes[a[0]].Rule,state.Clip);
        if (k == "FILLPATH") return Fill.Polygons(Subpaths(a).Select(p => Clipping.ClipPolygon(p.Points,state.Clip)).ToList(),styles.Brushes[a[0]].Rule,state.Clip);
        List<Segment> edges;
        if (k == "LINE") edges = [new(state.Transform(N(1),N(2)),state.Transform(N(3),N(4)))];
        else if (k == "RECT") { Rect r = state.DeviceRect(N(1),N(2),N(3),N(4)); edges = Raster.Segments([new(r.X0,r.Y0),new(r.X1,r.Y0),new(r.X1,r.Y1),new(r.X0,r.Y1)],true); }
        else if (k is "POLYGON" or "POLYLINE") edges = Raster.Segments(Vertices(a),k == "POLYGON"); else edges = Subpaths(a).SelectMany(p => Raster.Segments(p.Points,p.Closed)).ToList(); return Stroke(styles.Pens[a[0]],edges);
    }
    void Execute(Node command)
    {
        Execution execution = new(Executions.Count + 1,Layers.Count,command); Executions.Add(execution); string error = Check(command);
        if (error.Length > 0) { execution.Kind = "error"; execution.Error = error; return; }
        if (Raster.StateCommands.Contains(command.Keyword)) { execution.Kind = "state"; ApplyState(command); return; }
        HashSet<Point> pixels = Coverage(command); execution.Kind = "drawing"; execution.Pixels = pixels.Count; execution.Box = Raster.Bounds(pixels); if (command.Keyword == "ERASE") return;
        if (Raster.PenCommands.Contains(command.Keyword)) { Color color = styles.Colors[styles.Pens[command.Arguments[0]].Color]; foreach (Point p in pixels) layer.Paint(p,color,command.Line); }
        else
        {
            Brush brush = styles.Brushes[command.Arguments[0]]; Color first = styles.Colors[brush.Colors[0]];
            foreach (Point p in pixels)
            {
                Color color = first;
                if (brush.Axis.Length > 0) { Rect box = execution.Box!.Value; Color second = styles.Colors[brush.Colors[1]]; int offset = brush.Axis == "x" ? p.X - box.X0 : p.Y - box.Y0, length = brush.Axis == "x" ? box.X1 - box.X0 : box.Y1 - box.Y0; if (length > 0) color = new(first.R + CanvasMath.Round((second.R - first.R) * offset,length),first.G + CanvasMath.Round((second.G - first.G) * offset,length),first.B + CanvasMath.Round((second.B - first.B) * offset,length),first.A + CanvasMath.Round((second.A - first.A) * offset,length)); }
                layer.Paint(p,color,command.Line);
            }
        }
    }
}
sealed class KeywordTally
{
    public int Executed, Errors, Pixels;
}
static class Program
{
    static Styles ReadStyles()
    {
        Styles styles = new();
        foreach (string text in Raster.Read("styles.txt"))
        {
            if (text.Length == 0 || text[0] == '#') continue; string[] p = Raster.Words(text);
            switch (p[0])
            {
                case "color": styles.Colors.Add(p[1],new(int.Parse(p[2]),int.Parse(p[3]),int.Parse(p[4]),int.Parse(p[5]))); break;
                case "pen": styles.Pens.Add(p[1],new(int.Parse(p[2]),p[3],int.Parse(p[4]),int.Parse(p[5]))); break;
                case "brush": styles.Brushes.Add(p[1],new([p[2]],"",p[3])); break;
                case "gradient": styles.Brushes.Add(p[1],new([p[2],p[3]],p[4],p[5])); break;
            }
        }
        return styles;
    }
    static Font ReadFont()
    {
        string[] input = Raster.Read("font.txt"), header = Raster.Words(input[0]); Font font = new(int.Parse(header[1]),int.Parse(header[2]));
        for (int i = 1; i < input.Length; i += font.Height + 1) { List<Point> dots = []; for (int y = 0; y < font.Height; y++) for (int x = 0; x < font.Width; x++) if (input[i + y + 1][x] == '#') dots.Add(new(x,y)); font.Glyphs.Add(Raster.Words(input[i])[1][0],dots); } return font;
    }
    static Scene ReadScene()
    {
        Scene scene = new(); string[] input = Raster.Read("scene.txt"); Block block = null!; Stack<List<Node>> bodies = new();
        for (int i = 0; i < input.Length; i++)
        {
            string[] p = Raster.Words(input[i]); if (p.Length == 0 || p[0][0] == '#') continue;
            switch (p[0])
            {
                case "CANVAS": scene.Width = int.Parse(p[1]); scene.Height = int.Parse(p[2]); scene.Background = p[3]; break;
                case "LAYER": block = new(p[1],int.Parse(p[2]),p[3]); scene.Layers.Add(block); bodies.Clear(); bodies.Push(block.Body); break;
                case "SYMBOL": block = new(p[1]); scene.Symbols.Add(block.Name,block); bodies.Clear(); bodies.Push(block.Body); break;
                case "END": block.EndLine = i + 1; bodies.Clear(); break;
                case "REPEAT": { Node node = new() { Repeat = true,Line = i + 1,Count = int.Parse(p[1]),Dx = int.Parse(p[2]),Dy = int.Parse(p[3]) }; bodies.Peek().Add(node); bodies.Push(node.Body); break; }
                case "ENDREPEAT": bodies.Pop(); break;
                default: bodies.Peek().Add(new() { Line = i + 1,Keyword = p[0],Arguments = p.Skip(1).ToArray() }); break;
            }
        }
        return scene;
    }
    static List<Probe> ReadProbes()
    {
        string[] input = Raster.Read("probes.txt"); List<Probe> probes = []; for (int i = 1; i <= int.Parse(input[0]); i++) { string[] p = Raster.Words(input[i]); probes.Add(new(p[0],p.Skip(1).Select(int.Parse).ToArray())); } return probes;
    }
    static List<string> CommandLines(List<Execution> executions)
    {
        List<string> result = []; foreach (Execution execution in executions) { string head = $"cmd {execution.Sequence} line {execution.Command.Line} {execution.Command.Keyword}"; result.Add(head + (execution.Kind == "error" ? " error " + execution.Error : execution.Kind == "drawing" ? $" pixels {execution.Pixels} box {Raster.BoxText(execution.Box)}" : " ok")); } return result;
    }
    static List<KeyValuePair<T, int>> Ranked<T>(Dictionary<T, int> counts) where T : notnull => counts.OrderByDescending(p => p.Value).ThenBy(p => p.Key).ToList();
    static List<string> LayerLines(Scene scene, List<Layer> layers, List<Execution> executions)
    {
        int[] visible = new int[layers.Count];
        for (int y = 0; y < scene.Height; y++) for (int x = 0; x < scene.Width; x++) { bool covered = false; for (int i = layers.Count - 1; i >= 0; i--) { int alpha = layers[i].AlphaAt(new(x,y)); if (alpha > 0 && !covered) visible[i]++; if (alpha == 255) covered = true; } }
        List<string> result = [$"layers {layers.Count}"];
        for (int i = 0; i < layers.Count; i++)
        {
            Block block = scene.Layers[i]; Layer layer = layers[i]; List<Execution> own = executions.Where(e => e.Layer == i + 1).ToList(); HashSet<Point> painted = []; Dictionary<Color, int> counts = [];
            for (int y = 0; y < scene.Height; y++) for (int x = 0; x < scene.Width; x++) if (layer.ColorAt(new(x,y)) is Color color) { painted.Add(new(x,y)); counts[color] = counts.GetValueOrDefault(color) + 1; }
            result.Add($"layer {i + 1} {block.Name} opacity {block.Opacity} mode {block.Mode} commands {own.Count} errors {own.Count(e => e.Kind == "error")} pixels {painted.Count} box {Raster.BoxText(Raster.Bounds(painted))} visible {visible[i]} colors {counts.Count}");
            foreach (var color in Ranked(counts).Take(5)) result.Add($"color {color.Key} pixels {color.Value}");
        }
        return result;
    }
    static List<string> SummaryLines(Scene scene, Styles styles, List<Execution> executions, Rgb[][] image)
    {
        Dictionary<string, int> kinds = [], errors = [], uses = scene.Symbols.Keys.ToDictionary(name => name,_ => 0); Dictionary<string, KeywordTally> keywords = []; HashSet<string> usedPens = [], usedBrushes = [], usedColors = [scene.Background]; int painted = 0, erased = 0;
        foreach (Execution execution in executions)
        {
            Node command = execution.Command; kinds[execution.Kind] = kinds.GetValueOrDefault(execution.Kind) + 1; if (!keywords.TryGetValue(command.Keyword,out var tally)) keywords[command.Keyword] = tally = new(); tally.Executed++;
            if (execution.Kind == "error") { errors[execution.Error] = errors.GetValueOrDefault(execution.Error) + 1; tally.Errors++; }
            else if (execution.Kind == "drawing") { tally.Pixels += execution.Pixels; if (command.Keyword == "ERASE") erased += execution.Pixels; else painted += execution.Pixels; if (Raster.PenCommands.Contains(command.Keyword)) usedPens.Add(command.Arguments[0]); else if (Raster.BrushCommands.Contains(command.Keyword)) usedBrushes.Add(command.Arguments[0]); }
            else if (command.Keyword == "USE") uses[command.Arguments[0]]++;
        }
        foreach (string name in usedPens) usedColors.Add(styles.Pens[name].Color); foreach (string name in usedBrushes) usedColors.UnionWith(styles.Brushes[name].Colors);
        Color background = styles.Colors[scene.Background]; List<string> result = [$"canvas {scene.Width} {scene.Height}",$"background {background.R} {background.G} {background.B}",$"layers {scene.Layers.Count}",$"symbols {scene.Symbols.Count}",$"commands {executions.Count}",$"drawing {kinds.GetValueOrDefault("drawing")}",$"state {kinds.GetValueOrDefault("state")}",$"errors {kinds.GetValueOrDefault("error")}"];
        foreach (string error in Raster.ErrorNames) result.Add($"error {error} {errors.GetValueOrDefault(error)}"); result.Add($"painted {painted}"); result.Add($"erased {erased}"); Dictionary<Rgb, int> counts = [];
        foreach (Rgb color in image.SelectMany(row => row)) counts[color] = counts.GetValueOrDefault(color) + 1; result.Add($"colors {counts.Count}"); int rank = 0; foreach (var color in Ranked(counts).Take(8)) result.Add($"top {++rank} {color.Key} pixels {color.Value}");
        foreach (string name in uses.Keys.Order(StringComparer.Ordinal)) result.Add($"symbol {name} uses {uses[name]}"); foreach (string keyword in keywords.Keys.Order(StringComparer.Ordinal)) { KeywordTally tally = keywords[keyword]; result.Add($"keyword {keyword} executed {tally.Executed} errors {tally.Errors} pixels {tally.Pixels}"); }
        List<string> unused = []; foreach (string name in styles.Colors.Keys.Order(StringComparer.Ordinal)) if (!usedColors.Contains(name)) unused.Add("unused color " + name); foreach (string name in styles.Pens.Keys.Order(StringComparer.Ordinal)) if (!usedPens.Contains(name)) unused.Add("unused pen " + name); foreach (string name in styles.Brushes.Keys.Order(StringComparer.Ordinal)) if (!usedBrushes.Contains(name)) unused.Add("unused brush " + name); foreach (string name in uses.Keys.Order(StringComparer.Ordinal)) if (uses[name] == 0) unused.Add("unused symbol " + name); result.Add($"unused {unused.Count}"); result.AddRange(unused); return result;
    }
    static List<string> ProbeLines(List<Probe> probes, Rgb[][] image, List<Layer> layers)
    {
        List<string> result = [];
        for (int i = 0; i < probes.Count; i++)
        {
            Probe probe = probes[i]; int[] v = probe.Values;
            if (probe.Kind == "point") { Point point = new(v[0],v[1]); List<string> stack = []; for (int j = 0; j < layers.Count; j++) if (layers[j].AlphaAt(point) > 0) stack.Add($"{j + 1}:{layers[j].LineAt(point)}"); result.Add($"point {i + 1} {point.X} {point.Y} rgb {image[point.Y][point.X]} layers {stack.Count} stack {(stack.Count == 0 ? "none" : string.Join(' ',stack))}"); }
            else
            {
                int[] totals = new int[3], cover = new int[layers.Count]; HashSet<Rgb> colors = []; int count = (v[2] - v[0] + 1) * (v[3] - v[1] + 1);
                for (int y = v[1]; y <= v[3]; y++) for (int x = v[0]; x <= v[2]; x++) { Rgb color = image[y][x]; colors.Add(color); for (int c = 0; c < 3; c++) totals[c] += color[c]; for (int j = 0; j < layers.Count; j++) if (layers[j].AlphaAt(new(x,y)) > 0) cover[j]++; }
                result.Add($"area {i + 1} {v[0]} {v[1]} {v[2]} {v[3]} pixels {count} mean {totals[0] / count} {totals[1] / count} {totals[2] / count} colors {colors.Count} cover {string.Join(' ',cover)}");
            }
        }
        return result;
    }
    static void Main()
    {
        CultureInfo.CurrentCulture = CultureInfo.InvariantCulture; Styles styles = ReadStyles(); Font font = ReadFont(); Scene scene = ReadScene(); List<Probe> probes = ReadProbes(); Renderer renderer = new(scene,styles,font); renderer.Run(); Rgb[][] image = CanvasMath.Composite(renderer.Layers,styles.Colors[scene.Background],scene.Width,scene.Height);
        Directory.CreateDirectory("output"); PpmWriter.WritePpm("output/image.ppm",image); PpmWriter.WritePreview("output/preview.txt",image); Raster.Write("commands.txt",CommandLines(renderer.Executions)); Raster.Write("layers.txt",LayerLines(scene,renderer.Layers,renderer.Executions)); Raster.Write("summary.txt",SummaryLines(scene,styles,renderer.Executions,image)); Raster.Write("probes.txt",ProbeLines(probes,image,renderer.Layers));
    }
}
