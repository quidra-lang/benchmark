import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStreamReader;
import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.TreeMap;
import java.util.function.IntUnaryOperator;

public class Main {
    record Point(int x, int y) {}
    record Command(String name, int[] numbers, String slot, boolean fill) {}

    static final class CommandError extends RuntimeException {
        CommandError(String reason) { super(reason); }
    }

    static void check(boolean condition) {
        check(condition, "bad value");
    }

    static void check(boolean condition, String reason) {
        if (!condition) throw new CommandError(reason);
    }

    static int clamp(int value, int low, int high) {
        return Math.min(Math.max(value, low), high);
    }

    static boolean withinLimit(int... numbers) {
        for (int number : numbers)
            if (number < -1000 || number > 1000) return false;
        return true;
    }

    static final Point[] ADJACENT4 = {
        new Point(0, -1), new Point(-1, 0), new Point(1, 0), new Point(0, 1)
    };

    static final Point[] ADJACENT8 = {
        new Point(-1, -1), new Point(0, -1), new Point(1, -1),
        new Point(-1, 0), new Point(1, 0),
        new Point(-1, 1), new Point(0, 1), new Point(1, 1)
    };

    static final class Image {
        final int width;
        final int height;
        final int maxval;
        final int[] pixels;

        Image(int width, int height, int maxval, int[] pixels) {
            this.width = width;
            this.height = height;
            this.maxval = maxval;
            this.pixels = pixels;
        }

        int get(int x, int y) {
            return pixels[y * width + x];
        }

        boolean contains(int x, int y) {
            return x >= 0 && y >= 0 && x < width && y < height;
        }

        int clamp(int value) {
            return Main.clamp(value, 0, maxval);
        }

        Image withPixels(int[] values) {
            return new Image(width, height, maxval, values);
        }

        Image map(IntUnaryOperator action) {
            int[] values = new int[pixels.length];
            for (int i = 0; i < values.length; ++i)
                values[i] = action.applyAsInt(pixels[i]);
            return withPixels(values);
        }

        int[] neighborhood(int x, int y) {
            int[] values = new int[9];
            int index = 0;
            for (int dy = -1; dy <= 1; ++dy) {
                for (int dx = -1; dx <= 1; ++dx) {
                    values[index++] = get(Main.clamp(x + dx, 0, width - 1),
                                          Main.clamp(y + dy, 0, height - 1));
                }
            }
            return values;
        }

        String summary() {
            long checksum = 0;
            for (int i = 0; i < pixels.length; ++i)
                checksum += (long)(i + 1) * pixels[i];
            return width + "x" + height + " maxval " + maxval + " checksum " + checksum;
        }
    }

    interface PixelAt {
        int get(int x, int y);
    }

    static Image transformed(Image image, int width, int height, PixelAt function) {
        int[] values = new int[width * height];
        for (int y = 0; y < height; ++y)
            for (int x = 0; x < width; ++x)
                values[y * width + x] = function.get(x, y);
        return new Image(width, height, image.maxval, values);
    }

    static Image cropped(Image image, int x, int y, int width, int height) {
        return transformed(image, width, height, (i, j) -> image.get(x + i, y + j));
    }

    static Image translated(Image image, int width, int height, int dx, int dy, int fill) {
        return transformed(image, width, height, (x, y) ->
            image.contains(x - dx, y - dy) ? image.get(x - dx, y - dy) : fill);
    }

    static Image convolution(Image image, int[] kernel, int divisor) {
        return transformed(image, image.width, image.height, (x, y) -> {
            int[] q = image.neighborhood(x, y);
            int value = 0;
            for (int i = 0; i < 9; ++i) value += q[i] * kernel[i];
            return image.clamp(Math.floorDiv(value, divisor));
        });
    }

    static Image rankFilter(Image image, int index) {
        return transformed(image, image.width, image.height, (x, y) -> {
            int[] neighbors = image.neighborhood(x, y);
            Arrays.sort(neighbors);
            return neighbors[index];
        });
    }

