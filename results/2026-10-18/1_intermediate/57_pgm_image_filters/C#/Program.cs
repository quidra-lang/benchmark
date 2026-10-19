using System;
using System.Collections.Generic;
using System.Linq;
using System.Text.RegularExpressions;

readonly record struct Point(int X, int Y);
readonly record struct Command(string Name, int[] Numbers, string Slot, bool Fill);

sealed class CommandError : Exception
{
    public CommandError(string message) : base(message) { }
}

sealed class Image
{
    public int Width { get; }
    public int Height { get; }
    public int Maxval { get; }
    public int[] Pixels { get; }

    public Image(int width, int height, int maxval, int[] pixels)
    {
        Width = width;
        Height = height;
        Maxval = maxval;
        Pixels = pixels;
    }

    public int Get(int x, int y) => Pixels[y * Width + x];
    public bool Contains(int x, int y) => x >= 0 && y >= 0 && x < Width && y < Height;
    public int Clamp(int value) => Math.Clamp(value, 0, Maxval);
    public Image WithPixels(int[] pixels) => new(Width, Height, Maxval, pixels);

    public Image Map(Func<int, int> change) => WithPixels(Pixels.Select(change).ToArray());

    public int[] Neighborhood(int x, int y)
    {
        int[] values = new int[9];
        int index = 0;
        for (int dy = -1; dy <= 1; ++dy)
        {
            for (int dx = -1; dx <= 1; ++dx)
            {
                values[index++] = Get(Math.Clamp(x + dx, 0, Width - 1),
                                      Math.Clamp(y + dy, 0, Height - 1));
            }
        }
        return values;
    }

    public string Summary()
    {
        long checksum = 0;
        for (int i = 0; i < Pixels.Length; ++i) checksum += (long)(i + 1) * Pixels[i];
        return $"{Width}x{Height} maxval {Maxval} checksum {checksum}";
    }
}

static class ImageOperations
{
    public static void Check(bool condition, string reason = "bad value")
    {
        if (!condition) throw new CommandError(reason);
    }

    public static int FloorDivide(int dividend, int divisor)
    {
        int quotient = dividend / divisor;
        return dividend % divisor < 0 ? quotient - 1 : quotient;
    }

    public static Image Load(IReadOnlyList<string> lines)
    {
        List<string> words = new();
        foreach (string line in lines)
        {
            string uncommented = line.Split('#')[0];
            words.AddRange(uncommented.Split(' ', StringSplitOptions.RemoveEmptyEntries));
        }
        Check(words.Count > 0 && words[0] == "P2", "bad magic");

        int Header(int index, int limit, string reason)
        {
            Check(index < words.Count, "truncated header");
            Check(Regex.IsMatch(words[index], @"\A[0-9]+\z"), "bad number");
            int value = int.Parse(words[index]);
            Check(value >= 1 && value <= limit, reason);
            return value;
        }

        int width = Header(1, 64, "bad size");
        int height = Header(2, 64, "bad size");
        int maxval = Header(3, 255, "bad maxval");
        int[] pixels = new int[width * height];
        int count = words.Count - 4;
        for (int i = 0; i < pixels.Length; ++i)
        {
            int x = i % width;
            int y = i / width;
            Check(i < count, $"too few pixels ({count} of {pixels.Length})");
            string word = words[i + 4];
            Check(Regex.IsMatch(word, @"\A[0-9]+\z"), $"bad pixel at {x},{y}");
            int value = int.Parse(word);
            Check(value <= maxval, $"pixel out of range at {x},{y}");
            pixels[i] = value;
        }
        Check(count <= pixels.Length, $"too many pixels ({count} of {pixels.Length})");
        return new Image(width, height, maxval, pixels);
    }

    public static Image Transform(Image source, int width, int height, Func<int, int, int> pixel)
    {
        int[] values = new int[width * height];
        for (int y = 0; y < height; ++y)
            for (int x = 0; x < width; ++x)
                values[y * width + x] = pixel(x, y);
        return new Image(width, height, source.Maxval, values);
    }

    public static Image Crop(Image source, int x, int y, int width, int height) =>
        Transform(source, width, height, (i, j) => source.Get(x + i, y + j));

