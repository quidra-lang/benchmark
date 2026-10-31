using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Text;

class Program
{
    static readonly Dictionary<string, string> Initial = CreateInitial();
    static readonly List<Element> Elements = new();

    static int viewportWidth, viewportHeight;

    static Dictionary<string, string> CreateInitial()
    {
        string values = "display=block|position=static|box-sizing=content-box|width=auto|height=auto|"
                + "min-width=0|min-height=0|max-width=none|max-height=none|margin-top=0|"
                + "margin-right=0|margin-bottom=0|margin-left=0|padding-top=0|padding-right=0|"
                + "padding-bottom=0|padding-left=0|border-top=0|border-right=0|border-bottom=0|"
                + "border-left=0|top=auto|right=auto|bottom=auto|left=auto|"
                + "flex-direction=row|flex-wrap=nowrap|justify-content=start|align-items=stretch|align-self=auto|"
                + "row-gap=0|column-gap=0|order=0|flex-grow=0|flex-shrink=1|"
                + "flex-basis=auto|grid-template-columns=none|grid-template-rows=none|grid-column=auto|grid-row=auto";
        return values.Split('|').Select(s => s.Split('=')).ToDictionary(p => p[0], p => p[1]);
    }

    class Element
    {
        public string Type = "", Id = "", Text = null;
        public List<string> Classes = new(), Lines = new();
        public List<Element> Children = new();
        public Dictionary<string, string> Style = new(Initial);
        public Element Parent, Containing;
        public int Index, Depth, Cw, Ch, Rx, Ry, X, Y, Intrinsic = -1;
        public bool Displayed;
        public string Get(string property) => Style[property];
        public int Number(string property) => int.Parse(Get(property), CultureInfo.InvariantCulture);
        public int Hf => Number("padding-left") + Number("padding-right") + Number("border-left") + Number("border-right");
        public int Vf => Number("padding-top") + Number("padding-bottom") + Number("border-top") + Number("border-bottom");
        public int Hm => Number("margin-left") + Number("margin-right");
        public int Vm => Number("margin-top") + Number("margin-bottom");
        public int Bw => Cw + Hf;
        public int Bh => Ch + Vf;
        public int Cx => X + Number("border-left") + Number("padding-left");
        public int Cy => Y + Number("border-top") + Number("padding-top");
    }

    record Declaration(string Property, string Value);

    record Rule(string[] Selectors, List<Declaration> Declarations);

    record Track(char Kind, int Value);

    class GridItem
    {
        public Element Element;
        public int Row, Column, Rows, Columns, Aw, Ax, Width, Contribution;
        public bool Placed;
        public GridItem(Element element)
        {
            Element = element;
            int[] c = Placement(element.Get("grid-column")), r = Placement(element.Get("grid-row"));
            Column = c[0];
            Columns = c[1];
            Row = r[0];
            Rows = r[1];
        }
    }

    record Grid(List<GridItem> Items, int Columns, int Rows);

    class FlexItem(Element element)
    {
        public Element Element = element;
        public int Base, Hypothetical, Size, Cross, Outer;
        public long Weight;
        public bool Frozen;
    }

    static bool Integer(string value) => value.Length is >= 1 and <= 3 && value.All(c => c is >= '0' and <= '9');

    static bool Positive(string value) => Integer(value) && int.Parse(value, CultureInfo.InvariantCulture) > 0;

    static bool Signed(string value) => Integer(value) || value.StartsWith('-') && Integer(value[1..]);

    static bool Percentage(string value) => value.EndsWith('%') && Integer(value[..^1]);

    static bool OneOf(string value, string choices) => choices.Split(' ').Contains(value, StringComparer.Ordinal);

    static bool Known(string property) => Initial.ContainsKey(property) || OneOf(property, "margin padding border gap");