    static Image sobel(Image image) {
        return transformed(image, image.width, image.height, (x, y) -> {
            int[] q = image.neighborhood(x, y);
            int gx = q[2] + 2 * q[5] + q[8] - q[0] - 2 * q[3] - q[6];
            int gy = q[6] + 2 * q[7] + q[8] - q[0] - 2 * q[1] - q[2];
            return image.clamp(Math.abs(gx) + Math.abs(gy));
        });
    }

    static List<Point> linePoints(int x0, int y0, int x1, int y1) {
        int dx = Math.abs(x1 - x0), dy = -Math.abs(y1 - y0);
        int sx = x0 < x1 ? 1 : -1, sy = y0 < y1 ? 1 : -1;
        int error = dx + dy, x = x0, y = y0;
        List<Point> points = new ArrayList<>();
        while (true) {
            points.add(new Point(x, y));
            if (x == x1 && y == y1) return points;
            int twice = 2 * error;
            if (twice >= dy) { error += dy; x += sx; }
            if (twice <= dx) { error += dx; y += sy; }
        }
    }

    static List<Point> rectanglePoints(Image image, int x, int y, int width, int height,
                                        boolean fill) {
        int right = x + width - 1, bottom = y + height - 1;
        List<Point> points = new ArrayList<>();
        for (int j = Math.max(y, 0); j <= Math.min(bottom, image.height - 1); ++j) {
            for (int i = Math.max(x, 0); i <= Math.min(right, image.width - 1); ++i) {
                if (fill || i == x || i == right || j == y || j == bottom)
                    points.add(new Point(i, j));
            }
        }
        return points;
    }

    static List<Point> circlePoints(int cx, int cy, int radius) {
        int a = radius, b = 0, error = 1 - radius;
        List<Point> points = new ArrayList<>();
        while (a >= b) {
            points.add(new Point(cx + a, cy + b));
            points.add(new Point(cx + b, cy + a));
            points.add(new Point(cx - b, cy + a));
            points.add(new Point(cx - a, cy + b));
            points.add(new Point(cx - a, cy - b));
            points.add(new Point(cx - b, cy - a));
            points.add(new Point(cx + b, cy - a));
            points.add(new Point(cx + a, cy - b));
            ++b;
            if (error < 0) error += 2 * b + 1;
            else { --a; error += 2 * (b - a) + 1; }
        }
        return points;
    }

    static List<Point> discPoints(Image image, List<Point> outline) {
        Map<Integer, int[]> rows = new TreeMap<>();
        for (Point point : outline) {
            int[] limits = rows.get(point.y);
            if (limits == null) rows.put(point.y, new int[] { point.x, point.x });
            else {
                limits[0] = Math.min(limits[0], point.x);
                limits[1] = Math.max(limits[1], point.x);
            }
        }
        List<Point> points = new ArrayList<>();
        for (var entry : rows.entrySet()) {
            int y = entry.getKey();
            if (y < 0 || y >= image.height) continue;
            for (int x = Math.max(0, entry.getValue()[0]);
                 x <= Math.min(image.width - 1, entry.getValue()[1]); ++x)
                points.add(new Point(x, y));
        }
        return points;
    }

    static List<Point> floodPoints(Image image, int x, int y) {
        int target = image.get(x, y);
        Set<Integer> seen = new HashSet<>();
        ArrayDeque<Point> stack = new ArrayDeque<>();
        stack.push(new Point(x, y));
        seen.add(y * image.width + x);
        List<Point> result = new ArrayList<>();
        while (!stack.isEmpty()) {
            Point point = stack.pop();
            result.add(point);
            for (Point direction : ADJACENT4) {
                int nx = point.x + direction.x, ny = point.y + direction.y;
                if (!image.contains(nx, ny) || image.get(nx, ny) != target) continue;
                if (seen.add(ny * image.width + nx)) stack.push(new Point(nx, ny));
            }
        }
        return result;
    }

    static Image equalized(Image image) {
        int[] counts = new int[image.maxval + 1];
        for (int pixel : image.pixels) ++counts[pixel];
        int[] cdf = new int[counts.length];
        int total = 0;
        for (int i = 0; i < counts.length; ++i) {
            total += counts[i];
            cdf[i] = total;
        }
        int minimum = Arrays.stream(image.pixels).min().orElseThrow();
        int first = cdf[minimum], size = image.pixels.length;
        if (first == size) return image.withPixels(image.pixels.clone());
        int span = size - first;
        return image.map(pixel -> (2 * (cdf[pixel] - first) * image.maxval + span) / (2 * span));
    }