    public static Image Translate(Image source, int width, int height, int dx, int dy, int fill) =>
        Transform(source, width, height, (x, y) =>
            source.Contains(x - dx, y - dy) ? source.Get(x - dx, y - dy) : fill);

    public static Image Convolve(Image image, int[] weights, int divisor) =>
        Transform(image, image.Width, image.Height, (x, y) =>
        {
            int[] q = image.Neighborhood(x, y);
            int value = 0;
            for (int i = 0; i < 9; ++i) value += q[i] * weights[i];
            return image.Clamp(FloorDivide(value, divisor));
        });

    public static Image Rank(Image image, int index) =>
        Transform(image, image.Width, image.Height, (x, y) =>
        {
            int[] q = image.Neighborhood(x, y);
            Array.Sort(q);
            return q[index];
        });

    public static Image Sobel(Image image) =>
        Transform(image, image.Width, image.Height, (x, y) =>
        {
            int[] q = image.Neighborhood(x, y);
            int gx = q[2] + 2 * q[5] + q[8] - q[0] - 2 * q[3] - q[6];
            int gy = q[6] + 2 * q[7] + q[8] - q[0] - 2 * q[1] - q[2];
            return image.Clamp(Math.Abs(gx) + Math.Abs(gy));
        });

    public static List<Point> Line(int x0, int y0, int x1, int y1)
    {
        int dx = Math.Abs(x1 - x0);
        int dy = -Math.Abs(y1 - y0);
        int sx = x0 < x1 ? 1 : -1;
        int sy = y0 < y1 ? 1 : -1;
        int error = dx + dy;
        int x = x0, y = y0;
        List<Point> points = new();
        while (true)
        {
            points.Add(new Point(x, y));
            if (x == x1 && y == y1) break;
            int twice = 2 * error;
            if (twice >= dy) { error += dy; x += sx; }
            if (twice <= dx) { error += dx; y += sy; }
        }
        return points;
    }

    public static List<Point> Rectangle(Image image, int left, int top, int width, int height, bool fill)
    {
        int right = left + width - 1;
        int bottom = top + height - 1;
        List<Point> points = new();
        for (int y = Math.Max(top, 0); y <= Math.Min(bottom, image.Height - 1); ++y)
        {
            for (int x = Math.Max(left, 0); x <= Math.Min(right, image.Width - 1); ++x)
            {
                if (fill || x == left || x == right || y == top || y == bottom)
                    points.Add(new Point(x, y));
            }
        }
        return points;
    }

    public static List<Point> Circle(int cx, int cy, int radius)
    {
        int a = radius, b = 0, error = 1 - radius;
        List<Point> points = new();
        while (a >= b)
        {
            points.AddRange(new[]
            {
                new Point(cx + a, cy + b), new Point(cx + b, cy + a),
                new Point(cx - b, cy + a), new Point(cx - a, cy + b),
                new Point(cx - a, cy - b), new Point(cx - b, cy - a),
                new Point(cx + b, cy - a), new Point(cx + a, cy - b)
            });
            ++b;
            if (error < 0) error += 2 * b + 1;
            else { --a; error += 2 * (b - a) + 1; }
        }
        return points;
    }

    public static List<Point> Disc(Image image, IEnumerable<Point> outline)
    {
        Dictionary<int, (int Left, int Right)> rows = new();
        foreach (Point point in outline)
        {
            if (rows.TryGetValue(point.Y, out var limits))
                rows[point.Y] = (Math.Min(limits.Left, point.X), Math.Max(limits.Right, point.X));
            else rows[point.Y] = (point.X, point.X);
        }

        List<Point> points = new();
        foreach (var row in rows)
        {
            int y = row.Key;
            if (y < 0 || y >= image.Height) continue;
            for (int x = Math.Max(row.Value.Left, 0); x <= Math.Min(row.Value.Right, image.Width - 1); ++x)
                points.Add(new Point(x, y));
        }
        return points;
    }

    public static readonly Point[] Neighbors4 =
    {
        new(0, -1), new(-1, 0), new(1, 0), new(0, 1)
    };

    public static readonly Point[] Neighbors8 =
    {
        new(-1, -1), new(0, -1), new(1, -1), new(-1, 0),
        new(1, 0), new(-1, 1), new(0, 1), new(1, 1)
    };