    static Dictionary<string, string> ParseDeclaration(string property, string value)
    {
        string[] tokens = value.Split(' ');
        Dictionary<string, string> result = new();
        if (OneOf(property, "margin padding border gap"))
        {
            bool gap = property == "gap";
            if (tokens.Length < 1 || tokens.Length > (gap ? 2 : 4)) return null;
            foreach (string token in tokens) if (!Integer(token) || property == "border" && !OneOf(token, "0 1")) return null;
            if (gap)
            {
                result["row-gap"] = tokens[0];
                result["column-gap"] = tokens[^1];
            }
            else
            {
                string[] sides = { "top", "right", "bottom", "left" };
                string[] expanded = { tokens[0], tokens.Length > 1 ? tokens[1] : tokens[0], tokens.Length > 2 ? tokens[2] : tokens[0], tokens.Length > 3 ? tokens[3] : tokens.Length > 1 ? tokens[1] : tokens[0] };
                for (int i = 0; i < 4; i++) result[property + "-" + sides[i]] = expanded[i];
            }
            return result;
        }
        if (!Initial.ContainsKey(property)) return null;
        bool valid;
        if (property.StartsWith("grid-template-", StringComparison.Ordinal)) valid = value == "none" || tokens.All(t => Integer(t) || t == "auto" || t.EndsWith("fr", StringComparison.Ordinal) && Positive(t[..^2]));
        else if (property is "grid-column" or "grid-row")
            valid = tokens.Length == 1 && (value == "auto" || Positive(value))
                || tokens.Length == 2 && tokens[0] == "span" && Positive(tokens[1])
                || tokens.Length == 3 && Positive(tokens[0]) && tokens[1] == "/" && Positive(tokens[2]) && int.Parse(tokens[0], CultureInfo.InvariantCulture) < int.Parse(tokens[2], CultureInfo.InvariantCulture)
                || tokens.Length == 4 && Positive(tokens[0]) && tokens[1] == "/" && tokens[2] == "span" && Positive(tokens[3]);
        else
        {
            if (tokens.Length != 1) return null;
            valid = property switch
            {
                "display" => OneOf(value, "block flex grid none"),
                "position" => OneOf(value, "static relative absolute"),
                "box-sizing" => OneOf(value, "content-box border-box"),
                "width" or "height" or "flex-basis" => value == "auto" || Integer(value) || Percentage(value),
                "min-width" or "min-height" => Integer(value) || Percentage(value),
                "max-width" or "max-height" => value == "none" || Integer(value) || Percentage(value),
                "top" or "right" or "bottom" or "left" => value == "auto" || Signed(value),
                "order" => Signed(value),
                "flex-direction" => OneOf(value, "row row-reverse column column-reverse"),
                "flex-wrap" => OneOf(value, "nowrap wrap"),
                "justify-content" => OneOf(value, "start end center space-between space-around space-evenly"),
                "align-items" => OneOf(value, "stretch start end center"),
                "align-self" => OneOf(value, "auto stretch start end center"),
                _ => property.StartsWith("border-", StringComparison.Ordinal) ? OneOf(value, "0 1") : Integer(value)
            };
        }
        if (!valid) return null;
        result[property] = value;
        return result;
    }

    static List<Element> Flow(Element element, bool sorted)
    {
        IEnumerable<Element> children = element.Children.Where(e => e.Displayed && e.Get("position") != "absolute");
        return (sorted ? children.OrderBy(e => e.Number("order")).ThenBy(e => e.Index) : children).ToList();
    }

    static int Resolve(Element element, string property, int reference, bool horizontal)
    {
        string value = element.Get(property);
        if (value is "auto" or "none") return -1;
        int n;
        if (value.EndsWith('%'))
        {
            if (reference < 0) return -1;
            n = (int)((long)reference * int.Parse(value[..^1], CultureInfo.InvariantCulture) / 100);
        }
        else n = int.Parse(value, CultureInfo.InvariantCulture);
        return element.Get("box-sizing") == "border-box" ? Math.Max(0, n - (horizontal ? element.Hf : element.Vf)) : n;
    }

    static int Clamp(Element element, int value, int reference, bool horizontal)
    {
        string axis = horizontal ? "width" : "height";
        int low = Resolve(element, "min-" + axis, reference, horizontal), high = Resolve(element, "max-" + axis, reference, horizontal);
        if (high >= 0) value = Math.Min(value, high);
        return Math.Max(value, Math.Max(0, low));
    }

    static int[] Distribute(int total, long[] weights)
    {
        int[] result = new int[weights.Length];
        long sum = weights.Sum();
        if (sum == 0) return result;
        int remaining = total;
        for (int i = 0; i < weights.Length; i++)
        {
            result[i] = (int)((long)total * weights[i] / sum);
            remaining -= result[i];
        }
        for (int i = 0; i < weights.Length && remaining > 0; i++) if (weights[i] > 0)
        {
            result[i]++;
            remaining--;
        }
        return result;
    }

    static int[] Placement(string value)
    {
        string[] t = value.Split(' ');
        if (value == "auto") return new[] { 0, 1 };
        if (t[0] == "span") return new[] { 0, int.Parse(t[1], CultureInfo.InvariantCulture) };
        int start = int.Parse(t[0], CultureInfo.InvariantCulture);
        return new[] { start, t.Length == 1 ? 1 : t.Length == 3 ? int.Parse(t[2], CultureInfo.InvariantCulture) - start : int.Parse(t[3], CultureInfo.InvariantCulture) };
    }