    static List<List<Point>> components(Image image, int threshold) {
        boolean[] visited = new boolean[image.pixels.length];
        List<List<Point>> groups = new ArrayList<>();
        for (int start = 0; start < image.pixels.length; ++start) {
            if (visited[start] || image.pixels[start] < threshold) continue;
            visited[start] = true;
            ArrayDeque<Point> stack = new ArrayDeque<>();
            stack.push(new Point(start % image.width, start / image.width));
            List<Point> group = new ArrayList<>();
            while (!stack.isEmpty()) {
                Point point = stack.pop();
                group.add(point);
                for (Point delta : ADJACENT8) {
                    int nx = point.x + delta.x, ny = point.y + delta.y;
                    if (!image.contains(nx, ny)) continue;
                    int index = ny * image.width + nx;
                    if (image.pixels[index] >= threshold && !visited[index]) {
                        visited[index] = true;
                        stack.push(new Point(nx, ny));
                    }
                }
            }
            groups.add(group);
        }
        return groups;
    }

    static String componentText(Image image, int threshold, List<Point> group) {
        int minX = Integer.MAX_VALUE, minY = Integer.MAX_VALUE;
        int maxX = Integer.MIN_VALUE, maxY = Integer.MIN_VALUE;
        int sumX = 0, sumY = 0, perimeter = 0;
        for (Point point : group) {
            minX = Math.min(minX, point.x);
            minY = Math.min(minY, point.y);
            maxX = Math.max(maxX, point.x);
            maxY = Math.max(maxY, point.y);
            sumX += point.x;
            sumY += point.y;
            for (Point neighbor : ADJACENT4) {
                int x = point.x + neighbor.x, y = point.y + neighbor.y;
                if (!image.contains(x, y) || image.get(x, y) < threshold) {
                    ++perimeter;
                    break;
                }
            }
        }
        int size = group.size();
        return "area " + size + " perimeter " + perimeter + " box " +
               minX + " " + minY + " " + maxX + " " + maxY +
               " center " + sumX / size + " " + sumY / size;
    }

    static Image distanceMap(Image image, int threshold) {
        boolean hasBackground = false;
        for (int pixel : image.pixels)
            if (pixel < threshold) { hasBackground = true; break; }
        if (!hasBackground) {
            int[] result = new int[image.pixels.length];
            Arrays.fill(result, image.maxval);
            return image.withPixels(result);
        }
        int w = image.width, h = image.height;
        int[] distances = new int[image.pixels.length];
        for (int i = 0; i < distances.length; ++i)
            distances[i] = image.pixels[i] < threshold ? 0 : w + h;
        for (int y = 0; y < h; ++y) {
            for (int x = 0; x < w; ++x) {
                int index = y * w + x;
                if (x > 0) distances[index] = Math.min(distances[index], distances[index - 1] + 1);
                if (y > 0) distances[index] = Math.min(distances[index], distances[index - w] + 1);
            }
        }
        for (int y = h - 1; y >= 0; --y) {
            for (int x = w - 1; x >= 0; --x) {
                int index = y * w + x;
                if (x < w - 1) distances[index] = Math.min(distances[index], distances[index + 1] + 1);
                if (y < h - 1) distances[index] = Math.min(distances[index], distances[index + w] + 1);
                distances[index] = Math.min(distances[index], image.maxval);
            }
        }
        return image.withPixels(distances);
    }

    static String statistics(int[] pixels, int maxval) {
        int[] sorted = pixels.clone();
        Arrays.sort(sorted);
        int[] counts = new int[maxval + 1];
        long total = 0;
        for (int value : pixels) {
            ++counts[value];
            total += value;
        }
        int mode = 0;
        for (int i = 1; i < counts.length; ++i)
            if (counts[i] > counts[mode]) mode = i;
        int count = sorted.length;
        return "min " + sorted[0] + " max " + sorted[count - 1] +
               " mean " + total / count + " median " + sorted[(count - 1) / 2] +
               " mode " + mode;
    }

