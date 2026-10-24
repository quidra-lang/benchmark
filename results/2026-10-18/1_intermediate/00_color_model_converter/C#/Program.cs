using System;
using System.Collections.Generic;
using System.Linq;
using System.Globalization;
using System.Text.RegularExpressions;

class Program {
    record Entry(string Name, int[] Color);
    record Cluster(int[] Color, int Count);
    class Invalid : Exception {}
    static readonly string[] NAMES = {
        "black", "maroon", "green", "olive", "navy", "purple", "teal", "silver",
        "gray", "red", "lime", "yellow", "blue", "magenta", "cyan", "white",
        "orange", "pink", "brown", "gold", "coral", "salmon", "violet", "indigo"
    };
    static readonly int[] RGB = {
        0x000000, 0x800000, 0x008000, 0x808000, 0x000080, 0x800080, 0x008080, 0xC0C0C0,
        0x808080, 0xFF0000, 0x00FF00, 0xFFFF00, 0x0000FF, 0xFF00FF, 0x00FFFF, 0xFFFFFF,
        0xFFA500, 0xFFC0CB, 0xA52A2A, 0xFFD700, 0xFF7F50, 0xFA8072, 0xEE82EE, 0x4B0082
    };
    static readonly Regex INTEGER = new(@"\A-?[0-9]{1,9}\z");
    static readonly Regex NAME = new(@"\A[a-z]{1,12}\z");
    static readonly Regex HEX = new(@"\A#[0-9a-fA-F]{3}(?:[0-9a-fA-F]{3})?\z");
    static readonly Regex RGB_TEXT = new(@"\Argb\(([0-9]{1,3}),([0-9]{1,3}),([0-9]{1,3})\)\z");
    readonly List<Entry> registered = new();

