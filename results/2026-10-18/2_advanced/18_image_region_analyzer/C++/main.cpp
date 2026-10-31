#include "regions.hpp"
#include <filesystem>

static const std::string symbols = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz";
static const Lines orientations{"none", "horizontal", "vertical", "falling", "rising"};
static const std::string csvHeader = "image,label,class,flags,area,x0,y0,x1,y1,cx,cy,mean,variance,min,max,contrast,border,perimeter,chain,straight,diagonal,turns,compactness,runs,holes,hole_area,euler,parent,depth,var_x,var_y,cov_xy,hu1,orientation,anisotropy,extent,mirror_lr,mirror_tb,hull_area,solidity,feret2,width2,elongation,bays,bay_area,skeleton,endpoints,branches,neighbor,distance2,codes";
static const Pixels directions4{{1, 0}, {0, -1}, {-1, 0}, {0, 1}};
static const Pixels directions8{{1, 0}, {1, -1}, {0, -1}, {-1, -1}, {-1, 0}, {-1, 1}, {0, 1}, {1, 1}};
static const Pixels& directions(int connectivity) { return connectivity == 4 ? directions4 : directions8; }
static void extend(Lines& first, const Lines& second) { first.insert(first.end(), second.begin(), second.end()); }
static Rational parseRational(const std::string& value) { std::size_t slash = value.find('/'); return slash == std::string::npos ? Rational(std::stoll(value)) : Rational(std::stoll(value.substr(0, slash)), std::stoll(value.substr(slash + 1))); }
static std::string meanText(Integer sum, Integer count) { return count ? decimal(Rational(sum, count), 2) : "-"; }
struct Setting { std::string name; int connectivity; std::string threshold, polarity; Lines operations; std::string method() const { return threshold == "otsu" || threshold == "isodata" ? threshold : "fixed"; } };
struct Parameters { int otsuTop = 0, sweep = 0, bayMin = 0; Rational isotropy; std::map<std::string, Pixels> elements; std::map<std::string, Setting> settings; };
static Parameters readParameters() {
    Parameters p;
    for (const std::string& line : readLines("input/params.txt")) {
        Lines fields = words(line);
        if (fields[0] == "otsu_top") p.otsuTop = std::stoi(fields[1]);
        else if (fields[0] == "sweep") p.sweep = std::stoi(fields[1]);
        else if (fields[0] == "isotropy") p.isotropy = parseRational(fields[1]);
        else if (fields[0] == "bay_min") p.bayMin = std::stoi(fields[1]);
        else if (fields[0] == "element") {
            int ox = std::stoi(fields[4]), oy = std::stoi(fields[5]);
            Pixels offsets;
            for (std::size_t row = 6; row < fields.size(); ++row) for (std::size_t column = 0; column < fields[row].size(); ++column) if (fields[row][column] == '#') offsets.emplace_back(static_cast<int>(column) - ox, static_cast<int>(row - 6) - oy);
            p.elements.emplace(fields[1], std::move(offsets));
        } else p.settings.emplace(fields[1], Setting{fields[1], std::stoi(fields[2]), fields[3], fields[4], Lines(fields.begin() + 5, fields.end())});
    }
    return p;
}
struct Condition {
    std::string feature, comparison, spelling;
    Rational value;
    Condition(std::string feature, std::string comparison, std::string spelling) : feature(std::move(feature)), comparison(std::move(comparison)), spelling(std::move(spelling)), value(this->feature == "orientation" ? Rational(0) : parseRational(this->spelling)) {}
    bool holds(const std::map<std::string, Rational>& features, const std::string& orientation) const {
        int order = feature == "orientation" ? (orientation == spelling ? 0 : 1) : compare(features.at(feature), value);
        if (comparison == "<") return order < 0;
        if (comparison == "<=") return order <= 0;
        if (comparison == ">") return order > 0;
        if (comparison == ">=") return order >= 0;
        return comparison == "=" ? order == 0 : order != 0;
    }
};
struct Rule { std::string name; std::vector<Condition> conditions; };
struct Rules { std::vector<Condition> filters; std::vector<Rule> classes, flags; Lines classNames; };
static Rules readRules() {
    Rules rules;
    for (const std::string& line : readLines("input/rules.txt")) {
        Lines fields = words(line);
        if (fields[0] == "filter") rules.filters.emplace_back(fields[1], fields[2], fields[3]);
        else {
            Rule rule{fields[1], {}};
            for (std::size_t i = 2; i < fields.size(); i += 3) rule.conditions.emplace_back(fields[i], fields[i + 1], fields[i + 2]);
            if (fields[0] == "class") { if (std::find(rules.classNames.begin(), rules.classNames.end(), rule.name) == rules.classNames.end()) rules.classNames.push_back(rule.name); rules.classes.push_back(std::move(rule)); }
            else rules.flags.push_back(std::move(rule));
        }
    }
    rules.classNames.push_back("other");
    return rules;
}
static std::vector<Pixels> groupPixels(const Labeling& labels) {
    std::vector<Pixels> groups(labels.count + 1);
    for (int y = 0; y < labels.height; ++y) for (int x = 0; x < labels.width; ++x) groups[labels.labels[static_cast<std::size_t>(y * labels.width + x)]].emplace_back(x, y);
    return groups;
}
static std::vector<Pixels> enclosedComponents(const Mask& mask, int connectivity) {
    Mask background = mask;
    for (unsigned char& value : background.pixels) value = static_cast<unsigned char>(!value);
    Labeling labels = labelComponents(background, connectivity);
    std::vector<Pixels> groups = groupPixels(labels), enclosed;
    for (std::size_t i = 1; i < groups.size(); ++i) {
        bool border = false;
        for (const Pixel& pixel : groups[i]) if (!pixel.first || !pixel.second || pixel.first == mask.width - 1 || pixel.second == mask.height - 1) border = true;
        if (!border) enclosed.push_back(std::move(groups[i]));
    }
    return enclosed;
}
static Integer cross(Pixel a, Pixel b, Pixel point) { return static_cast<Integer>(b.first - a.first) * (point.second - a.second) - static_cast<Integer>(b.second - a.second) * (point.first - a.first); }
static Integer squaredDistance(Pixel a, Pixel b) { Integer dx = a.first - b.first, dy = a.second - b.second; return dx * dx + dy * dy; }
static Pixels halfHull(const Pixels& points) {
    Pixels chain;
    for (const Pixel& point : points) { while (chain.size() >= 2 && cross(chain[chain.size() - 2], chain.back(), point) <= 0) chain.pop_back(); chain.push_back(point); }
    return chain;
}
static Pixels convexHull(const Pixels& pixels) {
    PixelSet corners;
    for (const Pixel& point : pixels) { corners.insert(point); corners.emplace(point.first + 1, point.second); corners.emplace(point.first, point.second + 1); corners.emplace(point.first + 1, point.second + 1); }
    Pixels ordered(corners.begin(), corners.end()), first = halfHull(ordered);
    std::reverse(ordered.begin(), ordered.end());
    Pixels second = halfHull(ordered);
    first.pop_back(); second.pop_back(); first.insert(first.end(), second.begin(), second.end());
    return first;
}
static bool containsCenter(const Pixels& hull, Pixel point) {
    Pixel doubled{2 * point.first + 1, 2 * point.second + 1};
    for (std::size_t i = 0; i < hull.size(); ++i) { Pixel a = hull[i], b = hull[(i + 1) % hull.size()]; if (cross({2 * a.first, 2 * a.second}, {2 * b.first, 2 * b.second}, doubled) < 0) return false; }
    return true;
}
struct Hole { int number, owner; Pixels pixels; };
struct Region {
    int number, parent = 0, depth = 0, droppedBy = -1, neighbor = 0;
    Pixels pixels;
    std::map<std::string, Rational> features;
    std::vector<int> codes, children;
    PixelSet skeleton;
    Integer hullDoubled = 0, distance = 0;
    std::string orientation = "none", className = "other";
    Lines flags;
    bool kept = false;
    Integer integer(const std::string& name) const { return features.at(name).numerator; }
    bool matches(const Rule& rule) const { for (const Condition& condition : rule.conditions) if (!condition.holds(features, orientation)) return false; return true; }
};
class ImageAnalysis {
    const Parameters& parameters;
    const Rules& rules;
    int complement;
    Histogram histogram;
    Otsu otsuResult;
    std::pair<int, int> isodataResult;
    int cutoff;
    Mask initial, final;
    std::vector<int> morphCounts;
    std::vector<std::vector<int>> sweep;
    Labeling labels;
    std::vector<int> holeOf;
    int fourComponents, eightComponents, bitQuad;
    Mask binarize(int threshold) const {
        Mask result(image.width, image.height);
        for (std::size_t i = 0; i < image.pixels.size(); ++i) result.pixels[i] = static_cast<unsigned char>(setting.polarity == "bright" ? image.pixels[i] > threshold : image.pixels[i] <= threshold);
        return result;
    }
    int labelAt(int x, int y) const { return x >= 0 && y >= 0 && x < image.width && y < image.height ? labels.labels[static_cast<std::size_t>(y * image.width + x)] : -1; }
    std::vector<int> chainCode(const Region& region) const {
        const Pixels& offsets = directions(setting.connectivity);
        Pixel current = region.pixels.front(), first = current, second;
        int heading = static_cast<int>(offsets.size() - 1);
        std::vector<int> codes;
        while (true) {
            int start = setting.connectivity == 4 ? (heading + 3) % 4 : (heading + (heading % 2 ? 6 : 7)) % 8;
            int chosen = -1;
            for (int offset = 0; offset < static_cast<int>(offsets.size()); ++offset) { int direction = (start + offset) % static_cast<int>(offsets.size()); if (labelAt(current.first + offsets[direction].first, current.second + offsets[direction].second) == region.number) { chosen = direction; break; } }
            if (chosen < 0) return {};
            Pixel previous = current;
            current.first += offsets[chosen].first; current.second += offsets[chosen].second;
            codes.push_back(chosen); heading = chosen;
            if (codes.size() == 1) second = current;
            else if (current == second && previous == first) { codes.pop_back(); return codes; }
        }
    }
    void measure(Region& region) {
        std::map<std::string, Rational>& f = region.features;
        Integer area = static_cast<Integer>(region.pixels.size()), si = 0, sii = 0, sx = 0, sy = 0, sxx = 0, syy = 0, sxy = 0;
        int x0 = image.width, y0 = image.height, x1 = 0, y1 = 0, minimum = image.maxval, maximum = 0;
        PixelSet surrounding;
        Integer perimeter = 0, runs = 0;
        for (const Pixel& point : region.pixels) {
            int x = point.first, y = point.second, value = image.pixels[static_cast<std::size_t>(y * image.width + x)];
            x0 = std::min(x0, x); y0 = std::min(y0, y); x1 = std::max(x1, x); y1 = std::max(y1, y); minimum = std::min(minimum, value); maximum = std::max(maximum, value);
            si += value; sii += static_cast<Integer>(value) * value; sx += x; sy += y; sxx += x * x; syy += y * y; sxy += x * y;
            for (const Pixel& offset : directions8) if (labelAt(x + offset.first, y + offset.second) == 0) surrounding.emplace(x + offset.first, y + offset.second);
            bool boundary = false;
            for (const Pixel& offset : directions(complement)) if (labelAt(x + offset.first, y + offset.second) != region.number) boundary = true;
            perimeter += boundary; runs += labelAt(x - 1, y) != region.number;
        }
        f["area"] = area; f["x0"] = x0; f["y0"] = y0; f["x1"] = x1; f["y1"] = y1; f["width"] = x1 - x0 + 1; f["height"] = y1 - y0 + 1;
        f["border"] = !x0 || !y0 || x1 == image.width - 1 || y1 == image.height - 1;
        f["mean"] = Rational(si, area); f["variance"] = Rational(area * sii - si * si, area * area); f["min"] = minimum; f["max"] = maximum;
        Integer sumSurrounding = 0, countSurrounding = static_cast<Integer>(surrounding.size());
        for (const Pixel& point : surrounding) sumSurrounding += image.pixels[static_cast<std::size_t>(point.second * image.width + point.first)];
        f["contrast"] = countSurrounding ? Rational(si * countSurrounding - sumSurrounding * area, area * countSurrounding) : Rational(0);
        region.codes = chainCode(region);
        Integer straight = 0, diagonal = 0, turns = 0;
        for (std::size_t i = 0; i < region.codes.size(); ++i) { if (setting.connectivity == 4 || region.codes[i] % 2 == 0) ++straight; else ++diagonal; turns += region.codes[i] != region.codes[(i + region.codes.size() - 1) % region.codes.size()]; }
        Integer length = 5 * straight + 7 * diagonal;
        f["perimeter"] = perimeter; f["chain"] = static_cast<Integer>(region.codes.size()); f["straight"] = straight; f["diagonal"] = diagonal; f["turns"] = turns; f["compactness"] = Rational(length * length, 25 * area); f["runs"] = runs;
        Integer owned = 0, holeArea = 0;
        for (const Hole& hole : holes) if (hole.owner == region.number) { ++owned; holeArea += static_cast<Integer>(hole.pixels.size()); }
        f["holes"] = owned; f["hole_area"] = holeArea; f["euler"] = 1 - owned; f["depth"] = region.depth;
        Integer m20 = area * sxx - sx * sx, m02 = area * syy - sy * sy, m11 = area * sxy - sx * sy;
        f["cx"] = Rational(sx, area); f["cy"] = Rational(sy, area); f["var_x"] = Rational(m20, area * area); f["var_y"] = Rational(m02, area * area); f["cov_xy"] = Rational(m11, area * area); f["hu1"] = Rational(m20 + m02, area * area * area);
        f["anisotropy"] = m20 + m02 ? Rational(std::abs(m20 - m02) + 2 * std::abs(m11), m20 + m02) : Rational(0);
        if (compare(f.at("anisotropy"), parameters.isotropy) > 0) { Integer u = m20 - m02, v = 2 * m11; region.orientation = std::abs(v) >= std::abs(u) ? (v > 0 ? "falling" : "rising") : (u > 0 ? "horizontal" : "vertical"); }
        f["extent"] = Rational(area, (x1 - x0 + 1) * (y1 - y0 + 1));
        Integer lr = 0, tb = 0;
        for (const Pixel& point : region.pixels) { lr += labelAt(x0 + x1 - point.first, point.second) == region.number; tb += labelAt(point.first, y0 + y1 - point.second) == region.number; }
        f["mirror_lr"] = Rational(lr, area); f["mirror_tb"] = Rational(tb, area);
        Pixels hull = convexHull(region.pixels);
        Integer doubled = 0, feret = 0;
        Rational width;
        bool firstWidth = true;
        for (std::size_t i = 0; i < hull.size(); ++i) {
            Pixel a = hull[i], b = hull[(i + 1) % hull.size()];
            doubled += static_cast<Integer>(a.first) * b.second - static_cast<Integer>(b.first) * a.second;
            Integer reach = 0;
            for (const Pixel& point : hull) { reach = std::max(reach, std::abs(cross(a, b, point))); feret = std::max(feret, squaredDistance(a, point)); }
            Rational trial(reach * reach, squaredDistance(a, b));
            if (firstWidth || compare(trial, width) < 0) { width = trial; firstWidth = false; }
        }
        region.hullDoubled = std::abs(doubled);
        f["solidity"] = Rational(2 * area, region.hullDoubled); f["feret2"] = feret; f["width2"] = width; f["elongation"] = Rational(feret * width.denominator, width.numerator);
        Mask concavity(x1 - x0 + 1, y1 - y0 + 1);
        for (int y = y0; y <= y1; ++y) for (int x = x0; x <= x1; ++x) if (labelAt(x, y) == 0 && !holeOf[static_cast<std::size_t>(y * image.width + x)] && containsCenter(hull, {x, y})) concavity.set(x - x0, y - y0, true);
        Labeling bays = labelComponents(concavity, complement);
        std::vector<int> baySizes(bays.count + 1);
        for (int label : bays.labels) if (label) ++baySizes[label];
        Integer bayCount = 0;
        for (int label = 1; label <= bays.count; ++label) bayCount += baySizes[label] >= parameters.bayMin;
        f["bays"] = bayCount; f["bay_area"] = concavity.count();
        region.skeleton = thin(region.pixels);
        Integer endpoints = 0, branches = 0;
        for (const Pixel& point : region.skeleton) { int crossing = crossingNumber(region.skeleton, point); endpoints += crossing == 1; branches += crossing >= 3; }
        f["skeleton"] = static_cast<Integer>(region.skeleton.size()); f["endpoints"] = endpoints; f["branches"] = branches;
    }
    std::string treeText(int number) const {
        const Region& region = regions[number - 1];
        std::string value = text(number);
        if (!region.children.empty()) { Lines children; for (int child : region.children) children.push_back(treeText(child)); value += '(' + join(children) + ')'; }
        return value;
    }
    std::string intensityText(bool foreground) const { Integer sum = 0, count = 0; for (std::size_t i = 0; i < image.pixels.size(); ++i) if (static_cast<bool>(final.pixels[i]) == foreground) { sum += image.pixels[i]; ++count; } return meanText(sum, count); }
public:
    Image image;
    Setting setting;
    std::vector<Region> regions;
    std::vector<Hole> holes;
    ImageAnalysis(Image image, Setting setting, const Parameters& parameters, const Rules& rules) : parameters(parameters), rules(rules), complement(12 - setting.connectivity), histogram(image), otsuResult(otsu(histogram)), isodataResult(isodata(histogram)), cutoff(setting.threshold == "otsu" ? otsuResult.cutoff : setting.threshold == "isodata" ? isodataResult.first : std::stoi(setting.threshold)), initial(image.width, image.height), final(image.width, image.height), image(std::move(image)), setting(std::move(setting)) {
        initial = binarize(cutoff); final = initial;
        for (const std::string& operation : this->setting.operations) {
            if (operation == "fill") { for (const Pixels& pixels : enclosedComponents(final, complement)) for (const Pixel& point : pixels) final.set(point.first, point.second, true); }
            else {
                std::size_t colon = operation.find(':'); std::string kind = operation.substr(0, colon); const Pixels& offsets = parameters.elements.at(operation.substr(colon + 1));
                if (kind == "erode") final = erode(final, offsets); else if (kind == "dilate") final = dilate(final, offsets); else if (kind == "open") final = opening(final, offsets); else final = closing(final, offsets);
            }
            morphCounts.push_back(final.count());
        }
        for (int t = parameters.sweep; t < this->image.maxval; t += parameters.sweep) { Mask mask = binarize(t); sweep.push_back({t, mask.count(), labelComponents(mask, this->setting.connectivity).count}); }
        labels = labelComponents(final, this->setting.connectivity);
        std::vector<Pixels> groups = groupPixels(labels);
        for (int number = 1; number <= labels.count; ++number) { Region region; region.number = number; region.pixels = std::move(groups[number]); regions.push_back(std::move(region)); }
        fourComponents = labelComponents(final, 4).count; eightComponents = labelComponents(final, 8).count; bitQuad = bitQuadEuler(final, this->setting.connectivity);
        holeOf.resize(this->image.pixels.size());
        for (const Pixels& pixels : enclosedComponents(final, complement)) {
            int number = static_cast<int>(holes.size() + 1), owner = labelAt(pixels.front().first, pixels.front().second - 1);
            holes.push_back({number, owner, pixels}); for (const Pixel& point : pixels) holeOf[static_cast<std::size_t>(point.second * this->image.width + point.first)] = number;
        }
        for (Region& region : regions) {
            Pixel first = region.pixels.front();
            if (first.second > 0) { int hole = holeOf[static_cast<std::size_t>((first.second - 1) * this->image.width + first.first)]; if (hole) { region.parent = holes[hole - 1].owner; Region& parent = regions[region.parent - 1]; region.depth = parent.depth + 1; parent.children.push_back(region.number); } }
            measure(region);
            for (std::size_t i = 0; i < rules.filters.size(); ++i) if (!rules.filters[i].holds(region.features, region.orientation)) { region.droppedBy = static_cast<int>(i); break; }
            region.kept = region.droppedBy < 0;
            if (region.kept) { for (const Rule& rule : rules.classes) if (region.matches(rule)) { region.className = rule.name; break; } for (const Rule& rule : rules.flags) if (region.matches(rule)) region.flags.push_back(rule.name); }
        }
        for (Region& region : regions) if (region.kept) for (const Region& other : regions) if (other.kept && other.number != region.number) {
            Integer dx = region.integer("x0") + region.integer("x1") - other.integer("x0") - other.integer("x1"), dy = region.integer("y0") + region.integer("y1") - other.integer("y0") - other.integer("y1"), distance = dx * dx + dy * dy;
            if (!region.neighbor || distance < region.distance) { region.neighbor = other.number; region.distance = distance; }
        }
    }
    Lines thresholdLines() const {
        Lines lines{text("image ", image.name, " size ", image.width, ' ', image.height, " maxval ", image.maxval), text("histogram pixels ", histogram.pixels, " min ", histogram.minimum, " max ", histogram.maximum, " mean ", meanText(histogram.total, histogram.pixels), " median ", histogram.median, " mode ", histogram.mode, " levels ", histogram.levels), text("bins ", histogram.binWidth, ' ', join(histogram.bins)), text("otsu threshold ", otsuResult.cutoff, " upper ", otsuResult.upper, " candidates ", otsuResult.candidates.size())};
        for (std::size_t i = 0; i < otsuResult.candidates.size() && i < static_cast<std::size_t>(parameters.otsuTop); ++i) { const Candidate& c = otsuResult.candidates[i]; add(lines, "rank ", i + 1, " t ", c.cutoff, " below ", c.below, " above ", c.above, " mean_below ", meanText(c.sumBelow, c.below), " mean_above ", meanText(c.sumAbove, c.above), " gap ", decimal(Rational(c.sumAbove * c.below - c.sumBelow * c.above, c.below * c.above), 2)); }
        add(lines, "isodata threshold ", isodataResult.first, " iterations ", isodataResult.second); add(lines, "threshold ", cutoff, ' ', setting.method(), ' ', setting.polarity, " foreground ", initial.count());
        for (std::size_t i = 0; i < setting.operations.size(); ++i) add(lines, "morph ", setting.operations[i], " foreground ", morphCounts[i]);
        for (const std::vector<int>& row : sweep) add(lines, "sweep ", row[0], " foreground ", row[1], " regions ", row[2]);
        return lines;
    }
    Lines mapLines() const {
        Lines lines{text("morphology ", image.name, ' ', image.width, ' ', image.height)};
        for (int y = 0; y < image.height; ++y) { std::string row; for (int x = 0; x < image.width; ++x) row += final.at(x, y) ? (initial.at(x, y) ? '#' : '+') : (initial.at(x, y) ? '-' : '.'); lines.push_back(row); }
        for (bool skeletonOnly : {false, true}) {
            add(lines, skeletonOnly ? "skeleton " : "labels ", image.name, ' ', image.width, ' ', image.height);
            for (int y = 0; y < image.height; ++y) {
                std::string row;
                for (int x = 0; x < image.width; ++x) {
                    int label = labelAt(x, y);
                    if (!label) row += holeOf[static_cast<std::size_t>(y * image.width + x)] ? ':' : '.';
                    else { const Region& region = regions[label - 1]; row += skeletonOnly && !region.skeleton.count({x, y}) ? '+' : region.kept ? symbols[static_cast<std::size_t>(label % 62)] : '#'; }
                }
                lines.push_back(row);
            }
        }
        return lines;
    }
    Lines csvRows() const {
        Lines rows;
        for (const Region& region : regions) if (region.kept) {
            Lines fields{image.name, text(region.number), region.className, region.flags.empty() ? "-" : join(region.flags, "+")};
            for (const std::string& name : Lines{"area", "x0", "y0", "x1", "y1"}) fields.push_back(text(region.integer(name)));
            for (const std::pair<std::string, int>& item : std::vector<std::pair<std::string, int>>{{"cx", 3}, {"cy", 3}, {"mean", 2}, {"variance", 2}}) fields.push_back(decimal(region.features.at(item.first), item.second));
            fields.push_back(text(region.integer("min"))); fields.push_back(text(region.integer("max"))); fields.push_back(decimal(region.features.at("contrast"), 2));
            for (const std::string& name : Lines{"border", "perimeter", "chain", "straight", "diagonal", "turns"}) fields.push_back(text(region.integer(name)));
            fields.push_back(decimal(region.features.at("compactness"), 3));
            for (const std::string& name : Lines{"runs", "holes", "hole_area", "euler"}) fields.push_back(text(region.integer(name)));
            fields.push_back(region.parent ? text(region.parent) : "-"); fields.push_back(text(region.depth));
            for (const std::string& name : Lines{"var_x", "var_y", "cov_xy"}) fields.push_back(decimal(region.features.at(name), 3));
            fields.push_back(decimal(region.features.at("hu1"), 4)); fields.push_back(region.orientation);
            for (const std::string& name : Lines{"anisotropy", "extent", "mirror_lr", "mirror_tb"}) fields.push_back(decimal(region.features.at(name), 3));
            fields.push_back(hullAreaText(region.hullDoubled)); fields.push_back(decimal(region.features.at("solidity"), 3)); fields.push_back(text(region.integer("feret2"))); fields.push_back(decimal(region.features.at("width2"), 3)); fields.push_back(decimal(region.features.at("elongation"), 3));
            for (const std::string& name : Lines{"bays", "bay_area", "skeleton", "endpoints", "branches"}) fields.push_back(text(region.integer(name)));
            fields.push_back(region.neighbor ? text(region.neighbor) : "-"); fields.push_back(region.neighbor ? decimal(Rational(region.distance, 4), 2) : "-");
            std::string codes; for (int direction : region.codes) codes += static_cast<char>('0' + direction);
            fields.push_back(codes.empty() ? "-" : codes); rows.push_back(join(fields, ","));
        }
        return rows;
    }
    Lines summaryLines() const {
        int kept = 0, depth = 0, largest = 0, smallest = 0;
        Integer area = 0, holePixels = 0;
        Lines trees;
        for (const Region& region : regions) {
            depth = std::max(depth, region.depth); if (!region.parent) trees.push_back(treeText(region.number));
            if (!region.kept) continue;
            ++kept; area += region.integer("area");
            if (!largest || region.integer("area") > regions[largest - 1].integer("area")) largest = region.number;
            if (!smallest || region.integer("area") < regions[smallest - 1].integer("area")) smallest = region.number;
        }
        for (const Hole& hole : holes) holePixels += static_cast<Integer>(hole.pixels.size());
        Lines lines{text("image ", image.name), text("threshold ", cutoff, ' ', setting.method(), ' ', setting.polarity, " conn ", setting.connectivity), text("foreground ", initial.count(), ' ', final.count()), text("regions ", regions.size(), " provisional ", labels.provisional, " kept ", kept, " dropped ", static_cast<int>(regions.size()) - kept), text("connectivity four ", fourComponents, " eight ", eightComponents), text("holes ", holes.size(), " hole_pixels ", holePixels, " euler ", static_cast<int>(regions.size()) - static_cast<int>(holes.size()), " bitquad ", bitQuad)};
        for (const Hole& hole : holes) { int x0 = image.width, y0 = image.height, x1 = 0, y1 = 0; for (const Pixel& p : hole.pixels) { x0 = std::min(x0, p.first); y0 = std::min(y0, p.second); x1 = std::max(x1, p.first); y1 = std::max(y1, p.second); } add(lines, "hole ", hole.number, " owner ", hole.owner, " area ", hole.pixels.size(), " box ", x0, ' ', y0, ' ', x1, ' ', y1); }
        add(lines, "depth_max ", depth); add(lines, "tree", trees.empty() ? "" : " " + join(trees)); add(lines, "intensity foreground ", intensityText(true), " background ", intensityText(false));
        if (!kept) lines.push_back("area total 0 mean - largest - smallest -");
        else add(lines, "area total ", area, " mean ", meanText(area, kept), " largest ", largest, ' ', regions[largest - 1].integer("area"), " smallest ", smallest, ' ', regions[smallest - 1].integer("area"));
        std::string classes = "classes", flags = "flags", orientation = "orientations";
        for (const std::string& name : rules.classNames) { int count = 0; for (const Region& region : regions) count += region.kept && region.className == name; classes += text(' ', name, ' ', count); }
        for (const std::string& name : orientations) { int count = 0; for (const Region& region : regions) count += region.kept && region.orientation == name; orientation += text(' ', name, ' ', count); }
        for (const Rule& rule : rules.flags) { int count = 0; for (const Region& region : regions) count += region.kept && std::find(region.flags.begin(), region.flags.end(), rule.name) != region.flags.end(); flags += text(' ', rule.name, ' ', count); }
        extend(lines, Lines{classes, orientation, flags});
        return lines;
    }
};
static Lines overallLines(const std::vector<ImageAnalysis>& analyses, const Rules& rules) {
    int count = 0, kept = 0, holes = 0;
    std::vector<const Region*> regions;
    const ImageAnalysis* largestImage = nullptr;
    const Region* largest = nullptr;
    for (const ImageAnalysis& analysis : analyses) {
        count += static_cast<int>(analysis.regions.size()); holes += static_cast<int>(analysis.holes.size());
        for (const Region& region : analysis.regions) { regions.push_back(&region); if (region.kept) { ++kept; if (!largest || region.integer("area") > largest->integer("area")) { largest = &region; largestImage = &analysis; } } }
    }
    Lines lines{"overall", text("images ", analyses.size()), text("regions ", count, " kept ", kept, " dropped ", count - kept), text("holes ", holes, " euler ", count - holes)};
    for (std::size_t i = 0; i < rules.filters.size(); ++i) { int dropped = 0; for (const Region* region : regions) dropped += region->droppedBy == static_cast<int>(i); const Condition& c = rules.filters[i]; add(lines, "filter ", i + 1, ' ', c.feature, ' ', c.comparison, ' ', c.spelling, " dropped ", dropped); }
    for (const std::string& name : rules.classNames) { Integer area = 0; int size = 0; for (const Region* region : regions) if (region->kept && region->className == name) { ++size; area += region->integer("area"); } add(lines, "class ", name, " count ", size, " area ", area, " mean ", meanText(area, size)); }
    for (const Rule& rule : rules.flags) { int size = 0; for (const Region* region : regions) size += region->kept && std::find(region->flags.begin(), region->flags.end(), rule.name) != region->flags.end(); add(lines, "flag ", rule.name, " count ", size); }
    std::string orientation = "orientations";
    for (const std::string& name : orientations) { int size = 0; for (const Region* region : regions) size += region->kept && region->orientation == name; orientation += text(' ', name, ' ', size); }
    lines.push_back(orientation);
    if (largest) add(lines, "largest ", largestImage->image.name, ' ', largest->number, ' ', largest->integer("area")); else lines.push_back("largest -");
    return lines;
}
int main() {
    Parameters parameters = readParameters();
    Rules rules = readRules();
    std::vector<ImageAnalysis> analyses;
    for (const Image& image : readImages("input/images.txt")) analyses.emplace_back(image, parameters.settings.at(image.name), parameters, rules);
    Lines thresholds, maps, rows{csvHeader}, summary;
    for (const ImageAnalysis& analysis : analyses) { extend(thresholds, analysis.thresholdLines()); extend(maps, analysis.mapLines()); extend(rows, analysis.csvRows()); extend(summary, analysis.summaryLines()); }
    extend(summary, overallLines(analyses, rules));
    std::filesystem::create_directories("output");
    writeLines("thresholds.txt", thresholds); writeLines("labels.txt", maps); writeLines("regions.csv", rows); writeLines("summary.txt", summary);
}
