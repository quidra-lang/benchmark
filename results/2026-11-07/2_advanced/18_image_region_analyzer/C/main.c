#include "image.h"

enum Feature {
    AREA, X0, Y0, X1, Y1, WIDTH, HEIGHT, CX, CY, MEAN, VARIANCE, MINIMUM, MAXIMUM,
    CONTRAST, BORDER, PERIMETER, CHAIN, STRAIGHT, DIAGONAL, TURNS, COMPACTNESS,
    RUNS, HOLES, HOLE_AREA, EULER, DEPTH, VAR_X, VAR_Y, COV_XY, HU1, ANISOTROPY,
    EXTENT, MIRROR_LR, MIRROR_TB, SOLIDITY, FERET2, WIDTH2, ELONGATION, BAYS,
    BAY_AREA, SKELETON, ENDPOINTS, BRANCHES, FEATURE_COUNT
};
static const char *feature_names[] = {
    "area", "x0", "y0", "x1", "y1", "width", "height", "cx", "cy", "mean", "variance", "min", "max",
    "contrast", "border", "perimeter", "chain", "straight", "diagonal", "turns", "compactness",
    "runs", "holes", "hole_area", "euler", "depth", "var_x", "var_y", "cov_xy", "hu1", "anisotropy",
    "extent", "mirror_lr", "mirror_tb", "solidity", "feret2", "width2", "elongation", "bays",
    "bay_area", "skeleton", "endpoints", "branches"
};
static const char *orientations[] = {"none", "horizontal", "vertical", "falling", "rising"};
static const char symbols[] = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz";
static const Point directions4[] = {{1,0},{0,-1},{-1,0},{0,1}};
static const Point directions8[] = {{1,0},{1,-1},{0,-1},{-1,-1},{-1,0},{-1,1},{0,1},{1,1}};
static const char *csv_header =
    "image,label,class,flags,area,x0,y0,x1,y1,cx,cy,mean,variance,min,max,contrast,border,"
    "perimeter,chain,straight,diagonal,turns,compactness,runs,holes,hole_area,euler,parent,"
    "depth,var_x,var_y,cov_xy,hu1,orientation,anisotropy,extent,mirror_lr,mirror_tb,hull_area,"
    "solidity,feret2,width2,elongation,bays,bay_area,skeleton,endpoints,branches,neighbor,distance2,codes";

typedef struct { char *name; Point offsets[49]; int count; } Element;
typedef struct { char *name, *threshold, *polarity, *operations[6]; int connectivity, count; } Setting;
typedef struct {
    int otsu_top, sweep, bay_min, element_count, setting_count;
    Rational isotropy;
    Element elements[10];
    Setting settings[8];
} Parameters;
typedef struct { int feature; char *comparison, *text; Rational value; } Condition;
typedef struct { char *name; Condition conditions[6]; int count; } Rule;
typedef struct {
    Condition filters[20]; Rule classes[20], flags[20];
    int filter_count, class_count, flag_count, name_count;
    char *class_names[21];
} Rules;
typedef struct { int owner, area, first, x0, y0, x1, y1; } Hole;
typedef struct {
    Rational features[FEATURE_COUNT];
    int *pixels, count, parent, depth, orientation, class_number, dropped_by, neighbor;
    Integer hull_doubled, distance;
    char *codes;
    bool kept, flags[20];
    Mask skeleton;
} Region;
typedef struct {
    Image *image; Setting *setting; Parameters *parameters;
    Histogram histogram; Otsu otsu;
    int isodata_cutoff, isodata_iterations, cutoff, morph_counts[6];
    Mask initial, final;
    Labeling labels;
    int four, eight, bitquad, *hole_of, hole_count;
    Hole *holes;
    Region *regions;
} Analysis;

static Parameters read_parameters(void) {
    Parameters parameters = {0};
    Lines source = read_lines("input/params.txt");
    for (int line = 0; line < source.count; ++line) {
        char *parts[32];
        int count = words(source.items[line], parts);
        if (!strcmp(parts[0], "otsu_top")) parameters.otsu_top = atoi(parts[1]);
        else if (!strcmp(parts[0], "sweep")) parameters.sweep = atoi(parts[1]);
        else if (!strcmp(parts[0], "isotropy")) parameters.isotropy = parse_rational(parts[1]);
        else if (!strcmp(parts[0], "bay_min")) parameters.bay_min = atoi(parts[1]);
        else if (!strcmp(parts[0], "element")) {
            Element *element = &parameters.elements[parameters.element_count++];
            element->name = parts[1];
            int width = atoi(parts[2]), height = atoi(parts[3]);
            int ox = atoi(parts[4]), oy = atoi(parts[5]);
            for (int y = 0; y < height; ++y) {
                for (int x = 0; x < width; ++x) if (parts[6 + y][x] == '#') element->offsets[element->count++] = (Point){x - ox, y - oy};
            }
        } else {
            Setting *setting = &parameters.settings[parameters.setting_count++];
            setting->name = parts[1];
            setting->connectivity = atoi(parts[2]);
            setting->threshold = parts[3];
            setting->polarity = parts[4];
            for (int i = 5; i < count; ++i) setting->operations[setting->count++] = parts[i];
        }
    }
    return parameters;
}

