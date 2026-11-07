#include "stereo.h"
static const char *names[7] = {"sad", "ssd", "census", "sgm", "fusion", "wta_final", "sgm_final"},
                  *region_names[3] = {"nonocc", "all", "disc"},
                  *sources[5] = {"kept", "median", "background", "interpolated", "none"};
typedef struct {
    I *image, *reasons, *margins, lr[4], bounds;
    int window;
} Selection;
static bool consistent(int x, int y, int width, int disparity, const I *right, const Params *p) {
    return x - disparity >= 0 && llabs(disparity - right[y * width + x - disparity]) <= p->lr;
}
static Selection select_costs(Volume costs, const I *strength, int width, int height,
                              const Params *p) {
    int count = costs.disparities;
    I *right = allocate((size_t)(width * height), sizeof(I));
    for (int y = 0; y < height; ++y)
        for (int x = 0; x < width; ++x) {
            I best = LLONG_MAX;
            for (int d = p->minimum; d <= p->maximum && x + d < width; ++d) {
                I value = costs.values[(y * width + x + d) * count + d - p->minimum];
                if (value < best) {
                    best = value;
                    right[y * width + x] = d;
                }
            }
        }
    Selection out = {0};
    out.image = allocate((size_t)(width * height), sizeof(I));
    out.reasons = allocate((size_t)(width * height), sizeof(I));
    out.margins = allocate((size_t)(width * height), sizeof(I));
    for (int y = 0; y < height; ++y)
        for (int x = 0; x < width; ++x) {
            int index = y * width + x, first = 0;
            const I *row = costs.values + index * count;
            for (int i = 1; i < count; ++i)
                if (row[i] < row[first])
                    first = i;
            int disparity = p->minimum + first;
            I c1 = row[first], c2 = LLONG_MAX;
            for (int i = 0; i < count; ++i)
                if (abs(i - first) >= 2 && row[i] < c2)
                    c2 = row[i];
            I reason = 0;
            if (strength[index] < p->texture_threshold)
                reason = 50;
            else if (100 * c2 <= (100 + p->uniqueness) * c1)
                reason = 100;
            else if (x - disparity < 0)
                reason = 150;
            else if (!consistent(x, y, width, disparity, right, p)) {
                bool any = false;
                for (int d = p->minimum; d <= p->maximum; ++d)
                    any = any || consistent(x, y, width, d, right, p);
                reason = any ? 200 : 255;
            }
            out.reasons[index] = reason;
            if (!reason) {
                out.image[index] = disparity;
                out.margins[index] = c2 - c1;
            }
            if (reason == 0 || reason == 200 || reason == 255) {
                I difference = llabs(disparity - right[y * width + x - disparity]);
                ++out.lr[difference < 3 ? difference : 3];
            }
            out.bounds += disparity == p->minimum || disparity == p->maximum;
        }
    return out;
}
static int value_order(const void *a, const void *b) {
    I x = *(const I *)a, y = *(const I *)b;
    return x < y ? -1 : x > y;
}
static I median(I *values, int count) {
    qsort(values, (size_t)count, sizeof(I), value_order);
    return values[(count - 1) / 2];
}
typedef struct {
    Pixels *data;
    int count;
} Components;
static Components components(const I *image, int width, int height, I range) {
    bool *visited = allocate((size_t)(width * height), sizeof(bool));
    Components out = {allocate((size_t)(width * height), sizeof(Pixels)), 0};
    const Point steps[4] = {{1, 0}, {-1, 0}, {0, 1}, {0, -1}};
    for (int seed = 0; seed < width * height; ++seed) {
        if (!image[seed] || visited[seed])
            continue;
        int queue[3072], count = 1;
        queue[0] = seed;
        visited[seed] = true;
        for (int head = 0; head < count; ++head) {
            int index = queue[head], x = index % width, y = index / width;
            for (int direction = 0; direction < 4; ++direction) {
                int xx = x + steps[direction].x, yy = y + steps[direction].y;
                if (xx < 0 || xx >= width || yy < 0 || yy >= height)
                    continue;
                int other = yy * width + xx;
                if (!visited[other] && image[other] &&
                    llabs(image[index] - image[other]) <= range) {
                    visited[other] = true;
                    queue[count++] = other;
                }
            }
        }
        Pixels *group = &out.data[out.count++];
        group->data = allocate((size_t)count, sizeof(int));
        group->count = count;
        memcpy(group->data, queue, (size_t)count * sizeof(int));
    }
    return out;
}
typedef struct {
    I *image;
    int *source;
    I components, pixels, median_changes, background, interpolated, unfilled;
} Post;
static Post postprocess(Selection selection, int width, int height, const Params *p) {
    Post out = {0};
    int count = width * height;
    I *a1 = allocate((size_t)count, sizeof(I));
    memcpy(a1, selection.image, (size_t)count * sizeof(I));
    Components groups = components(selection.image, width, height, p->speckle_range);
    for (int i = 0; i < groups.count; ++i) {
        Pixels group = groups.data[i];
        if (group.count < p->speckle_size) {
            ++out.components;
            out.pixels += group.count;
            for (int j = 0; j < group.count; ++j)
                a1[group.data[j]] = 0;
        }
    }
    I *a2 = allocate((size_t)count, sizeof(I));
    memcpy(a2, a1, (size_t)count * sizeof(I));
    for (int y = 0; y < height; ++y)
        for (int x = 0; x < width; ++x) {
            int index = y * width + x;
            if (!a1[index])
                continue;
            I values[9];
            int n = 0;
            for (int dy = -1; dy <= 1; ++dy)
                for (int dx = -1; dx <= 1; ++dx) {
                    int xx = x + dx, yy = y + dy;
                    if (xx < 0 || xx >= width || yy < 0 || yy >= height)
                        continue;
                    if (a1[yy * width + xx])
                        values[n++] = a1[yy * width + xx];
                }
            a2[index] = median(values, n);
            out.median_changes += a2[index] != a1[index];
        }
    out.image = allocate((size_t)count, sizeof(I));
    memcpy(out.image, a2, (size_t)count * sizeof(I));
    out.source = allocate((size_t)count, sizeof(int));
    for (int y = 0; y < height; ++y)
        for (int x = 0; x < width; ++x) {
            int index = y * width + x;
            if (a2[index]) {
                out.source[index] = a2[index] == selection.image[index] ? 0 : 1;
                continue;
            }
            out.source[index] = 4;
            I values[8];
            int n = 0;
            bool background = selection.reasons[index] == 150 || selection.reasons[index] == 255;
            int paths = background ? 2 : 8;
            for (int direction = 0; direction < paths; ++direction) {
                int dx = directions[direction].x, dy = directions[direction].y, xx = x + dx,
                    yy = y + dy;
                while (xx >= 0 && xx < width && yy >= 0 && yy < height) {
                    I value = a2[yy * width + xx];
                    if (value) {
                        values[n++] = value;
                        break;
                    }
                    xx += dx;
                    yy += dy;
                }
            }
            if (!n) {
                ++out.unfilled;
                continue;
            }
            qsort(values, (size_t)n, sizeof(I), value_order);
            out.image[index] = background ? values[0] : values[(n - 1) / 2];
            out.source[index] = background ? 2 : 3;
            if (background)
                ++out.background;
            else
                ++out.interpolated;
        }
    return out;
}
static I valid_count(const I *image, int count) {
    I out = 0;
    for (int i = 0; i < count; ++i)
        out += image[i] != 0;
    return out;
}
static char *optional(I value) { return value ? format("%lld", value) : "-"; }
typedef struct {
    Pixels pixels;
    I minimum, maximum, dm, sum, truth, overlap;
    int x0, y0, x1, y1, first;
} Object;
static int object_order(const void *a, const void *b) {
    const Object *x = a, *y = b;
    if (x->dm != y->dm)
        return x->dm > y->dm ? -1 : 1;
    if (x->pixels.count != y->pixels.count)
        return y->pixels.count - x->pixels.count;
    return x->first - y->first;
}
static Lines object_report(const I *image, PGM truth, const Params *p) {
    int width = truth.width, height = truth.height, small = 0, total = 0;
    I layers[32] = {0};
    for (int i = 0; i < width * height; ++i)
        if (truth.pixels[i])
            ++layers[truth.pixels[i]];
    Object *objects = allocate((size_t)(width * height), sizeof(Object));
    int object_count = 0;
    Components groups = components(image, width, height, p->object_range);
    for (int i = 0; i < groups.count; ++i) {
        Pixels group = groups.data[i];
        if (group.count < p->object_size) {
            ++small;
            continue;
        }
        Object *object = &objects[object_count++];
        object->pixels = group;
        object->first = group.data[0];
        object->x0 = width;
        object->y0 = height;
        I values[3072], counts[32] = {0};
        for (int j = 0; j < group.count; ++j) {
            int index = group.data[j], x = index % width, y = index / width;
            if (index < object->first)
                object->first = index;
            if (x < object->x0)
                object->x0 = x;
            if (x > object->x1)
                object->x1 = x;
            if (y < object->y0)
                object->y0 = y;
            if (y > object->y1)
                object->y1 = y;
            values[j] = image[index];
            object->sum += image[index];
            if (truth.pixels[index])
                ++counts[truth.pixels[index]];
        }
        qsort(values, (size_t)group.count, sizeof(I), value_order);
        object->minimum = values[0];
        object->maximum = values[group.count - 1];
        object->dm = values[(group.count - 1) / 2];
        for (int g = 1; g <= 31; ++g)
            if (counts[g] > object->overlap) {
                object->truth = g;
                object->overlap = counts[g];
            }
        total += group.count;
    }
    qsort(objects, (size_t)object_count, sizeof(Object), object_order);
    Lines out = {0};
    line(&out, "objects %d small %d pixels %d", object_count, small, total);
    bool detected[32] = {false};
    for (int i = 0; i < object_count; ++i) {
        Object object = objects[i];
        I count = object.pixels.count;
        char *tail = "truth - iou -";
        if (object.truth) {
            I denominator = count + layers[object.truth] - object.overlap;
            tail = format("truth %lld iou %s", object.truth, ratio(object.overlap, denominator));
            if (2 * object.overlap > denominator)
                detected[object.truth] = true;
        }
        line(
            &out,
            "object %d pixels %lld box %d %d %d %d disparity %lld %lld median %lld mean %s depth %s size %s %s %s",
            i + 1, count, object.x0, object.y0, object.x1, object.y1, object.minimum,
            object.maximum, object.dm, two_decimals(object.sum, count),
            two_decimals(p->focal * p->baseline * count, object.sum),
            two_decimals((object.x1 - object.x0 + 1) * p->baseline, object.dm),
            two_decimals((object.y1 - object.y0 + 1) * p->baseline, object.dm), tail);
    }
    int layer_count = 0, detected_count = 0;
    char *missed = "";
    for (int g = 1; g <= 31; ++g)
        if (layers[g]) {
            ++layer_count;
            if (detected[g])
                ++detected_count;
            else
                missed = joined(missed, format("%s%d", strlen(missed) ? " " : "", g));
        }
    line(&out, "layers %d detected %d missed %s", layer_count, detected_count,
         strlen(missed) ? missed : "-");
    return out;
}
static Evaluation ranking_values[7];
static int ranking_order(const void *a, const void *b) {
    int i = *(const int *)a, j = *(const int *)b;
    Evaluation x = ranking_values[i], y = ranking_values[j];
    if (x.bad1 != y.bad1)
        return x.bad1 < y.bad1 ? -1 : 1;
    if (x.bad2 != y.bad2)
        return x.bad2 < y.bad2 ? -1 : 1;
    if ((x.valid > 0) != (y.valid > 0))
        return x.valid > 0 ? -1 : 1;
    if (x.valid && x.error_sum * y.valid != y.error_sum * x.valid)
        return x.error_sum * y.valid < y.error_sum * x.valid ? -1 : 1;
    return i - j;
}
static const I *confidence_margins;
static int confidence_order(const void *a, const void *b) {
    int i = *(const int *)a, j = *(const int *)b;
    if (confidence_margins[i] != confidence_margins[j])
        return confidence_margins[i] > confidence_margins[j] ? -1 : 1;
    return i - j;
}
int main(void) {
    PGM left = read_pgm("input/left.pgm"), right = read_pgm("input/right.pgm"),
        truth = read_pgm("input/ground_truth.pgm");
    Params params = read_parameters();
    const Params *p = &params;
    int width = left.width, height = left.height, count = width * height;
    Regions regions = truth_regions(truth);
    I *cl = census(left.pixels, width, height), *cr = census(right.pixels, width, height),
      *strength = texture(left.pixels, width, height, p->texture_window);
    Selection selections[4] = {0};
    I *images[7] = {0};
    Lines sweeps = {0}, paths = {0};
    for (int kind = 0; kind < 3; ++kind) {
        Evaluation best = {0};
        bool first = true;
        for (int k = 0; k < p->window_counts[kind]; ++k) {
            int window = p->windows[kind][k];
            Selection candidate = select_costs(cost_volume(left, right, cl, cr, kind, window, p),
                                               strength, width, height, p);
            candidate.window = window;
            Evaluation result = evaluate(candidate.image, truth.pixels, regions.region[0]);
            line(&sweeps, "sweep %s window %d valid %lld bad1 %s bad2 %s", names[kind], window,
                 valid_count(candidate.image, count), ratio(result.bad1, result.pixels),
                 ratio(result.bad2, result.pixels));
            if (first || result.bad1 < best.bad1 ||
                (result.bad1 == best.bad1 && result.bad2 < best.bad2)) {
                first = false;
                best = result;
                selections[kind] = candidate;
            }
        }
        images[kind] = selections[kind].image;
    }
    Volume base = cost_volume(left, right, cl, cr, p->sgm_kind, p->sgm_window, p),
           *cumulative = cumulative_costs(base, left, p);
    for (int i = 0; i < p->paths; ++i) {
        Selection candidate = select_costs(cumulative[i], strength, width, height, p);
        candidate.window = p->sgm_window;
        Evaluation result = evaluate(candidate.image, truth.pixels, regions.region[0]);
        line(&paths, "paths %d valid %lld bad1 %s bad2 %s", i + 1,
             valid_count(candidate.image, count), ratio(result.bad1, result.pixels),
             ratio(result.bad2, result.pixels));
        if (i + 1 == p->paths)
            selections[3] = candidate;
    }
    images[3] = selections[3].image;
    Post wta = postprocess(selections[p->wta_kind], width, height, p),
         sgm = postprocess(selections[3], width, height, p);
    images[5] = wta.image;
    images[6] = sgm.image;
    images[4] = allocate((size_t)count, sizeof(I));
    I votes[5] = {0};
    for (int index = 0; index < count; ++index) {
        I values[4];
        int n = 0;
        for (int method = 0; method < 4; ++method)
            if (images[method][index])
                values[n++] = images[method][index];
        ++votes[n];
        if (!n)
            continue;
        I middle = median(values, n), agree = 0;
        for (int i = 0; i < n; ++i)
            agree += llabs(values[i] - middle) <= 1;
        if (agree >= p->fusion_votes)
            images[4][index] = middle;
    }
    Lines report = {0};
    line(&report, "image %d %d", width, height);
    line(&report, "disparities %d %d", p->minimum, p->maximum);
    for (int side = 0; side < 2; ++side) {
        const I *image = side ? right.pixels : left.pixels;
        I sum = 0, minimum = image[0], maximum = image[0];
        for (int i = 0; i < count; ++i) {
            sum += image[i];
            if (image[i] < minimum)
                minimum = image[i];
            if (image[i] > maximum)
                maximum = image[i];
        }
        line(&report, "%s mean %s min %lld max %lld", side ? "right" : "left",
             two_decimals(sum, count), minimum, maximum);
    }
    I texture_sum = 0, textureless = 0;
    for (int i = 0; i < count; ++i) {
        texture_sum += strength[i];
        textureless += strength[i] < p->texture_threshold;
    }
    line(&report, "texture mean %s textureless %lld", two_decimals(texture_sum, count),
         textureless);
    line(&report, "ground_truth known %d nonocc %d occluded %d disc %d unknown %d",
         regions.region[1].count, regions.region[0].count, regions.occluded.count,
         regions.region[2].count, count - regions.region[1].count);
    I photometric_abs = 0, photometric_bias = 0;
    for (int i = 0; i < regions.region[0].count; ++i) {
        int index = regions.region[0].data[i];
        I delta = right.pixels[index - (int)truth.pixels[index]] - left.pixels[index];
        photometric_abs += llabs(delta);
        photometric_bias += delta;
    }
    char *bias = two_decimals(llabs(photometric_bias), regions.region[0].count);
    if (photometric_bias < 0 && strcmp(bias, "0.00") != 0)
        bias = joined("-", bias);
    line(&report, "photometric pixels %d mean_abs %s bias %s", regions.region[0].count,
         two_decimals(photometric_abs, regions.region[0].count), bias);
    for (int i = 0; i < sweeps.count; ++i)
        line(&report, "%s", sweeps.data[i]);
    for (int i = 0; i < paths.count; ++i)
        line(&report, "%s", paths.data[i]);
    Evaluation evaluations[7][3] = {0};
    for (int method = 0; method < 7; ++method) {
        const I *image = images[method];
        I valid[3072];
        int valid_size = 0;
        for (int i = 0; i < count; ++i)
            if (image[i])
                valid[valid_size++] = image[i];
        line(&report, "method %s valid %d invalid %d", names[method], valid_size,
             count - valid_size);
        if (!valid_size)
            line(&report, "disparity min - max - median - distinct 0");
        else {
            qsort(valid, (size_t)valid_size, sizeof(I), value_order);
            int distinct = 1;
            for (int i = 1; i < valid_size; ++i)
                distinct += valid[i] != valid[i - 1];
            line(&report, "disparity min %lld max %lld median %lld distinct %d", valid[0],
                 valid[valid_size - 1], valid[(valid_size - 1) / 2], distinct);
        }
        I horizontal = 0, vertical = 0;
        for (int y = 0; y < height; ++y)
            for (int x = 0; x < width; ++x) {
                int index = y * width + x;
                if (!image[index])
                    continue;
                if (x + 1 < width && image[index + 1])
                    horizontal += llabs(image[index] - image[index + 1]) >= 2;
                if (y + 1 < height && image[index + width])
                    vertical += llabs(image[index] - image[index + width]) >= 2;
            }
        line(&report, "jumps horizontal %lld vertical %lld", horizontal, vertical);
        if (method < 4) {
            Selection selection = selections[method];
            line(&report, "window %d bounds %lld", selection.window, selection.bounds);
            I reasons[6] = {0};
            for (int i = 0; i < count; ++i) {
                I value = selection.reasons[i];
                int code = value == 255 ? 5 : (int)(value / 50);
                ++reasons[code];
            }
            line(&report,
                 "reasons textureless %lld nonunique %lld outside %lld mismatch %lld occluded %lld",
                 reasons[1], reasons[2], reasons[3], reasons[4], reasons[5]);
            line(&report, "lr 0 %lld 1 %lld 2 %lld 3+ %lld", selection.lr[0], selection.lr[1],
                 selection.lr[2], selection.lr[3]);
        } else if (method == 4)
            line(&report, "votes 0 %lld 1 %lld 2 %lld 3 %lld 4 %lld", votes[0], votes[1], votes[2],
                 votes[3], votes[4]);
        else {
            Post post = method == 5 ? wta : sgm;
            line(
                &report,
                "postprocess speckles %lld %lld median %lld background %lld interpolated %lld unfilled %lld",
                post.components, post.pixels, post.median_changes, post.background,
                post.interpolated, post.unfilled);
            for (int source = 0; source < 5; ++source) {
                int indices[3072];
                Pixels region = {indices, 0};
                for (int i = 0; i < regions.region[1].count; ++i) {
                    int index = regions.region[1].data[i];
                    if (post.source[index] == source)
                        region.data[region.count++] = index;
                }
                Evaluation result = evaluate(image, truth.pixels, region);
                line(&report, "source %s pixels %lld bad1 %s", sources[source], result.pixels,
                     ratio(result.bad1, result.pixels));
            }
        }
        for (int region = 0; region < 3; ++region) {
            Evaluation result = evaluate(image, truth.pixels, regions.region[region]);
            evaluations[method][region] = result;
            line(&report, "region %s pixels %lld valid %lld bad1 %s bad2 %s mae %s exact %lld",
                 region_names[region], result.pixels, result.valid,
                 ratio(result.bad1, result.pixels), ratio(result.bad2, result.pixels),
                 result.valid ? two_decimals(result.error_sum, result.valid) : "-", result.exact);
        }
        I depth_count = 0, depth_sum = 0, depth_maximum = 0;
        for (int i = 0; i < regions.region[0].count; ++i) {
            int index = regions.region[0].data[i];
            if (image[index]) {
                I difference = llabs(depth_hundredths(image[index], p->focal, p->baseline) -
                                     depth_hundredths(truth.pixels[index], p->focal, p->baseline));
                ++depth_count;
                depth_sum += difference;
                if (difference > depth_maximum)
                    depth_maximum = difference;
            }
        }
        if (depth_count)
            line(&report, "depth_error pixels %lld mean %s max %s", depth_count,
                 two_decimals(depth_sum, 100 * depth_count), two_decimals(depth_maximum, 100));
        else
            line(&report, "depth_error pixels 0 mean - max -");
        I errors[6] = {0};
        for (int i = 0; i < regions.region[1].count; ++i) {
            int index = regions.region[1].data[i];
            if (!image[index])
                ++errors[5];
            else {
                I difference = llabs(image[index] - truth.pixels[index]);
                ++errors[difference < 4 ? difference : 4];
            }
        }
        line(&report, "errors 0 %lld 1 %lld 2 %lld 3 %lld 4+ %lld invalid %lld", errors[0],
             errors[1], errors[2], errors[3], errors[4], errors[5]);
    }
    for (int region = 0; region < 3; ++region) {
        int order[7] = {0, 1, 2, 3, 4, 5, 6};
        for (int i = 0; i < 7; ++i)
            ranking_values[i] = evaluations[i][region];
        qsort(order, 7, sizeof(int), ranking_order);
        char *row = format("ranking %s", region_names[region]);
        for (int i = 0; i < 7; ++i)
            row = joined(row, format(" %s", names[order[i]]));
        line(&report, "%s", row);
    }
    for (int method = 0; method < 4; ++method) {
        I tp = 0, fp = 0, fn = 0;
        for (int i = 0; i < regions.occluded.count; ++i) {
            int index = regions.occluded.data[i];
            bool detected = selections[method].reasons[index] == 150 ||
                            selections[method].reasons[index] == 255;
            tp += detected;
            fn += !detected;
        }
        for (int i = 0; i < regions.region[0].count; ++i) {
            int index = regions.region[0].data[i];
            fp += selections[method].reasons[index] == 150 ||
                  selections[method].reasons[index] == 255;
        }
        line(&report, "occlusion %s tp %lld fp %lld fn %lld precision %s recall %s", names[method],
             tp, fp, fn, ratio(tp, tp + fp), ratio(tp, tp + fn));
    }
    for (int method = 0; method < 4; ++method) {
        int order[3072], n = 0;
        for (int i = 0; i < regions.region[0].count; ++i) {
            int index = regions.region[0].data[i];
            if (images[method][index])
                order[n++] = index;
        }
        confidence_margins = selections[method].margins;
        qsort(order, (size_t)n, sizeof(int), confidence_order);
        for (int percent = 25; percent <= 100; percent += 25) {
            int size = (n * percent + 99) / 100;
            I bad = 0;
            for (int i = 0; i < size; ++i)
                bad += llabs(images[method][order[i]] - truth.pixels[order[i]]) > 1;
            line(&report, "confidence %s %d pixels %d margin %s bad1 %s", names[method], percent,
                 size, size ? format("%lld", selections[method].margins[order[size - 1]]) : "-",
                 ratio(bad, size));
        }
    }
    I layers[32] = {0};
    for (int i = 0; i < count; ++i)
        if (truth.pixels[i])
            ++layers[truth.pixels[i]];
    for (int g = 1; g <= 31; ++g)
        if (layers[g]) {
            int indices[3072];
            Pixels region = {indices, 0};
            for (int i = 0; i < regions.region[0].count; ++i) {
                int index = regions.region[0].data[i];
                if (truth.pixels[index] == g)
                    region.data[region.count++] = index;
            }
            char *row = format("layer %d pixels %lld nonocc %d bad1", g, layers[g], region.count);
            for (int method = 0; method < 7; ++method)
                row = joined(row,
                             format(" %lld", evaluate(images[method], truth.pixels, region).bad1));
            line(&report, "%s", row);
        }
    for (int disparity = p->minimum; disparity <= p->maximum; ++disparity) {
        int n = 0;
        for (int i = 0; i < count; ++i)
            n += images[6][i] == disparity;
        line(&report, "histogram %d %d", disparity, n);
    }
    Lines depth = {0};
    line(&depth, "x,y,sad,ssd,census,sgm,disparity,source,subpixel,depth,truth,truth_depth");
    for (int i = 0; i < p->sample_count; ++i) {
        Point sample = p->samples[i];
        int index = sample.y * width + sample.x;
        char *row = format("%d,%d", sample.x, sample.y);
        for (int method = 0; method < 4; ++method)
            row = joined(row, format(",%s", optional(images[method][index])));
        I disparity = images[6][index];
        if (disparity) {
            Refined refined =
                subpixel(disparity, cumulative[p->paths - 1].values + index * base.disparities, p);
            row = joined(row, format(",%lld,%s,%s,%s", disparity, sources[sgm.source[index]],
                                     refined.disparity, refined.depth));
        } else
            row = joined(row, ",-,none,-,-");
        I ground = truth.pixels[index];
        row = joined(
            row, ground ? format(",%lld,%s", ground, two_decimals(p->focal * p->baseline, ground))
                        : ",-,-");
        line(&depth, "%s", row);
    }
    mkdir("output", 0777);
    I *wta_pgm = allocate((size_t)count, sizeof(I)), *sgm_pgm = allocate((size_t)count, sizeof(I)),
      *error = allocate((size_t)count, sizeof(I));
    for (int i = 0; i < count; ++i) {
        wta_pgm[i] = 8 * images[5][i];
        sgm_pgm[i] = 8 * images[6][i];
        if (!truth.pixels[i])
            error[i] = 0;
        else if (!images[6][i])
            error[i] = 255;
        else {
            I difference = llabs(images[6][i] - truth.pixels[i]);
            error[i] = 50 + 50 * (difference < 3 ? difference : 3);
        }
    }
    write_pgm("disparity_wta.pgm", (PGM){width, height, wta_pgm});
    write_pgm("disparity_sgm.pgm", (PGM){width, height, sgm_pgm});
    write_pgm("occlusion.pgm", (PGM){width, height, selections[3].reasons});
    write_pgm("error_sgm.pgm", (PGM){width, height, error});
    save("depth.csv", depth);
    save("evaluation.txt", report);
    save("objects.txt", object_report(images[6], truth, p));
    return 0;
}