    static Image dithered(Image image) {
        int[] working = image.pixels.clone();
        int[] values = new int[working.length];
        int[][] neighbors = { {1, 0, 7}, {-1, 1, 3}, {0, 1, 5}, {1, 1, 1} };
        for (int y = 0; y < image.height; ++y) {
            for (int x = 0; x < image.width; ++x) {
                int index = y * image.width + x;
                int old = working[index];
                int value = 2 * old >= image.maxval ? image.maxval : 0;
                values[index] = value;
                int error = old - value;
                for (int[] neighbor : neighbors) {
                    int nx = x + neighbor[0], ny = y + neighbor[1];
                    if (image.contains(nx, ny))
                        working[ny * image.width + nx] += Math.floorDiv(error * neighbor[2], 16);
                }
            }
        }
        return image.withPixels(values);
    }

    static Image readPgm(List<String> lines) {
        List<String> words = new ArrayList<>();
        for (String line : lines) {
            String data = line.split("#", 2)[0].trim();
            if (!data.isEmpty()) Collections.addAll(words, data.split(" +"));
        }
        check(!words.isEmpty() && words.get(0).equals("P2"), "bad magic");

        int width = pgmHeader(words, 1, 64, "bad size");
        int height = pgmHeader(words, 2, 64, "bad size");
        int maxval = pgmHeader(words, 3, 255, "bad maxval");
        int[] pixels = new int[width * height];
        int count = words.size() - 4;
        for (int i = 0; i < pixels.length; ++i) {
            int x = i % width, y = i / width;
            check(i < count, "too few pixels (" + count + " of " + pixels.length + ")");
            String word = words.get(4 + i);
            check(word.matches("[0-9]+"), "bad pixel at " + x + "," + y);
            int value = Integer.parseInt(word);
            check(value <= maxval, "pixel out of range at " + x + "," + y);
            pixels[i] = value;
        }
        check(count <= pixels.length, "too many pixels (" + count + " of " + pixels.length + ")");
        return new Image(width, height, maxval, pixels);
    }

    static int pgmHeader(List<String> words, int index, int limit, String reason) {
        check(index < words.size(), "truncated header");
        String word = words.get(index);
        check(word.matches("[0-9]+"), "bad number");
        int value = Integer.parseInt(word);
        check(value >= 1 && value <= limit, reason);
        return value;
    }

    static final class Editor {
        static final Map<String, String> PATTERNS = new HashMap<>();
        static final Set<String> IMAGELESS =
            Set.of("NEW", "RECALL", "DROP", "SLOTS", "INFO", "UNDO", "REDO");
        static final Set<String> SLOT_COMMANDS =
            Set.of("RECALL", "DROP", "BLEND", "DIFF", "PASTE");
        static final Map<String, int[][]> KERNELS = Map.of(
            "BLUR", new int[][] {{1, 1, 1, 1, 1, 1, 1, 1, 1}, {9}},
            "GAUSS", new int[][] {{1, 2, 1, 2, 4, 2, 1, 2, 1}, {16}},
            "SHARPEN", new int[][] {{0, -1, 0, -1, 5, -1, 0, -1, 0}, {1}}
        );

        static {
            String[][] commands = {
                {"NEW", "iiii"}, {"OUTPUT", ""}, {"INVERT", ""},
                {"BRIGHTNESS", "i"}, {"CONTRAST", "ii"}, {"THRESHOLD", "i"},
                {"LEVELS", "ii"}, {"POSTERIZE", "i"}, {"MAXVAL", "i"},
                {"FLIPH", ""}, {"FLIPV", ""}, {"ROTATE", "i"},
                {"CROP", "iiii"}, {"PAD", "ii"}, {"SCALE", "ii"}, {"SHIFT", "iii"},
                {"TILE", "ii"}, {"BLUR", ""}, {"GAUSS", ""}, {"SHARPEN", ""},
                {"CONVOLVE", "iiiiiiiiii"}, {"SOBEL", ""}, {"MEDIAN", ""},
                {"ERODE", ""}, {"DILATE", ""}, {"OPEN", ""}, {"CLOSE", ""},
                {"GRADIENT", ""}, {"LINE", "iiiii"}, {"RECT", "iiiii"},
                {"CIRCLE", "iiii"}, {"FLOOD", "iii"}, {"HISTOGRAM", ""},
                {"EQUALIZE", ""}, {"LABEL", "i"}, {"DISTANCE", "i"},
                {"STATS", ""}, {"REGION", "iiii"}, {"DITHER", ""},
                {"ASCIIART", ""}, {"STORE", "n"}, {"RECALL", "n"},
                {"DROP", "n"}, {"BLEND", "nii"}, {"DIFF", "n"},
                {"PASTE", "nii"}, {"SLOTS", ""}, {"INFO", ""},
                {"UNDO", ""}, {"REDO", ""}
            };
            for (String[] command : commands) PATTERNS.put(command[0], command[1]);
        }