    static List<Track> Tracks(string value, bool columns)
    {
        List<Track> result = new();
        if (value == "none")
        {
            if (columns) result.Add(new Track('a', 0));
            return result;
        }
        foreach (string token in value.Split(' ')) result.Add(token == "auto" ? new Track('a', 0) : token.EndsWith("fr", StringComparison.Ordinal) ? new Track('f', int.Parse(token[..^2], CultureInfo.InvariantCulture)) : new Track('n', int.Parse(token, CultureInfo.InvariantCulture)));
        return result;
    }

    static bool Overlaps(List<GridItem> items, GridItem item, int row, int column) => items.Any(other => other.Placed && row < other.Row + other.Rows && other.Row < row + item.Rows && column < other.Column + other.Columns && other.Column < column + item.Columns);

    static Grid PlaceGrid(Element element)
    {
        List<GridItem> items = new();
        int nc = Tracks(element.Get("grid-template-columns"), true).Count, nr = Tracks(element.Get("grid-template-rows"), false).Count;
        foreach (Element child in Flow(element, true))
        {
            GridItem item = new(child);
            items.Add(item);
            nc = Math.Max(nc, item.Column == 0 ? item.Columns : item.Column + item.Columns - 1);
        }
        foreach (GridItem item in items) if (item.Row > 0 && item.Column > 0) item.Placed = true;
        int cr = 1, cc = 1;
        foreach (GridItem item in items)
        {
            if (item.Placed) continue;
            if (item.Row > 0)
            {
                int c = 1;
                while (c <= nc - item.Columns + 1 && Overlaps(items, item, item.Row, c)) c++;
                item.Column = c <= nc - item.Columns + 1 ? c : 1;
            }
            else if (item.Column > 0)
            {
                if (item.Column < cc) cr++;
                int r = cr;
                while (Overlaps(items, item, r, item.Column)) r++;
                item.Row = r;
                cr = r;
                cc = item.Column + item.Columns;
            }
            else
            {
                int r = cr, c = cc;
                while (true)
                {
                    if (c + item.Columns - 1 > nc)
                    {
                        r++;
                        c = 1;
                    }
                    else if (Overlaps(items, item, r, c)) c++;
                    else break;
                }
                item.Row = r;
                item.Column = c;
                cr = r;
                cc = c + item.Columns;
            }
            item.Placed = true;
        }
        foreach (GridItem item in items) nr = Math.Max(nr, item.Row + item.Rows - 1);
        return new Grid(items, nc, nr);
    }

    static int[] TrackSizes(Element element, Grid grid, bool columns, int available, bool intrinsic)
    {
        int count = columns ? grid.Columns : grid.Rows;
        List<Track> specs = Tracks(element.Get(columns ? "grid-template-columns" : "grid-template-rows"), columns);
        while (specs.Count < count) specs.Add(new Track('a', 0));
        int[] sizes = new int[count];
        for (int i = 0; i < count; i++)
        {
            Track track = specs[i];
            if (track.Kind == 'n') sizes[i] = track.Value;
            else if (track.Kind == 'a' || available < 0) foreach (GridItem item in grid.Items) if ((columns ? item.Column : item.Row) == i + 1 && (columns ? item.Columns : item.Rows) == 1) sizes[i] = Math.Max(sizes[i], intrinsic ? Contribution(item.Element) : item.Contribution);
        }
        int gap = element.Number(columns ? "column-gap" : "row-gap");
        int leftover = available - sizes.Sum() - gap * Math.Max(0, count - 1);
        if (available >= 0 && leftover > 0)
        {
            bool fr = specs.Any(t => t.Kind == 'f');
            long[] weights = new long[count];
            for (int i = 0; i < count; i++) if (fr ? specs[i].Kind == 'f' : specs[i].Kind == 'a') weights[i] = fr ? specs[i].Value : 1;
            int[] extra = Distribute(leftover, weights);
            for (int i = 0; i < count; i++) sizes[i] += extra[i];
        }
        return sizes;
    }

    static int MaxContent(Element element)
    {
        if (element.Intrinsic >= 0) return element.Intrinsic;
        int result = 0;
        if (element.Text != null) result = element.Text.Length;
        else if (element.Get("display") == "flex" && element.Get("flex-direction").StartsWith("row", StringComparison.Ordinal))
        {
            List<Element> children = Flow(element, false);
            result = children.Sum(Contribution) + element.Number("column-gap") * Math.Max(0, children.Count - 1);
        }
        else if (element.Get("display") == "grid")
        {
            Grid grid = PlaceGrid(element);
            result = TrackSizes(element, grid, true, -1, true).Sum() + element.Number("column-gap") * (grid.Columns - 1);
        }
        else foreach (Element child in Flow(element, false)) result = Math.Max(result, Contribution(child));
        element.Intrinsic = result;
        return result;
    }

