#include "stereo.hpp"
static const std::array<std::string, 7> names{"sad",    "ssd",       "census",   "sgm",
                                              "fusion", "wta_final", "sgm_final"};
static const std::array<std::string, 3> region_names{"nonocc", "all", "disc"};
static const std::array<std::string, 5> sources{"kept", "median", "background", "interpolated",
                                                "none"};
struct Selection {
    Image image, reasons, margins;
    std::array<I, 4> lr{};
    I bounds = 0;
    int window = 0;
};
static Selection select(const Volume &costs, const Image &texture, int width, int height,
                        const Params &p) {
    int count = p.maximum - p.minimum + 1;
    Image right(width * height, 0);
    for (int y = 0; y < height; ++y)
        for (int x = 0; x < width; ++x) {
            I best = std::numeric_limits<I>::max();
            for (int d = p.minimum; d <= p.maximum && x + d < width; ++d) {
                I value = costs[y * width + x + d][d - p.minimum];
                if (value < best) {
                    best = value;
                    right[y * width + x] = d;
                }
            }
        }
    Selection out;
    out.image.assign(width * height, 0);
    out.reasons.resize(width * height);
    out.margins.assign(width * height, 0);
    for (int y = 0; y < height; ++y)
        for (int x = 0; x < width; ++x) {
            int index = y * width + x;
            const Image &row = costs[index];
            int first = int(std::min_element(row.begin(), row.end()) - row.begin()),
                disparity = p.minimum + first;
            I c1 = row[first], c2 = std::numeric_limits<I>::max();
            for (int i = 0; i < count; ++i)
                if (std::abs(i - first) >= 2)
                    c2 = std::min(c2, row[i]);
            auto consistent = [&](int d) {
                return x - d >= 0 && std::llabs(d - right[y * width + x - d]) <= p.lr;
            };
            I reason = 0;
            if (texture[index] < p.texture_threshold)
                reason = 50;
            else if (100 * c2 <= (100 + p.uniqueness) * c1)
                reason = 100;
            else if (x - disparity < 0)
                reason = 150;
            else if (!consistent(disparity)) {
                bool any = false;
                for (int d = p.minimum; d <= p.maximum; ++d)
                    any = any || consistent(d);
                reason = any ? 200 : 255;
            }
            out.reasons[index] = reason;
            if (!reason) {
                out.image[index] = disparity;
                out.margins[index] = c2 - c1;
            }
            if (reason == 0 || reason == 200 || reason == 255) {
                I difference = std::llabs(disparity - right[y * width + x - disparity]);
                ++out.lr[std::min(I(3), difference)];
            }
            out.bounds += disparity == p.minimum || disparity == p.maximum;
        }
    return out;
}
static I median(Image values) {
    std::sort(values.begin(), values.end());
    return values[(values.size() - 1) / 2];
}
static std::vector<Pixels> components(const Image &image, int width, int height, I range) {
    std::vector<bool> visited(image.size());
    std::vector<Pixels> out;
    const std::array<std::pair<int, int>, 4> steps{{{1, 0}, {-1, 0}, {0, 1}, {0, -1}}};
    for (int seed = 0; seed < int(image.size()); ++seed) {
        if (!image[seed] || visited[seed])
            continue;
        Pixels queue{seed};
        visited[seed] = true;
        for (int head = 0; head < int(queue.size()); ++head) {
            int index = queue[head], x = index % width, y = index / width;
            for (auto step : steps) {
                int xx = x + step.first, yy = y + step.second;
                if (xx < 0 || xx >= width || yy < 0 || yy >= height)
                    continue;
                int other = yy * width + xx;
                if (!visited[other] && image[other] &&
                    std::llabs(image[index] - image[other]) <= range) {
                    visited[other] = true;
                    queue.push_back(other);
                }
            }
        }
        out.push_back(std::move(queue));
    }
    return out;
}
struct Post {
    Image image;
    std::vector<int> source;
    I components = 0, pixels = 0, median_changes = 0, background = 0, interpolated = 0,
      unfilled = 0;
};
static Post postprocess(const Selection &selection, int width, int height, const Params &p) {
    Post out;
    Image a1 = selection.image;
    for (const Pixels &group : components(selection.image, width, height, p.speckle_range))
        if (int(group.size()) < p.speckle_size) {
            ++out.components;
            out.pixels += I(group.size());
            for (int index : group)
                a1[index] = 0;
        }
    Image a2 = a1;
    for (int y = 0; y < height; ++y)
        for (int x = 0; x < width; ++x) {
            int index = y * width + x;
            if (!a1[index])
                continue;
            Image values;
            for (int yy = std::max(0, y - 1); yy <= std::min(height - 1, y + 1); ++yy)
                for (int xx = std::max(0, x - 1); xx <= std::min(width - 1, x + 1); ++xx)
                    if (a1[yy * width + xx])
                        values.push_back(a1[yy * width + xx]);
            a2[index] = median(values);
            out.median_changes += a2[index] != a1[index];
        }
    out.image = a2;
    out.source.assign(a2.size(), 4);
    for (int y = 0; y < height; ++y)
        for (int x = 0; x < width; ++x) {
            int index = y * width + x;
            if (a2[index]) {
                out.source[index] = a2[index] == selection.image[index] ? 0 : 1;
                continue;
            }
            Image values;
            bool background = selection.reasons[index] == 150 || selection.reasons[index] == 255;
            int paths = background ? 2 : 8;
            for (int direction = 0; direction < paths; ++direction) {
                int dx = directions[direction].first, dy = directions[direction].second,
                    xx = x + dx, yy = y + dy;
                while (xx >= 0 && xx < width && yy >= 0 && yy < height) {
                    I value = a2[yy * width + xx];
                    if (value) {
                        values.push_back(value);
                        break;
                    }
                    xx += dx;
                    yy += dy;
                }
            }
            if (values.empty()) {
                ++out.unfilled;
                continue;
            }
            out.image[index] =
                background ? *std::min_element(values.begin(), values.end()) : median(values);
            out.source[index] = background ? 2 : 3;
            if (background)
                ++out.background;
            else
                ++out.interpolated;
        }
    return out;
}
static I valid_count(const Image &image) {
    return std::count_if(image.begin(), image.end(), [](I value) { return value != 0; });
}
static std::string optional(I value) { return value ? std::to_string(value) : "-"; }
struct Object {
    Pixels pixels;
    I minimum = 0, maximum = 0, dm = 0, sum = 0, truth = 0, overlap = 0;
    int x0 = 0, y0 = 0, x1 = 0, y1 = 0, first = 0;
};
static Lines object_report(const Image &image, const PGM &truth, const Params &p) {
    int width = truth.width, height = truth.height, small = 0, total = 0;
    std::map<I, I> layers;
    for (I value : truth.pixels)
        if (value)
            ++layers[value];
    std::vector<Object> objects;
    for (Pixels group : components(image, width, height, p.object_range)) {
        if (int(group.size()) < p.object_size) {
            ++small;
            continue;
        }
        Object object;
        object.pixels = std::move(group);
        object.first = *std::min_element(object.pixels.begin(), object.pixels.end());
        object.x0 = width;
        object.y0 = height;
        Image values;
        std::map<I, I> counts;
        for (int index : object.pixels) {
            int x = index % width, y = index / width;
            object.x0 = std::min(object.x0, x);
            object.x1 = std::max(object.x1, x);
            object.y0 = std::min(object.y0, y);
            object.y1 = std::max(object.y1, y);
            values.push_back(image[index]);
            object.sum += image[index];
            if (truth.pixels[index])
                ++counts[truth.pixels[index]];
        }
        std::sort(values.begin(), values.end());
        object.minimum = values.front();
        object.maximum = values.back();
        object.dm = values[(values.size() - 1) / 2];
        for (const auto &entry : counts)
            if (entry.second > object.overlap) {
                object.truth = entry.first;
                object.overlap = entry.second;
            }
        total += int(object.pixels.size());
        objects.push_back(std::move(object));
    }
    std::sort(objects.begin(), objects.end(), [](const Object &a, const Object &b) {
        if (a.dm != b.dm)
            return a.dm > b.dm;
        if (a.pixels.size() != b.pixels.size())
            return a.pixels.size() > b.pixels.size();
        return a.first < b.first;
    });
    Lines out;
    line(out, "objects ", objects.size(), " small ", small, " pixels ", total);
    std::set<I> detected;
    for (int i = 0; i < int(objects.size()); ++i) {
        const Object &object = objects[i];
        I count = I(object.pixels.size());
        std::string tail = "truth - iou -";
        if (object.truth) {
            I denominator = count + layers[object.truth] - object.overlap;
            tail = "truth " + std::to_string(object.truth) + " iou " +
                   ratio(object.overlap, denominator);
            if (2 * object.overlap > denominator)
                detected.insert(object.truth);
        }
        line(out, "object ", i + 1, " pixels ", count, " box ", object.x0, " ", object.y0, " ",
             object.x1, " ", object.y1, " disparity ", object.minimum, " ", object.maximum,
             " median ", object.dm, " mean ", two_decimals(object.sum, count), " depth ",
             two_decimals(p.focal * p.baseline * count, object.sum), " size ",
             two_decimals((object.x1 - object.x0 + 1) * p.baseline, object.dm), " ",
             two_decimals((object.y1 - object.y0 + 1) * p.baseline, object.dm), " ", tail);
    }
    std::string missed;
    for (const auto &entry : layers)
        if (!detected.count(entry.first)) {
            if (!missed.empty())
                missed += " ";
            missed += std::to_string(entry.first);
        }
    line(out, "layers ", layers.size(), " detected ", detected.size(), " missed ",
         missed.empty() ? "-" : missed);
    return out;
}
int main() {
    const PGM left = read_pgm("input/left.pgm"), right = read_pgm("input/right.pgm"),
              truth = read_pgm("input/ground_truth.pgm");
    const Params p = read_parameters();
    const int width = left.width, height = left.height, count = width * height;
    const Regions regions = truth_regions(truth);
    const Image cl = census(left.pixels, width, height), cr = census(right.pixels, width, height),
                strength = texture(left.pixels, width, height, p.texture_window);
    std::array<Selection, 4> selections;
    std::array<Image, 7> images;
    Lines sweeps, paths;
    for (int kind = 0; kind < 3; ++kind) {
        Evaluation best;
        bool first = true;
        for (int window : p.windows[kind]) {
            Selection candidate = select(cost_volume(left, right, cl, cr, kind, window, p),
                                         strength, width, height, p);
            candidate.window = window;
            Evaluation result = evaluate(candidate.image, truth.pixels, regions.region[0]);
            line(sweeps, "sweep ", names[kind], " window ", window, " valid ",
                 valid_count(candidate.image), " bad1 ", ratio(result.bad1, result.pixels),
                 " bad2 ", ratio(result.bad2, result.pixels));
            if (first || result.bad1 < best.bad1 ||
                (result.bad1 == best.bad1 && result.bad2 < best.bad2)) {
                first = false;
                best = result;
                selections[kind] = std::move(candidate);
            }
        }
        images[kind] = selections[kind].image;
    }
    const Volume base = cost_volume(left, right, cl, cr, p.sgm_kind, p.sgm_window, p);
    const std::vector<Volume> cumulative = cumulative_costs(base, left, p);
    for (int i = 0; i < p.paths; ++i) {
        Selection candidate = select(cumulative[i], strength, width, height, p);
        candidate.window = p.sgm_window;
        Evaluation result = evaluate(candidate.image, truth.pixels, regions.region[0]);
        line(paths, "paths ", i + 1, " valid ", valid_count(candidate.image), " bad1 ",
             ratio(result.bad1, result.pixels), " bad2 ", ratio(result.bad2, result.pixels));
        if (i + 1 == p.paths)
            selections[3] = std::move(candidate);
    }
    images[3] = selections[3].image;
    const Post wta = postprocess(selections[p.wta_kind], width, height, p),
               sgm = postprocess(selections[3], width, height, p);
    images[5] = wta.image;
    images[6] = sgm.image;
    images[4].assign(count, 0);
    std::array<I, 5> votes{};
    for (int index = 0; index < count; ++index) {
        Image values;
        for (int method = 0; method < 4; ++method)
            if (images[method][index])
                values.push_back(images[method][index]);
        ++votes[values.size()];
        if (values.empty())
            continue;
        I middle = median(values), agree = 0;
        for (I value : values)
            agree += std::llabs(value - middle) <= 1;
        if (agree >= p.fusion_votes)
            images[4][index] = middle;
    }
    Lines report;
    line(report, "image ", width, " ", height);
    line(report, "disparities ", p.minimum, " ", p.maximum);
    for (int side = 0; side < 2; ++side) {
        const Image &image = side ? right.pixels : left.pixels;
        I sum = 0;
        for (I value : image)
            sum += value;
        line(report, side ? "right" : "left", " mean ", two_decimals(sum, count), " min ",
             *std::min_element(image.begin(), image.end()), " max ",
             *std::max_element(image.begin(), image.end()));
    }
    I texture_sum = 0, textureless = 0;
    for (I value : strength) {
        texture_sum += value;
        textureless += value < p.texture_threshold;
    }
    line(report, "texture mean ", two_decimals(texture_sum, count), " textureless ", textureless);
    line(report, "ground_truth known ", regions.region[1].size(), " nonocc ",
         regions.region[0].size(), " occluded ", regions.occluded.size(), " disc ",
         regions.region[2].size(), " unknown ", count - regions.region[1].size());
    I photometric_abs = 0, photometric_bias = 0;
    for (int index : regions.region[0]) {
        I delta = right.pixels[index - int(truth.pixels[index])] - left.pixels[index];
        photometric_abs += std::llabs(delta);
        photometric_bias += delta;
    }
    std::string bias = two_decimals(std::llabs(photometric_bias), I(regions.region[0].size()));
    if (photometric_bias < 0 && bias != "0.00")
        bias = "-" + bias;
    line(report, "photometric pixels ", regions.region[0].size(), " mean_abs ",
         two_decimals(photometric_abs, I(regions.region[0].size())), " bias ", bias);
    report.insert(report.end(), sweeps.begin(), sweeps.end());
    report.insert(report.end(), paths.begin(), paths.end());
    std::array<std::array<Evaluation, 3>, 7> evaluations{};
    for (int method = 0; method < 7; ++method) {
        const Image &image = images[method];
        Image valid;
        for (I value : image)
            if (value)
                valid.push_back(value);
        line(report, "method ", names[method], " valid ", valid.size(), " invalid ",
             count - valid.size());
        if (valid.empty())
            line(report, "disparity min - max - median - distinct 0");
        else {
            std::sort(valid.begin(), valid.end());
            line(report, "disparity min ", valid.front(), " max ", valid.back(), " median ",
                 valid[(valid.size() - 1) / 2], " distinct ",
                 std::set<I>(valid.begin(), valid.end()).size());
        }
        I horizontal = 0, vertical = 0;
        for (int y = 0; y < height; ++y)
            for (int x = 0; x < width; ++x) {
                int index = y * width + x;
                if (!image[index])
                    continue;
                if (x + 1 < width && image[index + 1])
                    horizontal += std::llabs(image[index] - image[index + 1]) >= 2;
                if (y + 1 < height && image[index + width])
                    vertical += std::llabs(image[index] - image[index + width]) >= 2;
            }
        line(report, "jumps horizontal ", horizontal, " vertical ", vertical);
        if (method < 4) {
            const Selection &selection = selections[method];
            line(report, "window ", selection.window, " bounds ", selection.bounds);
            std::array<I, 6> reasons{};
            for (I value : selection.reasons) {
                int code = value == 255 ? 5 : int(value / 50);
                ++reasons[code];
            }
            line(report, "reasons textureless ", reasons[1], " nonunique ", reasons[2], " outside ",
                 reasons[3], " mismatch ", reasons[4], " occluded ", reasons[5]);
            line(report, "lr 0 ", selection.lr[0], " 1 ", selection.lr[1], " 2 ", selection.lr[2],
                 " 3+ ", selection.lr[3]);
        } else if (method == 4)
            line(report, "votes 0 ", votes[0], " 1 ", votes[1], " 2 ", votes[2], " 3 ", votes[3],
                 " 4 ", votes[4]);
        else {
            const Post &post = method == 5 ? wta : sgm;
            line(report, "postprocess speckles ", post.components, " ", post.pixels, " median ",
                 post.median_changes, " background ", post.background, " interpolated ",
                 post.interpolated, " unfilled ", post.unfilled);
            for (int source = 0; source < 5; ++source) {
                Pixels region;
                for (int index : regions.region[1])
                    if (post.source[index] == source)
                        region.push_back(index);
                Evaluation result = evaluate(image, truth.pixels, region);
                line(report, "source ", sources[source], " pixels ", result.pixels, " bad1 ",
                     ratio(result.bad1, result.pixels));
            }
        }
        for (int region = 0; region < 3; ++region) {
            Evaluation result = evaluate(image, truth.pixels, regions.region[region]);
            evaluations[method][region] = result;
            line(report, "region ", region_names[region], " pixels ", result.pixels, " valid ",
                 result.valid, " bad1 ", ratio(result.bad1, result.pixels), " bad2 ",
                 ratio(result.bad2, result.pixels), " mae ",
                 result.valid ? two_decimals(result.error_sum, result.valid) : "-", " exact ",
                 result.exact);
        }
        I depth_count = 0, depth_sum = 0, depth_maximum = 0;
        for (int index : regions.region[0])
            if (image[index]) {
                I difference =
                    std::llabs(depth_hundredths(image[index], p.focal, p.baseline) -
                               depth_hundredths(truth.pixels[index], p.focal, p.baseline));
                ++depth_count;
                depth_sum += difference;
                depth_maximum = std::max(depth_maximum, difference);
            }
        if (depth_count)
            line(report, "depth_error pixels ", depth_count, " mean ",
                 two_decimals(depth_sum, 100 * depth_count), " max ",
                 two_decimals(depth_maximum, 100));
        else
            line(report, "depth_error pixels 0 mean - max -");
        std::array<I, 6> errors{};
        for (int index : regions.region[1]) {
            if (!image[index])
                ++errors[5];
            else
                ++errors[std::min(I(4), std::llabs(image[index] - truth.pixels[index]))];
        }
        line(report, "errors 0 ", errors[0], " 1 ", errors[1], " 2 ", errors[2], " 3 ", errors[3],
             " 4+ ", errors[4], " invalid ", errors[5]);
    }
    for (int region = 0; region < 3; ++region) {
        std::array<int, 7> order{0, 1, 2, 3, 4, 5, 6};
        std::sort(order.begin(), order.end(), [&](int a, int b) {
            Evaluation x = evaluations[a][region], y = evaluations[b][region];
            if (x.bad1 != y.bad1)
                return x.bad1 < y.bad1;
            if (x.bad2 != y.bad2)
                return x.bad2 < y.bad2;
            if ((x.valid > 0) != (y.valid > 0))
                return x.valid > 0;
            if (x.valid && x.error_sum * y.valid != y.error_sum * x.valid)
                return x.error_sum * y.valid < y.error_sum * x.valid;
            return a < b;
        });
        std::string row = "ranking " + region_names[region];
        for (int method : order)
            row += " " + names[method];
        report.push_back(row);
    }
    for (int method = 0; method < 4; ++method) {
        I tp = 0, fp = 0, fn = 0;
        for (int index : regions.occluded) {
            bool detected = selections[method].reasons[index] == 150 ||
                            selections[method].reasons[index] == 255;
            tp += detected;
            fn += !detected;
        }
        for (int index : regions.region[0])
            fp += selections[method].reasons[index] == 150 ||
                  selections[method].reasons[index] == 255;
        line(report, "occlusion ", names[method], " tp ", tp, " fp ", fp, " fn ", fn, " precision ",
             ratio(tp, tp + fp), " recall ", ratio(tp, tp + fn));
    }
    for (int method = 0; method < 4; ++method) {
        Pixels order;
        for (int index : regions.region[0])
            if (images[method][index])
                order.push_back(index);
        std::sort(order.begin(), order.end(), [&](int a, int b) {
            return selections[method].margins[a] != selections[method].margins[b]
                       ? selections[method].margins[a] > selections[method].margins[b]
                       : a < b;
        });
        for (int percent : {25, 50, 75, 100}) {
            int size = (int(order.size()) * percent + 99) / 100;
            I bad = 0;
            for (int i = 0; i < size; ++i)
                bad += std::llabs(images[method][order[i]] - truth.pixels[order[i]]) > 1;
            line(report, "confidence ", names[method], " ", percent, " pixels ", size, " margin ",
                 size ? std::to_string(selections[method].margins[order[size - 1]]) : "-", " bad1 ",
                 ratio(bad, size));
        }
    }
    std::map<I, I> layers;
    for (I value : truth.pixels)
        if (value)
            ++layers[value];
    for (const auto &entry : layers) {
        Pixels region;
        for (int index : regions.region[0])
            if (truth.pixels[index] == entry.first)
                region.push_back(index);
        std::string row = "layer " + std::to_string(entry.first) + " pixels " +
                          std::to_string(entry.second) + " nonocc " +
                          std::to_string(region.size()) + " bad1";
        for (const Image &image : images)
            row += " " + std::to_string(evaluate(image, truth.pixels, region).bad1);
        report.push_back(row);
    }
    for (int disparity = p.minimum; disparity <= p.maximum; ++disparity)
        line(report, "histogram ", disparity, " ",
             std::count(images[6].begin(), images[6].end(), disparity));
    Lines depth{"x,y,sad,ssd,census,sgm,disparity,source,subpixel,depth,truth,truth_depth"};
    for (auto sample : p.samples) {
        int index = sample.second * width + sample.first;
        std::string row = std::to_string(sample.first) + "," + std::to_string(sample.second);
        for (int method = 0; method < 4; ++method)
            row += "," + optional(images[method][index]);
        I disparity = images[6][index];
        if (disparity) {
            const auto refined = subpixel(disparity, cumulative.back()[index], p);
            row += "," + std::to_string(disparity) + "," + sources[sgm.source[index]] + "," +
                   refined.first + "," + refined.second;
        } else
            row += ",-,none,-,-";
        I ground = truth.pixels[index];
        row += ground
                   ? "," + std::to_string(ground) + "," + two_decimals(p.focal * p.baseline, ground)
                   : ",-,-";
        depth.push_back(row);
    }
    std::filesystem::create_directories("output");
    Image wta_pgm = images[5], sgm_pgm = images[6], error(count);
    for (int index = 0; index < count; ++index) {
        wta_pgm[index] *= 8;
        sgm_pgm[index] *= 8;
        if (!truth.pixels[index])
            error[index] = 0;
        else if (!images[6][index])
            error[index] = 255;
        else
            error[index] =
                50 + 50 * std::min(I(3), std::llabs(images[6][index] - truth.pixels[index]));
    }
    write_pgm("disparity_wta.pgm", {width, height, wta_pgm});
    write_pgm("disparity_sgm.pgm", {width, height, sgm_pgm});
    write_pgm("occlusion.pgm", {width, height, selections[3].reasons});
    write_pgm("error_sgm.pgm", {width, height, error});
    save("depth.csv", depth);
    save("evaluation.txt", report);
    save("objects.txt", object_report(images[6], truth, p));
}