static Condition condition(char **parts) {
    Condition result = {-1, parts[1], parts[2], {0,1}};
    for (int i = 0; i < FEATURE_COUNT; ++i) if (!strcmp(feature_names[i], parts[0])) result.feature = i;
    if (result.feature >= 0) result.value = parse_rational(parts[2]);
    return result;
}

static Rules read_rules(void) {
    Rules rules = {0};
    Lines source = read_lines("input/rules.txt");
    for (int line = 0; line < source.count; ++line) {
        char *parts[32];
        int count = words(source.items[line], parts);
        if (!strcmp(parts[0], "filter")) rules.filters[rules.filter_count++] = condition(parts + 1);
        else {
            bool is_class = !strcmp(parts[0], "class");
            Rule *rule = is_class ? &rules.classes[rules.class_count++] : &rules.flags[rules.flag_count++];
            rule->name = parts[1];
            for (int i = 2; i < count; i += 3) rule->conditions[rule->count++] = condition(parts + i);
            if (is_class) {
                bool present = false;
                for (int i = 0; i < rules.name_count; ++i) if (!strcmp(rules.class_names[i], rule->name)) present = true;
                if (!present) rules.class_names[rules.name_count++] = rule->name;
            }
        }
    }
    rules.class_names[rules.name_count++] = "other";
    return rules;
}

static int foreground_count(Mask mask) {
    int count = 0;
    for (int i = 0; i < mask.width * mask.height; ++i) count += mask.pixels[i];
    return count;
}

static Mask binarize(const Image *image, const Setting *setting, int cutoff) {
    Mask mask = new_mask(image->width, image->height);
    bool bright = !strcmp(setting->polarity, "bright");
    for (int i = 0; i < image->width * image->height; ++i) mask.pixels[i] = bright ? image->pixels[i] > cutoff : image->pixels[i] <= cutoff;
    return mask;
}

static Labeling background_components(Mask mask, int connectivity, bool *edge) {
    Mask background = new_mask(mask.width, mask.height);
    for (int i = 0; i < mask.width * mask.height; ++i) background.pixels[i] = !mask.pixels[i];
    Labeling labels = label_components(background, connectivity);
    for (int y = 0; y < mask.height; ++y) {
        for (int x = 0; x < mask.width; ++x) {
            if (x == 0 || y == 0 || x == mask.width - 1 || y == mask.height - 1) edge[labels.pixels[y * mask.width + x]] = true;
        }
    }
    return labels;
}

static Mask fill_holes(Mask mask, int connectivity) {
    bool edge[3073] = {false};
    Labeling background = background_components(mask, connectivity, edge);
    Mask result = new_mask(mask.width, mask.height);
    for (int i = 0; i < mask.width * mask.height; ++i) result.pixels[i] = mask.pixels[i] || (background.pixels[i] && !edge[background.pixels[i]]);
    return result;
}

static Mask apply_operation(Mask mask, const char *operation, Parameters *parameters, int connectivity) {
    if (!strcmp(operation, "fill")) return fill_holes(mask, 12 - connectivity);
    const char *name = strchr(operation, ':') + 1;
    Element *element = NULL;
    for (int i = 0; i < parameters->element_count; ++i) if (!strcmp(parameters->elements[i].name, name)) element = &parameters->elements[i];
    if (!strncmp(operation, "erode:", 6)) return erode(mask, element->offsets, element->count);
    if (!strncmp(operation, "dilate:", 7)) return dilate(mask, element->offsets, element->count);
    if (!strncmp(operation, "open:", 5)) return opening(mask, element->offsets, element->count);
    return closing(mask, element->offsets, element->count);
}

static int label_at(const Analysis *analysis, int x, int y) {
    if (x < 0 || y < 0 || x >= analysis->image->width || y >= analysis->image->height) return -1;
    return analysis->labels.pixels[y * analysis->image->width + x];
}

static void find_regions(Analysis *analysis) {
    int width = analysis->image->width, height = analysis->image->height;
    analysis->labels = label_components(analysis->final, analysis->setting->connectivity);
    analysis->four = label_components(analysis->final, 4).count;
    analysis->eight = label_components(analysis->final, 8).count;
    analysis->bitquad = bit_quad_euler(analysis->final, analysis->setting->connectivity);
    analysis->regions = allocate((size_t)(analysis->labels.count + 1) * sizeof(*analysis->regions));
    for (int i = 0; i < width * height; ++i) if (analysis->labels.pixels[i]) ++analysis->regions[analysis->labels.pixels[i]].count;
    int positions[63] = {0};
    for (int r = 1; r <= analysis->labels.count; ++r) {
        Region *region = &analysis->regions[r];
        region->pixels = allocate((size_t)region->count * sizeof(int));
        region->dropped_by = -1;
        for (int feature = 0; feature < FEATURE_COUNT; ++feature) region->features[feature] = rational(0, 1);
    }
    for (int i = 0; i < width * height; ++i) {
        int label = analysis->labels.pixels[i];
        if (label) analysis->regions[label].pixels[positions[label]++] = i;
    }
    bool edge[3073] = {false};
    Labeling background = background_components(analysis->final, 12 - analysis->setting->connectivity, edge);
    int numbers[3073] = {0};
    analysis->hole_of = allocate((size_t)width * height * sizeof(int));
    analysis->holes = allocate((size_t)(background.count + 1) * sizeof(*analysis->holes));
    for (int i = 0; i < width * height; ++i) {
        int label = background.pixels[i];
        if (!label || edge[label]) continue;
        int x = i % width, y = i / width;
        if (!numbers[label]) {
            numbers[label] = ++analysis->hole_count;
            analysis->holes[analysis->hole_count] = (Hole){analysis->labels.pixels[i - width], 0, i, x, y, x, y};
        }
        int number = numbers[label];
        analysis->hole_of[i] = number;
        Hole *hole = &analysis->holes[number];
        ++hole->area;
        if (x < hole->x0) hole->x0 = x;
        if (x > hole->x1) hole->x1 = x;
        if (y < hole->y0) hole->y0 = y;
        if (y > hole->y1) hole->y1 = y;
    }
    for (int r = 1; r <= analysis->labels.count; ++r) {
        Region *region = &analysis->regions[r];
        int first = region->pixels[0];
        if (first >= width && analysis->hole_of[first - width]) {
            region->parent = analysis->holes[analysis->hole_of[first - width]].owner;
            region->depth = analysis->regions[region->parent].depth + 1;
        }
    }
}