    static int Contribution(Element element)
    {
        int w = Resolve(element, "width", -1, true);
        return Clamp(element, w < 0 ? MaxContent(element) : w, -1, true) + element.Hf + element.Hm;
    }

    static string Align(Element parent, Element child) => child.Get("align-self") == "auto" ? parent.Get("align-items") : child.Get("align-self");

    static int Offset(string align, int space) => space <= 0 ? 0 : align == "end" ? space : align == "center" ? space / 2 : 0;

    static void Position(Element parent, Element child, int x, int y)
    {
        child.Rx = parent.Number("border-left") + parent.Number("padding-left") + x;
        child.Ry = parent.Number("border-top") + parent.Number("padding-top") + y;
    }

    static int Layout(Element element, int widthReference, int heightReference, int forcedWidth, int forcedHeight)
    {
        int w = Resolve(element, "width", widthReference, true);
        element.Cw = forcedWidth >= 0 ? forcedWidth : Clamp(element, w < 0 ? Math.Max(0, widthReference - element.Hm - element.Hf) : w, widthReference, true);
        if (forcedHeight < 0)
        {
            int h = Resolve(element, "height", heightReference, false);
            if (h >= 0) forcedHeight = Clamp(element, h, heightReference, false);
        }
        int a;
        if (element.Text != null)
        {
            element.Lines = new();
            string current = "";
            foreach (string word in element.Text.Split(' '))
            {
                if (current.Length == 0) current = word;
                else if (current.Length + 1 + word.Length <= element.Cw) current += " " + word;
                else
                {
                    element.Lines.Add(current);
                    current = word;
                }
            }
            element.Lines.Add(current);
            a = element.Lines.Count;
        }
        else if (element.Get("display") == "flex") a = Flex(element, forcedHeight, heightReference);
        else if (element.Get("display") == "grid") a = GridLayout(element, forcedHeight);
        else
        {
            a = 0;
            int previousBottom = 0;
            bool first = true;
            foreach (Element child in Flow(element, false))
            {
                Layout(child, element.Cw, forcedHeight, -1, -1);
                int y = a + (first ? child.Number("margin-top") : Math.Max(previousBottom, child.Number("margin-top")));
                Position(element, child, child.Number("margin-left"), y);
                a = y + child.Bh;
                previousBottom = child.Number("margin-bottom");
                first = false;
            }
            if (!first) a += previousBottom;
        }
        element.Ch = forcedHeight >= 0 ? forcedHeight : Clamp(element, a, heightReference, false);
        return a;
    }