        Image current;
        ArrayDeque<Image> undo = new ArrayDeque<>();
        ArrayDeque<Image> redo = new ArrayDeque<>();
        Map<String, Image> slots = new HashMap<>();
        List<String> output = new ArrayList<>();

        void emit(String line) {
            output.add(line);
        }

        Command parse(String[] words) {
            String name = words[0];
            check(PATTERNS.containsKey(name), "unknown command " + name);
            String pattern = PATTERNS.get(name);
            String[] given = Arrays.copyOfRange(words, 1, words.length);
            boolean fill = (name.equals("RECT") || name.equals("CIRCLE")) &&
                           given.length == pattern.length() + 1 &&
                           given[given.length - 1].equals("FILL");
            if (fill) given = Arrays.copyOf(given, given.length - 1);
            check(given.length == pattern.length(), "bad arguments");
            List<Integer> values = new ArrayList<>();
            String slot = "";
            for (int i = 0; i < given.length; ++i) {
                if (pattern.charAt(i) == 'i') {
                    check(given[i].matches("0|-?[1-9][0-9]{0,6}"), "bad arguments");
                    values.add(Integer.parseInt(given[i]));
                } else {
                    check(given[i].matches("[a-z]{1,8}"), "bad arguments");
                    slot = given[i];
                }
            }
            return new Command(name, values.stream().mapToInt(Integer::intValue).toArray(), slot, fill);
        }

        void execute(String[] words) {
            try {
                Command command = parse(words);
                if (!IMAGELESS.contains(command.name)) check(current != null, "no image");
                if (SLOT_COMMANDS.contains(command.name))
                    check(slots.containsKey(command.slot), "no slot " + command.slot);
                run(command);
            } catch (CommandError error) {
                emit("error: " + error.getMessage());
            }
        }

        void load(List<String> data) {
            try {
                replace(readPgm(data), "loaded");
            } catch (CommandError error) {
                emit("error: load: " + error.getMessage());
            }
        }

        void replace(Image image, String label) {
            current = image;
            undo.clear();
            redo.clear();
            emit(label + " " + image.summary());
        }

        void commit(Image image) {
            commit(image, null);
        }

        void commit(Image image, Integer painted) {
            undo.push(current);
            redo.clear();
            current = image;
            emit("ok " + image.summary() + (painted == null ? "" : " painted " + painted));
        }

        void paint(List<Point> points, int value) {
            Image image = current;
            Set<Integer> touched = new HashSet<>();
            for (Point point : points)
                if (image.contains(point.x, point.y))
                    touched.add(point.y * image.width + point.x);
            int[] pixels = image.pixels.clone();
            for (int index : touched) pixels[index] = value;
            commit(image.withPixels(pixels), touched.size());
        }

        void checkedCrop(int[] a) {
            check(a[0] >= 0 && a[1] >= 0 && a[2] >= 1 && a[3] >= 1);
            check(a[0] + a[2] <= current.width && a[1] + a[3] <= current.height);
        }

        Image matchingSlot(String name) {
            Image saved = slots.get(name);
            check(saved.width == current.width && saved.height == current.height, "size mismatch");
            check(saved.maxval == current.maxval, "maxval mismatch");
            return saved;
        }