    public static List<Point> Flood(Image image, int x, int y)
    {
        int target = image.Get(x, y);
        Stack<Point> stack = new();
        HashSet<int> seen = new();
        stack.Push(new Point(x, y));
        seen.Add(y * image.Width + x);
        List<Point> points = new();
        while (stack.Count > 0)
        {
            Point p = stack.Pop();
            points.Add(p);
            foreach (Point delta in Neighbors4)
            {
                int nx = p.X + delta.X, ny = p.Y + delta.Y;
                if (!image.Contains(nx, ny) || image.Get(nx, ny) != target) continue;
                if (seen.Add(ny * image.Width + nx)) stack.Push(new Point(nx, ny));
            }
        }
        return points;
    }

    public static Image Equalize(Image image)
    {
        int[] counts = new int[image.Maxval + 1];
        foreach (int pixel in image.Pixels) ++counts[pixel];
        int[] cdf = new int[counts.Length];
        int running = 0;
        for (int i = 0; i < counts.Length; ++i)
        {
            running += counts[i];
            cdf[i] = running;
        }
        int n = image.Pixels.Length;
        int first = cdf[image.Pixels.Min()];
        if (first == n) return image.WithPixels((int[])image.Pixels.Clone());
        int span = n - first;
        return image.Map(p => (2 * (cdf[p] - first) * image.Maxval + span) / (2 * span));
    }

    public static List<List<Point>> Components(Image image, int threshold)
    {
        HashSet<int> visited = new();
        List<List<Point>> groups = new();
        for (int start = 0; start < image.Pixels.Length; ++start)
        {
            if (visited.Contains(start) || image.Pixels[start] < threshold) continue;
            visited.Add(start);
            Stack<Point> stack = new();
            stack.Push(new Point(start % image.Width, start / image.Width));
            List<Point> group = new();
            while (stack.Count > 0)
            {
                Point p = stack.Pop();
                group.Add(p);
                foreach (Point delta in Neighbors8)
                {
                    int nx = p.X + delta.X, ny = p.Y + delta.Y;
                    if (!image.Contains(nx, ny)) continue;
                    int index = ny * image.Width + nx;
                    if (image.Pixels[index] >= threshold && visited.Add(index))
                        stack.Push(new Point(nx, ny));
                }
            }
            groups.Add(group);
        }
        return groups;
    }

    public static string ComponentDescription(Image image, int threshold, List<Point> group)
    {
        int left = group.Min(p => p.X), top = group.Min(p => p.Y);
        int right = group.Max(p => p.X), bottom = group.Max(p => p.Y);
        int perimeter = 0;
        foreach (Point point in group)
        {
            if (Neighbors4.Any(delta => !image.Contains(point.X + delta.X, point.Y + delta.Y) ||
                                        image.Get(point.X + delta.X, point.Y + delta.Y) < threshold))
                ++perimeter;
        }
        int count = group.Count;
        return $"area {count} perimeter {perimeter} box {left} {top} {right} {bottom} " +
               $"center {group.Sum(p => p.X) / count} {group.Sum(p => p.Y) / count}";
    }

    public static Image Distance(Image image, int threshold)
    {
        if (image.Pixels.All(pixel => pixel >= threshold))
            return image.WithPixels(Enumerable.Repeat(image.Maxval, image.Pixels.Length).ToArray());
        int width = image.Width, height = image.Height, far = width + height;
        int[] distances = image.Pixels.Select(p => p < threshold ? 0 : far).ToArray();
        for (int y = 0; y < height; ++y)
        {
            for (int x = 0; x < width; ++x)
            {
                int index = y * width + x;
                if (x > 0) distances[index] = Math.Min(distances[index], distances[index - 1] + 1);
                if (y > 0) distances[index] = Math.Min(distances[index], distances[index - width] + 1);
            }
        }
        for (int y = height - 1; y >= 0; --y)
        {
            for (int x = width - 1; x >= 0; --x)
            {
                int index = y * width + x;
                if (x < width - 1) distances[index] = Math.Min(distances[index], distances[index + 1] + 1);
                if (y < height - 1) distances[index] = Math.Min(distances[index], distances[index + width] + 1);
            }
        }
        return image.WithPixels(distances.Select(v => Math.Min(v, image.Maxval)).ToArray());
    }

