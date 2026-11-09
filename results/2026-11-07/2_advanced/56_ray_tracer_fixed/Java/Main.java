import java.util.*;
import java.nio.file.*;
import java.nio.charset.StandardCharsets;
import java.io.IOException;

public final class Main {
    static final long S = FixedPoint.S;
    static final String[] KINDS = {"primary", "reflection", "refraction", "shadow"};
    static Scene.Data scene;
    static int width, height, contrast, depthLimit, supersampled;
    static long far, epsilon, pad;
    static Node root;
    static Pixel[][] pixels;
    static Stats stats;
    static final Scene.Color BLACK = new Scene.Color(0, 0, 0);
    static final class Node {
        Intersect.Bounds bounds;
        Node left, right;
        List<Scene.Obj> objects;
        int depth;
        long visits;
    }
    static final class LightStats {
        long shadow, blocked, attenuated, backfacing, outside, pixels;
    }
    static final class Stats {
        long[] rays = new long[4], misses = new long[3], depth, nodes = new long[4], objects = new long[4],
               primary, secondary, shadow;
        LightStats[] lights;
        long internal, clamped;
        Stats(int d, int objects, int lights) {
            depth = new long[d + 1];
            primary = new long[objects];
            secondary = new long[objects];
            shadow = new long[objects];
            this.lights = new LightStats[lights];
            for (int i = 0; i < lights; i++)
                this.lights[i] = new LightStats();
        }
    }
    static final class Pixel {
        TraceResult center;
        Scene.Color color;
        long rays;
        int depth, samples = 1;
    }
    static final class Context {
        boolean counted;
        Pixel pixel;
        List<String> record;
        Context(boolean counted, Pixel pixel, List<String> record) {
            this.counted = counted;
            this.pixel = pixel;
            this.record = record;
        }
        void line(String text) {
            if (record != null)
                record.add(text)
            ;
        }
    }
    record Hit(Scene.Obj object, Intersect.Candidate candidate) {}
    static final class Search {
        Hit best;
    }
    record Sample(Vector3 direction, long distance, long intensity) {}
    record Local(Scene.Color color, int illumination, boolean[] lit) {}
    record TraceResult(Scene.Color color, Hit hit, Vector3 point, Vector3 normal, Scene.Color base,
                       int illumination, boolean[] lit) {}
    static long div(long a, long b) {
        return FixedPoint.divide(a, b);
    }
    static List<String> lines(String name) throws IOException {
        return Files.readAllLines(Path.of("input", name), StandardCharsets.US_ASCII);
    }
    static void write(String name, List<String> lines) throws IOException {
        Files.writeString(Path.of("output", name), lines.isEmpty() ? "" : String.join("\n", lines) + "\n",
                          StandardCharsets.US_ASCII);
    }
    static Intersect.Bounds union(List<Scene.Obj> objects) {
        long[] lo = {Long.MAX_VALUE, Long.MAX_VALUE, Long.MAX_VALUE},
               hi = {Long.MIN_VALUE, Long.MIN_VALUE, Long.MIN_VALUE};
        for (Scene.Obj object : objects)
            for (int a = 0; a < 3; a++) {
                lo[a] = Math.min(lo[a], object.bounds.lo().coordinate(a));
                hi[a] = Math.max(hi[a], object.bounds.hi().coordinate(a));
            }
        return new Intersect.Bounds(new Vector3(lo[0], lo[1], lo[2]), new Vector3(hi[0], hi[1], hi[2]));
    }
    static long area(Intersect.Bounds bounds) {
        Vector3 d = bounds.hi().subtract(bounds.lo());
        return d.x() * d.y() + d.y() * d.z() + d.z() * d.x();
    }
    static Node build(List<Scene.Obj> group, int depth) {
        Node node = new Node();
        node.bounds = union(group);
        node.depth = depth;
        if (group.size() <= 2) {
            node.objects = new ArrayList<>(group);
            node.objects.sort(Comparator.comparingInt(o -> o.number));
            for (Scene.Obj object : node.objects)
                object.leafDepth = depth;
            return node;
        }
        long best = Long.MAX_VALUE;
        List<Scene.Obj> chosen = null;
        int split = 0;
        for (int axis = 0; axis < 3; axis++) {
            int a = axis;
            List<Scene.Obj> sorted = new ArrayList<>(group);
            sorted.sort((x, y) -> {
                long cx = div(x.bounds.lo().coordinate(a) + x.bounds.hi().coordinate(a), 2),
                     cy = div(y.bounds.lo().coordinate(a) + y.bounds.hi().coordinate(a), 2);
                int c = Long.compare(cx, cy);
                return c != 0 ? c : Integer.compare(x.number, y.number);
            });
            for (int i = 1; i < sorted.size(); i++) {
                long cost = area(union(sorted.subList(0, i))) * i +
                            area(union(sorted.subList(i, sorted.size()))) * (sorted.size() - i);
                if (cost < best) {
                    best = cost;
                    chosen = sorted;
                    split = i;
                }
            }
        }
        node.left = build(new ArrayList<>(chosen.subList(0, split)), depth + 1);
        node.right = build(new ArrayList<>(chosen.subList(split, chosen.size())), depth + 1);
        return node;
    }
    static void prepare() throws IOException {
        List<String> settings = lines("render.txt");
        String[] size = settings.get(0).split(" ");
        width = Integer.parseInt(size[1]);
        height = Integer.parseInt(size[2]);
        contrast = Integer.parseInt(settings.get(1).split(" ")[1]);
        depthLimit = Integer.parseInt(settings.get(2).split(" ")[1]);
        far = Long.parseLong(settings.get(3).split(" ")[1]);
        epsilon = Long.parseLong(settings.get(4).split(" ")[1]);
        pad = Long.parseLong(settings.get(5).split(" ")[1]);
        List<Scene.Obj> bounded = new ArrayList<>();
        for (Scene.Obj object : scene.objects)
            if (!object.kind.equals("plane")) {
                object.bounds = Intersect.bounds(object, pad);
                bounded.add(object);
            }
        if (!bounded.isEmpty())
            root = build(bounded, 0);
        stats = new Stats(depthLimit, scene.objects.size(), scene.lights.size());
    }
    static Intersect.Candidate test(Scene.Obj object, Vector3 origin, Vector3 direction, int kind,
                                    Context context) {
        if (context.counted)
            stats.objects[kind]++;
        return Intersect.test(object, origin, direction, epsilon);
    }
    static Intersect.Slab test(Node node, Vector3 origin, Vector3 direction, int kind, Context context) {
        if (context.counted) {
            stats.nodes[kind]++;
            node.visits++;
        }
        return Intersect.slab(node.bounds, origin, direction);
    }
    static void consider(Scene.Obj object, Vector3 origin, Vector3 direction, int kind, Context context,
                         Search search) {
        Intersect.Candidate candidate = test(object, origin, direction, kind, context);
        if (candidate != null && candidate.distance() <= far &&
            (search.best == null || candidate.distance() < search.best.candidate().distance() ||
             candidate.distance() == search.best.candidate().distance() &&
                 object.number < search.best.object().number))
            search.best = new Hit(object, candidate);
    }
    static void nearest(Node node, Vector3 origin, Vector3 direction, int kind, Context context,
                        Search search) {
        Intersect.Slab slab = test(node, origin, direction, kind, context);
        if (slab == null || slab.far() <= epsilon || slab.near() > far ||
            search.best != null && slab.near() > search.best.candidate().distance())
            return;
        if (node.objects != null)
            for (Scene.Obj object : node.objects)
                consider(object, origin, direction, kind, context, search);
        else {
            nearest(node.left, origin, direction, kind, context, search);
            nearest(node.right, origin, direction, kind, context, search);
        }
    }
    static Hit nearest(Vector3 origin, Vector3 direction, int kind, Context context) {
        Search search = new Search();
        for (Scene.Obj object : scene.objects)
            if (object.kind.equals("plane"))
                consider(object, origin, direction, kind, context, search);
        if (root != null)
            nearest(root, origin, direction, kind, context, search);
        return search.best;
    }
    static void occluders(Node node, Vector3 origin, Vector3 direction, long distance, Context context,
                          List<Scene.Obj> result) {
        Intersect.Slab slab = test(node, origin, direction, 3, context);
        if (slab == null || slab.far() <= epsilon || slab.near() >= distance)
            return;
        if (node.objects != null)
            for (Scene.Obj object : node.objects) {
                Intersect.Candidate candidate = test(object, origin, direction, 3, context);
                if (candidate != null && candidate.distance() < distance)
                    result.add(object);
            }
        else {
            occluders(node.left, origin, direction, distance, context, result);
            occluders(node.right, origin, direction, distance, context, result);
        }
    }
    static List<Scene.Obj> occluders(Vector3 origin, Vector3 direction, long distance, Context context) {
        List<Scene.Obj> result = new ArrayList<>();
        for (Scene.Obj object : scene.objects)
            if (object.kind.equals("plane")) {
                Intersect.Candidate candidate = test(object, origin, direction, 3, context);
                if (candidate != null && candidate.distance() < distance)
                    result.add(object);
            }
        if (root != null)
            occluders(root, origin, direction, distance, context, result);
        result.sort(Comparator.comparingInt(o -> o.number));
        return result;
    }
    static Vector3 camera(long qx, long qy) {
        long u = div((qx - 2L * width) * scene.hw, 2L * width),
             v = div((2L * height - qy) * scene.hh, 2L * height);
        return scene.forward.add(scene.right.scale(u)).add(scene.up.scale(v)).normalize();
    }
    static List<Sample> samples(Scene.Light light, Vector3 point) {
        List<Sample> result = new ArrayList<>();
        if (light.kind.equals("sun")) {
            result.add(new Sample(light.direction, far, light.intensity));
            return result;
        }
        if (light.kind.equals("area")) {
            int k = light.divisions;
            for (int j = 0; j < k; j++)
                for (int i = 0; i < k; i++) {
                    long[] coordinates = new long[3];
                    for (int a = 0; a < 3; a++)
                        coordinates[a] = light.position.coordinate(a) +
                                         div((2L * i + 1) * light.u.coordinate(a), 2L * k) +
                                         div((2L * j + 1) * light.v.coordinate(a), 2L * k);
                    Vector3 relative =
                        new Vector3(coordinates[0], coordinates[1], coordinates[2]).subtract(point);
                    result.add(new Sample(relative.normalize(), relative.length(),
                                          div(light.intensity, light.samples())));
                }
        } else {
            Vector3 relative = light.position.subtract(point);
            result.add(new Sample(relative.normalize(), relative.length(), light.intensity));
        }
        return result;
    }
    static long cone(Scene.Light light, Vector3 direction) {
        if (!light.kind.equals("spot"))
            return S;
        long cosine = -direction.dot(light.direction);
        if (cosine <= light.outer)
            return 0;
        if (cosine >= light.inner)
            return S;
        return div((cosine - light.outer) * S, light.inner - light.outer);
    }
    static Local local(Hit hit, Vector3 point, Vector3 normal, Scene.Color base, Vector3 direction,
                       Context context) {
        long diffuseSum = 0, specularSum = 0;
        boolean[] lit = new boolean[scene.lights.size()];
        int illumination = 0;
        for (Scene.Light light : scene.lights) {
            long diffuse = 0, specular = 0;
            int count = 0;
            LightStats lightStats = stats.lights[light.number - 1];
            for (Sample sample : samples(light, point)) {
                long ndl = normal.dot(sample.direction());
                if (ndl <= 0) {
                    if (context.counted)
                        lightStats.backfacing++;
                    continue;
                }
                long factor = cone(light, sample.direction());
                if (factor == 0) {
                    if (context.counted)
                        lightStats.outside++;
                    continue;
                }
                if (context.counted) {
                    stats.rays[3]++;
                    lightStats.shadow++;
                    context.pixel.rays++;
                }
                List<Scene.Obj> blockers = occluders(point, sample.direction(), sample.distance(), context);
                for (Scene.Obj object : blockers) {
                    factor = FixedPoint.multiply(factor, object.material.kt);
                    if (context.counted)
                        stats.shadow[object.number - 1]++;
                }
                if (factor == 0) {
                    if (context.counted)
                        lightStats.blocked++;
                    continue;
                }
                if (!blockers.isEmpty() && context.counted)
                    lightStats.attenuated++;
                count++;
                Shading.Phong phong = Shading.phong(hit.object().material, normal, sample.direction(),
                                                    direction.negate(), ndl, sample.intensity(), factor);
                diffuse += phong.diffuse();
                specular += phong.specular();
            }
            if (count > 0) {
                lit[light.number - 1] = true;
                illumination++;
            }
            diffuseSum += diffuse;
            specularSum += specular;
            context.line("light " + light.number + " lit " + count + " of " + light.samples() + " diffuse " +
                         diffuse + " specular " + specular);
        }
        long[] color = new long[3];
        for (int c = 0; c < 3; c++) {
            long raw = div(base.component(c) * (scene.ambient + diffuseSum), S) + div(255 * specularSum, S);
            if (raw > 255 && context.counted)
                stats.clamped++;
            color[c] = Math.min(raw, 255);
        }
        Scene.Color result = Scene.Color.of(color);
        context.line("local " + result);
        return new Local(result, illumination, lit);
    }
    static TraceResult trace(Vector3 origin, Vector3 direction, int kind, int depth, Context context) {
        if (context.counted) {
            stats.rays[kind]++;
            stats.depth[depth]++;
            context.pixel.rays++;
            context.pixel.depth = Math.max(context.pixel.depth, depth);
        }
        context.line("ray " + KINDS[kind] + " " + depth + " origin " + origin + " direction " + direction);
        Hit hit = nearest(origin, direction, kind, context);
        if (hit == null) {
            if (context.counted)
                stats.misses[kind]++;
            context.line("miss");
            context.line("color " + scene.background);
            return new TraceResult(scene.background, null, null, null, null, 0, null);
        }
        if (context.counted) {
            if (kind == 0)
                stats.primary[hit.object().number - 1]++;
            else
                stats.secondary[hit.object().number - 1]++;
        }
        Vector3 point = origin.add(direction.scale(hit.candidate().distance())),
                outward = Intersect.outward(hit.object(), hit.candidate(), point, direction);
        boolean front = outward.dot(direction) <= 0;
        Vector3 normal = front ? outward : outward.negate();
        Scene.Color base = Shading.base(hit.object().material, point);
        context.line("hit " + hit.object().label + " t " + hit.candidate().distance() + " point " + point +
                     " normal " + normal + " base " + base);
        Local local = local(hit, point, normal, base, direction, context);
        Scene.Color color = local.color();
        Scene.Material material = hit.object().material;
        if (depth < depthLimit && (material.kr != 0 || material.kt != 0)) {
            Shading.Refraction refraction = Shading.refracted(material, direction, normal, front);
            if (refraction.internal()) {
                if (context.counted)
                    stats.internal++;
                context.line("total_internal_reflection");
            }
            context.line("weights " + (S - material.kr - material.kt) + " " + refraction.reflected() + " " +
                         refraction.transmitted());
            Scene.Color reflected = BLACK, transmitted = BLACK;
            if (refraction.reflected() > 0)
                reflected = trace(point, Shading.reflected(direction, normal), 1, depth + 1, context).color();
            if (refraction.transmitted() > 0)
                transmitted = trace(point, refraction.direction(), 2, depth + 1, context).color();
            color = Shading.mix(
                new Scene.Color[] {color, reflected, transmitted},
                new long[] {S - material.kr - material.kt, refraction.reflected(), refraction.transmitted()});
        }
        if (scene.fog != null) {
            long t = hit.candidate().distance(),
                 factor = t <= scene.fogStart ? 0
                          : t >= scene.fogEnd ? S
                                              : div((t - scene.fogStart) * S, scene.fogEnd - scene.fogStart);
            color = Shading.mix(new Scene.Color[] {color, scene.fog}, new long[] {S - factor, factor});
        }
        context.line("color " + color);
        return new TraceResult(color, hit, point, normal, base, local.illumination(), local.lit());
    }