    static int Flex(Element element, int k, int heightReference)
    {
        bool horizontal = element.Get("flex-direction").StartsWith("row", StringComparison.Ordinal), reverse = element.Get("flex-direction").EndsWith("reverse", StringComparison.Ordinal);
        int reference = horizontal ? element.Cw : k, gap = element.Number(horizontal ? "column-gap" : "row-gap");
        List<FlexItem> items = new();
        foreach (Element child in Flow(element, true))
        {
            FlexItem item = new(child);
            items.Add(item);
            item.Outer = horizontal ? child.Hm + child.Hf : child.Vm + child.Vf;
            if (!horizontal)
            {
                int r = Math.Max(0, element.Cw - child.Hm - child.Hf), width = Resolve(child, "width", element.Cw, true);
                item.Cross = Clamp(child, width >= 0 ? width : Align(element, child) == "stretch" ? r : Math.Min(MaxContent(child), r), element.Cw, true);
            }
            item.Base = Resolve(child, "flex-basis", reference, horizontal);
            if (item.Base < 0) item.Base = Resolve(child, horizontal ? "width" : "height", reference, horizontal);
            if (item.Base < 0) item.Base = horizontal ? MaxContent(child) : Layout(child, element.Cw, k, item.Cross, -1);
            item.Hypothetical = Clamp(child, item.Base, reference, horizontal);
        }
        int length = reference;
        if (length < 0)
        {
            length = gap * Math.Max(0, items.Count - 1);
            foreach (FlexItem item in items) length += item.Hypothetical + item.Outer;
            length = Clamp(element, length, heightReference, false);
        }
        List<List<FlexItem>> lines = new();
        int occupied = 0;
        foreach (FlexItem item in items)
        {
            if (lines.Count == 0 || horizontal && element.Get("flex-wrap") == "wrap" && occupied + gap + item.Hypothetical + item.Outer > length)
            {
                lines.Add(new());
                occupied = 0;
            }
            List<FlexItem> line = lines[^1];
            if (line.Count > 0) occupied += gap;
            occupied += item.Hypothetical + item.Outer;
            line.Add(item);
        }
        int crossStart = 0;
        foreach (List<FlexItem> line in lines)
        {
            int total = gap * (line.Count - 1);
            foreach (FlexItem item in line) total += item.Hypothetical + item.Outer;
            bool grow = total < length;
            foreach (FlexItem item in line)
            {
                item.Weight = grow ? item.Element.Number("flex-grow") : (long)item.Element.Number("flex-shrink") * item.Base;
                item.Size = item.Hypothetical;
                item.Frozen = item.Weight == 0 || (grow ? item.Base > item.Hypothetical : item.Base < item.Hypothetical);
            }
            while (true)
            {
                int free = length - gap * (line.Count - 1), remaining = 0;
                long[] weights = new long[line.Count];
                for (int i = 0; i < line.Count; i++)
                {
                    FlexItem item = line[i];
                    free -= (item.Frozen ? item.Size : item.Base) + item.Outer;
                    if (!item.Frozen)
                    {
                        weights[i] = item.Weight;
                        remaining++;
                    }
                }
                if (remaining == 0) break;
                int[] shares = Distribute(Math.Max(0, grow ? free : -free), weights), violations = new int[line.Count];
                int violation = 0;
                for (int i = 0; i < line.Count; i++)
                {
                    FlexItem item = line[i];
                    if (!item.Frozen)
                    {
                        int tentative = item.Base + (grow ? shares[i] : -shares[i]);
                        item.Size = Clamp(item.Element, tentative, reference, horizontal);
                        violations[i] = item.Size - tentative;
                        violation += violations[i];
                    }
                }
                for (int i = 0; i < line.Count; i++) if (violation == 0 || violation > 0 && violations[i] > 0 || violation < 0 && violations[i] < 0) line[i].Frozen = true;
            }
            int lc = horizontal ? 0 : element.Cw;
            if (horizontal)
            {
                foreach (FlexItem item in line)
                {
                    Layout(item.Element, element.Cw, k, item.Size, -1);
                    item.Cross = item.Element.Ch;
                    lc = Math.Max(lc, item.Cross + item.Element.Vf + item.Element.Vm);
                }
                if (lines.Count == 1) lc = k >= 0 ? k : Clamp(element, lc, heightReference, false);
            }
            int used = gap * (line.Count - 1);
            foreach (FlexItem item in line) used += item.Size + item.Outer;
            int space = length - used;
            int[] before = new int[line.Count + 1];
            if (space > 0)
            {
                string justify = element.Get("justify-content");
                if (justify == "end") before[0] = space;
                else if (justify == "center") before[0] = space / 2;
                else if (justify.StartsWith("space-", StringComparison.Ordinal))
                {
                    long[] weights = Enumerable.Repeat(1L, before.Length).ToArray();
                    if (justify == "space-between")
                    {
                        weights[0] = 0;
                        weights[^1] = 0;
                    }
                    else if (justify == "space-around") for (int i = 1; i < weights.Length - 1; i++) weights[i] = 2;
                    before = Distribute(space, weights);
                }
            }
            int cursor = 0;
            for (int i = 0; i < line.Count; i++)
            {
                FlexItem item = line[i];
                Element child = item.Element;
                string alignment = Align(element, child);
                if (horizontal)
                {
                    if (alignment == "stretch" && child.Get("height") == "auto")
                    {
                        item.Cross = Clamp(child, Math.Max(0, lc - child.Vm - child.Vf), k, false);
                        Layout(child, element.Cw, k, item.Size, item.Cross);
                    }
                    else Layout(child, element.Cw, k, item.Size, -1);
                }
                else Layout(child, element.Cw, k, item.Cross, item.Size);
                int cross = crossStart + Offset(alignment, lc - item.Cross - (horizontal ? child.Vf + child.Vm : child.Hf + child.Hm)) + child.Number(horizontal ? "margin-top" : "margin-left");
                cursor += before[i];
                int main = reverse ? length - cursor - child.Number(horizontal ? "margin-right" : "margin-bottom") - item.Size - (horizontal ? child.Hf : child.Vf) : cursor + child.Number(horizontal ? "margin-left" : "margin-top");
                Position(element, child, horizontal ? main : cross, horizontal ? cross : main);
                cursor += item.Size + item.Outer + gap;
            }
            crossStart += lc + element.Number("row-gap");
        }
        return horizontal ? lines.Count == 0 ? 0 : crossStart - element.Number("row-gap") : length;
    }

    static int Prefix(int[] sizes, int count, int gap)
    {
        int result = count * gap;
        for (int i = 0; i < count; i++) result += sizes[i];
        return result;
    }

    static int Area(int[] sizes, int start, int span, int gap)
    {
        int result = gap * (span - 1);
        for (int i = start - 1; i < start - 1 + span; i++) result += sizes[i];
        return result;
    }