    public static string Statistics(int[] pixels, int maxval)
    {
        int[] sorted = pixels.OrderBy(v => v).ToArray();
        int[] counts = new int[maxval + 1];
        foreach (int pixel in pixels) ++counts[pixel];
        int mode = 0;
        for (int i = 1; i <= maxval; ++i)
            if (counts[i] > counts[mode]) mode = i;
        return $"min {sorted[0]} max {sorted[^1]} mean {pixels.Sum() / pixels.Length} " +
               $"median {sorted[(pixels.Length - 1) / 2]} mode {mode}";
    }

    public static Image Dither(Image image)
    {
        int width = image.Width, height = image.Height;
        int[] errors = (int[])image.Pixels.Clone();
        int[] pixels = new int[errors.Length];
        var diffusion = new (int Dx, int Dy, int Weight)[]
        {
            (1, 0, 7), (-1, 1, 3), (0, 1, 5), (1, 1, 1)
        };
        for (int y = 0; y < height; ++y)
        {
            for (int x = 0; x < width; ++x)
            {
                int index = y * width + x;
                int old = errors[index];
                int value = 2 * old >= image.Maxval ? image.Maxval : 0;
                pixels[index] = value;
                int error = old - value;
                foreach (var (dx, dy, weight) in diffusion)
                {
                    if (image.Contains(x + dx, y + dy))
                        errors[(y + dy) * width + x + dx] += FloorDivide(error * weight, 16);
                }
            }
        }
        return image.WithPixels(pixels);
    }
}

sealed class Editor
{
    private static readonly Dictionary<string, string> Patterns = new()
    {
        ["NEW"] = "iiii", ["OUTPUT"] = "", ["INVERT"] = "",
        ["BRIGHTNESS"] = "i", ["CONTRAST"] = "ii", ["THRESHOLD"] = "i",
        ["LEVELS"] = "ii", ["POSTERIZE"] = "i", ["MAXVAL"] = "i",
        ["FLIPH"] = "", ["FLIPV"] = "", ["ROTATE"] = "i",
        ["CROP"] = "iiii", ["PAD"] = "ii", ["SCALE"] = "ii",
        ["SHIFT"] = "iii", ["TILE"] = "ii", ["BLUR"] = "",
        ["GAUSS"] = "", ["SHARPEN"] = "", ["CONVOLVE"] = "iiiiiiiiii",
        ["SOBEL"] = "", ["MEDIAN"] = "", ["ERODE"] = "",
        ["DILATE"] = "", ["OPEN"] = "", ["CLOSE"] = "",
        ["GRADIENT"] = "", ["LINE"] = "iiiii", ["RECT"] = "iiiii",
        ["CIRCLE"] = "iiii", ["FLOOD"] = "iii", ["HISTOGRAM"] = "",
        ["EQUALIZE"] = "", ["LABEL"] = "i", ["DISTANCE"] = "i",
        ["STATS"] = "", ["REGION"] = "iiii", ["DITHER"] = "",
        ["ASCIIART"] = "", ["STORE"] = "n", ["RECALL"] = "n",
        ["DROP"] = "n", ["BLEND"] = "nii", ["DIFF"] = "n",
        ["PASTE"] = "nii", ["SLOTS"] = "", ["INFO"] = "",
        ["UNDO"] = "", ["REDO"] = ""
    };

    private static readonly HashSet<string> Imageless = new()
    {
        "NEW", "RECALL", "DROP", "SLOTS", "INFO", "UNDO", "REDO"
    };

    private static readonly HashSet<string> NeedsSlot = new()
    {
        "RECALL", "DROP", "BLEND", "DIFF", "PASTE"
    };

    private static readonly Dictionary<string, (int[] Weights, int Divisor)> Kernels = new()
    {
        ["BLUR"] = (new[] { 1, 1, 1, 1, 1, 1, 1, 1, 1 }, 9),
        ["GAUSS"] = (new[] { 1, 2, 1, 2, 4, 2, 1, 2, 1 }, 16),
        ["SHARPEN"] = (new[] { 0, -1, 0, -1, 5, -1, 0, -1, 0 }, 1)
    };