static Integer cross(Point a, Point b, Point p) { return (Integer)(b.x - a.x) * (p.y - a.y) - (Integer)(b.y - a.y) * (p.x - a.x); }
static Integer squared_distance(Point a, Point b) { Integer dx = a.x - b.x, dy = a.y - b.y; return dx * dx + dy * dy; }
static int point_order(const void *first, const void *second) {
    const Point *a = first, *b = second;
    return a->x != b->x ? a->x - b->x : a->y - b->y;
}

static int convex_hull(const Region *region, int width, Point *hull) {
    int left[48], right[48];
    for (int y = 0; y < 48; ++y) { left[y] = 64; right[y] = -1; }
    for (int i = 0; i < region->count; ++i) {
        int x = region->pixels[i] % width, y = region->pixels[i] / width;
        if (x < left[y]) left[y] = x;
        if (x > right[y]) right[y] = x;
    }
    Point points[192];
    int count = 0;
    for (int y = 0; y < 48; ++y) if (right[y] >= 0) {
        points[count++] = (Point){left[y], y};
        points[count++] = (Point){left[y], y + 1};
        points[count++] = (Point){right[y] + 1, y};
        points[count++] = (Point){right[y] + 1, y + 1};
    }
    qsort(points, (size_t)count, sizeof(*points), point_order);
    int unique = 0;
    for (int i = 0; i < count; ++i) if (!unique || point_order(&points[i], &points[unique - 1])) points[unique++] = points[i];
    int length = 0;
    for (int i = 0; i < unique; ++i) {
        while (length >= 2 && cross(hull[length - 2], hull[length - 1], points[i]) <= 0) --length;
        hull[length++] = points[i];
    }
    int lower = length;
    for (int i = unique - 2; i >= 0; --i) {
        while (length > lower && cross(hull[length - 2], hull[length - 1], points[i]) <= 0) --length;
        hull[length++] = points[i];
    }
    return length - 1;
}

static bool contains_center(const Point *hull, int count, int x, int y) {
    Point center = {2 * x + 1, 2 * y + 1};
    for (int i = 0; i < count; ++i) {
        Point a = hull[i], b = hull[(i + 1) % count];
        a.x *= 2; a.y *= 2; b.x *= 2; b.y *= 2;
        if (cross(a, b, center) < 0) return false;
    }
    return true;
}

static void measure_boundary(Analysis *analysis, int number) {
    Region *region = &analysis->regions[number];
    int connectivity = analysis->setting->connectivity, complement = 12 - connectivity;
    const Point *neighbors = complement == 4 ? directions4 : directions8;
    const Point *directions = connectivity == 4 ? directions4 : directions8;
    int width = analysis->image->width, perimeter = 0, runs = 0;
    for (int i = 0; i < region->count; ++i) {
        int x = region->pixels[i] % width, y = region->pixels[i] / width;
        bool boundary = false;
        for (int j = 0; j < complement; ++j) if (label_at(analysis, x + neighbors[j].x, y + neighbors[j].y) != number) boundary = true;
        perimeter += boundary;
        runs += label_at(analysis, x - 1, y) != number;
    }
    Text codes = {0};
    Point start = {region->pixels[0] % width, region->pixels[0] / width}, current = start, first = start;
    int heading = connectivity - 1;
    while (true) {
        int search = connectivity == 4 ? (heading + 3) % 4 : (heading + (heading % 2 ? 6 : 7)) % 8;
        int direction = -1;
        for (int offset = 0; offset < connectivity; ++offset) {
            int candidate = (search + offset) % connectivity;
            if (label_at(analysis, current.x + directions[candidate].x, current.y + directions[candidate].y) == number) { direction = candidate; break; }
        }
        if (direction < 0) break;
        Point next = {current.x + directions[direction].x, current.y + directions[direction].y};
        if (codes.size && current.x == start.x && current.y == start.y && next.x == first.x && next.y == first.y) break;
        if (!codes.size) first = next;
        text_add(&codes, "%d", direction);
        current = next;
        heading = direction;
    }
    int straight = 0, turns = 0;
    for (size_t i = 0; i < codes.size; ++i) {
        if (connectivity == 4 || (codes.data[i] - '0') % 2 == 0) ++straight;
        if (codes.data[i] != codes.data[(i + codes.size - 1) % codes.size]) ++turns;
    }
    int diagonal = (int)codes.size - straight;
    Integer length = 5 * (Integer)straight + 7 * diagonal;
    region->codes = codes.size ? codes.data : "";
    region->features[PERIMETER] = rational(perimeter, 1);
    region->features[RUNS] = rational(runs, 1);
    region->features[CHAIN] = rational((Integer)codes.size, 1);
    region->features[STRAIGHT] = rational(straight, 1);
    region->features[DIAGONAL] = rational(diagonal, 1);
    region->features[TURNS] = rational(turns, 1);
    region->features[COMPACTNESS] = rational(length * length, 25 * (Integer)region->count);
}

