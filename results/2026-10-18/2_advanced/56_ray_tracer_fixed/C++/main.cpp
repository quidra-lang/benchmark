#include "renderer.hpp"
#include <filesystem>
template <typename... T> static void line(Lines &out, const T &...values) {
    std::ostringstream text;
    (text << ... << values);
    out.push_back(text.str());
}
static std::string triple(Vec value) {
    return std::to_string(value[0]) + " " + std::to_string(value[1]) + " " + std::to_string(value[2]);
}
static Settings settings() {
    Settings out;
    std::ifstream input("input/render.txt");
    std::string key;
    input >> key >> out.width >> out.height >> key >> out.contrast >> key >> out.depth >> key >> out.far >>
        key >> out.epsilon >> key >> out.pad;
    return out;
}
static Lines queries() {
    std::ifstream input("input/queries.txt");
    Lines out;
    std::string line;
    while (std::getline(input, line))
        out.push_back(line);
    return out;
}
struct Node {
    Bounds box;
    Ids objects;
    std::unique_ptr<Node> left, right;
    int depth = 0;
    I visits = 0;
};
struct Tests {
    I nodes = 0, objects = 0;
};
struct ObjectCounts {
    I primary = 0, secondary = 0, shadow = 0;
};
struct LightCounts {
    I shadow = 0, blocked = 0, attenuated = 0, backfacing = 0, outside = 0;
};
struct Statistics {
    std::array<I, 4> rays{};
    std::array<I, 3> misses{};
    std::array<Tests, 4> tests{};
    std::vector<I> depths;
    std::vector<ObjectCounts> objects;
    std::vector<LightCounts> lights;
    I total_internal = 0, saturated = 0;
};
struct Hit {
    int object;
    Candidate candidate;
};
struct Info {
    Hit hit;
    Vec point, normal;
    Color base;
    bool front;
};
struct LightResult {
    I lit = 0, diffuse = 0, specular = 0;
};
struct Result {
    Color color;
    std::optional<Info> info;
    std::vector<LightResult> lights;
    int illumination = 0;
};
struct Pixel {
    Color center{}, color{};
    std::optional<Info> info;
    Ids lit;
    I rays = 0;
    int depth = 0;
    bool subsampled = false;
};
struct Sample {
    Vec direction;
    I distance, intensity;
};
class Tracer {
  public:
    Scene scene;
    Settings render;
    std::vector<Bounds> boxes;
    std::unique_ptr<Node> root;
    Statistics stats;
    Tracer(Scene value, Settings settings) : scene(std::move(value)), render(settings) {
        stats.depths.resize(render.depth + 1);
        stats.objects.resize(scene.objects.size());
        stats.lights.resize(scene.lights.size());
        boxes.resize(scene.objects.size());
        Ids bounded;
        for (int i = 0; i < int(scene.objects.size()); ++i)
            if (scene.objects[i].kind != ObjectKind::plane) {
                bounded.push_back(i);
                boxes[i] = bounds(scene.objects[i], render.pad);
            }
        if (!bounded.empty())
            root = build(bounded, 0);
    }
    Bounds union_box(const Ids &objects) const {
        Bounds out = boxes[objects[0]];
        for (int id : objects)
            for (int axis = 0; axis < 3; ++axis) {
                out.lo[axis] = std::min(out.lo[axis], boxes[id].lo[axis]);
                out.hi[axis] = std::max(out.hi[axis], boxes[id].hi[axis]);
            }
        return out;
    }
    I area(const Ids &objects) const {
        const Bounds box = union_box(objects);
        const Vec d = sub(box.hi, box.lo);
        return d[0] * d[1] + d[1] * d[2] + d[2] * d[0];
    }
    std::unique_ptr<Node> build(Ids objects, int depth) {
        auto node = std::make_unique<Node>();
        node->box = union_box(objects);
        node->depth = depth;
        if (objects.size() <= 2) {
            std::sort(objects.begin(), objects.end());
            node->objects = std::move(objects);
            return node;
        }
        I best = std::numeric_limits<I>::max();
        Ids left, right;
        for (int axis = 0; axis < 3; ++axis) {
            Ids ordered = objects;
            std::sort(ordered.begin(), ordered.end(), [&](int a, int b) {
                const I x = floor_div(boxes[a].lo[axis] + boxes[a].hi[axis], 2),
                        y = floor_div(boxes[b].lo[axis] + boxes[b].hi[axis], 2);
                return x != y ? x < y : a < b;
            });
            for (int i = 1; i < int(ordered.size()); ++i) {
                const Ids a(ordered.begin(), ordered.begin() + i), b(ordered.begin() + i, ordered.end());
                const I cost = area(a) * I(a.size()) + area(b) * I(b.size());
                if (cost < best) {
                    best = cost;
                    left = a;
                    right = b;
                }
            }
        }
        node->left = build(left, depth + 1);
        node->right = build(right, depth + 1);
        return node;
    }
    Ray camera(int qx, int qy) const {
        const I u = floor_div(I(qx - 2 * render.width) * scene.half_width, 2 * render.width),
                v = floor_div(I(2 * render.height - qy) * scene.half_height, 2 * render.height);
        return {scene.eye, norm(add(add(scene.forward, sc(scene.right, u)), sc(scene.up, v)))};
    }
    std::optional<Hit> nearest(Ray ray, int kind, bool counted) {
        std::optional<Hit> hit;
        auto test = [&](int id) {
            if (counted)
                ++stats.tests[kind].objects;
            const auto candidate = intersect(scene.objects[id], ray, render.epsilon);
            if (candidate && candidate->distance <= render.far &&
                (!hit || candidate->distance < hit->candidate.distance ||
                 (candidate->distance == hit->candidate.distance && id < hit->object)))
                hit = Hit{id, *candidate};
        };
        for (int id = 0; id < int(scene.objects.size()); ++id)
            if (scene.objects[id].kind == ObjectKind::plane)
                test(id);
        std::function<void(Node *)> visit = [&](Node *node) {
            if (counted) {
                ++stats.tests[kind].nodes;
                ++node->visits;
            }
            const auto box_hit = slab(node->box, ray);
            if (!box_hit || box_hit->far <= render.epsilon || box_hit->near > render.far ||
                (hit && box_hit->near > hit->candidate.distance))
                return;
            if (!node->objects.empty())
                for (int id : node->objects)
                    test(id);
            else {
                visit(node->left.get());
                visit(node->right.get());
            }
        };
        if (root)
            visit(root.get());
        return hit;
    }
    Ids occluders(Ray ray, I distance, bool counted) {
        Ids out;
        auto test = [&](int id) {
            if (counted)
                ++stats.tests[3].objects;
            const auto candidate = intersect(scene.objects[id], ray, render.epsilon);
            if (candidate && candidate->distance < distance)
                out.push_back(id);
        };
        for (int id = 0; id < int(scene.objects.size()); ++id)
            if (scene.objects[id].kind == ObjectKind::plane)
                test(id);
        std::function<void(Node *)> visit = [&](Node *node) {
            if (counted) {
                ++stats.tests[3].nodes;
                ++node->visits;
            }
            const auto box_hit = slab(node->box, ray);
            if (!box_hit || box_hit->far <= render.epsilon || box_hit->near >= distance)
                return;
            if (!node->objects.empty())
                for (int id : node->objects)
                    test(id);
            else {
                visit(node->left.get());
                visit(node->right.get());
            }
        };
        if (root)
            visit(root.get());
        std::sort(out.begin(), out.end());
        if (counted)
            for (int id : out)
                ++stats.objects[id].shadow;
        return out;
    }
    std::vector<Sample> samples(const Light &light, Vec point) const {
        if (light.kind == LightKind::sun)
            return {{light.direction, render.far, light.intensity}};
        std::vector<Sample> out;
        const int count = light.kind == LightKind::area ? light.divisions : 1;
        for (int j = 0; j < count; ++j)
            for (int i = 0; i < count; ++i) {
                Vec position = light.position;
                if (light.kind == LightKind::area)
                    for (int axis = 0; axis < 3; ++axis)
                        position[axis] += floor_div((2 * i + 1) * light.u[axis], 2 * count) +
                                          floor_div((2 * j + 1) * light.v[axis], 2 * count);
                const Vec rel = sub(position, point);
                out.push_back({norm(rel), length(rel), floor_div(light.intensity, count * count)});
            }
        return out;
    }
    I cone(const Light &light, Vec direction) const {
        if (light.kind != LightKind::spot)
            return scale;
        const I cosine = -dot(direction, light.direction);
        if (cosine <= light.outer)
            return 0;
        if (cosine >= light.inner)
            return scale;
        return floor_div((cosine - light.outer) * scale, light.inner - light.outer);
    }
    Result trace(Ray ray, int kind, int depth, bool counted, Pixel *pixel = nullptr,
                 Lines *record = nullptr) {
        static const char *kinds[] = {"primary", "reflection", "refraction"};
        if (counted) {
            ++stats.rays[kind];
            ++stats.depths[depth];
            ++pixel->rays;
            pixel->depth = std::max(pixel->depth, depth);
        }
        if (record)
            line(*record, "ray ", kinds[kind], " ", depth, " origin ", triple(ray.origin), " direction ",
                 triple(ray.direction));
        Result out;
        const auto hit = nearest(ray, kind, counted);
        if (!hit) {
            out.color = scene.background;
            if (counted)
                ++stats.misses[kind];
            if (record) {
                line(*record, "miss");
                line(*record, "color ", triple(out.color));
            }
            return out;
        }
        const Object &object = scene.objects[hit->object];
        const Material &material = scene.materials[object.material];
        const Vec point = add(ray.origin, sc(ray.direction, hit->candidate.distance)),
                  normal0 = outward_normal(object, ray, point, hit->candidate);
        const bool front = dot(normal0, ray.direction) <= 0;
        const Vec normal = front ? normal0 : negate(normal0);
        const Color base = base_color(material, point);
        out.info = Info{*hit, point, normal, base, front};
        if (counted) {
            if (kind == 0)
                ++stats.objects[hit->object].primary;
            else
                ++stats.objects[hit->object].secondary;
        }
        if (record)
            line(*record, "hit ", object.label, " t ", hit->candidate.distance, " point ", triple(point),
                 " normal ", triple(normal), " base ", triple(base));
        I diffuse_sum = 0, specular_sum = 0;
        out.lights.resize(scene.lights.size());
        for (int index = 0; index < int(scene.lights.size()); ++index) {
            const Light &light = scene.lights[index];
            LightResult &result = out.lights[index];
            const auto light_samples = samples(light, point);
            for (const Sample &sample : light_samples) {
                const I ndl = dot(normal, sample.direction);
                if (ndl <= 0) {
                    if (counted)
                        ++stats.lights[index].backfacing;
                    continue;
                }
                I factor = cone(light, sample.direction);
                if (factor == 0) {
                    if (counted)
                        ++stats.lights[index].outside;
                    continue;
                }
                if (counted) {
                    ++stats.rays[3];
                    ++stats.lights[index].shadow;
                    ++pixel->rays;
                }
                const Ids blockers = occluders({point, sample.direction}, sample.distance, counted);
                for (int id : blockers)
                    factor = mul(factor, scene.materials[scene.objects[id].material].kt);
                if (factor == 0) {
                    if (counted)
                        ++stats.lights[index].blocked;
                    continue;
                }
                if (counted && !blockers.empty())
                    ++stats.lights[index].attenuated;
                ++result.lit;
                const auto terms = phong(material, normal, sample.direction, negate(ray.direction),
                                         mul(sample.intensity, factor));
                result.diffuse += terms[0];
                result.specular += terms[1];
            }
            diffuse_sum += result.diffuse;
            specular_sum += result.specular;
            out.illumination += result.lit > 0;
            if (record)
                line(*record, "light ", index + 1, " lit ", result.lit, " of ", light_samples.size(),
                     " diffuse ", result.diffuse, " specular ", result.specular);
        }
        Color local;
        for (int component = 0; component < 3; ++component) {
            const I raw = floor_div(base[component] * (scene.ambient + diffuse_sum), scale) +
                          floor_div(255 * specular_sum, scale);
            local[component] = std::min<I>(raw, 255);
            if (counted)
                stats.saturated += raw > 255;
        }
        if (record)
            line(*record, "local ", triple(local));
        Color color = local;
        if (depth < render.depth && (material.kr > 0 || material.kt > 0)) {
            const Weights weights = refracted(material, ray.direction, normal, front);
            if (weights.total_internal) {
                if (counted)
                    ++stats.total_internal;
                if (record)
                    line(*record, "total_internal_reflection");
            }
            if (record)
                line(*record, "weights ", scale - material.kr - material.kt, " ", weights.reflection, " ",
                     weights.refraction);
            Color reflected_color{}, refracted_color{};
            if (weights.reflection > 0)
                reflected_color =
                    trace({point, reflected(ray.direction, normal)}, 1, depth + 1, counted, pixel, record)
                        .color;
            if (weights.refraction > 0)
                refracted_color =
                    trace({point, *weights.direction}, 2, depth + 1, counted, pixel, record).color;
            color = mix(local, scale - material.kr - material.kt, reflected_color, weights.reflection,
                        refracted_color, weights.refraction);
        }
        if (scene.fog) {
            const I distance = hit->candidate.distance,
                    factor = distance <= scene.fog_start ? 0
                             : distance >= scene.fog_end ? scale
                                                         : floor_div((distance - scene.fog_start) * scale,
                                                                     scene.fog_end - scene.fog_start);
            color = mix(color, scale - factor, scene.fog_color, factor, Color{}, 0);
        }
        out.color = color;
        if (record)
            line(*record, "color ", triple(color));
        return out;
    }
    int leaf_depth(const Node *node, int object) const {
        if (!node->objects.empty())
            return std::find(node->objects.begin(), node->objects.end(), object) != node->objects.end()
                       ? node->depth
                       : -1;
        const int left = leaf_depth(node->left.get(), object);
        return left >= 0 ? left : leaf_depth(node->right.get(), object);
    }
};
static Lines ppm(const std::vector<Color> &values, int width, int height) {
    Lines out{"P3", std::to_string(width) + " " + std::to_string(height), "255"};
    for (int y = 0; y < height; ++y) {
        std::string row;
        for (int x = 0; x < width; ++x) {
            if (x)
                row += ' ';
            row += triple(values[y * width + x]);
        }
        out.push_back(row);
    }
    return out;
}
static Lines pgm(const std::vector<I> &values, int width, int height) {
    Lines out{"P2", std::to_string(width) + " " + std::to_string(height), "255"};
    for (int y = 0; y < height; ++y) {
        std::string row;
        for (int x = 0; x < width; ++x) {
            if (x)
                row += ' ';
            row += std::to_string(values[y * width + x]);
        }
        out.push_back(row);
    }
    return out;
}
static void save(const std::string &name, const Lines &lines) {
    std::ofstream out("output/" + name);
    for (const std::string &line : lines)
        out << line << '\n';
}
int main() {
    std::filesystem::create_directories("output");
    Tracer tracer(load_scene(), settings());
    const Settings &render = tracer.render;
    const int width = render.width, height = render.height, count = width * height;
    std::vector<Pixel> pixels(count);
    auto label = [&](const Pixel &pixel) {
        return pixel.info ? tracer.scene.objects[pixel.info->hit.object].label : '.';
    };
    for (int y = 0; y < height; ++y)
        for (int x = 0; x < width; ++x) {
            Pixel &pixel = pixels[y * width + x];
            const Result result = tracer.trace(tracer.camera(4 * x + 2, 4 * y + 2), 0, 0, true, &pixel);
            pixel.center = pixel.color = result.color;
            pixel.info = result.info;
            for (int light = 0; light < int(result.lights.size()); ++light)
                if (result.lights[light].lit > 0)
                    pixel.lit.push_back(light);
        }
    int supersampled = 0;
    const std::array<std::array<int, 2>, 4> neighbors{{{-1, 0}, {1, 0}, {0, -1}, {0, 1}}},
        offsets{{{1, 1}, {3, 1}, {1, 3}, {3, 3}}};
    for (int y = 0; y < height; ++y)
        for (int x = 0; x < width; ++x) {
            Pixel &pixel = pixels[y * width + x];
            for (auto offset : neighbors) {
                const int xx = x + offset[0], yy = y + offset[1];
                if (xx < 0 || xx >= width || yy < 0 || yy >= height)
                    continue;
                const Pixel &other = pixels[yy * width + xx];
                I difference = 0;
                for (int component = 0; component < 3; ++component)
                    difference =
                        std::max(difference, std::abs(pixel.center[component] - other.center[component]));
                if (label(pixel) != label(other) || difference > render.contrast)
                    pixel.subsampled = true;
            }
            if (pixel.subsampled) {
                ++supersampled;
                Color sum{};
                for (auto offset : offsets) {
                    const Color color =
                        tracer.trace(tracer.camera(4 * x + offset[0], 4 * y + offset[1]), 0, 0, true, &pixel)
                            .color;
                    for (int component = 0; component < 3; ++component)
                        sum[component] += color[component];
                }
                for (int component = 0; component < 3; ++component)
                    pixel.color[component] = floor_div(sum[component], 4);
            }
        }
    std::optional<I> minimum, maximum;
    I cost_max = 0;
    Color total_color{};
    std::array<I, 8> histogram{};
    std::vector<Color> colors(count), normal(count), albedo(count);
    std::vector<I> depth(count), cost(count);
    Lines object_map, light_map, ray_depth;
    for (int y = 0; y < height; ++y) {
        std::string objects, lights, depths;
        for (int x = 0; x < width; ++x) {
            const int index = y * width + x;
            const Pixel &pixel = pixels[index];
            colors[index] = pixel.color;
            objects += label(pixel);
            lights += pixel.info ? char('0' + pixel.lit.size()) : '.';
            depths += char('0' + pixel.depth);
            cost_max = std::max(cost_max, pixel.rays);
            for (int component = 0; component < 3; ++component)
                total_color[component] += pixel.color[component];
            const I brightness =
                floor_div(299 * pixel.color[0] + 587 * pixel.color[1] + 114 * pixel.color[2], 1000);
            ++histogram[floor_div(brightness, 32)];
            if (pixel.info) {
                const I distance = pixel.info->hit.candidate.distance;
                minimum = minimum ? std::min(*minimum, distance) : distance;
                maximum = maximum ? std::max(*maximum, distance) : distance;
                albedo[index] = pixel.info->base;
                for (int component = 0; component < 3; ++component)
                    normal[index][component] = std::max<I>(
                        0, std::min<I>(255,
                                       floor_div((pixel.info->normal[component] + scale) * 255, 2 * scale)));
            }
        }
        object_map.push_back(objects);
        light_map.push_back(lights);
        ray_depth.push_back(depths);
    }
    for (int index = 0; index < count; ++index) {
        cost[index] = floor_div(255 * pixels[index].rays, cost_max);
        if (pixels[index].info)
            depth[index] =
                *maximum == *minimum
                    ? 255
                    : 255 - floor_div(235 * (pixels[index].info->hit.candidate.distance - *minimum),
                                      *maximum - *minimum);
    }
    save("image.ppm", ppm(colors, width, height));
    save("depth.pgm", pgm(depth, width, height));
    save("normal.ppm", ppm(normal, width, height));
    save("albedo.ppm", ppm(albedo, width, height));
    save("cost.pgm", pgm(cost, width, height));
    save("object_map.txt", object_map);
    save("light_map.txt", light_map);
    save("ray_depth.txt", ray_depth);
    Lines stats;
    const Statistics &counts = tracer.stats;
    line(stats, "image ", width, " ", height);
    line(stats, "supersampled ", supersampled);
    line(stats, "rays primary ", counts.rays[0], " reflection ", counts.rays[1], " refraction ",
         counts.rays[2], " shadow ", counts.rays[3], " total ",
         std::accumulate(counts.rays.begin(), counts.rays.end(), I(0)));
    line(stats, "misses primary ", counts.misses[0], " reflection ", counts.misses[1], " refraction ",
         counts.misses[2]);
    std::string depth_counts = "depth";
    for (I value : counts.depths)
        depth_counts += " " + std::to_string(value);
    stats.push_back(depth_counts);
    const std::array<std::string, 4> ray_names{"primary", "reflection", "refraction", "shadow"};
    for (int kind = 0; kind < 4; ++kind)
        line(stats, "tests ", ray_names[kind], " nodes ", counts.tests[kind].nodes, " objects ",
             counts.tests[kind].objects);
    line(stats, "total_internal_reflection ", counts.total_internal);
    line(stats, "clamped ", counts.saturated);
    if (minimum)
        line(stats, "distance ", *minimum, " ", *maximum);
    else
        line(stats, "distance none");
    line(stats, "max_pixel_rays ", cost_max);
    Color mean;
    for (int component = 0; component < 3; ++component)
        mean[component] = floor_div(total_color[component], count);
    line(stats, "mean ", triple(mean));
    std::string histogram_line = "histogram";
    for (I value : histogram)
        histogram_line += " " + std::to_string(value);
    stats.push_back(histogram_line);
    std::function<void(const Node *)> report_node = [&](const Node *node) {
        if (!node->objects.empty()) {
            std::string labels;
            for (int id : node->objects)
                labels += tracer.scene.objects[id].label;
            line(stats, "node ", node->depth, " leaf ", labels, " box ", triple(node->box.lo), " ",
                 triple(node->box.hi), " visits ", node->visits);
        } else {
            line(stats, "node ", node->depth, " inner box ", triple(node->box.lo), " ", triple(node->box.hi),
                 " visits ", node->visits);
            report_node(node->left.get());
            report_node(node->right.get());
        }
    };
    if (tracer.root)
        report_node(tracer.root.get());
    for (int id = 0; id < int(tracer.scene.objects.size()); ++id) {
        const Object &object = tracer.scene.objects[id];
        I pixel_count = 0;
        int x0 = width, y0 = height, x1 = -1, y1 = -1;
        Color sum{};
        for (int y = 0; y < height; ++y)
            for (int x = 0; x < width; ++x) {
                const Pixel &pixel = pixels[y * width + x];
                if (!pixel.info || pixel.info->hit.object != id)
                    continue;
                ++pixel_count;
                x0 = std::min(x0, x);
                y0 = std::min(y0, y);
                x1 = std::max(x1, x);
                y1 = std::max(y1, y);
                for (int component = 0; component < 3; ++component)
                    sum[component] += pixel.color[component];
            }
        std::ostringstream out;
        out << "object " << object.label << ' ' << kind_name(object.kind) << " primary "
            << counts.objects[id].primary << " secondary " << counts.objects[id].secondary << " shadow "
            << counts.objects[id].shadow << " pixels " << pixel_count << " box ";
        if (pixel_count) {
            for (I &component : sum)
                component = floor_div(component, pixel_count);
            out << x0 << ' ' << y0 << ' ' << x1 << ' ' << y1 << " color " << triple(sum);
        } else
            out << "none color none";
        stats.push_back(out.str());
    }
    for (int id = 0; id < int(tracer.scene.lights.size()); ++id) {
        const Light &light = tracer.scene.lights[id];
        I lit_pixels = 0;
        for (const Pixel &pixel : pixels)
            lit_pixels += std::find(pixel.lit.begin(), pixel.lit.end(), id) != pixel.lit.end();
        const LightCounts &value = counts.lights[id];
        line(stats, "light ", id + 1, " ", kind_name(light.kind), " samples ",
             light.kind == LightKind::area ? light.divisions * light.divisions : 1, " pixels ", lit_pixels,
             " shadow_rays ", value.shadow, " blocked ", value.blocked, " attenuated ", value.attenuated,
             " backfacing ", value.backfacing, " outside ", value.outside);
    }
    save("stats.txt", stats);
    Lines answers;
    const Lines query_lines = queries();
    for (int index = 0; index < int(query_lines.size()); ++index) {
        line(answers, "query ", index + 1, " ", query_lines[index]);
        std::istringstream input(query_lines[index]);
        std::string kind;
        input >> kind;
        if (kind == "pixel") {
            int x, y;
            input >> x >> y;
            const Pixel &pixel = pixels[y * width + x];
            line(answers, "label ", label(pixel), " distance ",
                 pixel.info ? std::to_string(pixel.info->hit.candidate.distance) : "none", " color ",
                 triple(pixel.color), " samples ", pixel.subsampled ? 4 : 1, " rays ", pixel.rays);
        } else if (kind == "trace") {
            int x, y;
            input >> x >> y;
            tracer.trace(tracer.camera(4 * x + 2, 4 * y + 2), 0, 0, false, nullptr, &answers);
        } else if (kind == "ray") {
            Vec origin, direction;
            input >> origin[0] >> origin[1] >> origin[2] >> direction[0] >> direction[1] >> direction[2];
            tracer.trace({origin, norm(direction)}, 0, 0, false, nullptr, &answers);
        } else if (kind == "object") {
            char label;
            input >> label;
            int id = 0;
            while (tracer.scene.objects[id].label != label)
                ++id;
            const Object &object = tracer.scene.objects[id];
            const Material &material = tracer.scene.materials[object.material];
            if (object.kind == ObjectKind::plane)
                line(answers, "plane material ", material.name, " bounds none leaf none");
            else
                line(answers, kind_name(object.kind), " material ", material.name, " bounds ",
                     triple(tracer.boxes[id].lo), " ", triple(tracer.boxes[id].hi), " leaf ",
                     tracer.leaf_depth(tracer.root.get(), id));
        } else if (kind == "visible") {
            Vec point;
            input >> point[0] >> point[1] >> point[2];
            const Vec rel = sub(point, tracer.scene.eye);
            const Ray ray{tracer.scene.eye, norm(rel)};
            const Ids blockers = tracer.occluders(ray, length(rel) - render.epsilon, false);
            const auto first = tracer.nearest(ray, 0, false);
            if (first)
                line(answers, blockers.empty() ? "yes" : "no", " first ",
                     tracer.scene.objects[first->object].label, " t ", first->candidate.distance);
            else
                line(answers, blockers.empty() ? "yes" : "no", " first none");
        } else if (kind == "shadow") {
            Vec point;
            input >> point[0] >> point[1] >> point[2];
            for (int id = 0; id < int(tracer.scene.lights.size()); ++id) {
                const Light &light = tracer.scene.lights[id];
                std::vector<bool> seen(tracer.scene.objects.size());
                I transmittance = 0;
                for (const Sample &sample : tracer.samples(light, point)) {
                    I factor = tracer.cone(light, sample.direction);
                    for (int object : tracer.occluders({point, sample.direction}, sample.distance, false)) {
                        seen[object] = true;
                        factor =
                            mul(factor, tracer.scene.materials[tracer.scene.objects[object].material].kt);
                    }
                    transmittance += factor;
                }
                std::string labels;
                for (int object = 0; object < int(seen.size()); ++object)
                    if (seen[object])
                        labels += tracer.scene.objects[object].label;
                line(answers, "light ", id + 1, " factor ", transmittance, " occluders ",
                     labels.empty() ? "none" : labels);
            }
        } else {
            int x0, y0, x1, y1;
            input >> x0 >> y0 >> x1 >> y1;
            Color total{};
            std::vector<I> labels(tracer.scene.objects.size() + 1);
            const I region_count = I(x1 - x0 + 1) * (y1 - y0 + 1);
            for (int y = y0; y <= y1; ++y)
                for (int x = x0; x <= x1; ++x) {
                    const Pixel &pixel = pixels[y * width + x];
                    for (int component = 0; component < 3; ++component)
                        total[component] += pixel.color[component];
                    ++labels[pixel.info ? pixel.info->hit.object : tracer.scene.objects.size()];
                }
            for (I &component : total)
                component = floor_div(component, region_count);
            line(answers, "pixels ", region_count, " mean ", triple(total));
            for (int object = 0; object < int(labels.size()); ++object)
                if (labels[object])
                    line(answers, "label ",
                         object < int(tracer.scene.objects.size()) ? tracer.scene.objects[object].label : '.',
                         " ", labels[object]);
        }
    }
    save("queries.txt", answers);
}