        void run(Command cmd) {
            String name = cmd.name, slot = cmd.slot;
            int[] a = cmd.numbers;
            boolean fill = cmd.fill;
            Image image = current;
            int w = image == null ? 0 : image.width;
            int h = image == null ? 0 : image.height;
            int m = image == null ? 0 : image.maxval;

            switch (name) {
                case "NEW" -> {
                    check(a[0] >= 1 && a[0] <= 64 && a[1] >= 1 && a[1] <= 64);
                    check(a[2] >= 1 && a[2] <= 255 && a[3] >= 0 && a[3] <= a[2]);
                    int[] pixels = new int[a[0] * a[1]];
                    Arrays.fill(pixels, a[3]);
                    replace(new Image(a[0], a[1], a[2], pixels), "created");
                }
                case "OUTPUT" -> {
                    emit("P2");
                    emit(w + " " + h);
                    emit(Integer.toString(m));
                    for (int y = 0; y < h; ++y) {
                        StringBuilder line = new StringBuilder();
                        for (int x = 0; x < w; ++x) {
                            if (x > 0) line.append(' ');
                            line.append(image.get(x, y));
                        }
                        emit(line.toString());
                    }
                }
                case "INVERT" -> commit(image.map(p -> m - p));
                case "BRIGHTNESS" -> {
                    check(a[0] >= -255 && a[0] <= 255);
                    commit(image.map(p -> image.clamp(p + a[0])));
                }
                case "CONTRAST" -> {
                    check(a[0] >= 0 && a[0] <= 100 && a[1] >= 1 && a[1] <= 100);
                    int center = (m + 1) / 2;
                    commit(image.map(p -> image.clamp(center + Math.floorDiv((p - center) * a[0], a[1]))));
                }
                case "THRESHOLD" -> {
                    check(a[0] >= 0 && a[0] <= m);
                    commit(image.map(p -> p >= a[0] ? m : 0));
                }
                case "LEVELS" -> {
                    check(a[0] >= 0 && a[0] < a[1] && a[1] <= m);
                    commit(image.map(p -> image.clamp(Math.floorDiv((p - a[0]) * m, a[1] - a[0]))));
                }
                case "POSTERIZE" -> {
                    check(a[0] >= 2 && a[0] <= m + 1);
                    commit(image.map(p -> ((p * a[0]) / (m + 1) * m) / (a[0] - 1)));
                }
                case "MAXVAL" -> {
                    check(a[0] >= 1 && a[0] <= 255);
                    int[] pixels = Arrays.stream(image.pixels).map(p -> (2 * p * a[0] + m) / (2 * m)).toArray();
                    commit(new Image(w, h, a[0], pixels));
                }
                case "FLIPH" -> commit(transformed(image, w, h, (x, y) -> image.get(w - 1 - x, y)));
                case "FLIPV" -> commit(transformed(image, w, h, (x, y) -> image.get(x, h - 1 - y)));
                case "ROTATE" -> {
                    check(a[0] == 90 || a[0] == 180 || a[0] == 270);
                    if (a[0] == 90)
                        commit(transformed(image, h, w, (x, y) -> image.get(y, h - 1 - x)));
                    else if (a[0] == 180)
                        commit(transformed(image, w, h, (x, y) -> image.get(w - 1 - x, h - 1 - y)));
                    else
                        commit(transformed(image, h, w, (x, y) -> image.get(w - 1 - y, x)));
                }
                case "CROP" -> {
                    checkedCrop(a);
                    commit(cropped(image, a[0], a[1], a[2], a[3]));
                }
                case "PAD" -> {
                    check(a[0] >= 1 && a[1] >= 0 && a[1] <= m);
                    check(w + 2 * a[0] <= 64 && h + 2 * a[0] <= 64, "too large");
                    commit(translated(image, w + 2 * a[0], h + 2 * a[0], a[0], a[0], a[1]));
                }
                case "SCALE" -> {
                    check(a[0] >= 1 && a[0] <= 16 && a[1] >= 1 && a[1] <= 16);
                    int width = w * a[0] / a[1], height = h * a[0] / a[1];
                    check(width > 0 && height > 0, "too small");
                    check(width <= 64 && height <= 64, "too large");
                    commit(transformed(image, width, height, (x, y) ->
                        image.get((2 * x + 1) * a[1] / (2 * a[0]),
                                  (2 * y + 1) * a[1] / (2 * a[0]))));
                }
                case "SHIFT" -> {
                    check(withinLimit(a[0], a[1]) && a[2] >= 0 && a[2] <= m);
                    commit(translated(image, w, h, a[0], a[1], a[2]));
                }
                case "TILE" -> {
                    check(a[0] >= 1 && a[1] >= 1);
                    check(w * a[0] <= 64 && h * a[1] <= 64, "too large");
                    commit(transformed(image, w * a[0], h * a[1], (x, y) -> image.get(x % w, y % h)));
                }
                case "BLUR", "GAUSS", "SHARPEN" -> {
                    int[][] kernel = KERNELS.get(name);
                    commit(convolution(image, kernel[0], kernel[1][0]));
                }
                case "CONVOLVE" -> {
                    for (int i = 0; i < 9; ++i) check(a[i] >= -16 && a[i] <= 16);
                    check(a[9] >= 1 && a[9] <= 256);
                    commit(convolution(image, Arrays.copyOf(a, 9), a[9]));
                }
                case "SOBEL" -> commit(sobel(image));
                case "MEDIAN" -> commit(rankFilter(image, 4));
                case "ERODE" -> commit(rankFilter(image, 0));
                case "DILATE" -> commit(rankFilter(image, 8));
                case "OPEN" -> commit(rankFilter(rankFilter(image, 0), 8));
                case "CLOSE" -> commit(rankFilter(rankFilter(image, 8), 0));
                case "GRADIENT" -> {
                    int[] high = rankFilter(image, 8).pixels;
                    int[] low = rankFilter(image, 0).pixels;
                    int[] result = new int[high.length];
                    for (int i = 0; i < result.length; ++i) result[i] = high[i] - low[i];
                    commit(image.withPixels(result));
                }
                case "LINE" -> {
                    check(withinLimit(a[0], a[1], a[2], a[3]) && a[4] >= 0 && a[4] <= m);
                    paint(linePoints(a[0], a[1], a[2], a[3]), a[4]);
                }
                case "RECT" -> {
                    check(withinLimit(a[0], a[1]) && a[2] >= 1 && a[2] <= 1000 &&
                          a[3] >= 1 && a[3] <= 1000 && a[4] >= 0 && a[4] <= m);
                    paint(rectanglePoints(image, a[0], a[1], a[2], a[3], fill), a[4]);
                }
                case "CIRCLE" -> {
                    check(withinLimit(a[0], a[1]) && a[2] >= 0 && a[2] <= 1000 &&
                          a[3] >= 0 && a[3] <= m);
                    List<Point> outline = circlePoints(a[0], a[1], a[2]);
                    paint(fill ? discPoints(image, outline) : outline, a[3]);
                }
                case "FLOOD" -> {
                    check(image.contains(a[0], a[1]) && a[2] >= 0 && a[2] <= m);
                    paint(floodPoints(image, a[0], a[1]), a[2]);
                }
                case "HISTOGRAM" -> {
                    int[] lows = new int[16], highs = new int[16], counts = new int[16];
                    Arrays.fill(lows, -1);
                    for (int value = 0; value <= m; ++value) {
                        int bin = value * 16 / (m + 1);
                        if (lows[bin] < 0) lows[bin] = value;
                        highs[bin] = value;
                    }
                    for (int pixel : image.pixels) ++counts[pixel * 16 / (m + 1)];
                    int top = Arrays.stream(counts).max().orElseThrow();
                    for (int bin = 0; bin < 16; ++bin) {
                        if (lows[bin] < 0) continue;
                        emit(String.format("%3d-%3d %4d |%s", lows[bin], highs[bin],
                                           counts[bin], "#".repeat(counts[bin] * 32 / top)));
                    }
                }
                case "EQUALIZE" -> commit(equalized(image));
                case "LABEL" -> {
                    check(a[0] >= 0 && a[0] <= m);
                    List<List<Point>> groups = components(image, a[0]);
                    emit("labels " + groups.size());
                    for (int i = 0; i < groups.size(); ++i)
                        emit("label " + (i + 1) + " " + componentText(image, a[0], groups.get(i)));
                }
                case "DISTANCE" -> {
                    check(a[0] >= 0 && a[0] <= m);
                    commit(distanceMap(image, a[0]));
                }
                case "STATS" -> emit(statistics(image.pixels, m));
                case "REGION" -> {
                    checkedCrop(a);
                    emit(statistics(cropped(image, a[0], a[1], a[2], a[3]).pixels, m));
                }
                case "DITHER" -> commit(dithered(image));
                case "ASCIIART" -> {
                    String shades = "@#*+=~-:,.";
                    for (int y = 0; y < h; ++y) {
                        StringBuilder row = new StringBuilder();
                        for (int x = 0; x < w; ++x)
                            row.append(shades.charAt(image.get(x, y) * 10 / (m + 1)));
                        emit(row.toString());
                    }
                }
                case "STORE" -> {
                    slots.put(slot, image);
                    emit("stored " + slot + " " + image.summary());
                }
                case "RECALL" -> replace(slots.get(slot), "recalled " + slot);
                case "DROP" -> {
                    slots.remove(slot);
                    emit("dropped " + slot);
                }
                case "BLEND" -> {
                    check(a[0] >= 0 && a[0] <= a[1] && a[1] >= 1 && a[1] <= 100);
                    Image other = matchingSlot(slot);
                    int[] result = new int[image.pixels.length];
                    for (int i = 0; i < result.length; ++i)
                        result[i] = (image.pixels[i] * (a[1] - a[0]) +
                                     other.pixels[i] * a[0]) / a[1];
                    commit(image.withPixels(result));
                }
                case "DIFF" -> {
                    Image other = matchingSlot(slot);
                    int[] result = new int[image.pixels.length];
                    for (int i = 0; i < result.length; ++i)
                        result[i] = Math.abs(image.pixels[i] - other.pixels[i]);
                    commit(image.withPixels(result));
                }
                case "PASTE" -> {
                    check(withinLimit(a[0], a[1]));
                    Image other = slots.get(slot);
                    check(other.maxval == m, "maxval mismatch");
                    int[] result = image.pixels.clone();
                    int painted = 0;
                    for (int y = 0; y < other.height; ++y)
                        for (int x = 0; x < other.width; ++x)
                            if (image.contains(a[0] + x, a[1] + y)) {
                                result[(a[1] + y) * w + a[0] + x] = other.get(x, y);
                                ++painted;
                            }
                    commit(image.withPixels(result), painted);
                }
                case "SLOTS" -> {
                    if (slots.isEmpty()) emit("no slots");
                    List<String> keys = new ArrayList<>(slots.keySet());
                    Collections.sort(keys);
                    for (String key : keys) emit(key + " " + slots.get(key).summary());
                }
                case "INFO" ->
                    emit("image " + (image == null ? "none" : image.summary()) +
                         " undo " + undo.size() + " redo " + redo.size() +
                         " slots " + slots.size());
                case "UNDO" -> {
                    check(!undo.isEmpty(), "nothing to undo");
                    redo.push(current);
                    current = undo.pop();
                    emit("undo " + current.summary());
                }
                case "REDO" -> {
                    check(!redo.isEmpty(), "nothing to redo");
                    undo.push(current);
                    current = redo.pop();
                    emit("redo " + current.summary());
                }
                default -> throw new IllegalStateException("unhandled command " + name);
            }
        }
    }

    public static void main(String[] args) throws IOException {
        BufferedReader input = new BufferedReader(new InputStreamReader(System.in));
        int count = Integer.parseInt(input.readLine());
        Editor editor = new Editor();
        for (int i = 0; i < count; ++i) {
            String[] words = input.readLine().split(" ");
            if (words[0].equals("LOAD")) {
                int length = Integer.parseInt(words[1]);
                List<String> lines = new ArrayList<>();
                for (int j = 0; j < length; ++j) lines.add(input.readLine());
                editor.load(lines);
            } else {
                editor.execute(words);
            }
        }
        for (String line : editor.output) System.out.println(line);
    }
}