static void measure_hull(Analysis *analysis, int number) {
    Region *region = &analysis->regions[number];
    Point hull[384];
    int count = convex_hull(region, analysis->image->width, hull);
    Integer doubled = 0, feret = 0;
    Rational width2 = {0,1};
    for (int i = 0; i < count; ++i) {
        Point a = hull[i], b = hull[(i + 1) % count];
        doubled += (Integer)a.x * b.y - (Integer)b.x * a.y;
        Integer reach = 0;
        for (int j = 0; j < count; ++j) {
            Integer distance = squared_distance(a, hull[j]);
            if (distance > feret) feret = distance;
            Integer value = llabs(cross(a, b, hull[j]));
            if (value > reach) reach = value;
        }
        Rational candidate = rational(reach * reach, squared_distance(a, b));
        if (!i || compare_rational(candidate, width2) < 0) width2 = candidate;
    }
    region->hull_doubled = llabs(doubled);
    region->features[SOLIDITY] = rational(2 * (Integer)region->count, region->hull_doubled);
    region->features[FERET2] = rational(feret, 1);
    region->features[WIDTH2] = width2;
    region->features[ELONGATION] = rational(feret * width2.denominator, width2.numerator);
    Mask concavity = new_mask(analysis->image->width, analysis->image->height);
    int area = 0;
    for (int y = (int)region->features[Y0].numerator; y <= region->features[Y1].numerator; ++y) {
        for (int x = (int)region->features[X0].numerator; x <= region->features[X1].numerator; ++x) {
            int index = y * concavity.width + x;
            if (!analysis->labels.pixels[index] && !analysis->hole_of[index] && contains_center(hull, count, x, y)) { concavity.pixels[index] = true; ++area; }
        }
    }
    Labeling bays = label_components(concavity, 12 - analysis->setting->connectivity);
    int sizes[3073] = {0}, count_large = 0;
    for (int i = 0; i < concavity.width * concavity.height; ++i) ++sizes[bays.pixels[i]];
    for (int i = 1; i <= bays.count; ++i) if (sizes[i] >= analysis->parameters->bay_min) ++count_large;
    region->features[BAYS] = rational(count_large, 1);
    region->features[BAY_AREA] = rational(area, 1);
}