    static void Require(bool condition) {
        if (!condition) throw new Invalid();
    }
    static void Arity(string[] tokens, int count) {
        Require(tokens.Length == count + 1);
    }
    static int Number(string text, int low, int high) {
        Require(INTEGER.IsMatch(text));
        int value = int.Parse(text,CultureInfo.InvariantCulture);
        Require(value >= low && value <= high);
        return value;
    }
    static int Round(long numerator, long denominator) {
        return (int)Floor(2 * numerator + denominator, 2 * denominator);
    }
    static int Away(long numerator, long denominator) {
        return numerator < 0 ? -Round(-numerator, denominator) : Round(numerator, denominator);
    }
    static int Percent(long a, long b) {
        return Round(100 * a, b);
    }
    static int Mod(int value, int modulus) {
        return (value % modulus + modulus) % modulus;
    }
    static int Clamp(int value) {
        return Math.Clamp(value, 0, 255);
    }
    static int Root(long numerator, long scale) {
        long value = numerator / scale;
        long low = 0, high = value + 1;
        while (low + 1 < high) {
            long middle = (low + high) / 2;
            if (middle * middle <= value) low = middle;
            else high = middle;
        }
        return (int)low;
    }
    static int[] Unpack(int value) {
        return new int[]{value >> 16, value >> 8 & 255, value & 255};
    }
    static string Hex(int[] color) {
        return string.Format(CultureInfo.InvariantCulture,"#{0:X2}{1:X2}{2:X2}",color[0],color[1],color[2]);
    }
    List<Entry> Table() {
        return NAMES.Select((name, i) => new Entry(name, Unpack(RGB[i]))).Concat(registered).ToList();
    }
    int[] Color(string text) {
        if (HEX.IsMatch(text)) {
            string digits = text.Substring(1);
            if (digits.Length == 3) {
                digits = "" + digits[0] + digits[0] + digits[1] + digits[1]
                    + digits[2] + digits[2];
            }
            return Unpack(int.Parse(digits,NumberStyles.HexNumber,CultureInfo.InvariantCulture));
        }
        Match matcher = RGB_TEXT.Match(text);
        if (matcher.Success) {
            int[] result = Enumerable.Range(1, 3).Select(i => int.Parse(matcher.Groups[i].Value, CultureInfo.InvariantCulture)).ToArray();
            Require(result.All(value => value <= 255));
            return result;
        }
        return Table().FirstOrDefault(entry => entry.Name == text)?.Color ?? throw new Invalid();
    }
    static int Hue(int[] c) {
        int maximum = c.Max(), difference = maximum - c.Min();
        if (difference == 0) return 0;
        long numerator;
        if (maximum == c[0]) {
            numerator = 60L * (c[1] - c[2]);
            if (numerator < 0) numerator += 360L * difference;
        } else if (maximum == c[1]) numerator = 60L * (c[2] - c[0]) + 120L * difference;
        else numerator = 60L * (c[0] - c[1]) + 240L * difference;
        return Round(numerator, difference) % 360;
    }
    static int[] Hsl(int[] c) {
        int maximum = c.Max(), minimum = c.Min(), difference = maximum - minimum;
        int saturation = difference == 0 ? 0 : Percent(difference, 255 - Math.Abs(maximum + minimum - 255));
        return new int[]{Hue(c), saturation, Percent(maximum + minimum, 510)};
    }
    static int[] FromHue(int h, long chroma, long offset, long denominator) {
        int sector = h / 60, f = h % 60;
        int x = sector % 2 == 0 ? f : 60 - f;
        int[][] factors = {new[]{60,x,0},new[]{x,60,0},new[]{0,60,x},new[]{0,x,60},new[]{x,0,60},new[]{60,0,x}};
        int[] result = new int[3];
        for (int i = 0; i < 3; i++) result[i] = Round(255 * (chroma * factors[sector][i] + 60 * offset), 60 * denominator);
        return result;
    }
    static int[] FromHsl(int h, int s, int l) {
        long c = (100 - Math.Abs(2 * l - 100)) * s;
        return FromHue(h, 2 * c, 200L * l - c, 20000);
    }
    static long Distance(int[] a, int[] b) {
        long result = 0;
        for (int i = 0; i < 3; i++) result += (long)(a[i] - b[i]) * (a[i] - b[i]);
        return result;
    }
    static string Model(string command, int[] c) {
        int r = c[0], g = c[1], b = c[2], m = c.Max(), n = c.Min(), d = m - n;
        int[] v = Hsl(c);
        return command switch {
            "HSL" => "hsl(" + v[0] + "," + v[1] + "%," + v[2] + "%)",
            "HSV" => "hsv(" + Hue(c) + "," + (m == 0 ? 0 : Percent(d,m)) + "%," + Percent(m,255) + "%)",
            "HWB" => "hwb(" + Hue(c) + "," + Percent(n,255) + "%," + Percent(255 - m,255) + "%)",
            "CMYK" => m == 0 ? "cmyk(0%,0%,0%,100%)" :
                "cmyk(" + Percent(m-r,m) + "%," + Percent(m-g,m) + "%," + Percent(m-b,m) + "%," + Percent(255-m,255) + "%)",
            "YCBCR" => "ycbcr(" + Clamp(Round(299L*r+587L*g+114L*b,1000)) + "," +
                Clamp(Round(128000L-169L*r-331L*g+500L*b,1000)) + "," + Clamp(Round(128000L+500L*r-419L*g-81L*b,1000)) + ")",
            "YIQ" => "yiq(" + Round(299L*r+587L*g+114L*b,1000) + "," +
                Round(596L*r-274L*g-322L*b,1000) + "," + Round(211L*r-523L*g+312L*b,1000) + ")",
            _ => throw new Invalid(),
        };
    }
    static int[] Ansi(int number) {
        if (number < 16) return Unpack(RGB[number]);
        if (number >= 232) {
            int value = 8 + 10 * (number - 232);
            return new int[]{value, value, value};
        }
        int[] values = {0,95,135,175,215,255};
        int v = number - 16;
        return new int[]{values[v / 36], values[v / 6 % 6], values[v % 6]};
    }
    static int[] Gradient(int[] a, int[] b, int index, int denominator) {
        int[] result = new int[3];
        for (int i = 0; i < 3; i++) result[i] = a[i] + Away((long)(b[i] - a[i]) * index, denominator);
        return result;
    }
    static long Luminance(int[] c) {
        return 2126L*c[0]*c[0] + 7152L*c[1]*c[1] + 722L*c[2]*c[2];
    }
    static long[] Contrast(int[] a, int[] b) {
        long first = Luminance(a), second = Luminance(b);
        return new long[]{Math.Max(first,second) + 32512500, Math.Min(first,second) + 32512500};
    }
    static int Ratio(int[] a, int[] b) {
        long[] values = Contrast(a,b);
        return Round(100 * values[0], values[1]);
    }
    static bool Readable(int[] a, int[] b) {
        long[] values = Contrast(a,b);
        return 2 * values[0] >= 9 * values[1];
    }
    static string ContrastText(int[] a, int[] b) {
        long[] values = Contrast(a,b);
        int ratio = Round(100 * values[0], values[1]);
        string verdict = values[0] >= 7 * values[1] ? "AAA" : 2 * values[0] >= 9 * values[1] ? "AA" : "FAIL";
        return $"{ratio / 100}.{ratio % 100:D2} {verdict}";
    }
    static int BlendComponent(string mode, int x, int y) {
        int multiply = x * y / 255, screen = 255 - (255-x)*(255-y)/255;
        return mode switch {
            "MULTIPLY" => multiply,
            "SCREEN" => screen,
            "OVERLAY" => x < 128 ? 2*x*y/255 : 255-2*(255-x)*(255-y)/255,
            "HARDLIGHT" => y < 128 ? 2*x*y/255 : 255-2*(255-x)*(255-y)/255,
            "SOFTLIGHT" => ((255-x)*multiply+x*screen)/255,
            "DARKEN" => Math.Min(x,y),
            "LIGHTEN" => Math.Max(x,y),
            "DIFFERENCE" => Math.Abs(x-y),
            "EXCLUSION" => x+y-2*x*y/255,
            "ADD" => Math.Min(255,x+y),
            "SUBTRACT" => Math.Max(0,x-y),
            "COLORDODGE" => y == 255 ? 255 : Math.Min(255,255*x/(255-y)),
            "COLORBURN" => y == 0 ? 0 : Math.Max(0,255-255*(255-x)/y),
            _ => throw new Invalid(),
        };
    }
    static int[] Blend(string mode, int[] baseColor, int[] top) {
        if (new[]{"HUE","SATURATION","COLOR","LUMINOSITY"}.Contains(mode)) {
            int[] a = Hsl(baseColor), b = Hsl(top);
            return FromHsl(mode.Equals("HUE") || mode.Equals("COLOR") ? b[0] : a[0],
                mode.Equals("SATURATION") || mode.Equals("COLOR") ? b[1] : a[1], mode.Equals("LUMINOSITY") ? b[2] : a[2]);
        }
        int[] result = new int[3];
        for (int i = 0; i < 3; i++) result[i] = BlendComponent(mode,baseColor[i],top[i]);
        return result;
    }
    static int[] Mean(List<int[]> colors) {
        int[] result = new int[3];
        for (int component = 0; component < 3; component++) {
            result[component] = Round(colors.Sum(color => color[component]), colors.Count);
        }
        return result;
    }
    static int[] Ranges(List<int[]> colors) {
        return Enumerable.Range(0, 3).Select(i => colors.Max(color => color[i]) - colors.Min(color => color[i])).ToArray();
    }
    static List<Cluster> Palette(int k, List<int[]> colors) {
        List<List<int[]>> boxes = new();
        boxes.Add(new(colors));
        while (boxes.Count < k) {
            int selected = Enumerable.Range(0, boxes.Count).Where(i => boxes[i].Count > 1)
                .MaxBy(i => Ranges(boxes[i]).Max());
            List<int[]> box = boxes[selected];
            int[] ranges = Ranges(box);
            int component = Array.IndexOf(ranges, ranges.Max());
            box = box.OrderBy(c => c[component]).ToList();
            int middle = box.Count / 2;
            boxes[selected] = box.GetRange(0,middle);
            boxes.Insert(selected + 1,box.GetRange(middle,box.Count-middle));
        }
        return boxes.Select(box => new Cluster(Mean(box), box.Count)).ToList();
    }
    static string ClusterText(List<Cluster> clusters) {
        return string.Join(" ", clusters.Select(cluster => $"{Hex(cluster.Color)}:{cluster.Count}"));
    }
    static string Kmeans(int k, List<int[]> colors) {
        List<int[]> representatives = Palette(k, colors).Select(cluster => cluster.Color).ToList();
        List<Cluster> result = new();
        int iteration = 0;
        while (iteration < 20) {
            iteration++;
            var groups = Enumerable.Range(0, k).Select(_ => new List<int[]>()).ToList();
            foreach (int[] color in colors) {
                int best = Enumerable.Range(0, k).MinBy(j => Distance(color, representatives[j]));
                groups[best].Add(color);
            }
            result = new();
            bool unchanged = true;
            for (int j = 0; j < k; j++) {
                int[] next = groups[j].Count == 0 ? representatives[j] : Mean(groups[j]);
                if (!next.SequenceEqual(representatives[j])) unchanged = false;
                result.Add(new Cluster(next,groups[j].Count));
            }
            for (int j = 0; j < k; j++) representatives[j] = result[j].Color;
            if (unchanged) break;
        }
        return iteration + " " + ClusterText(result);
    }
    List<int[]> Colors(string[] tokens, int start) {
        return tokens.Skip(start).Select(Color).ToList();
    }
    static string ColorsText(List<int[]> colors) {
        return string.Join(" ",colors.Select(Hex));
    }
    string Execute(string line) {
        string[] t = line.Split(' ');
        string command = t[0];
        switch (command) {
            case "DEFINE": {
                Arity(t,2);
                Require(NAME.IsMatch(t[1]) && !NAMES.Contains(t[1],StringComparer.Ordinal));
                int[] c = Color(t[2]);
                Entry entry = new Entry(t[1],c);
                int index = registered.FindIndex(existing => existing.Name == t[1]);
                if (index < 0) registered.Add(entry);
                else registered[index] = entry;
                return t[1] + " " + Hex(c);
            }
            case "UNDEFINE": {
                Arity(t,1);
                Require(NAME.IsMatch(t[1]));
                int index = registered.FindIndex(entry => entry.Name == t[1]);
                Require(index >= 0);
                registered.RemoveAt(index);
                return t[1] + " removed";
            }
            case "LIST": {
                Arity(t,0);
                if (registered.Count == 0) return "NONE";
                return string.Join(" ",registered.OrderBy(e => e.Name,StringComparer.Ordinal)
                    .Select(e => e.Name + "=" + Hex(e.Color)));
            }
            case "PARSE": {
                Arity(t,1);
                int[] c = Color(t[1]);
                string name = Table().FirstOrDefault(entry => c.SequenceEqual(entry.Color))?.Name ?? "-";
                return Hex(c) + " rgb(" + c[0] + "," + c[1] + "," + c[2] + ") " +
                    Model("HSL",c) + " " + Model("HSV",c) + " " + Model("HWB",c) + " " +
                    Model("CMYK",c) + " " + Model("YCBCR",c) + " " + Model("YIQ",c) + " " + name;
            }
            case "HSL":
            case "HSV":
            case "HWB":
            case "CMYK":
            case "YCBCR":
            case "YIQ": {
                Arity(t,1);
                return Model(command,Color(t[1]));
            }
            case "FROMHSL":
            case "FROMHSV":
            case "FROMHWB": {
                Arity(t,3);
                int h = Number(t[1],0,359), s = Number(t[2],0,100), third = Number(t[3],0,100);
                int[] c;
                if (command.Equals("FROMHSL")) c = FromHsl(h,s,third);
                else if (command.Equals("FROMHSV")) c = FromHue(h,(long)third*s,100L*third-third*s,10000);
                else if (s + third >= 100) {
                    int value = Round(255L*s,s+third);
                    c = new int[]{value,value,value};
                } else c = FromHue(h,100-s-third,s,100);
                return Hex(c);
            }
            case "FROMCMYK": {
                Arity(t,4);
                int k = Number(t[4],0,100);
                int[] c = new int[3];
                for (int i = 0; i < 3; i++) c[i] = Round(255L*(100-Number(t[i+1],0,100))*(100-k),10000);
                return Hex(c);
            }
            case "FROMYCBCR":
            case "FROMYIQ": {
                Arity(t,3);
                int y = Number(t[1],0,255);
                bool iq = command.Equals("FROMYIQ");
                int a = Number(t[2],iq ? -255 : 0,255), b = Number(t[3],iq ? -255 : 0,255);
                long r, g, blue;
                if (iq) {
                    r = 1000L*y+956L*a+619L*b;
                    g = 1000L*y-272L*a-647L*b;
                    blue = 1000L*y-1106L*a+1703L*b;
                } else {
                    r = 1000L*y+1402L*(b-128);
                    g = 1000L*y-344L*(a-128)-714L*(b-128);
                    blue = 1000L*y+1772L*(a-128);
                }
                return Hex(new int[]{Clamp(Round(r,1000)),Clamp(Round(g,1000)),Clamp(Round(blue,1000))});
            }
            case "RGB565": {
                Arity(t,1);
                int[] c = Color(t[1]);
                int value = 2048*Round(31L*c[0],255)+32*Round(63L*c[1],255)+Round(31L*c[2],255);
                return $"0x{value:X4}";
            }
            case "FROM565": {
                Arity(t,1);
                Require(Regex.IsMatch(t[1],@"\A0x[0-9a-fA-F]{4}\z"));
                int v = int.Parse(t[1].Substring(2),NumberStyles.HexNumber,CultureInfo.InvariantCulture);
                return Hex(new int[]{Round(255L*(v/2048),31),Round(255L*(v/32%64),63),Round(255L*(v%32),31)});
            }
            case "FROMANSI": {
                Arity(t,1);
                return Hex(Ansi(Number(t[1],0,255)));
            }
            case "ANSI": {
                Arity(t,1);
                int[] c = Color(t[1]);
                int best = Enumerable.Range(16, 240).MinBy(i => Distance(c, Ansi(i)));
                return best + " " + Hex(Ansi(best)) + " " + Distance(c,Ansi(best));
            }
            case "WEBSAFE":
            case "INVERT": {
                Arity(t,1);
                int[] c = Color(t[1]), result = new int[3];
                for (int i = 0; i < 3; i++) result[i] = command.Equals("INVERT") ? 255-c[i] : 51*Round(c[i],51);
                return Hex(result);
            }
            case "GRAY": {
                Arity(t,2);
                int[] c = Color(t[1]);
                int value = t[2] switch {
                    "LUMA" => Round(299L*c[0]+587L*c[1]+114L*c[2],1000),
                    "AVERAGE" => Round(c.Sum(),3),
                    "LIGHTNESS" => Round(c.Max()+c.Min(),2),
                    "HSP" => Root(299L*c[0]*c[0]+587L*c[1]*c[1]+114L*c[2]*c[2],1000),
                    _ => throw new Invalid(),
                };
                return Hex(new int[]{value,value,value});
            }
            case "MIX":
            case "MIXHSL": {
                Arity(t,3);
                int[] a = Color(t[1]), b = Color(t[2]);
                int p = Number(t[3],0,100);
                int[] result = new int[3];
                if (command.Equals("MIX")) {
                    for (int i = 0; i < 3; i++) result[i] = Round((long)a[i]*(100-p)+(long)b[i]*p,100);
                } else {
                    int[] first = Hsl(a), second = Hsl(b);
                    int e = Mod(second[0]-first[0],360);
                    if (e > 180) e -= 360;
                    result = FromHsl(Mod(first[0]+Away((long)e*p,100),360),
                        first[1]+Away((long)(second[1]-first[1])*p,100),first[2]+Away((long)(second[2]-first[2])*p,100));
                }
                return Hex(result);
            }
            case "GRADIENT":
            case "TINTS":
            case "SHADES":
            case "TONES": {
                Arity(t,command.Equals("GRADIENT") ? 3 : 2);
                int[] a = Color(t[1]);
                List<int[]> result = new();
                if (command.Equals("GRADIENT")) {
                    int[] b = Color(t[2]);
                    int n = Number(t[3],2,16);
                    for (int i = 0; i < n; i++) result.Add(Gradient(a,b,i,n-1));
                } else {
                    int n = Number(t[2],1,10);
                    int target = command.Equals("TINTS") ? 255 : command.Equals("SHADES") ? 0 : 128;
                    int[] b = {target,target,target};
                    for (int i = 1; i <= n; i++) result.Add(Gradient(a,b,i,n+1));
                }
                return ColorsText(result);
            }
            case "BLEND": {
                Arity(t,3);
                return Hex(Blend(t[1],Color(t[2]),Color(t[3])));
            }
            case "ALPHA": {
                Arity(t,4);
                int[] fg = Color(t[1]), bg = Color(t[3]);
                int p = Number(t[2],0,100), q = Number(t[4],0,100), a = 100*p+q*(100-p);
                int[] result = new int[3];
                if (a > 0) {
                    for (int i = 0; i < 3; i++) result[i] = Round(100L*p*fg[i]+(long)q*(100-p)*bg[i],a);
                }
                return Hex(result) + " " + Round(a,100) + "%";
            }
            case "SIMULATE": {
                Arity(t,2);
                int[] c = Color(t[1]);
                int[][] coefficients = t[2] switch {
                    "PROTANOPIA" => new int[][]{new[]{567,433,0},new[]{558,442,0},new[]{0,242,758}},
                    "DEUTERANOPIA" => new int[][]{new[]{625,375,0},new[]{700,300,0},new[]{0,300,700}},
                    "TRITANOPIA" => new int[][]{new[]{950,50,0},new[]{0,433,567},new[]{0,475,525}},
                    "ACHROMATOPSIA" => new int[][]{new[]{299,587,114},new[]{299,587,114},new[]{299,587,114}},
                    _ => throw new Invalid(),
                };
                int[] result = new int[3];
                for (int i = 0; i < 3; i++) result[i] = Round((long)coefficients[i][0]*c[0]+
                    (long)coefficients[i][1]*c[1]+(long)coefficients[i][2]*c[2],1000);
                return Hex(result);
            }
            case "ROTATE":
            case "COMPLEMENT":
            case "TRIADIC":
            case "TETRADIC":
            case "SPLITCOMP":
            case "ANALOGOUS": {
                Arity(t,command.Equals("ROTATE") ? 2 : command.Equals("ANALOGOUS") ? 3 : 1);
                int[] values = Hsl(Color(t[1]));
                List<int> rotations = new();
                switch (command) {
                    case "ROTATE":
                        rotations.Add(Number(t[2],-720,720));
                        break;
                    case "COMPLEMENT":
                        rotations.Add(180);
                        break;
                    case "TRIADIC":
                        rotations.AddRange(new[]{120,240});
                        break;
                    case "TETRADIC":
                        rotations.AddRange(new[]{90,180,270});
                        break;
                    case "SPLITCOMP":
                        rotations.AddRange(new[]{150,210});
                        break;
                    default: {
                        int k = Number(t[2],1,6), step = Number(t[3],1,60);
                        for (int i = -k; i <= k; i++) {
                            if (i != 0) rotations.Add(i*step);
                        }
                        break;
                    }
                }
                List<int[]> result = new();
                foreach (int d in rotations) result.Add(FromHsl(Mod(values[0]+d,360),values[1],values[2]));
                return ColorsText(result);
            }
            case "LIGHTEN":
            case "DARKEN":
            case "SATURATE":
            case "DESATURATE": {
                Arity(t,2);
                int[] values = Hsl(Color(t[1]));
                int p = Number(t[2],0,100);
                if (command.Equals("LIGHTEN")) values[2] = Math.Min(100,values[2]+p);
                if (command.Equals("DARKEN")) values[2] = Math.Max(0,values[2]-p);
                if (command.Equals("SATURATE")) values[1] = Math.Min(100,values[1]+p);
                if (command.Equals("DESATURATE")) values[1] = Math.Max(0,values[1]-p);
                return Hex(FromHsl(values[0],values[1],values[2]));
            }
            case "NEAREST": {
                Arity(t,1);
                int[] c = Color(t[1]);
                Entry best = Table().MinBy(entry => Distance(c, entry.Color))!;
                return best.Name + " " + Hex(best.Color) + " " + Distance(c,best.Color);
            }
            case "DISTANCE": {
                Arity(t,2);
                int[] a = Color(t[1]), b = Color(t[2]);
                long dr = a[0]-b[0], dg = a[1]-b[1], db = a[2]-b[2];
                long w = (1024L+a[0]+b[0])*dr*dr+2048*dg*dg+(1534L-a[0]-b[0])*db*db;
                return Distance(a,b) + " " + Root(w,512);
            }
            case "CONTRAST": {
                Arity(t,2);
                return ContrastText(Color(t[1]),Color(t[2]));
            }
            case "ACCESSIBLE": {
                Arity(t,2);
                int[] fg = Color(t[1]), bg = Color(t[2]), result = fg;
                if (!Readable(fg,bg)) {
                    int[] values = Hsl(fg);
                    for (int d = 1; d <= 100; d++) {
                        foreach (int l in new int[]{values[2]-d,values[2]+d}) {
                            if (l < 0 || l > 100) continue;
                            int[] candidate = FromHsl(values[0],values[1],l);
                            if (Readable(candidate,bg)) {
                                return Hex(candidate) + " " + ContrastText(candidate,bg);
                            }
                        }
                    }
                }
                return Hex(result) + " " + ContrastText(result,bg);
            }
            case "BEST": {
                Require(t.Length >= 3 && t.Length <= 34);
                int[] bg = Color(t[1]);
                List<int[]> options = Colors(t,2);
                int[] best = options.MaxBy(c => Ratio(c, bg))!;
                return Hex(best) + " " + ContrastText(best,bg);
            }
            case "DESCRIBE": {
                Arity(t,1);
                int[] values = Hsl(Color(t[1]));
                int h = values[0], s = values[1], l = values[2];
                if (l <= 5) return "black";
                if (l >= 95) return "white";
                string lightness = l <= 20 ? "very dark" : l <= 40 ? "dark" : l <= 60 ? "medium" : l <= 80 ? "light" : "very light";
                if (s < 10) return lightness + " gray";
                string saturation = s < 40 ? "muted" : s < 80 ? "moderate" : "vivid";
                string[] hues = {"red","orange","yellow","chartreuse","green","spring-green","cyan","azure","blue","violet","magenta","rose"};
                return lightness + " " + saturation + " " + hues[(h+15)%360/30];
            }
            case "PALETTE":
            case "KMEANS": {
                Require(t.Length >= 3 && t.Length <= 34);
                int k = Number(t[1],1,t.Length-2);
                List<int[]> options = Colors(t,2);
                return command.Equals("PALETTE") ? ClusterText(Palette(k,options)) : Kmeans(k,options);
            }
            case "SORT": {
                Require(t.Length >= 2 && t.Length <= 33);
                List<int[]> options = Colors(t,1);
                options = options.OrderBy(c => Hsl(c)[0]).ThenBy(c => Hsl(c)[1]).ThenBy(c => Hsl(c)[2]).ToList();
                return ColorsText(options);
            }
            case "DITHER": {
                Require(t.Length >= 2 && t.Length <= 33);
                List<int[]> options = Colors(t,1);
                int[] error = new int[3];
                List<string> result = new();
                foreach (int[] c in options) {
                    int[] adjusted = {Clamp(c[0]+error[0]),Clamp(c[1]+error[1]),Clamp(c[2]+error[2])};
                    int best = Enumerable.Range(0, 16).MinBy(i => Distance(adjusted, Unpack(RGB[i])));
                    result.Add(NAMES[best]);
                    int[] chosen = Unpack(RGB[best]);
                    for (int i = 0; i < 3; i++) error[i] = adjusted[i]-chosen[i];
                }
                return string.Join(" ",result);
            }
            case "RANDOM": {
                Arity(t,2);
                long state = Number(t[1],1,999999999);
                int n = Number(t[2],1,16);
                List<int[]> result = new();
                for (int i = 0; i < n; i++) {
                    state = state*48271%2147483647;
                    int h = (int)(state%360);
                    state = state*48271%2147483647;
                    int s = 40+(int)(state%61);
                    state = state*48271%2147483647;
                    int l = 25+(int)(state%51);
                    result.Add(FromHsl(h,s,l));
                }
                return ColorsText(result);
            }
            default: throw new Invalid();
        }
    }
    static long Floor(long numerator, long denominator) {
        long quotient = numerator / denominator;
        return numerator < 0 && numerator % denominator != 0 ? quotient - 1 : quotient;
    }
    static void Main() {
        CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
        int count = int.Parse(Console.ReadLine()!,CultureInfo.InvariantCulture);
        Program converter = new Program();
        for (int i = 0; i < count; i++) {
            string line = Console.ReadLine()!;
            try {
                Console.WriteLine(converter.Execute(line));
            } catch (Invalid) {
                Console.WriteLine("INVALID");
            }
        }
    }
}