    private Image? current;
    private readonly Stack<Image> undo = new();
    private readonly Stack<Image> redo = new();
    private readonly Dictionary<string, Image> slots = new(StringComparer.Ordinal);
    public List<string> Output { get; } = new();

    private void Emit(string line) => Output.Add(line);

    private static Command Parse(string[] words)
    {
        string name = words[0];
        ImageOperations.Check(Patterns.TryGetValue(name, out string? pattern), $"unknown command {name}");
        string[] given = words.Skip(1).ToArray();
        bool fill = (name == "RECT" || name == "CIRCLE") &&
                    given.Length == pattern!.Length + 1 && given[^1] == "FILL";
        if (fill) given = given[..^1];
        ImageOperations.Check(given.Length == pattern!.Length, "bad arguments");
        List<int> numbers = new();
        string slot = "";
        for (int i = 0; i < given.Length; ++i)
        {
            if (pattern[i] == 'i')
            {
                ImageOperations.Check(Regex.IsMatch(given[i], @"\A(?:0|-?[1-9][0-9]{0,6})\z"), "bad arguments");
                numbers.Add(int.Parse(given[i]));
            }
            else
            {
                ImageOperations.Check(Regex.IsMatch(given[i], @"\A[a-z]{1,8}\z"), "bad arguments");
                slot = given[i];
            }
        }
        return new Command(name, numbers.ToArray(), slot, fill);
    }

    public void Execute(string[] words)
    {
        try
        {
            Command cmd = Parse(words);
            if (!Imageless.Contains(cmd.Name)) ImageOperations.Check(current != null, "no image");
            if (NeedsSlot.Contains(cmd.Name))
                ImageOperations.Check(slots.ContainsKey(cmd.Slot), $"no slot {cmd.Slot}");
            Run(cmd);
        }
        catch (CommandError error)
        {
            Emit("error: " + error.Message);
        }
    }

    public void Load(IReadOnlyList<string> lines)
    {
        try { Replace(ImageOperations.Load(lines), "loaded"); }
        catch (CommandError error) { Emit("error: load: " + error.Message); }
    }

    private void Replace(Image image, string label)
    {
        current = image;
        undo.Clear();
        redo.Clear();
        Emit(label + " " + image.Summary());
    }

    private void Commit(Image image, int? painted = null)
    {
        undo.Push(current!);
        redo.Clear();
        current = image;
        Emit("ok " + image.Summary() + (painted.HasValue ? $" painted {painted}" : ""));
    }

    private void Paint(IEnumerable<Point> points, int value)
    {
        Image image = current!;
        HashSet<int> painted = new();
        foreach (Point point in points)
            if (image.Contains(point.X, point.Y))
                painted.Add(point.Y * image.Width + point.X);
        int[] pixels = image.Pixels.Select((p, i) => painted.Contains(i) ? value : p).ToArray();
        Commit(image.WithPixels(pixels), painted.Count);
    }

    private int[] CropArea(int[] args)
    {
        var (x, y, width, height) = (args[0], args[1], args[2], args[3]);
        Image image = current!;
        ImageOperations.Check(x >= 0 && y >= 0 && width >= 1 && height >= 1 &&
                              x + width <= image.Width && y + height <= image.Height);
        return args;
    }

    private Image MatchingSlot(string name)
    {
        Image saved = slots[name];
        Image image = current!;
        ImageOperations.Check(image.Width == saved.Width && image.Height == saved.Height, "size mismatch");
        ImageOperations.Check(image.Maxval == saved.Maxval, "maxval mismatch");
        return saved;
    }

    private static bool WithinLimit(params int[] numbers) => numbers.All(n => n >= -1000 && n <= 1000);