static void measure(Analysis *analysis, int number) {
    Region *region = &analysis->regions[number];
    Rational *features = region->features;
    Image *image = analysis->image;
    Integer area = region->count, sum_x = 0, sum_y = 0, sum_x2 = 0, sum_y2 = 0, sum_xy = 0, sum_i = 0, sum_i2 = 0;
    int x0 = image->width, y0 = image->height, x1 = 0, y1 = 0, minimum = image->maxval, maximum = 0;
    bool surrounding[3072] = {false};
    Mask region_mask = new_mask(image->width, image->height);
    for (int i = 0; i < region->count; ++i) {
        int index = region->pixels[i], x = index % image->width, y = index / image->width, value = image->pixels[index];
        region_mask.pixels[index] = true;
        if (x < x0) x0 = x;
        if (x > x1) x1 = x;
        if (y < y0) y0 = y;
        if (y > y1) y1 = y;
        if (value < minimum) minimum = value;
        if (value > maximum) maximum = value;
        sum_x += x; sum_y += y; sum_x2 += x * x; sum_y2 += y * y; sum_xy += x * y;
        sum_i += value; sum_i2 += value * value;
        for (int j = 0; j < 8; ++j) {
            int nx = x + directions8[j].x, ny = y + directions8[j].y;
            if (label_at(analysis, nx, ny) == 0) surrounding[ny * image->width + nx] = true;
        }
    }
    int surrounding_count = 0;
    Integer surrounding_sum = 0;
    for (int i = 0; i < image->width * image->height; ++i) if (surrounding[i]) { ++surrounding_count; surrounding_sum += image->pixels[i]; }
    features[AREA] = rational(area, 1);
    features[X0] = rational(x0, 1); features[Y0] = rational(y0, 1); features[X1] = rational(x1, 1); features[Y1] = rational(y1, 1);
    features[WIDTH] = rational(x1 - x0 + 1, 1); features[HEIGHT] = rational(y1 - y0 + 1, 1);
    features[BORDER] = rational(x0 == 0 || y0 == 0 || x1 == image->width - 1 || y1 == image->height - 1, 1);
    features[MEAN] = rational(sum_i, area);
    features[VARIANCE] = rational(area * sum_i2 - sum_i * sum_i, area * area);
    features[MINIMUM] = rational(minimum, 1); features[MAXIMUM] = rational(maximum, 1);
    if (surrounding_count) features[CONTRAST] = rational(sum_i * surrounding_count - surrounding_sum * area, area * surrounding_count);
    features[CX] = rational(sum_x, area); features[CY] = rational(sum_y, area);
    Integer m20 = area * sum_x2 - sum_x * sum_x, m02 = area * sum_y2 - sum_y * sum_y, m11 = area * sum_xy - sum_x * sum_y;
    features[VAR_X] = rational(m20, area * area); features[VAR_Y] = rational(m02, area * area); features[COV_XY] = rational(m11, area * area);
    features[HU1] = rational(m20 + m02, area * area * area);
    if (m20 + m02) features[ANISOTROPY] = rational(llabs(m20 - m02) + 2 * llabs(m11), m20 + m02);
    if (compare_rational(features[ANISOTROPY], analysis->parameters->isotropy) > 0) {
        Integer u = m20 - m02, v = 2 * m11;
        region->orientation = llabs(v) >= llabs(u) ? (v > 0 ? 3 : 4) : (u > 0 ? 1 : 2);
    }
    features[EXTENT] = rational(area, (x1 - x0 + 1) * (y1 - y0 + 1));
    int mirror_lr = 0, mirror_tb = 0, holes = 0, hole_area = 0;
    for (int i = 0; i < region->count; ++i) {
        int x = region->pixels[i] % image->width, y = region->pixels[i] / image->width;
        mirror_lr += label_at(analysis, x0 + x1 - x, y) == number;
        mirror_tb += label_at(analysis, x, y0 + y1 - y) == number;
    }
    features[MIRROR_LR] = rational(mirror_lr, area); features[MIRROR_TB] = rational(mirror_tb, area);
    for (int i = 1; i <= analysis->hole_count; ++i) if (analysis->holes[i].owner == number) { ++holes; hole_area += analysis->holes[i].area; }
    features[HOLES] = rational(holes, 1); features[HOLE_AREA] = rational(hole_area, 1); features[EULER] = rational(1 - holes, 1); features[DEPTH] = rational(region->depth, 1);
    measure_boundary(analysis, number);
    measure_hull(analysis, number);
    region->skeleton = thin(region_mask);
    int endpoints = 0, branches = 0;
    for (int i = 0; i < region->count; ++i) {
        int index = region->pixels[i];
        if (!region->skeleton.pixels[index]) continue;
        int crossing = crossing_number(region->skeleton, index % image->width, index / image->width);
        endpoints += crossing == 1;
        branches += crossing >= 3;
    }
    features[SKELETON] = rational(foreground_count(region->skeleton), 1);
    features[ENDPOINTS] = rational(endpoints, 1); features[BRANCHES] = rational(branches, 1);
}

static bool holds(Condition condition, const Region *region) {
    int comparison = condition.feature < 0 ? strcmp(orientations[region->orientation], condition.text) : compare_rational(region->features[condition.feature], condition.value);
    if (!strcmp(condition.comparison, "<")) return comparison < 0;
    if (!strcmp(condition.comparison, "<=")) return comparison <= 0;
    if (!strcmp(condition.comparison, ">")) return comparison > 0;
    if (!strcmp(condition.comparison, ">=")) return comparison >= 0;
    if (!strcmp(condition.comparison, "=")) return comparison == 0;
    return comparison != 0;
}

static bool matches(const Rule *rule, const Region *region) {
    for (int i = 0; i < rule->count; ++i) if (!holds(rule->conditions[i], region)) return false;
    return true;
}

static void apply_rules(Analysis *analysis, const Rules *rules) {
    for (int r = 1; r <= analysis->labels.count; ++r) {
        Region *region = &analysis->regions[r];
        for (int i = 0; i < rules->filter_count; ++i) if (!holds(rules->filters[i], region)) { region->dropped_by = i; break; }
        if (region->dropped_by >= 0) continue;
        region->kept = true;
        const char *class_name = "other";
        for (int i = 0; i < rules->class_count; ++i) if (matches(&rules->classes[i], region)) { class_name = rules->classes[i].name; break; }
        for (int i = 0; i < rules->name_count; ++i) if (!strcmp(class_name, rules->class_names[i])) region->class_number = i;
        for (int i = 0; i < rules->flag_count; ++i) region->flags[i] = matches(&rules->flags[i], region);
    }
    for (int r = 1; r <= analysis->labels.count; ++r) {
        Region *region = &analysis->regions[r];
        if (!region->kept) continue;
        for (int s = 1; s <= analysis->labels.count; ++s) {
            Region *other = &analysis->regions[s];
            if (r == s || !other->kept) continue;
            Integer dx = region->features[X0].numerator + region->features[X1].numerator - other->features[X0].numerator - other->features[X1].numerator;
            Integer dy = region->features[Y0].numerator + region->features[Y1].numerator - other->features[Y0].numerator - other->features[Y1].numerator;
            Integer distance = dx * dx + dy * dy;
            if (!region->neighbor || distance < region->distance) { region->neighbor = s; region->distance = distance; }
        }
    }
}

