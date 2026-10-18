import java.io.*;
import java.util.*;
import java.util.regex.*;
import java.util.stream.IntStream;
import java.util.stream.Stream;

public class Main {
    record Entry(String name, int[] color) {}
    record Cluster(int[] color, int count) {}
    static class Invalid extends RuntimeException {}
    static final String[] NAMES = {
        "black", "maroon", "green", "olive", "navy", "purple", "teal", "silver",
        "gray", "red", "lime", "yellow", "blue", "magenta", "cyan", "white",
        "orange", "pink", "brown", "gold", "coral", "salmon", "violet", "indigo"
    };
    static final int[] RGB = {
        0x000000, 0x800000, 0x008000, 0x808000, 0x000080, 0x800080, 0x008080, 0xC0C0C0,
        0x808080, 0xFF0000, 0x00FF00, 0xFFFF00, 0x0000FF, 0xFF00FF, 0x00FFFF, 0xFFFFFF,
        0xFFA500, 0xFFC0CB, 0xA52A2A, 0xFFD700, 0xFF7F50, 0xFA8072, 0xEE82EE, 0x4B0082
    };
    static final Pattern INTEGER = Pattern.compile("-?[0-9]{1,9}");
    static final Pattern NAME = Pattern.compile("[a-z]{1,12}");
    static final Pattern HEX = Pattern.compile("#[0-9a-fA-F]{3}(?:[0-9a-fA-F]{3})?");
    static final Pattern RGB_TEXT = Pattern.compile("rgb\\(([0-9]{1,3}),([0-9]{1,3}),([0-9]{1,3})\\)");
    final List<Entry> registered = new ArrayList<>();