    static int GridLayout(Element element, int k)
    {
        Grid grid = PlaceGrid(element);
        int cg = element.Number("column-gap"), rg = element.Number("row-gap");
        int[] columns = TrackSizes(element, grid, true, element.Cw, true);
        foreach (GridItem item in grid.Items)
        {
            item.Aw = Area(columns, item.Column, item.Columns, cg);
            item.Ax = Prefix(columns, item.Column - 1, cg);
            int width = Resolve(item.Element, "width", item.Aw, true);
            item.Width = Clamp(item.Element, width < 0 ? Math.Max(0, item.Aw - item.Element.Hm - item.Element.Hf) : width, item.Aw, true);
            Layout(item.Element, item.Aw, -1, item.Width, -1);
            item.Contribution = item.Element.Bh + item.Element.Vm;
        }
        int[] rows = TrackSizes(element, grid, false, k, false);
        foreach (GridItem item in grid.Items)
        {
            int ah = Area(rows, item.Row, item.Rows, rg), ay = Prefix(rows, item.Row - 1, rg);
            string alignment = Align(element, item.Element);
            int fh = alignment == "stretch" && item.Element.Get("height") == "auto" ? Clamp(item.Element, Math.Max(0, ah - item.Element.Vm - item.Element.Vf), ah, false) : -1;
            Layout(item.Element, item.Aw, ah, item.Width, fh);
            Position(element, item.Element, item.Ax + item.Element.Number("margin-left"), ay + Offset(alignment, ah - item.Element.Bh - item.Element.Vm) + item.Element.Number("margin-top"));
        }
        return rows.Sum() + rg * Math.Max(0, grid.Rows - 1);
    }

    static void Relayout()
    {
        foreach (Element element in Elements)
        {
            element.Displayed = element.Get("display") != "none" && (element.Parent == null || element.Parent.Displayed);
            element.Intrinsic = -1;
            element.Containing = null;
        }
        Element root = Elements[0];
        if (root.Displayed && root.Get("position") != "absolute")
        {
            Layout(root, viewportWidth, viewportHeight, -1, -1);
            root.Rx = root.Number("margin-left");
            root.Ry = root.Number("margin-top");
        }
        foreach (Element element in Elements) if (element.Displayed && element.Get("position") == "absolute")
        {
            Element cb = element.Parent;
            while (cb != null && cb.Get("position") == "static") cb = cb.Parent;
            element.Containing = cb;
            int width = cb == null ? viewportWidth : cb.Cw + cb.Number("padding-left") + cb.Number("padding-right"), height = cb == null ? viewportHeight : cb.Ch + cb.Number("padding-top") + cb.Number("padding-bottom");
            int left = element.Get("left") == "auto" ? 0 : element.Number("left"), right = element.Get("right") == "auto" ? 0 : element.Number("right"), top = element.Get("top") == "auto" ? 0 : element.Number("top"), bottom = element.Get("bottom") == "auto" ? 0 : element.Number("bottom");
            int w = Resolve(element, "width", width, true);
            if (element.Get("width") == "auto")
            {
                int r = Math.Max(0, width - left - right - element.Hm - element.Hf);
                w = element.Get("left") != "auto" && element.Get("right") != "auto" ? r : Math.Min(MaxContent(element), r);
            }
            int h = element.Get("height") == "auto" && element.Get("top") != "auto" && element.Get("bottom") != "auto" ? Clamp(element, Math.Max(0, height - top - bottom - element.Vm - element.Vf), height, false) : -1;
            Layout(element, width, height, Clamp(element, w, width, true), h);
            element.Rx = element.Get("left") != "auto" ? left + element.Number("margin-left") : element.Get("right") != "auto" ? width - right - element.Number("margin-right") - element.Bw : element.Number("margin-left");
            element.Ry = element.Get("top") != "auto" ? top + element.Number("margin-top") : element.Get("bottom") != "auto" ? height - bottom - element.Number("margin-bottom") - element.Bh : element.Number("margin-top");
        }
        foreach (Element element in Elements) if (element.Displayed)
        {
            Element reference = element.Get("position") == "absolute" ? element.Containing : element.Parent;
            element.X = element.Rx + (reference == null ? 0 : reference.X + (element.Get("position") == "absolute" ? reference.Number("border-left") : 0));
            element.Y = element.Ry + (reference == null ? 0 : reference.Y + (element.Get("position") == "absolute" ? reference.Number("border-top") : 0));
            if (element.Get("position") == "relative")
            {
                element.X += element.Get("left") != "auto" ? element.Number("left") : element.Get("right") != "auto" ? -element.Number("right") : 0;
                element.Y += element.Get("top") != "auto" ? element.Number("top") : element.Get("bottom") != "auto" ? -element.Number("bottom") : 0;
            }
        }
    }