static const char *method(const Setting *setting) {
    return !strcmp(setting->threshold, "otsu") || !strcmp(setting->threshold, "isodata") ? setting->threshold : "fixed";
}

static Analysis analyze(Image *image, Setting *setting, Parameters *parameters, const Rules *rules) {
    Analysis result = {0};
    result.image = image;
    result.setting = setting;
    result.parameters = parameters;
    result.histogram = histogram(image);
    result.otsu = otsu(&result.histogram);
    result.isodata_cutoff = isodata(&result.histogram, &result.isodata_iterations);
    result.cutoff = !strcmp(setting->threshold, "otsu") ? result.otsu.cutoff : !strcmp(setting->threshold, "isodata") ? result.isodata_cutoff : atoi(setting->threshold);
    result.initial = binarize(image, setting, result.cutoff);
    result.final = result.initial;
    for (int i = 0; i < setting->count; ++i) {
        result.final = apply_operation(result.final, setting->operations[i], parameters, setting->connectivity);
        result.morph_counts[i] = foreground_count(result.final);
    }
    find_regions(&result);
    for (int r = 1; r <= result.labels.count; ++r) measure(&result, r);
    apply_rules(&result, rules);
    return result;
}

static char *mean_text(Integer sum, Integer count) { return count ? decimal(rational(sum, count), 2) : "-"; }
static char *integer_feature(const Region *region, int feature) { return format("%lld", region->features[feature].numerator); }
static char *decimal_feature(const Region *region, int feature, int places) { return decimal(region->features[feature], places); }

static void threshold_lines(const Analysis *analysis, Lines *lines) {
    const Image *image = analysis->image;
    const Histogram *hist = &analysis->histogram;
    add_line(lines, "image %s size %d %d maxval %d", image->name, image->width, image->height, image->maxval);
    add_line(lines, "histogram pixels %d min %d max %d mean %s median %d mode %d levels %d", hist->pixels, hist->minimum, hist->maximum, mean_text(hist->total, hist->pixels), hist->median, hist->mode, hist->levels);
    Text bins = {0};
    text_add(&bins, "bins %d", hist->bin_width);
    for (int i = 0; i < hist->bin_count; ++i) text_add(&bins, " %d", hist->bins[i]);
    add_line(lines, "%s", bins.data);
    add_line(lines, "otsu threshold %d upper %d candidates %d", analysis->otsu.cutoff, analysis->otsu.upper, analysis->otsu.count);
    for (int i = 0; i < analysis->otsu.count && i < analysis->parameters->otsu_top; ++i) {
        Candidate candidate = analysis->otsu.candidates[i];
        Rational gap = rational(candidate.sum_above * candidate.below - candidate.sum_below * candidate.above, (Integer)candidate.below * candidate.above);
        add_line(lines, "rank %d t %d below %d above %d mean_below %s mean_above %s gap %s", i + 1, candidate.cutoff, candidate.below, candidate.above, mean_text(candidate.sum_below, candidate.below), mean_text(candidate.sum_above, candidate.above), decimal(gap, 2));
    }
    add_line(lines, "isodata threshold %d iterations %d", analysis->isodata_cutoff, analysis->isodata_iterations);
    add_line(lines, "threshold %d %s %s foreground %d", analysis->cutoff, method(analysis->setting), analysis->setting->polarity, foreground_count(analysis->initial));
    for (int i = 0; i < analysis->setting->count; ++i) add_line(lines, "morph %s foreground %d", analysis->setting->operations[i], analysis->morph_counts[i]);
    for (int cutoff = analysis->parameters->sweep; cutoff < image->maxval; cutoff += analysis->parameters->sweep) {
        Mask mask = binarize(image, analysis->setting, cutoff);
        add_line(lines, "sweep %d foreground %d regions %d", cutoff, foreground_count(mask), label_components(mask, analysis->setting->connectivity).count);
    }
}

static void map_lines(const Analysis *analysis, Lines *lines) {
    const Image *image = analysis->image;
    const char *headings[] = {"morphology", "labels", "skeleton"};
    for (int kind = 0; kind < 3; ++kind) {
        add_line(lines, "%s %s %d %d", headings[kind], image->name, image->width, image->height);
        for (int y = 0; y < image->height; ++y) {
            char row[65];
            for (int x = 0; x < image->width; ++x) {
                int index = y * image->width + x, label = analysis->labels.pixels[index];
                if (!kind) {
                    bool initial = analysis->initial.pixels[index], final = analysis->final.pixels[index];
                    row[x] = final ? (initial ? '#' : '+') : (initial ? '-' : '.');
                } else if (!label) row[x] = analysis->hole_of[index] ? ':' : '.';
                else {
                    const Region *region = &analysis->regions[label];
                    row[x] = kind == 2 && !region->skeleton.pixels[index] ? '+' : region->kept ? symbols[label % 62] : '#';
                }
            }
            row[image->width] = '\0';
            add_line(lines, "%s", row);
        }
    }
}