    private void Run(Command command)
    {
        string name = command.Name, slot = command.Slot;
        int[] a = command.Numbers;
        bool fill = command.Fill;
        Image image = current!;
        int width = image?.Width ?? 0, height = image?.Height ?? 0, m = image?.Maxval ?? 0;

        switch (name)
        {
            case "NEW":
            {
                var (w, h, maxval, v) = (a[0], a[1], a[2], a[3]);
                ImageOperations.Check(w >= 1 && w <= 64 && h >= 1 && h <= 64);
                ImageOperations.Check(maxval >= 1 && maxval <= 255 && v >= 0 && v <= maxval);
                Replace(new Image(w, h, maxval, Enumerable.Repeat(v, w * h).ToArray()), "created");
                break;
            }
            case "OUTPUT":
                Emit("P2");
                Emit($"{width} {height}");
                Emit(m.ToString());
                for (int y = 0; y < height; ++y)
                    Emit(string.Join(" ", Enumerable.Range(0, width).Select(x => image.Get(x, y))));
                break;
            case "INVERT":
                Commit(image.Map(p => m - p));
                break;
            case "BRIGHTNESS":
                ImageOperations.Check(a[0] >= -255 && a[0] <= 255);
                Commit(image.Map(p => image.Clamp(p + a[0])));
                break;
            case "CONTRAST":
            {
                var (num, den) = (a[0], a[1]);
                ImageOperations.Check(num >= 0 && num <= 100 && den >= 1 && den <= 100);
                int center = (m + 1) / 2;
                Commit(image.Map(p => image.Clamp(center + ImageOperations.FloorDivide((p - center) * num, den))));
                break;
            }
            case "THRESHOLD":
                ImageOperations.Check(a[0] >= 0 && a[0] <= m);
                Commit(image.Map(p => p >= a[0] ? m : 0));
                break;
            case "LEVELS":
            {
                var (low, high) = (a[0], a[1]);
                ImageOperations.Check(low >= 0 && low < high && high <= m);
                Commit(image.Map(p => image.Clamp(ImageOperations.FloorDivide((p - low) * m, high - low))));
                break;
            }
            case "POSTERIZE":
            {
                int levels = a[0];
                ImageOperations.Check(levels >= 2 && levels <= m + 1);
                Commit(image.Map(p => ((p * levels) / (m + 1)) * m / (levels - 1)));
                break;
            }
            case "MAXVAL":
            {
                int maxval = a[0];
                ImageOperations.Check(maxval >= 1 && maxval <= 255);
                Commit(new Image(width, height, maxval,
                    image.Pixels.Select(p => (2 * p * maxval + m) / (2 * m)).ToArray()));
                break;
            }
            case "FLIPH":
                Commit(ImageOperations.Transform(image, width, height, (x, y) => image.Get(width - 1 - x, y)));
                break;
            case "FLIPV":
                Commit(ImageOperations.Transform(image, width, height, (x, y) => image.Get(x, height - 1 - y)));
                break;
            case "ROTATE":
            {
                int angle = a[0];
                ImageOperations.Check(angle == 90 || angle == 180 || angle == 270);
                if (angle == 180)
                    Commit(ImageOperations.Transform(image, width, height,
                        (x, y) => image.Get(width - 1 - x, height - 1 - y)));
                else if (angle == 90)
                    Commit(ImageOperations.Transform(image, height, width,
                        (x, y) => image.Get(y, height - 1 - x)));
                else
                    Commit(ImageOperations.Transform(image, height, width,
                        (x, y) => image.Get(width - 1 - y, x)));
                break;
            }
            case "CROP":
            {
                int[] area = CropArea(a);
                Commit(ImageOperations.Crop(image, area[0], area[1], area[2], area[3]));
                break;
            }
            case "PAD":
            {
                var (border, value) = (a[0], a[1]);
                ImageOperations.Check(border >= 1 && value >= 0 && value <= m);
                ImageOperations.Check(width + 2 * border <= 64 && height + 2 * border <= 64, "too large");
                Commit(ImageOperations.Translate(image, width + 2 * border, height + 2 * border,
                                                 border, border, value));
                break;
            }
            case "SCALE":
            {
                var (num, den) = (a[0], a[1]);
                ImageOperations.Check(num >= 1 && num <= 16 && den >= 1 && den <= 16);
                int w = width * num / den, h = height * num / den;
                ImageOperations.Check(w > 0 && h > 0, "too small");
                ImageOperations.Check(w <= 64 && h <= 64, "too large");
                Commit(ImageOperations.Transform(image, w, h, (x, y) =>
                    image.Get(((2 * x + 1) * den) / (2 * num),
                              ((2 * y + 1) * den) / (2 * num))));
                break;
            }
            case "SHIFT":
                ImageOperations.Check(WithinLimit(a[0], a[1]) && a[2] >= 0 && a[2] <= m);
                Commit(ImageOperations.Translate(image, width, height, a[0], a[1], a[2]));
                break;
            case "TILE":
            {
                var (nx, ny) = (a[0], a[1]);
                ImageOperations.Check(nx >= 1 && ny >= 1);
                ImageOperations.Check(width * nx <= 64 && height * ny <= 64, "too large");
                Commit(ImageOperations.Transform(image, width * nx, height * ny,
                    (x, y) => image.Get(x % width, y % height)));
                break;
            }
            case "BLUR":
            case "GAUSS":
            case "SHARPEN":
            {
                var kernel = Kernels[name];
                Commit(ImageOperations.Convolve(image, kernel.Weights, kernel.Divisor));
                break;
            }
            case "CONVOLVE":
                ImageOperations.Check(a.Take(9).All(v => v >= -16 && v <= 16) && a[9] >= 1 && a[9] <= 256);
                Commit(ImageOperations.Convolve(image, a[..9], a[9]));
                break;
            case "SOBEL":
                Commit(ImageOperations.Sobel(image));
                break;
            case "MEDIAN":
                Commit(ImageOperations.Rank(image, 4));
                break;
            case "ERODE":
                Commit(ImageOperations.Rank(image, 0));
                break;
            case "DILATE":
                Commit(ImageOperations.Rank(image, 8));
                break;
            case "OPEN":
                Commit(ImageOperations.Rank(ImageOperations.Rank(image, 0), 8));
                break;
            case "CLOSE":
                Commit(ImageOperations.Rank(ImageOperations.Rank(image, 8), 0));
                break;
            case "GRADIENT":
            {
                int[] high = ImageOperations.Rank(image, 8).Pixels;
                int[] low = ImageOperations.Rank(image, 0).Pixels;
                Commit(image.WithPixels(high.Select((p, i) => p - low[i]).ToArray()));
                break;
            }
            case "LINE":
                ImageOperations.Check(WithinLimit(a[..4]) && a[4] >= 0 && a[4] <= m);
                Paint(ImageOperations.Line(a[0], a[1], a[2], a[3]), a[4]);
                break;
            case "RECT":
                ImageOperations.Check(WithinLimit(a[0], a[1]) && a[2] >= 1 && a[2] <= 1000 &&
                                      a[3] >= 1 && a[3] <= 1000 && a[4] >= 0 && a[4] <= m);
                Paint(ImageOperations.Rectangle(image, a[0], a[1], a[2], a[3], fill), a[4]);
                break;
            case "CIRCLE":
                ImageOperations.Check(WithinLimit(a[0], a[1]) && a[2] >= 0 && a[2] <= 1000 &&
                                      a[3] >= 0 && a[3] <= m);
                List<Point> outline = ImageOperations.Circle(a[0], a[1], a[2]);
                Paint(fill ? ImageOperations.Disc(image, outline) : outline, a[3]);
                break;
            case "FLOOD":
                ImageOperations.Check(image.Contains(a[0], a[1]) && a[2] >= 0 && a[2] <= m);
                Paint(ImageOperations.Flood(image, a[0], a[1]), a[2]);
                break;
            case "HISTOGRAM":
            {
                int?[] lows = new int?[16];
                int[] highs = new int[16], counts = new int[16];
                for (int value = 0; value <= m; ++value)
                {
                    int bin = value * 16 / (m + 1);
                    lows[bin] ??= value;
                    highs[bin] = value;
                }
                foreach (int pixel in image.Pixels) ++counts[pixel * 16 / (m + 1)];
                int top = counts.Max();
                for (int bin = 0; bin < 16; ++bin)
                {
                    if (lows[bin] == null) continue;
                    Emit($"{lows[bin],3}-{highs[bin],3} {counts[bin],4} |" +
                         new string('#', counts[bin] * 32 / top));
                }
                break;
            }
            case "EQUALIZE":
                Commit(ImageOperations.Equalize(image));
                break;
            case "LABEL":
            {
                ImageOperations.Check(a[0] >= 0 && a[0] <= m);
                var groups = ImageOperations.Components(image, a[0]);
                Emit("labels " + groups.Count);
                for (int i = 0; i < groups.Count; ++i)
                    Emit($"label {i + 1} " + ImageOperations.ComponentDescription(image, a[0], groups[i]));
                break;
            }
            case "DISTANCE":
                ImageOperations.Check(a[0] >= 0 && a[0] <= m);
                Commit(ImageOperations.Distance(image, a[0]));
                break;
            case "STATS":
                Emit(ImageOperations.Statistics(image.Pixels, m));
                break;
            case "REGION":
            {
                int[] area = CropArea(a);
                Emit(ImageOperations.Statistics(
                    ImageOperations.Crop(image, area[0], area[1], area[2], area[3]).Pixels, m));
                break;
            }
            case "DITHER":
                Commit(ImageOperations.Dither(image));
                break;
            case "ASCIIART":
            {
                const string shades = "@#*+=~-:,.";
                for (int y = 0; y < height; ++y)
                {
                    char[] row = new char[width];
                    for (int x = 0; x < width; ++x)
                        row[x] = shades[image.Get(x, y) * 10 / (m + 1)];
                    Emit(new string(row));
                }
                break;
            }
            case "STORE":
                slots[slot] = image;
                Emit($"stored {slot} {image.Summary()}");
                break;
            case "RECALL":
                Replace(slots[slot], "recalled " + slot);
                break;
            case "DROP":
                slots.Remove(slot);
                Emit("dropped " + slot);
                break;
            case "BLEND":
            {
                var (num, den) = (a[0], a[1]);
                ImageOperations.Check(num >= 0 && num <= den && den >= 1 && den <= 100);
                Image saved = MatchingSlot(slot);
                Commit(image.WithPixels(image.Pixels.Select((p, i) =>
                    (p * (den - num) + saved.Pixels[i] * num) / den).ToArray()));
                break;
            }
            case "DIFF":
            {
                Image saved = MatchingSlot(slot);
                Commit(image.WithPixels(image.Pixels.Select((p, i) => Math.Abs(p - saved.Pixels[i])).ToArray()));
                break;
            }
            case "PASTE":
            {
                var (x, y) = (a[0], a[1]);
                ImageOperations.Check(WithinLimit(x, y));
                Image saved = slots[slot];
                ImageOperations.Check(saved.Maxval == m, "maxval mismatch");
                int[] pixels = (int[])image.Pixels.Clone();
                int painted = 0;
                for (int j = 0; j < saved.Height; ++j)
                {
                    for (int i = 0; i < saved.Width; ++i)
                    {
                        if (!image.Contains(x + i, y + j)) continue;
                        pixels[(y + j) * width + x + i] = saved.Get(i, j);
                        ++painted;
                    }
                }
                Commit(image.WithPixels(pixels), painted);
                break;
            }
            case "SLOTS":
                if (slots.Count == 0) Emit("no slots");
                foreach (string key in slots.Keys.OrderBy(v => v, StringComparer.Ordinal))
                    Emit($"{key} {slots[key].Summary()}");
                break;
            case "INFO":
                Emit($"image {(image == null ? "none" : image.Summary())} undo {undo.Count} " +
                     $"redo {redo.Count} slots {slots.Count}");
                break;
            case "UNDO":
                ImageOperations.Check(undo.Count > 0, "nothing to undo");
                redo.Push(current!);
                current = undo.Pop();
                Emit("undo " + current.Summary());
                break;
            case "REDO":
                ImageOperations.Check(redo.Count > 0, "nothing to redo");
                undo.Push(current!);
                current = redo.Pop();
                Emit("redo " + current.Summary());
                break;
        }
    }
}

static class Program
{
    static void Main()
    {
        int commands = int.Parse(Console.ReadLine()!);
        Editor editor = new();
        for (int i = 0; i < commands; ++i)
        {
            string[] words = Console.ReadLine()!.Split(' ');
            if (words[0] == "LOAD")
            {
                int count = int.Parse(words[1]);
                List<string> lines = new();
                for (int j = 0; j < count; ++j) lines.Add(Console.ReadLine()!);
                editor.Load(lines);
            }
            else
            {
                editor.Execute(words);
            }
        }
        foreach (string line in editor.Output) Console.WriteLine(line);
    }
}
