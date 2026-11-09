using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public static class Program {
    public static readonly long S = FixedPoint.S;
    public static readonly string[] KINDS = { "primary", "reflection", "refraction", "shadow" };
    public static Scene.Data scene;
    public static int width, height, contrast, depthLimit, supersampled;
    public static long far, epsilon, pad;
    public static Node root;
    public static Pixel[][] pixels;
    public static Stats stats;
    public static readonly Scene.Color BLACK = new Scene.Color(0, 0, 0);
    public sealed class Node {
        public Intersect.Bounds bounds;
        public Node left, right;
        public List<Scene.Obj> objects;
        public int depth;
        public long visits;
    }
    public sealed class LightStats {
        public long shadow, blocked, attenuated, backfacing, outside, pixels;
    }
    public sealed class Stats {
        public long[] rays = new long[4], misses = new long[3], depth, nodes = new long[4],
                      objects = new long[4], primary, secondary, shadow;
        public LightStats[] lights;
        public long totalInternal, clamped;
        public Stats(int d, int objects, int lights) {
            depth = new long[d + 1];
            primary = new long[objects];
            secondary = new long[objects];
            shadow = new long[objects];
            this.lights = new LightStats[lights];
            for (int i = 0; i < lights; i++)
                this.lights[i] = new LightStats();
        }
    }
    public sealed class Pixel {
        public TraceResult center;
        public Scene.Color color;
        public long rays;
        public int depth, samples = 1;
    }
    public sealed class Context {
        public bool counted;
        public Pixel pixel;
        public List<string> record;
        public Context(bool counted, Pixel pixel, List<string> record) {
            this.counted = counted;
            this.pixel = pixel;
            this.record = record;
        }
        public void Line(string text) {
            if (record != null)
                record.Add(text);
        }
    }
    public record Hit(Scene.Obj sceneObject, Intersect.Candidate candidate) {
    }
    public sealed class Search {
        public Hit best;
    }
    public record Sample(Vector3 direction, long distance, long intensity) {
    }
    public record Local(Scene.Color color, int illumination, bool[] lit) {
    }
    public record TraceResult(Scene.Color color, Hit hit, Vector3 point, Vector3 normal,
                              Scene.Color baseColor, int illumination, bool[] lit) {
    }
    public static long Div(long a, long b) {
        return FixedPoint.Divide(a, b);
    }
    public static List<string> Lines(string name) {
        return File.ReadAllLines(Path.Combine("input", name), Encoding.ASCII).ToList();
    }
    public static void Write(string name, List<string> lines) {
        File.WriteAllText(Path.Combine("output", name),
                          lines.Count == 0 ? "" : string.Join("\n", lines) + "\n", Encoding.ASCII);
    }
    public static Intersect.Bounds Union(List<Scene.Obj> objects) {
        long[] lo = { long.MaxValue, long.MaxValue, long.MaxValue },
               hi = { long.MinValue, long.MinValue, long.MinValue };
        foreach (Scene.Obj sceneObject in objects)
            for (int a = 0; a < 3; a++) {
                lo[a] = Math.Min(lo[a], sceneObject.bounds.lo.Coordinate(a));
                hi[a] = Math.Max(hi[a], sceneObject.bounds.hi.Coordinate(a));
            }
        return new Intersect.Bounds(new Vector3(lo[0], lo[1], lo[2]), new Vector3(hi[0], hi[1], hi[2]));
    }
    public static long Area(Intersect.Bounds bounds) {
        Vector3 d = bounds.hi.Subtract(bounds.lo);
        return d.x * d.y + d.y * d.z + d.z * d.x;
    }
    public static Node Build(List<Scene.Obj> group, int depth) {
        Node node = new Node();
        node.bounds = Union(group);
        node.depth = depth;
        if (group.Count <= 2) {
            node.objects = new(group);
            node.objects.Sort(Comparer<Scene.Obj>.Create((a, b) => a.number.CompareTo(b.number)));
            foreach (Scene.Obj sceneObject in node.objects)
                sceneObject.leafDepth = depth;
            return node;
        }
        long best = long.MaxValue;
        List<Scene.Obj> chosen = null;
        int split = 0;
        for (int axis = 0; axis < 3; axis++) {
            int a = axis;
            List<Scene.Obj> sorted = new(group);
            sorted.Sort((x, y) => {
                long cx = Div(x.bounds.lo.Coordinate(a) + x.bounds.hi.Coordinate(a), 2),
                     cy = Div(y.bounds.lo.Coordinate(a) + y.bounds.hi.Coordinate(a), 2);
                int c = (cx).CompareTo(cy);
                return c != 0 ? c : (x.number).CompareTo(y.number);
            });
            for (int i = 1; i < sorted.Count; i++) {
                long cost = Area(Union(sorted.GetRange(0, i - (0)))) * i +
                            Area(Union(sorted.GetRange(i, sorted.Count - (i)))) * (sorted.Count - i);
                if (cost < best) {
                    best = cost;
                    chosen = sorted;
                    split = i;
                }
            }
        }
        node.left = Build(new(chosen.GetRange(0, split - (0))), depth + 1);
        node.right = Build(new(chosen.GetRange(split, chosen.Count - (split))), depth + 1);
        return node;
    }
    public static void Prepare() {
        List<string> settings = Lines("render.txt");
        string[] size = settings[0].Split(' ');
        width = int.Parse(size[1]);
        height = int.Parse(size[2]);
        contrast = int.Parse(settings[1].Split(' ')[1]);
        depthLimit = int.Parse(settings[2].Split(' ')[1]);
        far = long.Parse(settings[3].Split(' ')[1]);
        epsilon = long.Parse(settings[4].Split(' ')[1]);
        pad = long.Parse(settings[5].Split(' ')[1]);
        List<Scene.Obj> bounded = new();
        foreach (Scene.Obj sceneObject in scene.objects)
            if (!sceneObject.kind.Equals("plane")) {
                sceneObject.bounds = Intersect.ObjectBounds(sceneObject, pad);
                bounded.Add(sceneObject);
            }
        if (bounded.Count != 0)
            root = Build(bounded, 0);
        stats = new Stats(depthLimit, scene.objects.Count, scene.lights.Count);
    }
    public static Intersect.Candidate Test(Scene.Obj sceneObject, Vector3 origin, Vector3 direction, int kind,
                                           Context context) {
        if (context.counted)
            stats.objects[kind]++;
        return Intersect.Test(sceneObject, origin, direction, epsilon);
    }
    public static Intersect.Slab Test(Node node, Vector3 origin, Vector3 direction, int kind,
                                      Context context) {
        if (context.counted) {
            stats.nodes[kind]++;
            node.visits++;
        }
        return Intersect.SlabTest(node.bounds, origin, direction);
    }
    public static void Consider(Scene.Obj sceneObject, Vector3 origin, Vector3 direction, int kind,
                                Context context, Search search) {
        Intersect.Candidate candidate = Test(sceneObject, origin, direction, kind, context);
        if (candidate != null && candidate.distance <= far &&
            (search.best == null || candidate.distance < search.best.candidate.distance ||
             candidate.distance == search.best.candidate.distance &&
                 sceneObject.number < search.best.sceneObject.number))
            search.best = new Hit(sceneObject, candidate);
    }
    public static void Nearest(Node node, Vector3 origin, Vector3 direction, int kind, Context context,
                               Search search) {
        Intersect.Slab slab = Test(node, origin, direction, kind, context);
        if (slab == null || slab.far <= epsilon || slab.near > far ||
            search.best != null && slab.near > search.best.candidate.distance)
            return;
        if (node.objects != null)
            foreach (Scene.Obj sceneObject in node.objects)
                Consider(sceneObject, origin, direction, kind, context, search);
        else {
            Nearest(node.left, origin, direction, kind, context, search);
            Nearest(node.right, origin, direction, kind, context, search);
        }
    }
    public static Hit Nearest(Vector3 origin, Vector3 direction, int kind, Context context) {
        Search search = new Search();
        foreach (Scene.Obj sceneObject in scene.objects)
            if (sceneObject.kind.Equals("plane"))
                Consider(sceneObject, origin, direction, kind, context, search);
        if (root != null)
            Nearest(root, origin, direction, kind, context, search);
        return search.best;
    }
    public static void Occluders(Node node, Vector3 origin, Vector3 direction, long distance, Context context,
                                 List<Scene.Obj> result) {
        Intersect.Slab slab = Test(node, origin, direction, 3, context);
        if (slab == null || slab.far <= epsilon || slab.near >= distance)
            return;
        if (node.objects != null)
            foreach (Scene.Obj sceneObject in node.objects) {
                Intersect.Candidate candidate = Test(sceneObject, origin, direction, 3, context);
                if (candidate != null && candidate.distance < distance)
                    result.Add(sceneObject);
            }
        else {
            Occluders(node.left, origin, direction, distance, context, result);
            Occluders(node.right, origin, direction, distance, context, result);
        }
    }
    public static List<Scene.Obj> Occluders(Vector3 origin, Vector3 direction, long distance,
                                            Context context) {
        List<Scene.Obj> result = new();
        foreach (Scene.Obj sceneObject in scene.objects)
            if (sceneObject.kind.Equals("plane")) {
                Intersect.Candidate candidate = Test(sceneObject, origin, direction, 3, context);
                if (candidate != null && candidate.distance < distance)
                    result.Add(sceneObject);
            }
        if (root != null)
            Occluders(root, origin, direction, distance, context, result);
        result.Sort(Comparer<Scene.Obj>.Create((a, b) => a.number.CompareTo(b.number)));
        return result;
    }
    public static Vector3 Camera(long qx, long qy) {
        long u = Div((qx - 2L * width) * scene.hw, 2L * width),
             v = Div((2L * height - qy) * scene.hh, 2L * height);
        return scene.forward.Add(scene.right.Scale(u)).Add(scene.up.Scale(v)).Normalize();
    }
    public static List<Sample> Samples(Scene.Light light, Vector3 point) {
        List<Sample> result = new();
        if (light.kind.Equals("sun")) {
            result.Add(new Sample(light.direction, far, light.intensity));
            return result;
        }
        if (light.kind.Equals("area")) {
            int k = light.divisions;
            for (int j = 0; j < k; j++)
                for (int i = 0; i < k; i++) {
                    long[] coordinates = new long[3];
                    for (int a = 0; a < 3; a++)
                        coordinates[a] = light.position.Coordinate(a) +
                                         Div((2L * i + 1) * light.u.Coordinate(a), 2L * k) +
                                         Div((2L * j + 1) * light.v.Coordinate(a), 2L * k);
                    Vector3 relative =
                        new Vector3(coordinates[0], coordinates[1], coordinates[2]).Subtract(point);
                    result.Add(new Sample(relative.Normalize(), relative.Length(),
                                          Div(light.intensity, light.Samples())));
                }
        } else {
            Vector3 relative = light.position.Subtract(point);
            result.Add(new Sample(relative.Normalize(), relative.Length(), light.intensity));
        }
        return result;
    }
    public static long Cone(Scene.Light light, Vector3 direction) {
        if (!light.kind.Equals("spot"))
            return S;
        long cosine = -direction.Dot(light.direction);
        if (cosine <= light.outer)
            return 0;
        if (cosine >= light.inner)
            return S;
        return Div((cosine - light.outer) * S, light.inner - light.outer);
    }
    public static Local LocalColor(Hit hit, Vector3 point, Vector3 normal, Scene.Color baseColor,
                                   Vector3 direction, Context context) {
        long diffuseSum = 0, specularSum = 0;
        bool[] lit = new bool[scene.lights.Count];
        int illumination = 0;
        foreach (Scene.Light light in scene.lights) {
            long diffuse = 0, specular = 0;
            int count = 0;
            LightStats lightStats = stats.lights[light.number - 1];
            foreach (Sample sample in Samples(light, point)) {
                long ndl = normal.Dot(sample.direction);
                if (ndl <= 0) {
                    if (context.counted)
                        lightStats.backfacing++;
                    continue;
                }
                long factor = Cone(light, sample.direction);
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
                List<Scene.Obj> blockers = Occluders(point, sample.direction, sample.distance, context);
                foreach (Scene.Obj sceneObject in blockers) {
                    factor = FixedPoint.Multiply(factor, sceneObject.material.kt);
                    if (context.counted)
                        stats.shadow[sceneObject.number - 1]++;
                }
                if (factor == 0) {
                    if (context.counted)
                        lightStats.blocked++;
                    continue;
                }
                if (blockers.Count != 0 && context.counted)
                    lightStats.attenuated++;
                count++;
                Shading.Phong phong = Shading.PhongTerms(hit.sceneObject.material, normal, sample.direction,
                                                         direction.Negate(), ndl, sample.intensity, factor);
                diffuse += phong.diffuse;
                specular += phong.specular;
            }
            if (count > 0) {
                lit[light.number - 1] = true;
                illumination++;
            }
            diffuseSum += diffuse;
            specularSum += specular;
            context.Line("light " + light.number + " lit " + count + " of " + light.Samples() + " diffuse " +
                         diffuse + " specular " + specular);
        }
        long[] color = new long[3];
        for (int c = 0; c < 3; c++) {
            long raw =
                Div(baseColor.Component(c) * (scene.ambient + diffuseSum), S) + Div(255 * specularSum, S);
            if (raw > 255 && context.counted)
                stats.clamped++;
            color[c] = Math.Min(raw, 255);
        }
        Scene.Color result = Scene.Color.Of(color);
        context.Line("local " + result);
        return new Local(result, illumination, lit);
    }
    public static TraceResult Trace(Vector3 origin, Vector3 direction, int kind, int depth, Context context) {
        if (context.counted) {
            stats.rays[kind]++;
            stats.depth[depth]++;
            context.pixel.rays++;
            context.pixel.depth = Math.Max(context.pixel.depth, depth);
        }
        context.Line("ray " + KINDS[kind] + " " + depth + " origin " + origin + " direction " + direction);
        Hit hit = Nearest(origin, direction, kind, context);
        if (hit == null) {
            if (context.counted)
                stats.misses[kind]++;
            context.Line("miss");
            context.Line("color " + scene.background);
            return new TraceResult(scene.background, null, null, null, null, 0, null);
        }
        if (context.counted) {
            if (kind == 0)
                stats.primary[hit.sceneObject.number - 1]++;
            else
                stats.secondary[hit.sceneObject.number - 1]++;
        }
        Vector3 point = origin.Add(direction.Scale(hit.candidate.distance)),
                outward = Intersect.Outward(hit.sceneObject, hit.candidate, point, direction);
        bool front = outward.Dot(direction) <= 0;
        Vector3 normal = front ? outward : outward.Negate();
        Scene.Color baseColor = Shading.Base(hit.sceneObject.material, point);
        context.Line("hit " + hit.sceneObject.label + " t " + hit.candidate.distance + " point " + point +
                     " normal " + normal + " base " + baseColor);
        Local local = LocalColor(hit, point, normal, baseColor, direction, context);
        Scene.Color color = local.color;
        Scene.Material material = hit.sceneObject.material;
        if (depth < depthLimit && (material.kr != 0 || material.kt != 0)) {
            Shading.Refraction refraction = Shading.Refracted(material, direction, normal, front);
            if (refraction.totalInternal) {
                if (context.counted)
                    stats.totalInternal++;
                context.Line("total_internal_reflection");
            }
            context.Line("weights " + (S - material.kr - material.kt) + " " + refraction.reflected + " " +
                         refraction.transmitted);
            Scene.Color reflected = BLACK, transmitted = BLACK;
            if (refraction.reflected > 0)
                reflected = Trace(point, Shading.Reflected(direction, normal), 1, depth + 1, context).color;
            if (refraction.transmitted > 0)
                transmitted = Trace(point, refraction.direction, 2, depth + 1, context).color;
            color = Shading.Mix(
                new Scene.Color[] { color, reflected, transmitted },
                new long[] { S - material.kr - material.kt, refraction.reflected, refraction.transmitted });
        }
        if (scene.fog != null) {
            long t = hit.candidate.distance,
                 factor = t <= scene.fogStart ? 0
                          : t >= scene.fogEnd ? S
                                              : Div((t - scene.fogStart) * S, scene.fogEnd - scene.fogStart);
            color = Shading.Mix(new Scene.Color[] { color, scene.fog }, new long[] { S - factor, factor });
        }
        context.Line("color " + color);
        return new TraceResult(color, hit, point, normal, baseColor, local.illumination, local.lit);
    }

    public static long minimumDistance = long.MaxValue, maximumDistance = long.MinValue, maxPixelRays;
    public static char Label(Pixel pixel) {
        return pixel.center.hit == null ? '.' : pixel.center.hit.sceneObject.label;
    }
    public static long Contrast(Scene.Color a, Scene.Color b) {
        long maximum = 0;
        for (int c = 0; c < 3; c++)
            maximum = Math.Max(maximum, Math.Abs(a.Component(c) - b.Component(c)));
        return maximum;
    }
    public static void Render() {
        pixels = Enumerable.Range(0, height)
                     .Select(
                         _ => new Pixel[width])
                     .ToArray();
        for (int y = 0; y < height; y++)
            for (int x = 0; x < width; x++) {
                Pixel pixel = new Pixel();
                pixels[y][x] = pixel;
                Context context = new Context(true, pixel, null);
                pixel.center = Trace(scene.eye, Camera(4L * x + 2, 4L * y + 2), 0, 0, context);
                pixel.color = pixel.center.color;
                if (pixel.center.hit != null)
                    for (int l = 0; l < scene.lights.Count; l++)
                        if (pixel.center.lit[l])
                            stats.lights[l].pixels++;
            }
        for (int y = 0; y < height; y++)
            for (int x = 0; x < width; x++) {
                Pixel pixel = pixels[y][x];
                bool adaptive = false;
                foreach (int[] offset in new int[][] { new int[] { -1, 0 }, new int[] { 1, 0 },
                                                       new int[] { 0, -1 }, new int[] { 0, 1 } }) {
                    int xx = x + offset[0], yy = y + offset[1];
                    if (xx >= 0 && xx < width && yy >= 0 && yy < height) {
                        Pixel neighbor = pixels[yy][xx];
                        if (Label(pixel) != Label(neighbor) ||
                            Contrast(pixel.center.color, neighbor.center.color) > contrast)
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
                                Trace(scene.eye, Camera(4L * x + dx, 4L * y + dy), 0, 0, context).color;
                            for (int c = 0; c < 3; c++)
                                sum[c] += color.Component(c);
                        }
                    pixel.color = new Scene.Color(Div(sum[0], 4), Div(sum[1], 4), Div(sum[2], 4));
                }
                if (pixel.center.hit != null) {
                    long t = pixel.center.hit.candidate.distance;
                    minimumDistance = Math.Min(minimumDistance, t);
                    maximumDistance = Math.Max(maximumDistance, t);
                }
                maxPixelRays = Math.Max(maxPixelRays, pixel.rays);
            }
    }
    public static long Clamp(long value) {
        return Math.Max(0, Math.Min(255, value));
    }
    public static List<string> Header(string kind) {
        return new([kind, width + " " + height, "255"]);
    }
    public static void Images() {
        List<string> image = Header("P3"), depth = Header("P2"), normal = Header("P3"), albedo = Header("P3"),
                     cost = Header("P2"), objects = new(), lights = new(), rayDepth = new();
        for (int y = 0; y < height; y++) {
            List<string> colors = new(), distances = new(), normals = new(), bases = new(), costs = new();
            StringBuilder labels = new StringBuilder(), illumination = new StringBuilder(),
                          depths = new StringBuilder();
            for (int x = 0; x < width; x++) {
                Pixel pixel = pixels[y][x];
                colors.Add(pixel.color.ToString());
                costs.Add(long.ToString(Div(255 * pixel.rays, maxPixelRays)));
                labels.Append(Label(pixel));
                depths.Append((char)('0' + pixel.depth));
                if (pixel.center.hit == null) {
                    distances.Add("0");
                    normals.Add(BLACK.ToString());
                    bases.Add(BLACK.ToString());
                    illumination.Append('.');
                } else {
                    long t = pixel.center.hit.candidate.distance;
                    distances.Add(long.ToString(
                        maximumDistance == minimumDistance
                            ? 255
                            : 255 - Div(235 * (t - minimumDistance), maximumDistance - minimumDistance)));
                    Vector3 n = pixel.center.normal;
                    Scene.Color color = new Scene.Color(Clamp(Div((n.x + S) * 255, 2 * S)),
                                                        Clamp(Div((n.y + S) * 255, 2 * S)),
                                                        Clamp(Div((n.z + S) * 255, 2 * S)));
                    normals.Add(color.ToString());
                    bases.Add(pixel.center.baseColor.ToString());
                    illumination.Append((char)('0' + pixel.center.illumination));
                }
            }
            image.Add(string.Join(" ", colors));
            depth.Add(string.Join(" ", distances));
            normal.Add(string.Join(" ", normals));
            albedo.Add(string.Join(" ", bases));
            cost.Add(string.Join(" ", costs));
            objects.Add(labels.ToString());
            lights.Add(illumination.ToString());
            rayDepth.Add(depths.ToString());
        }
        Write("image.ppm", image);
        Write("depth.pgm", depth);
        Write("normal.ppm", normal);
        Write("albedo.ppm", albedo);
        Write("cost.pgm", cost);
        Write("object_map.txt", objects);
        Write("light_map.txt", lights);
        Write("ray_depth.txt", rayDepth);
    }
    public static string Labels(List<Scene.Obj> objects) {
        StringBuilder text = new StringBuilder();
        foreach (Scene.Obj sceneObject in objects)
            text.Append(sceneObject.label);
        return text.ToString();
    }
    public static void Nodes(Node node, List<string> output) {
        string description = node.objects == null ? "inner" : "leaf " + Labels(node.objects);
        output.Add("node " + node.depth + " " + description + " box " + node.bounds.lo + " " +
                   node.bounds.hi + " visits " + node.visits);
        if (node.objects == null) {
            Nodes(node.left, output);
            Nodes(node.right, output);
        }
    }
    public static List<string> Statistics() {
        List<string> output = new();
        output.Add("image " + width + " " + height);
        output.Add("supersampled " + supersampled);
        long total = 0;
        foreach (long value in stats.rays)
            total += value;
        output.Add("rays primary " + stats.rays[0] + " reflection " + stats.rays[1] + " refraction " +
                   stats.rays[2] + " shadow " + stats.rays[3] + " total " + total);
        output.Add("misses primary " + stats.misses[0] + " reflection " + stats.misses[1] + " refraction " +
                   stats.misses[2]);
        string line = "depth";
        foreach (long value in stats.depth)
            line += " " + value;
        output.Add(line);
        for (int kind = 0; kind < 4; kind++)
            output.Add("tests " + KINDS[kind] + " nodes " + stats.nodes[kind] + " objects " +
                       stats.objects[kind]);
        output.Add("total_internal_reflection " + stats.totalInternal);
        output.Add("clamped " + stats.clamped);
        output.Add(minimumDistance == long.MaxValue ? "distance none"
                                                    : "distance " + minimumDistance + " " + maximumDistance);
        output.Add("max_pixel_rays " + maxPixelRays);
        long[] sum = new long[3], histogram = new long[8];
        foreach (Pixel[] row in pixels)
            foreach (Pixel pixel in row) {
                for (int c = 0; c < 3; c++)
                    sum[c] += pixel.color.Component(c);
                long brightness = Div(299 * pixel.color.r + 587 * pixel.color.g + 114 * pixel.color.b, 1000);
                histogram[(int)Div(brightness, 32)]++;
            }
        output.Add("mean " + new Scene.Color(Div(sum[0], width * height), Div(sum[1], width * height),
                                             Div(sum[2], width * height)));
        line = "histogram";
        foreach (long value in histogram)
            line += " " + value;
        output.Add(line);
        if (root != null)
            Nodes(root, output);
        foreach (Scene.Obj sceneObject in scene.objects) {
            int count = 0, x0 = width, y0 = height, x1 = -1, y1 = -1;
            Array.Fill(sum, 0);
            for (int y = 0; y < height; y++)
                for (int x = 0; x < width; x++)
                    if (Label(pixels[y][x]) == sceneObject.label) {
                        count++;
                        x0 = Math.Min(x0, x);
                        y0 = Math.Min(y0, y);
                        x1 = Math.Max(x1, x);
                        y1 = Math.Max(y1, y);
                        for (int c = 0; c < 3; c++)
                            sum[c] += pixels[y][x].color.Component(c);
                    }
            string box = count == 0 ? "none" : x0 + " " + y0 + " " + x1 + " " + y1,
                   color = count == 0
                               ? "none"
                               : new Scene.Color(Div(sum[0], count), Div(sum[1], count), Div(sum[2], count))
                                     .ToString();
            int i = sceneObject.number - 1;
            output.Add("object " + sceneObject.label + " " + sceneObject.kind + " primary " +
                       stats.primary[i] + " secondary " + stats.secondary[i] + " shadow " + stats.shadow[i] +
                       " pixels " + count + " box " + box + " color " + color);
        }
        foreach (Scene.Light light in scene.lights) {
            LightStats s = stats.lights[light.number - 1];
            output.Add("light " + light.number + " " + light.kind + " samples " + light.Samples() +
                       " pixels " + s.pixels + " shadow_rays " + s.shadow + " blocked " + s.blocked +
                       " attenuated " + s.attenuated + " backfacing " + s.backfacing + " outside " +
                       s.outside);
        }
        return output;
    }
    public static List<string> Queries() {
        List<string> output = new(), queries = Lines("queries.txt");
        Context context = new Context(false, null, null);
        for (int q = 0; q < queries.Count; q++) {
            string line = queries[q];
            output.Add("query " + (q + 1) + " " + line);
            string[] words = line.Split(' ');
            switch (words[0]) {
            case "pixel": {
                int x = int.Parse(words[1]), y = int.Parse(words[2]);
                Pixel pixel = pixels[y][x];
                output.Add(
                    "label " + Label(pixel) + " distance " +
                    (pixel.center.hit == null ? "none" : long.ToString(pixel.center.hit.candidate.distance)) +
                    " color " + pixel.color + " samples " + pixel.samples + " rays " + pixel.rays);
                break;
            }
            case "trace": {
                int x = int.Parse(words[1]), y = int.Parse(words[2]);
                Trace(scene.eye, Camera(4L * x + 2, 4L * y + 2), 0, 0, new Context(false, null, output));
                break;
            }
            case "ray":
                Trace(Scene.Vector(words, 1), Scene.Vector(words, 4).Normalize(), 0, 0,
                      new Context(false, null, output));
                break;
            case "object": {
                Scene.Obj sceneObject = null;
                foreach (Scene.Obj candidate in scene.objects)
                    if (candidate.label == words[1][0]) {
                        sceneObject = candidate;
                        break;
                    }
                output.Add(sceneObject.kind + " material " + sceneObject.material.name + " bounds " +
                           (sceneObject.kind.Equals("plane")
                                ? "none leaf none"
                                : sceneObject.bounds.lo + " " + sceneObject.bounds.hi + " leaf " +
                                      sceneObject.leafDepth));
                break;
            }
            case "visible": {
                Vector3 relative = Scene.Vector(words, 1).Subtract(scene.eye),
                        direction = relative.Normalize();
                bool visible =
                    Occluders(scene.eye, direction, relative.Length() - epsilon, context).Count == 0;
                Hit first = Nearest(scene.eye, direction, 0, context);
                output.Add(
                    (visible ? "yes" : "no") + " first " +
                    (first == null ? "none" : first.sceneObject.label + " t " + first.candidate.distance));
                break;
            }
            case "shadow": {
                Vector3 point = Scene.Vector(words, 1);
                foreach (Scene.Light light in scene.lights) {
                    HashSet<Scene.Obj> seen = new();
                    long transmittance = 0;
                    foreach (Sample sample in Samples(light, point)) {
                        long factor = Cone(light, sample.direction);
                        List<Scene.Obj> blockers =
                            Occluders(point, sample.direction, sample.distance, context);
                        seen.UnionWith(blockers);
                        foreach (Scene.Obj sceneObject in blockers)
                            factor = FixedPoint.Multiply(factor, sceneObject.material.kt);
                        transmittance += factor;
                    }
                    List<Scene.Obj> allBlockers = new();
                    foreach (Scene.Obj sceneObject in scene.objects)
                        if (seen.Contains(sceneObject))
                            allBlockers.Add(sceneObject);
                    output.Add("light " + light.number + " factor " + transmittance + " occluders " +
                               (allBlockers.Count == 0 ? "none" : Labels(allBlockers)));
                }
                break;
            }
            case "region": {
                int x0 = int.Parse(words[1]), y0 = int.Parse(words[2]), x1 = int.Parse(words[3]),
                    y1 = int.Parse(words[4]), count = (x1 - x0 + 1) * (y1 - y0 + 1);
                long[] sum = new long[3];
                Dictionary<char, int> counts = new();
                for (int y = y0; y <= y1; y++)
                    for (int x = x0; x <= x1; x++) {
                        Pixel pixel = pixels[y][x];
                        char label = Label(pixel);
                        counts[label] = counts.GetValueOrDefault(label, 0) + 1;
                        for (int c = 0; c < 3; c++)
                            sum[c] += pixel.color.Component(c);
                    }
                output.Add("pixels " + count + " mean " +
                           new Scene.Color(Div(sum[0], count), Div(sum[1], count), Div(sum[2], count)));
                foreach (Scene.Obj sceneObject in scene.objects)
                    if (counts.GetValueOrDefault(sceneObject.label, 0) > 0)
                        output.Add("label " + sceneObject.label + " " + counts[sceneObject.label]);
                if (counts.GetValueOrDefault('.', 0) > 0)
                    output.Add("label . " + counts['.']);
                break;
            }
            }
        }
        return output;
    }
    public static void Main(string[] args) {
        CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
        scene = Scene.Read();
        Prepare();
        Render();
        Images();
        Write("stats.txt", Statistics());
        Write("queries.txt", Queries());
    }
}