static void csv_lines(const Analysis *analysis, const Rules *rules, Lines *lines) {
    for (int number = 1; number <= analysis->labels.count; ++number) {
        const Region *region = &analysis->regions[number];
        if (!region->kept) continue;
        Text flags = {0};
        for (int i = 0; i < rules->flag_count; ++i) if (region->flags[i]) text_add(&flags, "%s%s", flags.size ? "+" : "", rules->flags[i].name);
        char *fields[] = {
            analysis->image->name, format("%d", number), rules->class_names[region->class_number], flags.size ? flags.data : "-",
            integer_feature(region, AREA), integer_feature(region, X0), integer_feature(region, Y0), integer_feature(region, X1), integer_feature(region, Y1),
            decimal_feature(region, CX, 3), decimal_feature(region, CY, 3), decimal_feature(region, MEAN, 2), decimal_feature(region, VARIANCE, 2),
            integer_feature(region, MINIMUM), integer_feature(region, MAXIMUM), decimal_feature(region, CONTRAST, 2), integer_feature(region, BORDER),
            integer_feature(region, PERIMETER), integer_feature(region, CHAIN), integer_feature(region, STRAIGHT), integer_feature(region, DIAGONAL), integer_feature(region, TURNS),
            decimal_feature(region, COMPACTNESS, 3), integer_feature(region, RUNS), integer_feature(region, HOLES), integer_feature(region, HOLE_AREA), integer_feature(region, EULER),
            region->parent ? format("%d", region->parent) : "-", integer_feature(region, DEPTH),
            decimal_feature(region, VAR_X, 3), decimal_feature(region, VAR_Y, 3), decimal_feature(region, COV_XY, 3), decimal_feature(region, HU1, 4),
            (char *)orientations[region->orientation], decimal_feature(region, ANISOTROPY, 3), decimal_feature(region, EXTENT, 3),
            decimal_feature(region, MIRROR_LR, 3), decimal_feature(region, MIRROR_TB, 3), hull_area_text(region->hull_doubled), decimal_feature(region, SOLIDITY, 3),
            integer_feature(region, FERET2), decimal_feature(region, WIDTH2, 3), decimal_feature(region, ELONGATION, 3), integer_feature(region, BAYS), integer_feature(region, BAY_AREA),
            integer_feature(region, SKELETON), integer_feature(region, ENDPOINTS), integer_feature(region, BRANCHES),
            region->neighbor ? format("%d", region->neighbor) : "-", region->neighbor ? decimal(rational(region->distance, 4), 2) : "-", region->codes[0] ? region->codes : "-"
        };
        Text row = {0};
        for (size_t i = 0; i < sizeof(fields) / sizeof(*fields); ++i) text_add(&row, "%s%s", i ? "," : "", fields[i]);
        add_line(lines, "%s", row.data);
    }
}

static void tree_text(const Analysis *analysis, int number, Text *text) {
    text_add(text, "%d", number);
    bool first = true;
    for (int child = number + 1; child <= analysis->labels.count; ++child) {
        if (analysis->regions[child].parent != number) continue;
        text_add(text, "%s", first ? "(" : " ");
        tree_text(analysis, child, text);
        first = false;
    }
    if (!first) text_add(text, ")");
}

static void orientation_line(const int *counts, Lines *lines) {
    Text text = {0};
    text_add(&text, "orientations");
    for (int i = 0; i < 5; ++i) text_add(&text, " %s %d", orientations[i], counts[i]);
    add_line(lines, "%s", text.data);
}