    static long minimumDistance = Long.MAX_VALUE, maximumDistance = Long.MIN_VALUE, maxPixelRays;
    static char label(Pixel pixel) {
        return pixel.center.hit() == null ? '.' : pixel.center.hit().object().label;
    }
    static long contrast(Scene.Color a, Scene.Color b) {
        long maximum = 0;
        for (int c = 0; c < 3; c++)
            maximum = Math.max(maximum, Math.abs(a.component(c) - b.component(c)));
        return maximum;
    }
    static void render() {
        pixels = new Pixel[height][width];
        for (int y = 0; y < height; y++)
            for (int x = 0; x < width; x++) {
                Pixel pixel = new Pixel();
                pixels[y][x] = pixel;
                Context context = new Context(true, pixel, null);
                pixel.center = trace(scene.eye, camera(4L * x + 2, 4L * y + 2), 0, 0, context);
                pixel.color = pixel.center.color();
                if (pixel.center.hit() != null)
                    for (int l = 0; l < scene.lights.size(); l++)
                        if (pixel.center.lit()[l])
                            stats.lights[l].pixels++;
            }
        for (int y = 0; y < height; y++)
            for (int x = 0; x < width; x++) {
                Pixel pixel = pixels[y][x];
                boolean adaptive = false;
                for (int[] offset : new int[][] {{-1, 0}, {1, 0}, {0, -1}, {0, 1}}) {
                    int xx = x + offset[0], yy = y + offset[1];
                    if (xx >= 0 && xx < width && yy >= 0 && yy < height) {
                        Pixel neighbor = pixels[yy][xx];
                        if (label(pixel) != label(neighbor) ||
                            contrast(pixel.center.color(), neighbor.center.color()) > contrast)
                            adaptive = true;
                    }
                }
                if (adaptive) {
                    supersampled++;
                    pixel.samples = 4;
                    long[] sum = new long[3];
                    Context context = new Context(true, pixel, null);
                    for (int dy = 1; dy <= 3; dy += 2)
                        for (int dx = 1; dx <= 3; dx += 2) {
                            Scene.Color color =
                                trace(scene.eye, camera(4L * x + dx, 4L * y + dy), 0, 0, context).color();
                            for (int c = 0; c < 3; c++)
                                sum[c] += color.component(c);
                        }
                    pixel.color = new Scene.Color(div(sum[0], 4), div(sum[1], 4), div(sum[2], 4));
                }
                if (pixel.center.hit() != null) {
                    long t = pixel.center.hit().candidate().distance();
                    minimumDistance = Math.min(minimumDistance, t);
                    maximumDistance = Math.max(maximumDistance, t);
                }
                maxPixelRays = Math.max(maxPixelRays, pixel.rays);
            }
    }
    static long clamp(long value) {
        return Math.max(0, Math.min(255, value));
    }
    static List<String> header(String kind) {
        return new ArrayList<>(List.of(kind, width + " " + height, "255"));
    }
    static void images() throws IOException {
        List<String> image = header("P3"), depth = header("P2"), normal = header("P3"), albedo = header("P3"),
                     cost = header("P2"), objects = new ArrayList<>(), lights = new ArrayList<>(),
                     rayDepth = new ArrayList<>();
        for (int y = 0; y < height; y++) {
            List<String> colors = new ArrayList<>(), distances = new ArrayList<>(),
                         normals = new ArrayList<>(), bases = new ArrayList<>(), costs = new ArrayList<>();
            StringBuilder labels = new StringBuilder(), illumination = new StringBuilder(),
                          depths = new StringBuilder();
            for (int x = 0; x < width; x++) {
                Pixel pixel = pixels[y][x];
                colors.add(pixel.color.toString());
                costs.add(Long.toString(div(255 * pixel.rays, maxPixelRays)));
                labels.append(label(pixel));
                depths.append((char)('0' + pixel.depth));
                if (pixel.center.hit() == null) {
                    distances.add("0");
                    normals.add(BLACK.toString());
                    bases.add(BLACK.toString());
                    illumination.append('.');
                } else {
                    long t = pixel.center.hit().candidate().distance();
                    distances.add(Long.toString(
                        maximumDistance == minimumDistance
                            ? 255
                            : 255 - div(235 * (t - minimumDistance), maximumDistance - minimumDistance)));
                    Vector3 n = pixel.center.normal();
                    Scene.Color color = new Scene.Color(clamp(div((n.x() + S) * 255, 2 * S)),
                                                        clamp(div((n.y() + S) * 255, 2 * S)),
                                                        clamp(div((n.z() + S) * 255, 2 * S)));
                    normals.add(color.toString());
                    bases.add(pixel.center.base().toString());
                    illumination.append((char)('0' + pixel.center.illumination()));
                }
            }
            image.add(String.join(" ", colors));
            depth.add(String.join(" ", distances));
            normal.add(String.join(" ", normals));
            albedo.add(String.join(" ", bases));
            cost.add(String.join(" ", costs));
            objects.add(labels.toString());
            lights.add(illumination.toString());
            rayDepth.add(depths.toString());
        }
        write("image.ppm", image);
        write("depth.pgm", depth);
        write("normal.ppm", normal);
        write("albedo.ppm", albedo);
        write("cost.pgm", cost);
        write("object_map.txt", objects);
        write("light_map.txt", lights);
        write("ray_depth.txt", rayDepth);
    }
    static String labels(List<Scene.Obj> objects) {
        StringBuilder text = new StringBuilder();
        for (Scene.Obj object : objects)
            text.append(object.label);
        return text.toString();
    }
    static void nodes(Node node, List<String> out) {
        String description = node.objects == null ? "inner" : "leaf " + labels(node.objects);
        out.add("node " + node.depth + " " + description + " box " + node.bounds.lo() + " " +
                node.bounds.hi() + " visits " + node.visits);
        if (node.objects == null) {
            nodes(node.left, out);
            nodes(node.right, out);
        }
    }
    static List<String> statistics() {
        List<String> out = new ArrayList<>();
        out.add("image " + width + " " + height);
        out.add("supersampled " + supersampled);
        long total = 0;
        for (long value : stats.rays)
            total += value;
        out.add("rays primary " + stats.rays[0] + " reflection " + stats.rays[1] + " refraction " +
                stats.rays[2] + " shadow " + stats.rays[3] + " total " + total);
        out.add("misses primary " + stats.misses[0] + " reflection " + stats.misses[1] + " refraction " +
                stats.misses[2]);
        String line = "depth";
        for (long value : stats.depth)
            line += " " + value;
        out.add(line);
        for (int kind = 0; kind < 4; kind++)
            out.add("tests " + KINDS[kind] + " nodes " + stats.nodes[kind] + " objects " +
                    stats.objects[kind]);
        out.add("total_internal_reflection " + stats.internal);
        out.add("clamped " + stats.clamped);
        out.add(minimumDistance == Long.MAX_VALUE ? "distance none"
                                                  : "distance " + minimumDistance + " " + maximumDistance);
        out.add("max_pixel_rays " + maxPixelRays);
        long[] sum = new long[3], histogram = new long[8];
        for (Pixel[] row : pixels)
            for (Pixel pixel : row) {
                for (int c = 0; c < 3; c++)
                    sum[c] += pixel.color.component(c);
                long brightness =
                    div(299 * pixel.color.r() + 587 * pixel.color.g() + 114 * pixel.color.b(), 1000);
                histogram[(int)div(brightness, 32)]++;
            }
        out.add("mean " + new Scene.Color(div(sum[0], width * height), div(sum[1], width * height),
                                          div(sum[2], width * height)));
        line = "histogram";
        for (long value : histogram)
            line += " " + value;
        out.add(line);
        if (root != null)
            nodes(root, out);
        for (Scene.Obj object : scene.objects) {
            int count = 0, x0 = width, y0 = height, x1 = -1, y1 = -1;
            Arrays.fill(sum, 0);
            for (int y = 0; y < height; y++)
                for (int x = 0; x < width; x++)
                    if (label(pixels[y][x]) == object.label) {
                        count++;
                        x0 = Math.min(x0, x);
                        y0 = Math.min(y0, y);
                        x1 = Math.max(x1, x);
                        y1 = Math.max(y1, y);
                        for (int c = 0; c < 3; c++)
                            sum[c] += pixels[y][x].color.component(c);
                    }
            String box = count == 0 ? "none" : x0 + " " + y0 + " " + x1 + " " + y1,
                   color = count == 0
                               ? "none"
                               : new Scene.Color(div(sum[0], count), div(sum[1], count), div(sum[2], count))
                                     .toString();
            int i = object.number - 1;
            out.add("object " + object.label + " " + object.kind + " primary " + stats.primary[i] +
                    " secondary " + stats.secondary[i] + " shadow " + stats.shadow[i] + " pixels " + count +
                    " box " + box + " color " + color);
        }
        for (Scene.Light light : scene.lights) {
            LightStats s = stats.lights[light.number - 1];
            out.add("light " + light.number + " " + light.kind + " samples " + light.samples() + " pixels " +
                    s.pixels + " shadow_rays " + s.shadow + " blocked " + s.blocked + " attenuated " +
                    s.attenuated + " backfacing " + s.backfacing + " outside " + s.outside);
        }
        return out;
    }
    static List<String> queries() throws IOException {
        List<String> out = new ArrayList<>(), queries = lines("queries.txt");
        Context context = new Context(false, null, null);
        for (int q = 0; q < queries.size(); q++) {
            String line = queries.get(q);
            out.add("query " + (q + 1) + " " + line);
            String[] words = line.split(" ");
            switch (words[0]) {
            case "pixel" -> {
                int x = Integer.parseInt(words[1]), y = Integer.parseInt(words[2]);
                Pixel pixel = pixels[y][x];
                out.add("label " + label(pixel) + " distance " +
                        (pixel.center.hit() == null
                             ? "none"
                             : Long.toString(pixel.center.hit().candidate().distance())) +
                        " color " + pixel.color + " samples " + pixel.samples + " rays " + pixel.rays);
            }
            case "trace" -> {
                int x = Integer.parseInt(words[1]), y = Integer.parseInt(words[2]);
                trace(scene.eye, camera(4L * x + 2, 4L * y + 2), 0, 0, new Context(false, null, out));
            }
            case "ray" ->
                trace(Scene.vector(words, 1), Scene.vector(words, 4).normalize(), 0, 0,
                      new Context(false, null, out));
            case "object" -> {
                Scene.Obj object = null;
                for (Scene.Obj candidate : scene.objects)
                    if (candidate.label == words[1].charAt(0)) {
                        object = candidate;
                        break;
                    }
                out.add(object.kind + " material " + object.material.name + " bounds " +
                        (object.kind.equals("plane")
                             ? "none leaf none"
                             : object.bounds.lo() + " " + object.bounds.hi() + " leaf " + object.leafDepth));
            }
            case "visible" -> {
                Vector3 relative = Scene.vector(words, 1).subtract(scene.eye), direction =
                                                                                   relative.normalize();
                boolean visible =
                    occluders(scene.eye, direction, relative.length() - epsilon, context).isEmpty();
                Hit first = nearest(scene.eye, direction, 0, context);
                out.add(
                    (visible ? "yes" : "no") + " first " +
                    (first == null ? "none" : first.object().label + " t " + first.candidate().distance()));
            }
            case "shadow" -> {
                Vector3 point = Scene.vector(words, 1);
                for (Scene.Light light : scene.lights) {
                    Set<Scene.Obj> seen = new HashSet<>();
                    long transmittance = 0;
                    for (Sample sample : samples(light, point)) {
                        long factor = cone(light, sample.direction());
                        List<Scene.Obj> blockers =
                            occluders(point, sample.direction(), sample.distance(), context);
                        seen.addAll(blockers);
                        for (Scene.Obj object : blockers)
                            factor = FixedPoint.multiply(factor, object.material.kt);
                        transmittance += factor;
                    }
                    List<Scene.Obj> blockers = new ArrayList<>();
                    for (Scene.Obj object : scene.objects)
                        if (seen.contains(object))
                            blockers.add(object);
                    out.add("light " + light.number + " factor " + transmittance + " occluders " +
                            (blockers.isEmpty() ? "none" : labels(blockers)));
                }
            }
            case "region" -> {
                int x0 = Integer.parseInt(words[1]), y0 = Integer.parseInt(words[2]),
                    x1 = Integer.parseInt(words[3]), y1 = Integer.parseInt(words[4]),
                    count = (x1 - x0 + 1) * (y1 - y0 + 1);
                long[] sum = new long[3];
                Map<Character, Integer> counts = new HashMap<>();
                for (int y = y0; y <= y1; y++)
                    for (int x = x0; x <= x1; x++) {
                        Pixel pixel = pixels[y][x];
                        char label = label(pixel);
                        counts.put(label, counts.getOrDefault(label, 0) + 1);
                        for (int c = 0; c < 3; c++)
                            sum[c] += pixel.color.component(c);
                    }
                out.add("pixels " + count + " mean " +
                        new Scene.Color(div(sum[0], count), div(sum[1], count), div(sum[2], count)));
                for (Scene.Obj object : scene.objects)
                    if (counts.getOrDefault(object.label, 0) > 0)
                        out.add("label " + object.label + " " + counts.get(object.label));
                if (counts.getOrDefault('.', 0) > 0)
                    out.add("label . " + counts.get('.'));
            }
            }
        }
        return out;
    }
    public static void main(String[] args) throws IOException {
        scene = Scene.read();
        prepare();
        render();
        images();
        write("stats.txt", statistics());
        write("queries.txt", queries());
    }
}