    static void require(boolean condition) {
        if (!condition) throw new Invalid();
    }
    static void arity(String[] tokens, int count) {
        require(tokens.length == count + 1);
    }
    static int number(String text, int low, int high) {
        require(INTEGER.matcher(text).matches());
        int value = Integer.parseInt(text);
        require(value >= low && value <= high);
        return value;
    }
    static int round(long numerator, long denominator) {
        return (int)Math.floorDiv(2 * numerator + denominator, 2 * denominator);
    }
    static int away(long numerator, long denominator) {
        return numerator < 0 ? -round(-numerator, denominator) : round(numerator, denominator);
    }
    static int percent(long a, long b) {
        return round(100 * a, b);
    }
    static int clamp(int value) {
        return Math.clamp(value, 0, 255);
    }
    static int root(long numerator, long scale) {
        long value = numerator / scale;
        long low = 0, high = value + 1;
        while (low + 1 < high) {
            long middle = (low + high) / 2;
            if (middle * middle <= value) low = middle;
            else high = middle;
        }
        return (int)low;
    }
    static int[] unpack(int value) {
        return new int[]{value >> 16, value >> 8 & 255, value & 255};
    }
    static String hex(int[] color) {
        return String.format(Locale.ROOT, "#%02X%02X%02X", color[0], color[1], color[2]);
    }
    List<Entry> table() {
        return Stream.concat(IntStream.range(0, NAMES.length).mapToObj(i -> new Entry(NAMES[i], unpack(RGB[i]))),
                registered.stream()).toList();
    }
    int[] color(String text) {
        if (HEX.matcher(text).matches()) {
            String digits = text.substring(1);
            if (digits.length() == 3) {
                digits = "" + digits.charAt(0) + digits.charAt(0) + digits.charAt(1) + digits.charAt(1)
                    + digits.charAt(2) + digits.charAt(2);
            }
            return unpack(Integer.parseInt(digits, 16));
        }
        Matcher matcher = RGB_TEXT.matcher(text);
        if (matcher.matches()) {
            int[] result = new int[3];
            for (int i = 0; i < 3; i++) {
                result[i] = Integer.parseInt(matcher.group(i + 1));
                require(result[i] <= 255);
            }
            return result;
        }
        for (Entry entry : table()) {
            if (entry.name().equals(text)) return entry.color();
        }
        throw new Invalid();
    }
    static int hue(int[] c) {
        var statistics = Arrays.stream(c).summaryStatistics();
        int maximum = statistics.getMax(), difference = maximum - statistics.getMin();
        if (difference == 0) return 0;
        long numerator;
        if (maximum == c[0]) {
            numerator = 60L * (c[1] - c[2]);
            if (numerator < 0) numerator += 360L * difference;
        } else if (maximum == c[1]) numerator = 60L * (c[2] - c[0]) + 120L * difference;
        else numerator = 60L * (c[0] - c[1]) + 240L * difference;
        return round(numerator, difference) % 360;
    }
    static int[] hsl(int[] c) {
        var statistics = Arrays.stream(c).summaryStatistics();
        int maximum = statistics.getMax(), minimum = statistics.getMin(), difference = maximum - minimum;
        int saturation = difference == 0 ? 0 : percent(difference, 255 - Math.abs(maximum + minimum - 255));
        return new int[]{hue(c), saturation, percent(maximum + minimum, 510)};
    }
    static int[] fromHue(int h, long chroma, long offset, long denominator) {
        int sector = h / 60, f = h % 60;
        int x = sector % 2 == 0 ? f : 60 - f;
        int[][] factors = {{60,x,0},{x,60,0},{0,60,x},{0,x,60},{x,0,60},{60,0,x}};
        int[] result = new int[3];
        for (int i = 0; i < 3; i++) result[i] = round(255 * (chroma * factors[sector][i] + 60 * offset), 60 * denominator);
        return result;
    }
    static int[] fromHsl(int h, int s, int l) {
        long c = (100 - Math.abs(2 * l - 100)) * s;
        return fromHue(h, 2 * c, 200L * l - c, 20000);
    }
    static long distance(int[] a, int[] b) {
        long result = 0;
        for (int i = 0; i < 3; i++) result += (long)(a[i] - b[i]) * (a[i] - b[i]);
        return result;
    }
    static String model(String command, int[] c) {
        var statistics = Arrays.stream(c).summaryStatistics();
        int r = c[0], g = c[1], b = c[2], m = statistics.getMax(), n = statistics.getMin(), d = m - n;
        return switch (command) {
            case "HSL" -> {
                int[] v = hsl(c);
                yield "hsl(" + v[0] + "," + v[1] + "%," + v[2] + "%)";
            }
            case "HSV" -> "hsv(" + hue(c) + "," + (m == 0 ? 0 : percent(d,m)) + "%," + percent(m,255) + "%)";
            case "HWB" -> "hwb(" + hue(c) + "," + percent(n,255) + "%," + percent(255 - m,255) + "%)";
            case "CMYK" -> m == 0 ? "cmyk(0%,0%,0%,100%)" :
                "cmyk(" + percent(m-r,m) + "%," + percent(m-g,m) + "%," + percent(m-b,m) + "%," + percent(255-m,255) + "%)";
            case "YCBCR" -> "ycbcr(" + clamp(round(299L*r+587L*g+114L*b,1000)) + "," +
                clamp(round(128000L-169L*r-331L*g+500L*b,1000)) + "," + clamp(round(128000L+500L*r-419L*g-81L*b,1000)) + ")";
            case "YIQ" -> "yiq(" + round(299L*r+587L*g+114L*b,1000) + "," +
                round(596L*r-274L*g-322L*b,1000) + "," + round(211L*r-523L*g+312L*b,1000) + ")";
            default -> throw new Invalid();
        };
    }
    static int[] ansi(int number) {
        if (number < 16) return unpack(RGB[number]);
        if (number >= 232) {
            int value = 8 + 10 * (number - 232);
            return new int[]{value, value, value};
        }
        int[] values = {0,95,135,175,215,255};
        int v = number - 16;
        return new int[]{values[v / 36], values[v / 6 % 6], values[v % 6]};
    }
    static int[] gradient(int[] a, int[] b, int index, int denominator) {
        int[] result = new int[3];
        for (int i = 0; i < 3; i++) result[i] = a[i] + away((long)(b[i] - a[i]) * index, denominator);
        return result;
    }
    static long luminance(int[] c) {
        return 2126L*c[0]*c[0] + 7152L*c[1]*c[1] + 722L*c[2]*c[2];
    }
    static long[] contrast(int[] a, int[] b) {
        long first = luminance(a), second = luminance(b);
        return new long[]{Math.max(first,second) + 32512500, Math.min(first,second) + 32512500};
    }
    static int ratio(int[] a, int[] b) {
        long[] values = contrast(a,b);
        return round(100 * values[0], values[1]);
    }
    static boolean readable(int[] a, int[] b) {
        long[] values = contrast(a,b);
        return 2 * values[0] >= 9 * values[1];
    }
    static String contrastText(int[] a, int[] b) {
        long[] values = contrast(a,b);
        int ratio = round(100 * values[0], values[1]);
        String verdict = values[0] >= 7 * values[1] ? "AAA" : 2 * values[0] >= 9 * values[1] ? "AA" : "FAIL";
        return String.format(Locale.ROOT, "%d.%02d %s", ratio / 100, ratio % 100, verdict);
    }
    static int blendComponent(String mode, int x, int y) {
        int multiply = x * y / 255, screen = 255 - (255-x)*(255-y)/255;
        return switch (mode) {
            case "MULTIPLY" -> multiply;
            case "SCREEN" -> screen;
            case "OVERLAY" -> x < 128 ? 2*x*y/255 : 255-2*(255-x)*(255-y)/255;
            case "HARDLIGHT" -> y < 128 ? 2*x*y/255 : 255-2*(255-x)*(255-y)/255;
            case "SOFTLIGHT" -> ((255-x)*multiply+x*screen)/255;
            case "DARKEN" -> Math.min(x,y);
            case "LIGHTEN" -> Math.max(x,y);
            case "DIFFERENCE" -> Math.abs(x-y);
            case "EXCLUSION" -> x+y-2*x*y/255;
            case "ADD" -> Math.min(255,x+y);
            case "SUBTRACT" -> Math.max(0,x-y);
            case "COLORDODGE" -> y == 255 ? 255 : Math.min(255,255*x/(255-y));
            case "COLORBURN" -> y == 0 ? 0 : Math.max(0,255-255*(255-x)/y);
            default -> throw new Invalid();
        };
    }
    static int[] blend(String mode, int[] base, int[] top) {
        if (Set.of("HUE","SATURATION","COLOR","LUMINOSITY").contains(mode)) {
            int[] a = hsl(base), b = hsl(top);
            return fromHsl(mode.equals("HUE") || mode.equals("COLOR") ? b[0] : a[0],
                mode.equals("SATURATION") || mode.equals("COLOR") ? b[1] : a[1], mode.equals("LUMINOSITY") ? b[2] : a[2]);
        }
        int[] result = new int[3];
        for (int i = 0; i < 3; i++) result[i] = blendComponent(mode,base[i],top[i]);
        return result;
    }
    static int[] mean(List<int[]> colors) {
        return IntStream.range(0, 3).map(component ->
                round(colors.stream().mapToLong(color -> color[component]).sum(), colors.size())).toArray();
    }
    static int[] ranges(List<int[]> colors) {
        return IntStream.range(0, 3).map(component -> {
            var statistics = colors.stream().mapToInt(color -> color[component]).summaryStatistics();
            return statistics.getMax() - statistics.getMin();
        }).toArray();
    }
    static List<Cluster> palette(int k, List<int[]> colors) {
        List<List<int[]>> boxes = new ArrayList<>();
        boxes.add(new ArrayList<>(colors));
        while (boxes.size() < k) {
            int selected = -1, width = -1;
            for (int i = 0; i < boxes.size(); i++) {
                if (boxes.get(i).size() < 2) continue;
                int candidate = Arrays.stream(ranges(boxes.get(i))).max().orElseThrow();
                if (candidate > width) {
                    width = candidate;
                    selected = i;
                }
            }
            List<int[]> box = boxes.get(selected);
            int[] ranges = ranges(box);
            int component = 0;
            for (int i = 1; i < 3; i++) {
                if (ranges[i] > ranges[component]) component = i;
            }
            final int axis = component;
            box.sort(Comparator.comparingInt(c -> c[axis]));
            int middle = box.size() / 2;
            boxes.set(selected,new ArrayList<>(box.subList(0,middle)));
            boxes.add(selected + 1,new ArrayList<>(box.subList(middle,box.size())));
        }
        return boxes.stream().map(box -> new Cluster(mean(box), box.size())).toList();
    }
    static String clusterText(List<Cluster> clusters) {
        return String.join(" ", clusters.stream().map(cluster -> hex(cluster.color()) + ":" + cluster.count()).toList());
    }
    static String kmeans(int k, List<int[]> colors) {
        List<Cluster> initial = palette(k,colors);
        List<int[]> representatives = new ArrayList<>();
        for (Cluster cluster : initial) representatives.add(cluster.color());
        List<Cluster> result = new ArrayList<>();
        int iteration = 0;
        while (iteration < 20) {
            iteration++;
            List<List<int[]>> groups = new ArrayList<>();
            for (int i = 0; i < k; i++) groups.add(new ArrayList<>());
            for (int[] color : colors) {
                int best = 0;
                for (int j = 1; j < k; j++) {
                    if (distance(color,representatives.get(j)) < distance(color,representatives.get(best))) best = j;
                }
                groups.get(best).add(color);
            }
            result = new ArrayList<>();
            boolean unchanged = true;
            for (int j = 0; j < k; j++) {
                int[] next = groups.get(j).isEmpty() ? representatives.get(j) : mean(groups.get(j));
                if (!Arrays.equals(next,representatives.get(j))) unchanged = false;
                result.add(new Cluster(next,groups.get(j).size()));
            }
            for (int j = 0; j < k; j++) representatives.set(j,result.get(j).color());
            if (unchanged) break;
        }
        return iteration + " " + clusterText(result);
    }
    List<int[]> colors(String[] tokens, int start) {
        return Arrays.stream(tokens, start, tokens.length).map(this::color).toList();
    }
    static String colorsText(List<int[]> colors) {
        return String.join(" ",colors.stream().map(Main::hex).toList());
    }
    String execute(String line) {
        String[] t = line.split(" ");
        String command = t[0];
        switch (command) {
            case "DEFINE": {
                arity(t,2);
                require(NAME.matcher(t[1]).matches() && !Arrays.asList(NAMES).contains(t[1]));
                int[] c = color(t[2]);
                Entry entry = new Entry(t[1],c);
                for (int i = 0; i < registered.size(); i++) {
                    if (registered.get(i).name().equals(t[1])) {
                        registered.set(i,entry);
                        return t[1] + " " + hex(c);
                    }
                }
                registered.add(entry);
                return t[1] + " " + hex(c);
            }
            case "UNDEFINE": {
                arity(t,1);
                require(NAME.matcher(t[1]).matches());
                for (int i = 0; i < registered.size(); i++) {
                    if (registered.get(i).name().equals(t[1])) {
                        registered.remove(i);
                        return t[1] + " removed";
                    }
                }
                throw new Invalid();
            }
            case "LIST": {
                arity(t,0);
                if (registered.isEmpty()) return "NONE";
                return String.join(" ",registered.stream().sorted(Comparator.comparing(Entry::name))
                    .map(e -> e.name() + "=" + hex(e.color())).toList());
            }
            case "PARSE": {
                arity(t,1);
                int[] c = color(t[1]);
                String name = table().stream().filter(entry -> Arrays.equals(c, entry.color()))
                        .map(Entry::name).findFirst().orElse("-");
                return hex(c) + " rgb(" + c[0] + "," + c[1] + "," + c[2] + ") " +
                    model("HSL",c) + " " + model("HSV",c) + " " + model("HWB",c) + " " +
                    model("CMYK",c) + " " + model("YCBCR",c) + " " + model("YIQ",c) + " " + name;
            }
            case "HSL", "HSV", "HWB", "CMYK", "YCBCR", "YIQ": {
                arity(t,1);
                return model(command,color(t[1]));
            }
            case "FROMHSL", "FROMHSV", "FROMHWB": {
                arity(t,3);
                int h = number(t[1],0,359), s = number(t[2],0,100), third = number(t[3],0,100);
                int[] c;
                if (command.equals("FROMHSL")) c = fromHsl(h,s,third);
                else if (command.equals("FROMHSV")) c = fromHue(h,(long)third*s,100L*third-third*s,10000);
                else if (s + third >= 100) {
                    int value = round(255L*s,s+third);
                    c = new int[]{value,value,value};
                } else c = fromHue(h,100-s-third,s,100);
                return hex(c);
            }
            case "FROMCMYK": {
                arity(t,4);
                int k = number(t[4],0,100);
                int[] c = new int[3];
                for (int i = 0; i < 3; i++) c[i] = round(255L*(100-number(t[i+1],0,100))*(100-k),10000);
                return hex(c);
            }
            case "FROMYCBCR", "FROMYIQ": {
                arity(t,3);
                int y = number(t[1],0,255);
                boolean iq = command.equals("FROMYIQ");
                int a = number(t[2],iq ? -255 : 0,255), b = number(t[3],iq ? -255 : 0,255);
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
                return hex(new int[]{clamp(round(r,1000)),clamp(round(g,1000)),clamp(round(blue,1000))});
            }
            case "RGB565": {
                arity(t,1);
                int[] c = color(t[1]);
                int value = 2048*round(31L*c[0],255)+32*round(63L*c[1],255)+round(31L*c[2],255);
                return String.format(Locale.ROOT,"0x%04X",value);
            }
            case "FROM565": {
                arity(t,1);
                require(t[1].matches("0x[0-9a-fA-F]{4}"));
                int v = Integer.parseInt(t[1].substring(2),16);
                return hex(new int[]{round(255L*(v/2048),31),round(255L*(v/32%64),63),round(255L*(v%32),31)});
            }
            case "FROMANSI": {
                arity(t,1);
                return hex(ansi(number(t[1],0,255)));
            }
            case "ANSI": {
                arity(t,1);
                int[] c = color(t[1]);
                int best = 16;
                for (int i = 17; i <= 255; i++) {
                    if (distance(c,ansi(i)) < distance(c,ansi(best))) best = i;
                }
                return best + " " + hex(ansi(best)) + " " + distance(c,ansi(best));
            }
            case "WEBSAFE", "INVERT": {
                arity(t,1);
                int[] c = color(t[1]), result = new int[3];
                for (int i = 0; i < 3; i++) result[i] = command.equals("INVERT") ? 255-c[i] : 51*round(c[i],51);
                return hex(result);
            }
            case "GRAY": {
                arity(t,2);
                int[] c = color(t[1]);
                var statistics = Arrays.stream(c).summaryStatistics();
                int value = switch (t[2]) {
                    case "LUMA" -> round(299L*c[0]+587L*c[1]+114L*c[2],1000);
                    case "AVERAGE" -> round(statistics.getSum(),3);
                    case "LIGHTNESS" -> round(statistics.getMax()+statistics.getMin(),2);
                    case "HSP" -> root(299L*c[0]*c[0]+587L*c[1]*c[1]+114L*c[2]*c[2],1000);
                    default -> throw new Invalid();
                };
                return hex(new int[]{value,value,value});
            }
            case "MIX", "MIXHSL": {
                arity(t,3);
                int[] a = color(t[1]), b = color(t[2]);
                int p = number(t[3],0,100);
                int[] result = new int[3];
                if (command.equals("MIX")) {
                    for (int i = 0; i < 3; i++) result[i] = round((long)a[i]*(100-p)+(long)b[i]*p,100);
                } else {
                    int[] first = hsl(a), second = hsl(b);
                    int e = Math.floorMod(second[0]-first[0],360);
                    if (e > 180) e -= 360;
                    result = fromHsl(Math.floorMod(first[0]+away((long)e*p,100),360),
                        first[1]+away((long)(second[1]-first[1])*p,100),first[2]+away((long)(second[2]-first[2])*p,100));
                }
                return hex(result);
            }
            case "GRADIENT", "TINTS", "SHADES", "TONES": {
                arity(t,command.equals("GRADIENT") ? 3 : 2);
                int[] a = color(t[1]);
                List<int[]> result = new ArrayList<>();
                if (command.equals("GRADIENT")) {
                    int[] b = color(t[2]);
                    int n = number(t[3],2,16);
                    for (int i = 0; i < n; i++) result.add(gradient(a,b,i,n-1));
                } else {
                    int n = number(t[2],1,10);
                    int target = command.equals("TINTS") ? 255 : command.equals("SHADES") ? 0 : 128;
                    int[] b = {target,target,target};
                    for (int i = 1; i <= n; i++) result.add(gradient(a,b,i,n+1));
                }
                return colorsText(result);
            }
            case "BLEND": {
                arity(t,3);
                return hex(blend(t[1],color(t[2]),color(t[3])));
            }
            case "ALPHA": {
                arity(t,4);
                int[] fg = color(t[1]), bg = color(t[3]);
                int p = number(t[2],0,100), q = number(t[4],0,100), a = 100*p+q*(100-p);
                int[] result = new int[3];
                if (a > 0) {
                    for (int i = 0; i < 3; i++) result[i] = round(100L*p*fg[i]+(long)q*(100-p)*bg[i],a);
                }
                return hex(result) + " " + round(a,100) + "%";
            }
            case "SIMULATE": {
                arity(t,2);
                int[] c = color(t[1]);
                int[][] coefficients = switch (t[2]) {
                    case "PROTANOPIA" -> new int[][]{{567,433,0},{558,442,0},{0,242,758}};
                    case "DEUTERANOPIA" -> new int[][]{{625,375,0},{700,300,0},{0,300,700}};
                    case "TRITANOPIA" -> new int[][]{{950,50,0},{0,433,567},{0,475,525}};
                    case "ACHROMATOPSIA" -> new int[][]{{299,587,114},{299,587,114},{299,587,114}};
                    default -> throw new Invalid();
                };
                int[] result = new int[3];
                for (int i = 0; i < 3; i++) result[i] = round((long)coefficients[i][0]*c[0]+
                    (long)coefficients[i][1]*c[1]+(long)coefficients[i][2]*c[2],1000);
                return hex(result);
            }
            case "ROTATE", "COMPLEMENT", "TRIADIC", "TETRADIC", "SPLITCOMP", "ANALOGOUS": {
                arity(t,command.equals("ROTATE") ? 2 : command.equals("ANALOGOUS") ? 3 : 1);
                int[] values = hsl(color(t[1]));
                List<Integer> rotations = new ArrayList<>();
                switch (command) {
                    case "ROTATE" -> rotations.add(number(t[2],-720,720));
                    case "COMPLEMENT" -> rotations.add(180);
                    case "TRIADIC" -> rotations.addAll(List.of(120,240));
                    case "TETRADIC" -> rotations.addAll(List.of(90,180,270));
                    case "SPLITCOMP" -> rotations.addAll(List.of(150,210));
                    default -> {
                        int k = number(t[2],1,6), step = number(t[3],1,60);
                        for (int i = -k; i <= k; i++) {
                            if (i != 0) rotations.add(i*step);
                        }
                    }
                }
                List<int[]> result = new ArrayList<>();
                for (int d : rotations) result.add(fromHsl(Math.floorMod(values[0]+d,360),values[1],values[2]));
                return colorsText(result);
            }
            case "LIGHTEN", "DARKEN", "SATURATE", "DESATURATE": {
                arity(t,2);
                int[] values = hsl(color(t[1]));
                int p = number(t[2],0,100);
                if (command.equals("LIGHTEN")) values[2] = Math.min(100,values[2]+p);
                if (command.equals("DARKEN")) values[2] = Math.max(0,values[2]-p);
                if (command.equals("SATURATE")) values[1] = Math.min(100,values[1]+p);
                if (command.equals("DESATURATE")) values[1] = Math.max(0,values[1]-p);
                return hex(fromHsl(values[0],values[1],values[2]));
            }
            case "NEAREST": {
                arity(t,1);
                int[] c = color(t[1]);
                List<Entry> entries = table();
                Entry best = entries.getFirst();
                for (Entry entry : entries) {
                    if (distance(c,entry.color()) < distance(c,best.color())) best = entry;
                }
                return best.name() + " " + hex(best.color()) + " " + distance(c,best.color());
            }
            case "DISTANCE": {
                arity(t,2);
                int[] a = color(t[1]), b = color(t[2]);
                long dr = a[0]-b[0], dg = a[1]-b[1], db = a[2]-b[2];
                long w = (1024L+a[0]+b[0])*dr*dr+2048*dg*dg+(1534L-a[0]-b[0])*db*db;
                return distance(a,b) + " " + root(w,512);
            }
            case "CONTRAST": {
                arity(t,2);
                return contrastText(color(t[1]),color(t[2]));
            }
            case "ACCESSIBLE": {
                arity(t,2);
                int[] fg = color(t[1]), bg = color(t[2]), result = fg;
                if (!readable(fg,bg)) {
                    int[] values = hsl(fg);
                    search: for (int d = 1; d <= 100; d++) {
                        for (int l : new int[]{values[2]-d,values[2]+d}) {
                            if (l < 0 || l > 100) continue;
                            int[] candidate = fromHsl(values[0],values[1],l);
                            if (readable(candidate,bg)) {
                                result = candidate;
                                break search;
                            }
                        }
                    }
                }
                return hex(result) + " " + contrastText(result,bg);
            }
            case "BEST": {
                require(t.length >= 3 && t.length <= 34);
                int[] bg = color(t[1]);
                List<int[]> options = colors(t,2);
                int[] best = options.getFirst();
                for (int[] c : options) {
                    if (ratio(c,bg) > ratio(best,bg)) best = c;
                }
                return hex(best) + " " + contrastText(best,bg);
            }
            case "DESCRIBE": {
                arity(t,1);
                int[] values = hsl(color(t[1]));
                int h = values[0], s = values[1], l = values[2];
                if (l <= 5) return "black";
                if (l >= 95) return "white";
                String lightness = l <= 20 ? "very dark" : l <= 40 ? "dark" : l <= 60 ? "medium" : l <= 80 ? "light" : "very light";
                if (s < 10) return lightness + " gray";
                String saturation = s < 40 ? "muted" : s < 80 ? "moderate" : "vivid";
                String[] hues = {"red","orange","yellow","chartreuse","green","spring-green","cyan","azure","blue","violet","magenta","rose"};
                return lightness + " " + saturation + " " + hues[(h+15)%360/30];
            }
            case "PALETTE", "KMEANS": {
                require(t.length >= 3 && t.length <= 34);
                int k = number(t[1],1,t.length-2);
                List<int[]> options = colors(t,2);
                return command.equals("PALETTE") ? clusterText(palette(k,options)) : kmeans(k,options);
            }
            case "SORT": {
                require(t.length >= 2 && t.length <= 33);
                List<int[]> options = colors(t,1);
                options = options.stream().sorted(Comparator.<int[]>comparingInt(c -> hsl(c)[0])
                    .thenComparingInt(c -> hsl(c)[1]).thenComparingInt(c -> hsl(c)[2])).toList();
                return colorsText(options);
            }
            case "DITHER": {
                require(t.length >= 2 && t.length <= 33);
                List<int[]> options = colors(t,1);
                int[] error = new int[3];
                List<String> result = new ArrayList<>();
                for (int[] c : options) {
                    int[] adjusted = {clamp(c[0]+error[0]),clamp(c[1]+error[1]),clamp(c[2]+error[2])};
                    int best = 0;
                    for (int i = 1; i < 16; i++) {
                        if (distance(adjusted,unpack(RGB[i])) < distance(adjusted,unpack(RGB[best]))) best = i;
                    }
                    result.add(NAMES[best]);
                    int[] chosen = unpack(RGB[best]);
                    for (int i = 0; i < 3; i++) error[i] = adjusted[i]-chosen[i];
                }
                return String.join(" ",result);
            }
            case "RANDOM": {
                arity(t,2);
                long state = number(t[1],1,999999999);
                int n = number(t[2],1,16);
                List<int[]> result = new ArrayList<>();
                for (int i = 0; i < n; i++) {
                    state = state*48271%2147483647;
                    int h = (int)(state%360);
                    state = state*48271%2147483647;
                    int s = 40+(int)(state%61);
                    state = state*48271%2147483647;
                    int l = 25+(int)(state%51);
                    result.add(fromHsl(h,s,l));
                }
                return colorsText(result);
            }
            default: throw new Invalid();
        }
    }
    public static void main(String[] args) throws IOException {
        BufferedReader input = new BufferedReader(new InputStreamReader(System.in));
        int count = Integer.parseInt(input.readLine());
        Main converter = new Main();
        PrintWriter output = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        for (int i = 0; i < count; i++) {
            String line = input.readLine();
            try {
                output.println(converter.execute(line));
            } catch (Invalid invalid) {
                output.println("INVALID");
            }
        }
        output.flush();
    }
}