    static int[][] Snapshot() => Elements.Select(e => new[] { e.Displayed ? 1 : 0, e.X, e.Y, e.Bw, e.Bh }).ToArray();

    static string Changes(int[][] old)
    {
        int[][] now = Snapshot();
        List<string> changed = Elements.Where(e => old[e.Index][0] != now[e.Index][0] || e.Displayed && !old[e.Index].SequenceEqual(now[e.Index])).Select(e => e.Id).ToList();
        return changed.Count == 0 ? "no change" : string.Join(" ", changed);
    }

    static string Rectangle(string name, int x, int y, int width, int height) => $"{name} {x} {y} {width} {height}\n";

    static void Render(StringBuilder output)
    {
        char[][] screen = Enumerable.Range(0, viewportHeight).Select(_ => Enumerable.Repeat('.', viewportWidth).ToArray()).ToArray();
        foreach (Element element in Elements) if (element.Displayed)
        {
            for (int y = Math.Max(0, element.Y); y < Math.Min(viewportHeight, element.Y + element.Bh); y++) for (int x = Math.Max(0, element.X); x < Math.Min(viewportWidth, element.X + element.Bw); x++)
            {
                bool horizontal = element.Number("border-top") == 1 && y == element.Y || element.Number("border-bottom") == 1 && y == element.Y + element.Bh - 1, vertical = element.Number("border-left") == 1 && x == element.X || element.Number("border-right") == 1 && x == element.X + element.Bw - 1;
                screen[y][x] = horizontal ? vertical ? '+' : '-' : vertical ? '|' : ' ';
            }
            if (element.Text != null) for (int i = 0; i < element.Lines.Count; i++)
            {
                int y = element.Cy + i;
                if (y < 0 || y >= viewportHeight) continue;
                string line = element.Lines[i];
                for (int j = 0; j < line.Length; j++)
                {
                    int x = element.Cx + j;
                    if (x >= 0 && x < viewportWidth) screen[y][x] = line[j];
                }
            }
        }
        string edge = new('#', viewportWidth + 2);
        output.Append($"render {viewportWidth}x{viewportHeight}\n{edge}\n");
        foreach (char[] row in screen) output.Append('#').Append(row).Append("#\n");
        output.Append(edge).Append('\n');
    }

    static void Command(string line, StringBuilder output)
    {
        string[] t = line.Split(' ');
        Element element = t.Length > 1 ? Elements.FirstOrDefault(e => e.Id == t[1]) : null;
        switch (t[0])
        {
            case "LAYOUT":
                output.Append($"layout {viewportWidth}x{viewportHeight}\n");
                foreach (Element e in Elements) output.Append(new string(' ', 2 * e.Depth)).Append(e.Displayed ? Rectangle(e.Id, e.X, e.Y, e.Bw, e.Bh) : $"{e.Id} none\n");
                break;
            case "BOX":
                if (element == null) output.Append($"error: unknown element {t[1]}\n");
                else if (!element.Displayed) output.Append($"box {element.Id}: none\n");
                else
                {
                    output.Append($"box {element.Id}\n");
                    output.Append(Rectangle("margin", element.X - element.Number("margin-left"), element.Y - element.Number("margin-top"), element.Bw + element.Hm, element.Bh + element.Vm));
                    output.Append(Rectangle("border", element.X, element.Y, element.Bw, element.Bh));
                    output.Append(Rectangle("padding", element.X + element.Number("border-left"), element.Y + element.Number("border-top"), element.Cw + element.Number("padding-left") + element.Number("padding-right"), element.Ch + element.Number("padding-top") + element.Number("padding-bottom")));
                    output.Append(Rectangle("content", element.Cx, element.Cy, element.Cw, element.Ch));
                }
                break;
            case "RENDER":
                Render(output);
                break;
            case "HIT":
            {
                int x = int.Parse(t[1], CultureInfo.InvariantCulture), y = int.Parse(t[2], CultureInfo.InvariantCulture);
                if (x >= viewportWidth || y >= viewportHeight) output.Append($"error: point {x} {y} outside viewport\n");
                else
                {
                    Element hit = Elements.LastOrDefault(e => e.Displayed && x >= e.X && x < e.X + e.Bw && y >= e.Y && y < e.Y + e.Bh);
                    List<string> path = new();
                    for (; hit != null; hit = hit.Parent) path.Insert(0, hit.Id);
                    output.Append($"hit {x} {y}: {(path.Count == 0 ? "none" : string.Join(" > ", path))}\n");
                }
                break;
            }
            case "SET":
            {
                string value = line[(t[0].Length + t[1].Length + t[2].Length + 3)..];
                if (element == null) output.Append($"error: unknown element {t[1]}\n");
                else if (!Known(t[2])) output.Append($"error: unknown property {t[2]}\n");
                else
                {
                    Dictionary<string, string> values = ParseDeclaration(t[2], value);
                    if (values == null) output.Append($"error: invalid value for {t[2]}: {value}\n");
                    else
                    {
                        int[][] old = Snapshot();
                        foreach (var pair in values) element.Style[pair.Key] = pair.Value;
                        Relayout();
                        output.Append($"set {element.Id} {t[2]} {value}: {Changes(old)}\n");
                    }
                }
                break;
            }
            case "VIEWPORT":
            {
                int w = int.Parse(t[1], CultureInfo.InvariantCulture), h = int.Parse(t[2], CultureInfo.InvariantCulture);
                if (w < 1 || w > 80 || h < 1 || h > 40) output.Append($"error: invalid viewport {w} {h}\n");
                else
                {
                    int[][] old = Snapshot();
                    viewportWidth = w;
                    viewportHeight = h;
                    Relayout();
                    output.Append($"viewport {w} {h}: {Changes(old)}\n");
                }
                break;
            }
            case "OVERFLOW":
            {
                List<string> list = new();
                foreach (Element e in Elements) if (e.Displayed)
                {
                    bool overflow = e.Text != null && (e.Lines.Count > e.Ch || e.Lines.Any(s => s.Length > e.Cw));
                    if (e.Text == null) foreach (Element child in Flow(e, false)) if (child.X - child.Number("margin-left") < e.Cx || child.Y - child.Number("margin-top") < e.Cy || child.X + child.Bw + child.Number("margin-right") > e.Cx + e.Cw || child.Y + child.Bh + child.Number("margin-bottom") > e.Cy + e.Ch) overflow = true;
                    if (overflow) list.Add(e.Id);
                }
                output.Append($"overflow: {(list.Count == 0 ? "none" : string.Join(" ", list))}\n");
                break;
            }
            default:
                output.Append($"error: unknown command {t[0]}\n");
                break;
        }
    }