static void summary_lines(const Analysis *analysis, const Rules *rules, Lines *lines) {
    int region_count = analysis->labels.count, kept = 0, hole_pixels = 0, depth = 0, largest = 0, smallest = 0;
    int classes[21] = {0}, flags[20] = {0}, orientation_counts[5] = {0};
    Integer area = 0, foreground_sum = 0, background_sum = 0;
    int foreground = foreground_count(analysis->final), size = analysis->image->width * analysis->image->height;
    for (int i = 0; i < size; ++i) {
        if (analysis->final.pixels[i]) foreground_sum += analysis->image->pixels[i];
        else background_sum += analysis->image->pixels[i];
    }
    for (int r = 1; r <= region_count; ++r) {
        const Region *region = &analysis->regions[r];
        if (region->depth > depth) depth = region->depth;
        if (!region->kept) continue;
        ++kept;
        area += region->count;
        ++classes[region->class_number];
        ++orientation_counts[region->orientation];
        for (int i = 0; i < rules->flag_count; ++i) flags[i] += region->flags[i];
        if (!largest || region->count > analysis->regions[largest].count) largest = r;
        if (!smallest || region->count < analysis->regions[smallest].count) smallest = r;
    }
    for (int i = 1; i <= analysis->hole_count; ++i) hole_pixels += analysis->holes[i].area;
    add_line(lines, "image %s", analysis->image->name);
    add_line(lines, "threshold %d %s %s conn %d", analysis->cutoff, method(analysis->setting), analysis->setting->polarity, analysis->setting->connectivity);
    add_line(lines, "foreground %d %d", foreground_count(analysis->initial), foreground);
    add_line(lines, "regions %d provisional %d kept %d dropped %d", region_count, analysis->labels.provisional, kept, region_count - kept);
    add_line(lines, "connectivity four %d eight %d", analysis->four, analysis->eight);
    add_line(lines, "holes %d hole_pixels %d euler %d bitquad %d", analysis->hole_count, hole_pixels, region_count - analysis->hole_count, analysis->bitquad);
    for (int i = 1; i <= analysis->hole_count; ++i) {
        Hole hole = analysis->holes[i];
        add_line(lines, "hole %d owner %d area %d box %d %d %d %d", i, hole.owner, hole.area, hole.x0, hole.y0, hole.x1, hole.y1);
    }
    add_line(lines, "depth_max %d", depth);
    Text tree = {0};
    text_add(&tree, "tree");
    for (int r = 1; r <= region_count; ++r) if (!analysis->regions[r].parent) { text_add(&tree, " "); tree_text(analysis, r, &tree); }
    add_line(lines, "%s", tree.data);
    add_line(lines, "intensity foreground %s background %s", mean_text(foreground_sum, foreground), mean_text(background_sum, size - foreground));
    if (kept) add_line(lines, "area total %lld mean %s largest %d %d smallest %d %d", area, mean_text(area, kept), largest, analysis->regions[largest].count, smallest, analysis->regions[smallest].count);
    else add_line(lines, "area total 0 mean - largest - smallest -");
    Text class_line = {0};
    text_add(&class_line, "classes");
    for (int i = 0; i < rules->name_count; ++i) text_add(&class_line, " %s %d", rules->class_names[i], classes[i]);
    add_line(lines, "%s", class_line.data);
    orientation_line(orientation_counts, lines);
    Text flag_line = {0};
    text_add(&flag_line, "flags");
    for (int i = 0; i < rules->flag_count; ++i) text_add(&flag_line, " %s %d", rules->flags[i].name, flags[i]);
    add_line(lines, "%s", flag_line.data);
}

static void overall_lines(const Analysis *analyses, int count, const Rules *rules, Lines *lines) {
    int regions = 0, kept = 0, holes = 0, filters[20] = {0}, classes[21] = {0}, flags[20] = {0}, orientation_counts[5] = {0};
    Integer areas[21] = {0};
    int largest_image = -1, largest_region = 0, largest_area = -1;
    for (int i = 0; i < count; ++i) {
        const Analysis *analysis = &analyses[i];
        regions += analysis->labels.count;
        holes += analysis->hole_count;
        for (int r = 1; r <= analysis->labels.count; ++r) {
            const Region *region = &analysis->regions[r];
            if (!region->kept) { ++filters[region->dropped_by]; continue; }
            ++kept;
            ++classes[region->class_number];
            areas[region->class_number] += region->count;
            ++orientation_counts[region->orientation];
            for (int j = 0; j < rules->flag_count; ++j) flags[j] += region->flags[j];
            if (region->count > largest_area) { largest_image = i; largest_region = r; largest_area = region->count; }
        }
    }
    add_line(lines, "overall");
    add_line(lines, "images %d", count);
    add_line(lines, "regions %d kept %d dropped %d", regions, kept, regions - kept);
    add_line(lines, "holes %d euler %d", holes, regions - holes);
    for (int i = 0; i < rules->filter_count; ++i) {
        Condition filter = rules->filters[i];
        add_line(lines, "filter %d %s %s %s dropped %d", i + 1, filter.feature < 0 ? "orientation" : feature_names[filter.feature], filter.comparison, filter.text, filters[i]);
    }
    for (int i = 0; i < rules->name_count; ++i) add_line(lines, "class %s count %d area %lld mean %s", rules->class_names[i], classes[i], areas[i], mean_text(areas[i], classes[i]));
    for (int i = 0; i < rules->flag_count; ++i) add_line(lines, "flag %s count %d", rules->flags[i].name, flags[i]);
    orientation_line(orientation_counts, lines);
    if (largest_image >= 0) add_line(lines, "largest %s %d %d", analyses[largest_image].image->name, largest_region, largest_area);
    else add_line(lines, "largest -");
}

int main(void) {
    Parameters parameters = read_parameters();
    Rules rules = read_rules();
    int count;
    Image *images = read_images(&count);
    Analysis *analyses = allocate((size_t)count * sizeof(*analyses));
    Lines thresholds = {0}, labels = {0}, regions = {0}, summary = {0};
    add_line(&regions, "%s", csv_header);
    for (int i = 0; i < count; ++i) {
        Setting *setting = NULL;
        for (int j = 0; j < parameters.setting_count; ++j) if (!strcmp(parameters.settings[j].name, images[i].name)) setting = &parameters.settings[j];
        analyses[i] = analyze(&images[i], setting, &parameters, &rules);
        threshold_lines(&analyses[i], &thresholds);
        map_lines(&analyses[i], &labels);
        csv_lines(&analyses[i], &rules, &regions);
        summary_lines(&analyses[i], &rules, &summary);
    }
    overall_lines(analyses, count, &rules, &summary);
    write_lines("thresholds.txt", thresholds);
    write_lines("labels.txt", labels);
    write_lines("regions.csv", regions);
    write_lines("summary.txt", summary);
    return 0;
}
