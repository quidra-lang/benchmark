#include "renderer.h"
static char *triple(Vec value) {
    return format("%" PRId64 " %" PRId64 " %" PRId64, value.data[0], value.data[1], value.data[2]);
}
static Settings settings(void) {
    Lines lines = read_lines("input/render.txt");
    Settings out;
    Tokens row = split_words(lines.data[0]);
    out.width = atoi(row.data[1]);
    out.height = atoi(row.data[2]);
    row = split_words(lines.data[1]);
    out.contrast = atoi(row.data[1]);
    row = split_words(lines.data[2]);
    out.depth = atoi(row.data[1]);
    row = split_words(lines.data[3]);
    out.far = strtoll(row.data[1], NULL, 10);
    row = split_words(lines.data[4]);
    out.epsilon = strtoll(row.data[1], NULL, 10);
    row = split_words(lines.data[5]);
    out.pad = strtoll(row.data[1], NULL, 10);
    return out;
}
typedef struct Node {
    Bounds box;
    Ids objects;
    struct Node *left;
    struct Node *right;
    int depth;
    I visits;
} Node;
typedef struct {
    I nodes, objects;
} Tests;
typedef struct {
    I primary, secondary, shadow;
} ObjectCounts;
typedef struct {
    I shadow, blocked, attenuated, backfacing, outside;
} LightCounts;
typedef struct {
    I rays[4], misses[3], depths[4];
    Tests tests[4];
    ObjectCounts objects[26];
    LightCounts lights[9];
    I total_internal, saturated;
} Statistics;
typedef struct {
    int object;
    Candidate candidate;
    bool valid;
} Hit;
typedef struct {
    Hit hit;
    Vec point, normal;
    Color base;
    bool front;
} Info;
typedef struct {
    I lit, diffuse, specular;
} LightResult;
typedef struct {
    Color color;
    Info info;
    bool has_info;
    LightResult lights[9];
    int illumination;
} Result;
typedef struct {
    Color center, color;
    Info info;
    bool has_info, lit[9];
    I rays;
    int depth;
    bool subsampled;
} Pixel;
typedef struct {
    Vec direction;
    I distance, intensity;
} Sample;
typedef struct {
    Sample data[16];
    int count;
} Samples;
typedef struct {
    Scene scene;
    Settings render;
    Bounds boxes[26];
    Node *root;
    Statistics stats;
} Tracer;
static I minimum(I a, I b) {
    return a < b ? a : b;
}
static I maximum(I a, I b) {
    return a > b ? a : b;
}
static I absolute(I value) {
    return value < 0 ? -value : value;
}
static Bounds union_box(const Tracer *tracer, Ids objects) {
    Bounds out = tracer->boxes[objects.data[0]];
    for (int i = 0; i < objects.count; ++i)
        for (int axis = 0; axis < 3; ++axis) {
            Bounds box = tracer->boxes[objects.data[i]];
            out.lo.data[axis] = minimum(out.lo.data[axis], box.lo.data[axis]);
            out.hi.data[axis] = maximum(out.hi.data[axis], box.hi.data[axis]);
        }
    return out;
}
static I area(const Tracer *tracer, Ids objects) {
    Bounds box = union_box(tracer, objects);
    Vec d = sub(box.hi, box.lo);
    return d.data[0] * d.data[1] + d.data[1] * d.data[2] + d.data[2] * d.data[0];
}
static void sort_ids(Ids *ids) {
    for (int i = 1; i < ids->count; ++i) {
        int value = ids->data[i], j = i;
        while (j > 0 && ids->data[j - 1] > value) {
            ids->data[j] = ids->data[j - 1];
            --j;
        }
        ids->data[j] = value;
    }
}
static bool center_less(const Tracer *tracer, int a, int b, int axis) {
    I x = floor_div(tracer->boxes[a].lo.data[axis] + tracer->boxes[a].hi.data[axis], 2),
      y = floor_div(tracer->boxes[b].lo.data[axis] + tracer->boxes[b].hi.data[axis], 2);
    return x != y ? x < y : a < b;
}
static Node *build(Tracer *tracer, Ids objects, int depth) {
    Node *node = allocate(1, sizeof(Node));
    node->box = union_box(tracer, objects);
    node->depth = depth;
    if (objects.count <= 2) {
        sort_ids(&objects);
        node->objects = objects;
        return node;
    }
    I best = INT64_MAX;
    Ids left = {0}, right = {0};
    for (int axis = 0; axis < 3; ++axis) {
        Ids ordered = objects;
        for (int i = 1; i < ordered.count; ++i) {
            int value = ordered.data[i], j = i;
            while (j > 0 && center_less(tracer, value, ordered.data[j - 1], axis)) {
                ordered.data[j] = ordered.data[j - 1];
                --j;
            }
            ordered.data[j] = value;
        }
        for (int i = 1; i < ordered.count; ++i) {
            Ids a = {0}, b = {0};
            for (int j = 0; j < i; ++j)
                a.data[a.count++] = ordered.data[j];
            for (int j = i; j < ordered.count; ++j)
                b.data[b.count++] = ordered.data[j];
            I cost = area(tracer, a) * a.count + area(tracer, b) * b.count;
            if (cost < best) {
                best = cost;
                left = a;
                right = b;
            }
        }
    }
    node->left = build(tracer, left, depth + 1);
    node->right = build(tracer, right, depth + 1);
    return node;
}
static void prepare(Tracer *tracer) {
    Ids bounded = {0};
    for (int i = 0; i < tracer->scene.object_count; ++i)
        if (tracer->scene.objects[i].kind != PLANE) {
            bounded.data[bounded.count++] = i;
            tracer->boxes[i] = bounds(tracer->scene.objects[i], tracer->render.pad);
        }
    if (bounded.count)
        tracer->root = build(tracer, bounded, 0);
}
static Ray camera(const Tracer *tracer, int qx, int qy) {
    I u = floor_div((I)(qx - 2 * tracer->render.width) * tracer->scene.half_width, 2 * tracer->render.width),
      v = floor_div((I)(2 * tracer->render.height - qy) * tracer->scene.half_height,
                    2 * tracer->render.height);
    return (Ray){tracer->scene.eye,
                 norm(add(add(tracer->scene.forward, sc(tracer->scene.right, u)), sc(tracer->scene.up, v)))};
}
static void test_nearest(Tracer *tracer, int id, Ray ray, int kind, bool counted, Hit *hit) {
    if (counted)
        ++tracer->stats.tests[kind].objects;
    Candidate candidate = intersect(tracer->scene.objects[id], ray, tracer->render.epsilon);
    if (candidate.valid && candidate.distance <= tracer->render.far &&
        (!hit->valid || candidate.distance < hit->candidate.distance ||
         (candidate.distance == hit->candidate.distance && id < hit->object)))
        *hit = (Hit){id, candidate, true};
}
static void nearest_node(Tracer *tracer, Node *node, Ray ray, int kind, bool counted, Hit *hit) {
    if (counted) {
        ++tracer->stats.tests[kind].nodes;
        ++node->visits;
    }
    Slab result = slab(node->box, ray);
    if (!result.valid || result.far <= tracer->render.epsilon || result.near > tracer->render.far ||
        (hit->valid && result.near > hit->candidate.distance))
        return;
    if (node->objects.count)
        for (int i = 0; i < node->objects.count; ++i)
            test_nearest(tracer, node->objects.data[i], ray, kind, counted, hit);
    else {
        nearest_node(tracer, node->left, ray, kind, counted, hit);
        nearest_node(tracer, node->right, ray, kind, counted, hit);
    }
}
static Hit nearest(Tracer *tracer, Ray ray, int kind, bool counted) {
    Hit hit = {0};
    for (int id = 0; id < tracer->scene.object_count; ++id)
        if (tracer->scene.objects[id].kind == PLANE)
            test_nearest(tracer, id, ray, kind, counted, &hit);
    if (tracer->root)
        nearest_node(tracer, tracer->root, ray, kind, counted, &hit);
    return hit;
}
static void test_occluder(Tracer *tracer, int id, Ray ray, I distance, bool counted, Ids *out) {
    if (counted)
        ++tracer->stats.tests[3].objects;
    Candidate candidate = intersect(tracer->scene.objects[id], ray, tracer->render.epsilon);
    if (candidate.valid && candidate.distance < distance)
        out->data[out->count++] = id;
}
static void occluder_node(Tracer *tracer, Node *node, Ray ray, I distance, bool counted, Ids *out) {
    if (counted) {
        ++tracer->stats.tests[3].nodes;
        ++node->visits;
    }
    Slab result = slab(node->box, ray);
    if (!result.valid || result.far <= tracer->render.epsilon || result.near >= distance)
        return;
    if (node->objects.count)
        for (int i = 0; i < node->objects.count; ++i)
            test_occluder(tracer, node->objects.data[i], ray, distance, counted, out);
    else {
        occluder_node(tracer, node->left, ray, distance, counted, out);
        occluder_node(tracer, node->right, ray, distance, counted, out);
    }
}
static Ids occluders(Tracer *tracer, Ray ray, I distance, bool counted) {
    Ids out = {0};
    for (int id = 0; id < tracer->scene.object_count; ++id)
        if (tracer->scene.objects[id].kind == PLANE)
            test_occluder(tracer, id, ray, distance, counted, &out);
    if (tracer->root)
        occluder_node(tracer, tracer->root, ray, distance, counted, &out);
    sort_ids(&out);
    if (counted)
        for (int i = 0; i < out.count; ++i)
            ++tracer->stats.objects[out.data[i]].shadow;
    return out;
}
static Samples samples(const Tracer *tracer, Light light, Vec point) {
    Samples out = {0};
    if (light.kind == SUN) {
        out.data[out.count++] = (Sample){light.direction, tracer->render.far, light.intensity};
        return out;
    }
    int count = light.kind == AREA ? light.divisions : 1;
    for (int j = 0; j < count; ++j)
        for (int i = 0; i < count; ++i) {
            Vec position = light.position;
            if (light.kind == AREA)
                for (int axis = 0; axis < 3; ++axis)
                    position.data[axis] += floor_div((2 * i + 1) * light.u.data[axis], 2 * count) +
                                           floor_div((2 * j + 1) * light.v.data[axis], 2 * count);
            Vec rel = sub(position, point);
            out.data[out.count++] =
                (Sample){norm(rel), length(rel), floor_div(light.intensity, count * count)};
        }
    return out;
}
static I cone(Light light, Vec direction) {
    if (light.kind != SPOT)
        return SCALE;
    I cosine = -dot(direction, light.direction);
    if (cosine <= light.outer)
        return 0;
    if (cosine >= light.inner)
        return SCALE;
    return floor_div((cosine - light.outer) * SCALE, light.inner - light.outer);
}
static Result trace(Tracer *tracer, Ray ray, int kind, int depth, bool counted, Pixel *pixel, Lines *record) {
    static const char *kinds[] = {"primary", "reflection", "refraction"};
    if (counted) {
        ++tracer->stats.rays[kind];
        ++tracer->stats.depths[depth];
        ++pixel->rays;
        if (depth > pixel->depth)
            pixel->depth = depth;
    }
    if (record)
        line(record, "ray %s %d origin %s direction %s", kinds[kind], depth, triple(ray.origin),
             triple(ray.direction));
    Result out = {0};
    Hit hit = nearest(tracer, ray, kind, counted);
    if (!hit.valid) {
        out.color = tracer->scene.background;
        if (counted)
            ++tracer->stats.misses[kind];
        if (record) {
            line(record, "miss");
            line(record, "color %s", triple(out.color));
        }
        return out;
    }
    Object object = tracer->scene.objects[hit.object];
    Material material = tracer->scene.materials[object.material];
    Vec point = add(ray.origin, sc(ray.direction, hit.candidate.distance)),
        normal0 = outward_normal(object, ray, point, hit.candidate);
    bool front = dot(normal0, ray.direction) <= 0;
    Vec normal = front ? normal0 : negate(normal0);
    Color base = base_color(material, point);
    out.info = (Info){hit, point, normal, base, front};
    out.has_info = true;
    if (counted) {
        if (kind == 0)
            ++tracer->stats.objects[hit.object].primary;
        else
            ++tracer->stats.objects[hit.object].secondary;
    }
    if (record)
        line(record, "hit %c t %" PRId64 " point %s normal %s base %s", object.label, hit.candidate.distance,
             triple(point), triple(normal), triple(base));
    I diffuse_sum = 0, specular_sum = 0;
    for (int index = 0; index < tracer->scene.light_count; ++index) {
        Light light = tracer->scene.lights[index];
        LightResult *result = &out.lights[index];
        Samples source = samples(tracer, light, point);
        for (int i = 0; i < source.count; ++i) {
            Sample sample = source.data[i];
            I ndl = dot(normal, sample.direction);
            if (ndl <= 0) {
                if (counted)
                    ++tracer->stats.lights[index].backfacing;
                continue;
            }
            I factor = cone(light, sample.direction);
            if (!factor) {
                if (counted)
                    ++tracer->stats.lights[index].outside;
                continue;
            }
            if (counted) {
                ++tracer->stats.rays[3];
                ++tracer->stats.lights[index].shadow;
                ++pixel->rays;
            }
            Ids blockers = occluders(tracer, (Ray){point, sample.direction}, sample.distance, counted);
            for (int j = 0; j < blockers.count; ++j)
                factor =
                    mul(factor, tracer->scene.materials[tracer->scene.objects[blockers.data[j]].material].kt);
            if (!factor) {
                if (counted)
                    ++tracer->stats.lights[index].blocked;
                continue;
            }
            if (counted && blockers.count)
                ++tracer->stats.lights[index].attenuated;
            ++result->lit;
            I diffuse, specular;
            phong(material, normal, sample.direction, negate(ray.direction), mul(sample.intensity, factor),
                  &diffuse, &specular);
            result->diffuse += diffuse;
            result->specular += specular;
        }
        diffuse_sum += result->diffuse;
        specular_sum += result->specular;
        out.illumination += result->lit > 0;
        if (record)
            line(record, "light %d lit %" PRId64 " of %d diffuse %" PRId64 " specular %" PRId64, index + 1,
                 result->lit, source.count, result->diffuse, result->specular);
    }
    Color local;
    for (int component = 0; component < 3; ++component) {
        I raw = floor_div(base.data[component] * (tracer->scene.ambient + diffuse_sum), SCALE) +
                floor_div(255 * specular_sum, SCALE);
        local.data[component] = minimum(raw, 255);
        if (counted)
            tracer->stats.saturated += raw > 255;
    }
    if (record)
        line(record, "local %s", triple(local));
    Color color = local;
    if (depth < tracer->render.depth && (material.kr > 0 || material.kt > 0)) {
        Weights weights = refracted(material, ray.direction, normal, front);
        if (weights.total_internal) {
            if (counted)
                ++tracer->stats.total_internal;
            if (record)
                line(record, "total_internal_reflection");
        }
        if (record)
            line(record, "weights %" PRId64 " %" PRId64 " %" PRId64, SCALE - material.kr - material.kt,
                 weights.reflection, weights.refraction);
        Color reflected_color = {0}, refracted_color = {0};
        if (weights.reflection > 0)
            reflected_color = trace(tracer, (Ray){point, reflected(ray.direction, normal)}, 1, depth + 1,
                                    counted, pixel, record)
                                  .color;
        if (weights.refraction > 0)
            refracted_color =
                trace(tracer, (Ray){point, weights.direction}, 2, depth + 1, counted, pixel, record).color;
        color = mix(local, SCALE - material.kr - material.kt, reflected_color, weights.reflection,
                    refracted_color, weights.refraction);
    }
    if (tracer->scene.fog) {
        I distance = hit.candidate.distance,
          factor = distance <= tracer->scene.fog_start ? 0
                   : distance >= tracer->scene.fog_end
                       ? SCALE
                       : floor_div((distance - tracer->scene.fog_start) * SCALE,
                                   tracer->scene.fog_end - tracer->scene.fog_start);
        color = mix(color, SCALE - factor, tracer->scene.fog_color, factor, (Color){0}, 0);
    }
    out.color = color;
    if (record)
        line(record, "color %s", triple(color));
    return out;
}
static int leaf_depth(const Node *node, int object) {
    if (node->objects.count) {
        for (int i = 0; i < node->objects.count; ++i)
            if (node->objects.data[i] == object)
                return node->depth;
        return -1;
    }
    int left = leaf_depth(node->left, object);
    return left >= 0 ? left : leaf_depth(node->right, object);
}
static char label(const Tracer *tracer, Pixel pixel) {
    return pixel.has_info ? tracer->scene.objects[pixel.info.hit.object].label : '.';
}
static Lines ppm(const Color *values, int width, int height) {
    Lines out = {0};
    line(&out, "P3");
    line(&out, "%d %d", width, height);
    line(&out, "255");
    for (int y = 0; y < height; ++y) {
        char *row = allocate((size_t)width * 12 + 1, 1);
        size_t offset = 0;
        for (int x = 0; x < width; ++x) {
            Color color = values[y * width + x];
            offset += (size_t)sprintf(row + offset, "%s%" PRId64 " %" PRId64 " %" PRId64, x ? " " : "",
                                      color.data[0], color.data[1], color.data[2]);
        }
        line(&out, "%s", row);
    }
    return out;
}
static Lines pgm(const I *values, int width, int height) {
    Lines out = {0};
    line(&out, "P2");
    line(&out, "%d %d", width, height);
    line(&out, "255");
    for (int y = 0; y < height; ++y) {
        char *row = allocate((size_t)width * 4 + 1, 1);
        size_t offset = 0;
        for (int x = 0; x < width; ++x)
            offset += (size_t)sprintf(row + offset, "%s%" PRId64, x ? " " : "", values[y * width + x]);
        line(&out, "%s", row);
    }
    return out;
}
static void save(const char *name, Lines lines) {
    FILE *out = fopen(format("output/%s", name), "w");
    for (int i = 0; i < lines.count; ++i)
        fprintf(out, "%s\n", lines.data[i]);
    fclose(out);
}
static void report_node(const Tracer *tracer, const Node *node, Lines *out) {
    if (node->objects.count) {
        char labels[27] = {0};
        for (int i = 0; i < node->objects.count; ++i)
            labels[i] = tracer->scene.objects[node->objects.data[i]].label;
        line(out, "node %d leaf %s box %s %s visits %" PRId64, node->depth, labels, triple(node->box.lo),
             triple(node->box.hi), node->visits);
    } else {
        line(out, "node %d inner box %s %s visits %" PRId64, node->depth, triple(node->box.lo),
             triple(node->box.hi), node->visits);
        report_node(tracer, node->left, out);
        report_node(tracer, node->right, out);
    }
}
int main(void) {
    mkdir("output", 0777);
    Tracer *tracer = allocate(1, sizeof(Tracer));
    tracer->scene = load_scene();
    tracer->render = settings();
    prepare(tracer);
    Settings render = tracer->render;
    int width = render.width, height = render.height, count = width * height;
    Pixel *pixels = allocate(count, sizeof(Pixel));
    for (int y = 0; y < height; ++y)
        for (int x = 0; x < width; ++x) {
            Pixel *pixel = &pixels[y * width + x];
            Result result = trace(tracer, camera(tracer, 4 * x + 2, 4 * y + 2), 0, 0, true, pixel, NULL);
            pixel->center = pixel->color = result.color;
            pixel->info = result.info;
            pixel->has_info = result.has_info;
            for (int light = 0; light < tracer->scene.light_count; ++light)
                pixel->lit[light] = result.lights[light].lit > 0;
        }
    int supersampled = 0;
    const int neighbors[4][2] = {{-1, 0}, {1, 0}, {0, -1}, {0, 1}},
              offsets[4][2] = {{1, 1}, {3, 1}, {1, 3}, {3, 3}};
    for (int y = 0; y < height; ++y)
        for (int x = 0; x < width; ++x) {
            Pixel *pixel = &pixels[y * width + x];
            for (int neighbor = 0; neighbor < 4; ++neighbor) {
                int xx = x + neighbors[neighbor][0], yy = y + neighbors[neighbor][1];
                if (xx < 0 || xx >= width || yy < 0 || yy >= height)
                    continue;
                Pixel other = pixels[yy * width + xx];
                I difference = 0;
                for (int component = 0; component < 3; ++component)
                    difference = maximum(
                        difference, absolute(pixel->center.data[component] - other.center.data[component]));
                if (label(tracer, *pixel) != label(tracer, other) || difference > render.contrast)
                    pixel->subsampled = true;
            }
            if (pixel->subsampled) {
                ++supersampled;
                Color sum = {0};
                for (int sample = 0; sample < 4; ++sample) {
                    Color color =
                        trace(tracer, camera(tracer, 4 * x + offsets[sample][0], 4 * y + offsets[sample][1]),
                              0, 0, true, pixel, NULL)
                            .color;
                    for (int component = 0; component < 3; ++component)
                        sum.data[component] += color.data[component];
                }
                for (int component = 0; component < 3; ++component)
                    pixel->color.data[component] = floor_div(sum.data[component], 4);
            }
        }
    bool has_distance = false;
    I min_distance = 0, max_distance = 0, cost_max = 0;
    Color total_color = {0};
    I histogram[8] = {0};
    Color *colors = allocate(count, sizeof(Color));
    Color *normal = allocate(count, sizeof(Color));
    Color *albedo = allocate(count, sizeof(Color));
    I *depth = allocate(count, sizeof(I));
    I *cost = allocate(count, sizeof(I));
    Lines object_map = {0}, light_map = {0}, ray_depth = {0};
    for (int y = 0; y < height; ++y) {
        char *objects = allocate(width + 1, 1);
        char *lights = allocate(width + 1, 1);
        char *depths = allocate(width + 1, 1);
        for (int x = 0; x < width; ++x) {
            int index = y * width + x;
            Pixel pixel = pixels[index];
            colors[index] = pixel.color;
            objects[x] = label(tracer, pixel);
            int illumination = 0;
            for (int i = 0; i < tracer->scene.light_count; ++i)
                illumination += pixel.lit[i];
            lights[x] = pixel.has_info ? (char)('0' + illumination) : '.';
            depths[x] = (char)('0' + pixel.depth);
            cost_max = maximum(cost_max, pixel.rays);
            for (int component = 0; component < 3; ++component)
                total_color.data[component] += pixel.color.data[component];
            I brightness = floor_div(
                299 * pixel.color.data[0] + 587 * pixel.color.data[1] + 114 * pixel.color.data[2], 1000);
            ++histogram[floor_div(brightness, 32)];
            if (pixel.has_info) {
                I distance = pixel.info.hit.candidate.distance;
                if (!has_distance) {
                    min_distance = max_distance = distance;
                    has_distance = true;
                } else {
                    min_distance = minimum(min_distance, distance);
                    max_distance = maximum(max_distance, distance);
                }
                albedo[index] = pixel.info.base;
                for (int component = 0; component < 3; ++component)
                    normal[index].data[component] =
                        maximum(0, minimum(255, floor_div((pixel.info.normal.data[component] + SCALE) * 255,
                                                          2 * SCALE)));
            }
        }
        line(&object_map, "%s", objects);
        line(&light_map, "%s", lights);
        line(&ray_depth, "%s", depths);
    }
    for (int index = 0; index < count; ++index) {
        cost[index] = floor_div(255 * pixels[index].rays, cost_max);
        if (pixels[index].has_info)
            depth[index] =
                max_distance == min_distance
                    ? 255
                    : 255 - floor_div(235 * (pixels[index].info.hit.candidate.distance - min_distance),
                                      max_distance - min_distance);
    }
    save("image.ppm", ppm(colors, width, height));
    save("depth.pgm", pgm(depth, width, height));
    save("normal.ppm", ppm(normal, width, height));
    save("albedo.ppm", ppm(albedo, width, height));
    save("cost.pgm", pgm(cost, width, height));
    save("object_map.txt", object_map);
    save("light_map.txt", light_map);
    save("ray_depth.txt", ray_depth);
    Lines stats = {0};
    Statistics *counts = &tracer->stats;
    line(&stats, "image %d %d", width, height);
    line(&stats, "supersampled %d", supersampled);
    line(&stats,
         "rays primary %" PRId64 " reflection %" PRId64 " refraction %" PRId64 " shadow %" PRId64
         " total %" PRId64,
         counts->rays[0], counts->rays[1], counts->rays[2], counts->rays[3],
         counts->rays[0] + counts->rays[1] + counts->rays[2] + counts->rays[3]);
    line(&stats, "misses primary %" PRId64 " reflection %" PRId64 " refraction %" PRId64, counts->misses[0],
         counts->misses[1], counts->misses[2]);
    char *depth_counts = "depth";
    for (int i = 0; i <= render.depth; ++i)
        depth_counts = format("%s %" PRId64, depth_counts, counts->depths[i]);
    line(&stats, "%s", depth_counts);
    const char *ray_names[] = {"primary", "reflection", "refraction", "shadow"};
    for (int kind = 0; kind < 4; ++kind)
        line(&stats, "tests %s nodes %" PRId64 " objects %" PRId64, ray_names[kind],
             counts->tests[kind].nodes, counts->tests[kind].objects);
    line(&stats, "total_internal_reflection %" PRId64, counts->total_internal);
    line(&stats, "clamped %" PRId64, counts->saturated);
    if (has_distance)
        line(&stats, "distance %" PRId64 " %" PRId64, min_distance, max_distance);
    else
        line(&stats, "distance none");
    line(&stats, "max_pixel_rays %" PRId64, cost_max);
    Color mean;
    for (int component = 0; component < 3; ++component)
        mean.data[component] = floor_div(total_color.data[component], count);
    line(&stats, "mean %s", triple(mean));
    char *histogram_line = "histogram";
    for (int i = 0; i < 8; ++i)
        histogram_line = format("%s %" PRId64, histogram_line, histogram[i]);
    line(&stats, "%s", histogram_line);
    if (tracer->root)
        report_node(tracer, tracer->root, &stats);
    for (int id = 0; id < tracer->scene.object_count; ++id) {
        Object object = tracer->scene.objects[id];
        I pixel_count = 0;
        int x0 = width, y0 = height, x1 = -1, y1 = -1;
        Color sum = {0};
        for (int y = 0; y < height; ++y)
            for (int x = 0; x < width; ++x) {
                Pixel pixel = pixels[y * width + x];
                if (!pixel.has_info || pixel.info.hit.object != id)
                    continue;
                ++pixel_count;
                if (x < x0)
                    x0 = x;
                if (y < y0)
                    y0 = y;
                if (x > x1)
                    x1 = x;
                if (y > y1)
                    y1 = y;
                for (int component = 0; component < 3; ++component)
                    sum.data[component] += pixel.color.data[component];
            }
        char *prefix = format("object %c %s primary %" PRId64 " secondary %" PRId64 " shadow %" PRId64
                              " pixels %" PRId64 " box",
                              object.label, object_kind(object.kind), counts->objects[id].primary,
                              counts->objects[id].secondary, counts->objects[id].shadow, pixel_count);
        if (pixel_count) {
            for (int component = 0; component < 3; ++component)
                sum.data[component] = floor_div(sum.data[component], pixel_count);
            line(&stats, "%s %d %d %d %d color %s", prefix, x0, y0, x1, y1, triple(sum));
        } else
            line(&stats, "%s none color none", prefix);
    }
    for (int id = 0; id < tracer->scene.light_count; ++id) {
        Light light = tracer->scene.lights[id];
        I lit_pixels = 0;
        for (int i = 0; i < count; ++i)
            lit_pixels += pixels[i].lit[id];
        LightCounts value = counts->lights[id];
        line(&stats,
             "light %d %s samples %d pixels %" PRId64 " shadow_rays %" PRId64 " blocked %" PRId64
             " attenuated %" PRId64 " backfacing %" PRId64 " outside %" PRId64,
             id + 1, light_kind(light.kind), light.kind == AREA ? light.divisions * light.divisions : 1,
             lit_pixels, value.shadow, value.blocked, value.attenuated, value.backfacing, value.outside);
    }
    save("stats.txt", stats);
    Lines answers = {0}, query_lines = read_lines("input/queries.txt");
    for (int index = 0; index < query_lines.count; ++index) {
        line(&answers, "query %d %s", index + 1, query_lines.data[index]);
        Tokens fields = split_words(query_lines.data[index]);
        const char *kind = fields.data[0];
        if (!strcmp(kind, "pixel")) {
            int x = atoi(fields.data[1]), y = atoi(fields.data[2]);
            Pixel pixel = pixels[y * width + x];
            line(&answers, "label %c distance %s color %s samples %d rays %" PRId64, label(tracer, pixel),
                 pixel.has_info ? format("%" PRId64, pixel.info.hit.candidate.distance) : "none",
                 triple(pixel.color), pixel.subsampled ? 4 : 1, pixel.rays);
        } else if (!strcmp(kind, "trace")) {
            int x = atoi(fields.data[1]), y = atoi(fields.data[2]);
            trace(tracer, camera(tracer, 4 * x + 2, 4 * y + 2), 0, 0, false, NULL, &answers);
        } else if (!strcmp(kind, "ray")) {
            Vec origin = parse_vec(fields, 1), direction = parse_vec(fields, 4);
            trace(tracer, (Ray){origin, norm(direction)}, 0, 0, false, NULL, &answers);
        } else if (!strcmp(kind, "object")) {
            char object_label = fields.data[1][0];
            int id = 0;
            while (tracer->scene.objects[id].label != object_label)
                ++id;
            Object object = tracer->scene.objects[id];
            Material material = tracer->scene.materials[object.material];
            if (object.kind == PLANE)
                line(&answers, "plane material %s bounds none leaf none", material.name);
            else
                line(&answers, "%s material %s bounds %s %s leaf %d", object_kind(object.kind), material.name,
                     triple(tracer->boxes[id].lo), triple(tracer->boxes[id].hi),
                     leaf_depth(tracer->root, id));
        } else if (!strcmp(kind, "visible")) {
            Vec point = parse_vec(fields, 1), rel = sub(point, tracer->scene.eye);
            Ray ray = {tracer->scene.eye, norm(rel)};
            Ids blockers = occluders(tracer, ray, length(rel) - render.epsilon, false);
            Hit first = nearest(tracer, ray, 0, false);
            if (first.valid)
                line(&answers, "%s first %c t %" PRId64, blockers.count ? "no" : "yes",
                     tracer->scene.objects[first.object].label, first.candidate.distance);
            else
                line(&answers, "%s first none", blockers.count ? "no" : "yes");
        } else if (!strcmp(kind, "shadow")) {
            Vec point = parse_vec(fields, 1);
            for (int id = 0; id < tracer->scene.light_count; ++id) {
                Light light = tracer->scene.lights[id];
                bool seen[26] = {0};
                I transmittance = 0;
                Samples source = samples(tracer, light, point);
                for (int i = 0; i < source.count; ++i) {
                    Sample sample = source.data[i];
                    I factor = cone(light, sample.direction);
                    Ids blockers = occluders(tracer, (Ray){point, sample.direction}, sample.distance, false);
                    for (int j = 0; j < blockers.count; ++j) {
                        int object = blockers.data[j];
                        seen[object] = true;
                        factor =
                            mul(factor, tracer->scene.materials[tracer->scene.objects[object].material].kt);
                    }
                    transmittance += factor;
                }
                char labels[27] = {0};
                int used = 0;
                for (int object = 0; object < tracer->scene.object_count; ++object)
                    if (seen[object])
                        labels[used++] = tracer->scene.objects[object].label;
                line(&answers, "light %d factor %" PRId64 " occluders %s", id + 1, transmittance,
                     used ? labels : "none");
            }
        } else {
            int x0 = atoi(fields.data[1]), y0 = atoi(fields.data[2]), x1 = atoi(fields.data[3]),
                y1 = atoi(fields.data[4]);
            Color total = {0};
            I labels[27] = {0}, region_count = (I)(x1 - x0 + 1) * (y1 - y0 + 1);
            for (int y = y0; y <= y1; ++y)
                for (int x = x0; x <= x1; ++x) {
                    Pixel pixel = pixels[y * width + x];
                    for (int component = 0; component < 3; ++component)
                        total.data[component] += pixel.color.data[component];
                    ++labels[pixel.has_info ? pixel.info.hit.object : tracer->scene.object_count];
                }
            for (int component = 0; component < 3; ++component)
                total.data[component] = floor_div(total.data[component], region_count);
            line(&answers, "pixels %" PRId64 " mean %s", region_count, triple(total));
            for (int object = 0; object <= tracer->scene.object_count; ++object)
                if (labels[object])
                    line(&answers, "label %c %" PRId64,
                         object < tracer->scene.object_count ? tracer->scene.objects[object].label : '.',
                         labels[object]);
        }
    }
    save("queries.txt", answers);
    release_all();
    return 0;
}