    static void Main()
    {
        CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
        string[] dimensions = Console.ReadLine().Split(' ');
        viewportWidth = int.Parse(dimensions[0], CultureInfo.InvariantCulture);
        viewportHeight = int.Parse(dimensions[1], CultureInfo.InvariantCulture);
        List<Rule> rules = new();
        string line;
        while ((line = Console.ReadLine()) != "---")
        {
            int brace = line.IndexOf(" { ", StringComparison.Ordinal);
            List<Declaration> declarations = new();
            foreach (string raw in line[(brace + 3)..^2].Split("; ", StringSplitOptions.None))
            {
                int colon = raw.IndexOf(": ", StringComparison.Ordinal);
                Dictionary<string, string> values = ParseDeclaration(raw[..colon], raw[(colon + 2)..]);
                if (values != null) foreach (var pair in values) declarations.Add(new Declaration(pair.Key, pair.Value));
            }
            rules.Add(new Rule(line[..brace].Split(", ", StringSplitOptions.None), declarations));
        }
        Element[] ancestors = new Element[11];
        while ((line = Console.ReadLine()) != "===")
        {
            int spaces = 0;
            while (line[spaces] == ' ') spaces++;
            Element element = new() { Depth = spaces / 2, Index = Elements.Count };
            string body = line[spaces..];
            int end = body.IndexOf(' ');
            string head = end < 0 ? body : body[..end];
            if (end >= 0) element.Text = body[(end + 2)..^1];
            string[] parts = head.Split(new[] { '#', '.' });
            element.Type = parts[0];
            element.Id = parts[1];
            element.Classes.AddRange(parts.Skip(2));
            if (element.Depth > 0)
            {
                element.Parent = ancestors[element.Depth - 1];
                element.Parent.Children.Add(element);
            }
            ancestors[element.Depth] = element;
            Elements.Add(element);
            Dictionary<string, int> scores = new();
            foreach (Rule rule in rules)
            {
                int score = -1;
                foreach (string selector in rule.Selectors)
                {
                    if (selector.StartsWith('#') && selector[1..] == element.Id) score = Math.Max(score, 2);
                    else if (selector.StartsWith('.') && element.Classes.Contains(selector[1..])) score = Math.Max(score, 1);
                    else if (selector == element.Type) score = Math.Max(score, 0);
                }
                if (score >= 0) foreach (Declaration declaration in rule.Declarations) if (score >= scores.GetValueOrDefault(declaration.Property, -1))
                {
                    element.Style[declaration.Property] = declaration.Value;
                    scores[declaration.Property] = score;
                }
            }
        }
        Relayout();
        while ((line = Console.ReadLine()) != "END")
        {
            StringBuilder output = new();
            Command(line, output);
            Console.Write(output);
        }
    }
}
