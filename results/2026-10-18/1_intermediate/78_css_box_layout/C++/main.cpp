#include <algorithm>
#include <array>
#include <cstddef>
#include <iostream>
#include <map>
#include <numeric>
#include <optional>
#include <set>
#include <sstream>
#include <string>
#include <tuple>
#include <utility>
#include <vector>

using Declarations = std::vector<std::pair<std::string, std::string>>;

static std::vector<std::string> split(const std::string& text, const std::string& separator) {
    std::vector<std::string> result;
    std::size_t start = 0;
    while (true) {
        std::size_t end = text.find(separator, start);
        result.push_back(text.substr(start, end == std::string::npos ? end : end - start));
        if (end == std::string::npos) return result;
        start = end + separator.size();
    }
}

static std::string trim(const std::string& text) {
    std::size_t first = text.find_first_not_of(' ');
    return first == std::string::npos ? "" : text.substr(first, text.find_last_not_of(' ') - first + 1);
}

static std::string join(const std::vector<std::string>& names, const std::string& separator = " ") {
    std::string result;
    for (const std::string& name : names) {
        if (!result.empty()) result += separator;
        result += name;
    }
    return result;
}

static const std::map<std::string, std::string>& initialValues() {
    static const std::map<std::string, std::string> values = [] {
        std::map<std::string, std::string> defaults = {
            {"display", "block"}, {"position", "static"}, {"box-sizing", "content-box"},
            {"width", "auto"}, {"height", "auto"}, {"min-width", "0"}, {"min-height", "0"},
            {"max-width", "none"}, {"max-height", "none"}, {"top", "auto"}, {"right", "auto"},
            {"bottom", "auto"}, {"left", "auto"}, {"flex-direction", "row"}, {"flex-wrap", "nowrap"},
            {"justify-content", "start"}, {"align-items", "stretch"}, {"align-self", "auto"},
            {"row-gap", "0"}, {"column-gap", "0"}, {"order", "0"}, {"flex-grow", "0"},
            {"flex-shrink", "1"}, {"flex-basis", "auto"}, {"grid-template-columns", "none"},
            {"grid-template-rows", "none"}, {"grid-column", "auto"}, {"grid-row", "auto"}
        };
        for (const std::string& prefix : {"margin", "padding", "border"}) {
            for (const std::string& side : {"top", "right", "bottom", "left"}) defaults[prefix + '-' + side] = "0";
        }
        return defaults;
    }();
    return values;
}

static bool integer(const std::string& text) {
    return !text.empty() && text.size() <= 3 && std::all_of(text.begin(), text.end(), [](char c) { return c >= '0' && c <= '9'; });
}

static bool positive(const std::string& text) { return integer(text) && std::stoi(text) > 0; }
static bool signedInteger(const std::string& text) { return integer(text) || (!text.empty() && text[0] == '-' && integer(text.substr(1))); }
static bool percentage(const std::string& text) { return !text.empty() && text.back() == '%' && integer(text.substr(0, text.size() - 1)); }
static bool fraction(const std::string& text) { return text.size() > 2 && text.substr(text.size() - 2) == "fr" && positive(text.substr(0, text.size() - 2)); }

static bool known(const std::string& property) {
    return initialValues().count(property) || property == "margin" || property == "padding" || property == "border" || property == "gap";
}

static std::optional<Declarations> declaration(const std::string& property, const std::string& value) {
    if (!known(property)) return std::nullopt;
    std::vector<std::string> tokens = split(value, " ");
    if (property == "margin" || property == "padding" || property == "border") {
        if (tokens.size() > 4) return std::nullopt;
        for (const std::string& token : tokens) {
            if (property == "border" ? token != "0" && token != "1" : !integer(token)) return std::nullopt;
        }
        std::array<std::string, 4> expanded = {tokens[0], tokens.size() >= 2 ? tokens[1] : tokens[0],
            tokens.size() >= 3 ? tokens[2] : tokens[0], tokens.size() == 4 ? tokens[3] : (tokens.size() >= 2 ? tokens[1] : tokens[0])};
        Declarations result;
        const char* sides[] = {"top", "right", "bottom", "left"};
        for (int i = 0; i < 4; ++i) result.emplace_back(property + '-' + sides[i], expanded[i]);
        return result;
    }
    if (property == "gap") {
        if (tokens.size() > 2 || !std::all_of(tokens.begin(), tokens.end(), integer)) return std::nullopt;
        return Declarations{{"row-gap", tokens[0]}, {"column-gap", tokens.back()}};
    }
    bool valid = false;
    if (property == "grid-template-columns" || property == "grid-template-rows") {
        valid = value == "none" || std::all_of(tokens.begin(), tokens.end(), [](const std::string& token) { return token == "auto" || integer(token) || fraction(token); });
    } else if (property == "grid-column" || property == "grid-row") {
        valid = value == "auto" || (tokens.size() == 1 && positive(tokens[0]))
             || (tokens.size() == 2 && tokens[0] == "span" && positive(tokens[1]))
             || (tokens.size() == 3 && positive(tokens[0]) && tokens[1] == "/" && positive(tokens[2]) && std::stoi(tokens[0]) < std::stoi(tokens[2]))
             || (tokens.size() == 4 && positive(tokens[0]) && tokens[1] == "/" && tokens[2] == "span" && positive(tokens[3]));
    } else if (tokens.size() == 1) {
        static const std::map<std::string, std::set<std::string>> choices = {
            {"display", {"block", "flex", "grid", "none"}}, {"position", {"static", "relative", "absolute"}},
            {"box-sizing", {"content-box", "border-box"}}, {"flex-direction", {"row", "row-reverse", "column", "column-reverse"}},
            {"flex-wrap", {"nowrap", "wrap"}}, {"justify-content", {"start", "end", "center", "space-between", "space-around", "space-evenly"}},
            {"align-items", {"stretch", "start", "end", "center"}}, {"align-self", {"auto", "stretch", "start", "end", "center"}}
        };
        auto choice = choices.find(property);
        if (choice != choices.end()) valid = choice->second.count(value) != 0;
        else if (property == "width" || property == "height" || property == "flex-basis") valid = value == "auto" || integer(value) || percentage(value);
        else if (property == "min-width" || property == "min-height") valid = integer(value) || percentage(value);
        else if (property == "max-width" || property == "max-height") valid = value == "none" || integer(value) || percentage(value);
        else if (property == "top" || property == "right" || property == "bottom" || property == "left") valid = value == "auto" || signedInteger(value);
        else if (property == "order") valid = signedInteger(value);
        else if (property.compare(0, 7, "border-") == 0) valid = value == "0" || value == "1";
        else valid = integer(value);
    }
    return valid ? std::optional<Declarations>(Declarations{{property, value}}) : std::nullopt;
}

struct StyleRule {
    std::vector<std::string> selectors;
    Declarations declarations;
};

struct Element {
    std::string type;
    std::string id;
    std::set<std::string> classes;
    std::optional<std::string> text;
    int parent = -1;
    int depth = 0;
    std::vector<int> children;
    std::map<std::string, std::string> overrides, style;
    std::array<int, 4> margin{}, padding{}, border{};
    bool displayed = false;
    int cw = 0, ch = 0, naturalHeight = 0;
    int relativeX = 0, relativeY = 0, x = 0, y = 0;
    std::vector<std::string> lines;
    std::optional<int> maxContent, contribution;

    const std::string& get(const std::string& property) const { return style.at(property); }
    int number(const std::string& property) const { return std::stoi(get(property)); }
    int frame(bool horizontal) const { return horizontal ? padding[1] + padding[3] + border[1] + border[3] : padding[0] + padding[2] + border[0] + border[2]; }
    int margins(bool horizontal) const { return horizontal ? margin[1] + margin[3] : margin[0] + margin[2]; }
    int width() const { return cw + frame(true); }
    int height() const { return ch + frame(false); }
};

struct Rect {
    int x, y, width, height;
    bool contains(int px, int py) const { return x <= px && px < x + width && y <= py && py < y + height; }
};

struct Placement {
    int element;
    int column, row, columnSpan, rowSpan;
    int areaWidth = 0, areaX = 0, width = 0, rowContribution = 0;
};

struct Grid {
    std::vector<Placement> items;
    int columns, rows;
    std::vector<std::string> columnTracks, rowTracks;
};

class Layout {
    int width = 0, height = 0;
    std::vector<StyleRule> rules;
    std::vector<Element> elements;
    std::map<std::string, int> ids;

    std::vector<int> children(int index, bool ordered = false) const {
        std::vector<int> result;
        for (int child : elements[index].children) {
            if (elements[child].displayed && elements[child].get("position") != "absolute") result.push_back(child);
        }
        if (ordered) std::stable_sort(result.begin(), result.end(), [&](int a, int b) { return elements[a].number("order") < elements[b].number("order"); });
        return result;
    }

    std::string align(int parent, int child) const {
        return elements[child].get("align-self") == "auto" ? elements[parent].get("align-items") : elements[child].get("align-self");
    }

    std::optional<int> resolve(int index, const std::string& property, std::optional<int> reference, bool horizontal) const {
        const Element& element = elements[index];
        const std::string& value = element.get(property);
        if (value == "auto" || value == "none" || (value.back() == '%' && !reference)) return std::nullopt;
        int result = value.back() == '%' ? static_cast<int>(static_cast<long long>(*reference) * std::stoi(value) / 100) : std::stoi(value);
        if (element.get("box-sizing") == "border-box") result = std::max(0, result - element.frame(horizontal));
        return result;
    }

    int clamp(int index, int value, std::optional<int> reference, bool horizontal) const {
        std::string axis = horizontal ? "width" : "height";
        int lower = resolve(index, "min-" + axis, reference, horizontal).value_or(0);
        std::optional<int> upper = resolve(index, "max-" + axis, reference, horizontal);
        if (upper) value = std::min(value, *upper);
        return std::max(value, lower);
    }

    static std::vector<int> distribute(int total, const std::vector<int>& weights) {
        int sum = std::accumulate(weights.begin(), weights.end(), 0), assigned = 0;
        std::vector<int> result(weights.size(), 0);
        if (sum == 0) return result;
        for (std::size_t i = 0; i < weights.size(); ++i) {
            result[i] = static_cast<int>(static_cast<long long>(total) * weights[i] / sum);
            assigned += result[i];
        }
        for (std::size_t i = 0; i < weights.size() && assigned < total; ++i) {
            if (weights[i] > 0) {
                ++result[i];
                ++assigned;
            }
        }
        return result;
    }

    static std::pair<int, int> gridPosition(const std::string& value) {
        std::vector<std::string> parts = split(value, " ");
        if (value == "auto") return {0, 1};
        if (parts[0] == "span") return {0, std::stoi(parts[1])};
        int start = std::stoi(parts[0]);
        if (parts.size() == 1) return {start, 1};
        return {start, parts[2] == "span" ? std::stoi(parts[3]) : std::stoi(parts[2]) - start};
    }

    Grid placement(int index) const {
        const Element& element = elements[index];
        Grid grid;
        grid.columnTracks = element.get("grid-template-columns") == "none" ? std::vector<std::string>{"auto"} : split(element.get("grid-template-columns"), " ");
        grid.rowTracks = element.get("grid-template-rows") == "none" ? std::vector<std::string>{} : split(element.get("grid-template-rows"), " ");
        grid.columns = static_cast<int>(grid.columnTracks.size());
        grid.rows = static_cast<int>(grid.rowTracks.size());
        for (int child : children(index, true)) {
            auto [column, columnSpan] = gridPosition(elements[child].get("grid-column"));
            auto [row, rowSpan] = gridPosition(elements[child].get("grid-row"));
            grid.items.push_back({child, column, row, columnSpan, rowSpan});
            grid.columns = std::max(grid.columns, column == 0 ? columnSpan : column + columnSpan - 1);
        }
        std::set<std::pair<int, int>> occupied;
        auto overlaps = [&](const Placement& item, int row, int column) {
            for (int r = row; r < row + item.rowSpan; ++r) {
                for (int c = column; c < column + item.columnSpan; ++c) {
                    if (occupied.count({r, c})) return true;
                }
            }
            return false;
        };
        auto occupy = [&](const Placement& item) {
            for (int r = item.row; r < item.row + item.rowSpan; ++r) {
                for (int c = item.column; c < item.column + item.columnSpan; ++c) occupied.insert({r, c});
            }
        };
        for (const Placement& item : grid.items) {
            if (item.row && item.column) occupy(item);
        }
        int cursorRow = 1, cursorColumn = 1;
        for (Placement& item : grid.items) {
            if (item.row && item.column) continue;
            if (item.row) {
                int column = 1;
                while (column + item.columnSpan - 1 <= grid.columns && overlaps(item, item.row, column)) ++column;
                item.column = column + item.columnSpan - 1 <= grid.columns ? column : 1;
            } else if (item.column) {
                if (item.column < cursorColumn) ++cursorRow;
                item.row = cursorRow;
                while (overlaps(item, item.row, item.column)) ++item.row;
                cursorRow = item.row;
                cursorColumn = item.column + item.columnSpan;
            } else {
                item.row = cursorRow;
                item.column = cursorColumn;
                while (true) {
                    if (item.column + item.columnSpan - 1 > grid.columns) {
                        ++item.row;
                        item.column = 1;
                    }
                    else if (overlaps(item, item.row, item.column)) ++item.column;
                    else break;
                }
                cursorRow = item.row;
                cursorColumn = item.column + item.columnSpan;
            }
            occupy(item);
        }
        for (const Placement& item : grid.items) grid.rows = std::max(grid.rows, item.row + item.rowSpan - 1);
        return grid;
    }

    std::vector<int> trackSizes(const Grid& grid, bool horizontal, std::optional<int> available, int gap, const std::vector<int>& contributions) const {
        int count = horizontal ? grid.columns : grid.rows;
        std::vector<std::string> specifications = horizontal ? grid.columnTracks : grid.rowTracks;
        specifications.resize(count, "auto");
        std::vector<int> sizes(count, 0), weights(count, 0);
        bool hasFractions = std::any_of(specifications.begin(), specifications.end(), fraction);
        for (int i = 0; i < count; ++i) {
            const std::string& specification = specifications[i];
            if (integer(specification)) sizes[i] = std::stoi(specification);
            else {
                if (specification == "auto" || !available) {
                    for (std::size_t j = 0; j < grid.items.size(); ++j) {
                        const Placement& item = grid.items[j];
                        if ((horizontal ? item.column : item.row) == i + 1 && (horizontal ? item.columnSpan : item.rowSpan) == 1) sizes[i] = std::max(sizes[i], contributions[j]);
                    }
                }
                weights[i] = hasFractions ? (fraction(specification) ? std::stoi(specification) : 0) : (specification == "auto" ? 1 : 0);
            }
        }
        if (available && count > 0) {
            int leftover = *available - std::accumulate(sizes.begin(), sizes.end(), 0) - gap * (count - 1);
            if (leftover > 0) {
                std::vector<int> additions = distribute(leftover, weights);
                for (int i = 0; i < count; ++i) sizes[i] += additions[i];
            }
        }
        return sizes;
    }

    int contribution(int index) {
        Element& element = elements[index];
        if (!element.contribution) {
            int content = resolve(index, "width", std::nullopt, true).value_or(maxContent(index));
            element.contribution = clamp(index, content, std::nullopt, true) + element.frame(true) + element.margins(true);
        }
        return *element.contribution;
    }

    int maxContent(int index) {
        Element& element = elements[index];
        if (element.maxContent) return *element.maxContent;
        int result = 0;
        if (element.text) result = static_cast<int>(element.text->size());
        else if (element.get("display") == "grid") {
            Grid grid = placement(index);
            std::vector<int> contributions;
            for (const Placement& item : grid.items) contributions.push_back(contribution(item.element));
            std::vector<int> sizes = trackSizes(grid, true, std::nullopt, element.number("column-gap"), contributions);
            result = std::accumulate(sizes.begin(), sizes.end(), 0) + element.number("column-gap") * (grid.columns - 1);
        } else {
            std::vector<int> items = children(index);
            bool row = element.get("display") == "flex" && (element.get("flex-direction") == "row" || element.get("flex-direction") == "row-reverse");
            for (int child : items) result = row ? result + contribution(child) : std::max(result, contribution(child));
            if (row && !items.empty()) result += element.number("column-gap") * (static_cast<int>(items.size()) - 1);
        }
        element.maxContent = result;
        return result;
    }

    void positionChild(int parent, int child, int x, int y) {
        elements[child].relativeX = x + elements[parent].border[3] + elements[parent].padding[3];
        elements[child].relativeY = y + elements[parent].border[0] + elements[parent].padding[0];
    }

    int block(int index, std::optional<int> reference) {
        int bottom = 0, previousMargin = 0;
        bool first = true;
        for (int child : children(index)) {
            layout(child, elements[index].cw, reference);
            const Element& item = elements[child];
            int top = first ? item.margin[0] : bottom + std::max(previousMargin, item.margin[0]);
            positionChild(index, child, item.margin[3], top);
            bottom = top + item.height();
            previousMargin = item.margin[2];
            first = false;
        }
        return first ? 0 : bottom + previousMargin;
    }

    static int alignmentOffset(int remainder, const std::string& alignment) {
        if (remainder <= 0) return 0;
        return alignment == "end" ? remainder : (alignment == "center" ? remainder / 2 : 0);
    }

    int flex(int index, std::optional<int> reference, std::optional<int> heightReference) {
        const Element& container = elements[index];
        std::string direction = container.get("flex-direction");
        bool horizontal = direction == "row" || direction == "row-reverse";
        bool reverse = direction == "row-reverse" || direction == "column-reverse";
        int gap = container.number(horizontal ? "column-gap" : "row-gap"), crossGap = container.number("row-gap");
        std::optional<int> mainReference = horizontal ? std::optional<int>(container.cw) : reference;
        struct Item {
            int element, base, hypothetical, outer, cross = 0, size = 0;
            std::string alignment;
        };
        std::vector<Item> items;
        for (int child : children(index, true)) {
            const Element& item = elements[child];
            std::string alignment = align(index, child);
            int cross = 0;
            if (!horizontal) {
                int room = std::max(0, container.cw - item.margins(true) - item.frame(true));
                cross = item.get("width") != "auto" ? *resolve(child, "width", container.cw, true)
                      : (alignment == "stretch" ? room : std::min(maxContent(child), room));
                cross = clamp(child, cross, container.cw, true);
            }
            std::optional<int> base = resolve(child, "flex-basis", mainReference, horizontal);
            if (!base) base = resolve(child, horizontal ? "width" : "height", mainReference, horizontal);
            if (!base) base = horizontal ? maxContent(child) : layout(child, container.cw, reference, cross);
            items.push_back({child, *base, clamp(child, *base, mainReference, horizontal), item.frame(horizontal) + item.margins(horizontal), cross, 0, alignment});
        }
        int mainLength = horizontal ? container.cw : reference.value_or(0);
        if (!horizontal && !reference) {
            for (const Item& item : items) mainLength += item.hypothetical + item.outer;
            if (!items.empty()) mainLength += gap * (static_cast<int>(items.size()) - 1);
            mainLength = clamp(index, mainLength, heightReference, false);
        }
        std::vector<std::vector<std::size_t>> lines;
        int used = 0;
        for (std::size_t i = 0; i < items.size(); ++i) {
            int outer = items[i].hypothetical + items[i].outer;
            if (lines.empty() || (horizontal && container.get("flex-wrap") == "wrap" && used + gap + outer > mainLength)) {
                lines.push_back({});
                used = 0;
            }
            if (!lines.back().empty()) used += gap;
            lines.back().push_back(i);
            used += outer;
        }
        int crossStart = 0;
        for (const auto& line : lines) {
            int gaps = gap * (static_cast<int>(line.size()) - 1), hypothetical = gaps;
            for (std::size_t i : line) hypothetical += items[i].hypothetical + items[i].outer;
            bool growing = hypothetical < mainLength;
            std::vector<bool> frozen(line.size(), false);
            std::vector<int> weights(line.size(), 0), violations(line.size(), 0);
            for (std::size_t j = 0; j < line.size(); ++j) {
                Item& item = items[line[j]];
                weights[j] = elements[item.element].number(growing ? "flex-grow" : "flex-shrink") * (growing ? 1 : item.base);
                frozen[j] = weights[j] == 0 || (growing ? item.base > item.hypothetical : item.base < item.hypothetical);
                item.size = item.hypothetical;
            }
            while (std::find(frozen.begin(), frozen.end(), false) != frozen.end()) {
                int free = mainLength - gaps;
                std::vector<int> activeWeights = weights;
                for (std::size_t j = 0; j < line.size(); ++j) {
                    const Item& item = items[line[j]];
                    free -= (frozen[j] ? item.size : item.base) + item.outer;
                    if (frozen[j]) activeWeights[j] = 0;
                }
                std::vector<int> shares = distribute(std::max(0, growing ? free : -free), activeWeights);
                int violation = 0;
                for (std::size_t j = 0; j < line.size(); ++j) {
                    if (frozen[j]) continue;
                    Item& item = items[line[j]];
                    int tentative = item.base + (growing ? shares[j] : -shares[j]);
                    item.size = clamp(item.element, tentative, mainReference, horizontal);
                    violations[j] = item.size - tentative;
                    violation += violations[j];
                }
                for (std::size_t j = 0; j < line.size(); ++j) {
                    if (violation == 0 || (violation > 0 && violations[j] > 0) || (violation < 0 && violations[j] < 0)) frozen[j] = true;
                }
            }
            int lineCross = horizontal ? 0 : container.cw;
            for (std::size_t i : line) {
                Item& item = items[i];
                if (horizontal) {
                    layout(item.element, container.cw, reference, item.size);
                    item.cross = elements[item.element].ch;
                    lineCross = std::max(lineCross, item.cross + elements[item.element].frame(false) + elements[item.element].margins(false));
                }
            }
            if (horizontal && lines.size() == 1) lineCross = reference ? *reference : clamp(index, lineCross, heightReference, false);
            int remainder = mainLength - gaps;
            for (std::size_t i : line) remainder -= items[i].size + items[i].outer;
            std::vector<int> spaces(line.size() + 1, 0);
            const std::string& justify = container.get("justify-content");
            if (remainder > 0) {
                if (justify == "end") spaces[0] = remainder;
                else if (justify == "center") spaces[0] = remainder / 2;
                else if (justify != "start") {
                    std::vector<int> weightsOfSpaces(spaces.size(), justify == "space-around" ? 2 : 1);
                    if (justify == "space-between") weightsOfSpaces.front() = weightsOfSpaces.back() = 0;
                    else if (justify == "space-around") weightsOfSpaces.front() = weightsOfSpaces.back() = 1;
                    spaces = distribute(remainder, weightsOfSpaces);
                }
            }
            int cursor = 0;
            for (std::size_t j = 0; j < line.size(); ++j) {
                Item& item = items[line[j]];
                Element& child = elements[item.element];
                if (horizontal) {
                    std::optional<int> forcedHeight;
                    if (item.alignment == "stretch" && child.get("height") == "auto") forcedHeight = clamp(item.element, std::max(0, lineCross - child.margins(false) - child.frame(false)), reference, false);
                    layout(item.element, container.cw, reference, item.size, forcedHeight);
                    item.cross = child.ch;
                } else layout(item.element, container.cw, reference, item.cross, item.size);
                int cross = crossStart + alignmentOffset(lineCross - item.cross - child.frame(!horizontal) - child.margins(!horizontal), item.alignment)
                          + child.margin[horizontal ? 0 : 3];
                cursor += spaces[j];
                int startMargin = child.margin[horizontal ? (reverse ? 1 : 3) : (reverse ? 2 : 0)];
                int main = reverse ? mainLength - cursor - startMargin - item.size - child.frame(horizontal) : cursor + startMargin;
                positionChild(index, item.element, horizontal ? main : cross, horizontal ? cross : main);
                cursor += item.size + item.outer + gap;
            }
            crossStart += lineCross + crossGap;
        }
        return horizontal ? (lines.empty() ? 0 : crossStart - crossGap) : mainLength;
    }

    int gridLayout(int index, std::optional<int> reference) {
        Grid grid = placement(index);
        const Element& container = elements[index];
        int columnGap = container.number("column-gap"), rowGap = container.number("row-gap");
        std::vector<int> contributions;
        for (const Placement& item : grid.items) contributions.push_back(contribution(item.element));
        std::vector<int> columns = trackSizes(grid, true, container.cw, columnGap, contributions), rowContributions;
        for (Placement& item : grid.items) {
            const Element& child = elements[item.element];
            item.areaX = std::accumulate(columns.begin(), columns.begin() + item.column - 1, 0) + columnGap * (item.column - 1);
            item.areaWidth = std::accumulate(columns.begin() + item.column - 1, columns.begin() + item.column + item.columnSpan - 1, 0) + columnGap * (item.columnSpan - 1);
            int content = resolve(item.element, "width", item.areaWidth, true).value_or(std::max(0, item.areaWidth - child.margins(true) - child.frame(true)));
            item.width = clamp(item.element, content, item.areaWidth, true);
            layout(item.element, item.areaWidth, std::nullopt, item.width);
            item.rowContribution = child.height() + child.margins(false);
            rowContributions.push_back(item.rowContribution);
        }
        std::vector<int> rows = trackSizes(grid, false, reference, rowGap, rowContributions);
        for (const Placement& item : grid.items) {
            const Element& child = elements[item.element];
            int areaY = std::accumulate(rows.begin(), rows.begin() + item.row - 1, 0) + rowGap * (item.row - 1);
            int areaHeight = std::accumulate(rows.begin() + item.row - 1, rows.begin() + item.row + item.rowSpan - 1, 0) + rowGap * (item.rowSpan - 1);
            std::string alignment = align(index, item.element);
            std::optional<int> forcedHeight;
            if (alignment == "stretch" && child.get("height") == "auto") forcedHeight = clamp(item.element, std::max(0, areaHeight - child.margins(false) - child.frame(false)), areaHeight, false);
            layout(item.element, item.areaWidth, areaHeight, item.width, forcedHeight);
            int offset = alignmentOffset(areaHeight - child.height() - child.margins(false), alignment);
            positionChild(index, item.element, item.areaX + child.margin[3], areaY + offset + child.margin[0]);
        }
        return grid.rows == 0 ? 0 : std::accumulate(rows.begin(), rows.end(), 0) + rowGap * (grid.rows - 1);
    }

    int layout(int index, int widthReference, std::optional<int> heightReference, std::optional<int> forcedWidth = std::nullopt, std::optional<int> forcedHeight = std::nullopt) {
        Element& element = elements[index];
        element.cw = forcedWidth ? *forcedWidth : clamp(index, resolve(index, "width", widthReference, true).value_or(std::max(0, widthReference - element.margins(true) - element.frame(true))), widthReference, true);
        if (!forcedHeight) {
            std::optional<int> resolved = resolve(index, "height", heightReference, false);
            if (resolved) forcedHeight = clamp(index, *resolved, heightReference, false);
        }
        int natural = 0;
        element.lines.clear();
        if (element.text) {
            for (const std::string& word : split(*element.text, " ")) {
                if (element.lines.empty() || static_cast<int>(element.lines.back().size() + 1 + word.size()) > element.cw) element.lines.push_back(word);
                else element.lines.back() += ' ' + word;
            }
            natural = static_cast<int>(element.lines.size());
        } else if (element.get("display") == "flex") natural = flex(index, forcedHeight, heightReference);
        else if (element.get("display") == "grid") natural = gridLayout(index, forcedHeight);
        else natural = block(index, forcedHeight);
        element.naturalHeight = natural;
        element.ch = forcedHeight ? *forcedHeight : clamp(index, natural, heightReference, false);
        return natural;
    }

    int containingBlock(int index) const {
        for (int parent = elements[index].parent; parent >= 0; parent = elements[parent].parent) {
            if (elements[parent].get("position") != "static") return parent;
        }
        return -1;
    }

    void recompute() {
        const char* sides[] = {"top", "right", "bottom", "left"};
        for (std::size_t i = 0; i < elements.size(); ++i) {
            Element& element = elements[i];
            element.style = initialValues();
            std::map<std::string, int> specificities;
            for (const StyleRule& rule : rules) {
                int specificity = -1;
                for (const std::string& selector : rule.selectors) {
                    if (selector[0] == '#' && selector.substr(1) == element.id) specificity = 2;
                    else if (selector[0] == '.' && element.classes.count(selector.substr(1))) specificity = std::max(specificity, 1);
                    else if (selector == element.type) specificity = std::max(specificity, 0);
                }
                if (specificity < 0) continue;
                for (const auto& [property, value] : rule.declarations) {
                    auto previous = specificities.find(property);
                    if (previous == specificities.end() || specificity >= previous->second) {
                        element.style[property] = value;
                        specificities[property] = specificity;
                    }
                }
            }
            for (const auto& [property, value] : element.overrides) element.style[property] = value;
            for (int side = 0; side < 4; ++side) {
                element.margin[side] = element.number(std::string("margin-") + sides[side]);
                element.padding[side] = element.number(std::string("padding-") + sides[side]);
                element.border[side] = element.number(std::string("border-") + sides[side]);
            }
            element.displayed = element.get("display") != "none" && (element.parent < 0 || elements[element.parent].displayed);
            element.maxContent.reset();
            element.contribution.reset();
        }
        if (elements[0].displayed && elements[0].get("position") != "absolute") {
            layout(0, width, height);
            elements[0].relativeX = elements[0].margin[3];
            elements[0].relativeY = elements[0].margin[0];
        }
        for (std::size_t i = 0; i < elements.size(); ++i) {
            Element& element = elements[i];
            if (!element.displayed || element.get("position") != "absolute") continue;
            int block = containingBlock(static_cast<int>(i));
            int blockWidth = block < 0 ? width : elements[block].cw + elements[block].padding[1] + elements[block].padding[3];
            int blockHeight = block < 0 ? height : elements[block].ch + elements[block].padding[0] + elements[block].padding[2];
            auto inset = [&](const std::string& property) -> std::optional<int> { return element.get(property) == "auto" ? std::nullopt : std::optional<int>(element.number(property)); };
            std::optional<int> left = inset("left"), right = inset("right"), top = inset("top"), bottom = inset("bottom");
            int contentWidth;
            if (element.get("width") != "auto") contentWidth = *resolve(static_cast<int>(i), "width", blockWidth, true);
            else {
                int room = std::max(0, blockWidth - left.value_or(0) - right.value_or(0) - element.margins(true) - element.frame(true));
                contentWidth = left && right ? room : std::min(maxContent(static_cast<int>(i)), room);
            }
            contentWidth = clamp(static_cast<int>(i), contentWidth, blockWidth, true);
            std::optional<int> forcedHeight;
            if (element.get("height") == "auto" && top && bottom) forcedHeight = clamp(static_cast<int>(i), std::max(0, blockHeight - *top - *bottom - element.margins(false) - element.frame(false)), blockHeight, false);
            layout(static_cast<int>(i), blockWidth, blockHeight, contentWidth, forcedHeight);
            element.relativeX = left ? *left + element.margin[3] : (right ? blockWidth - *right - element.margin[1] - element.width() : element.margin[3]);
            element.relativeY = top ? *top + element.margin[0] : (bottom ? blockHeight - *bottom - element.margin[2] - element.height() : element.margin[0]);
        }
        for (std::size_t i = 0; i < elements.size(); ++i) {
            Element& element = elements[i];
            if (!element.displayed) continue;
            int parent = element.get("position") == "absolute" ? containingBlock(static_cast<int>(i)) : element.parent;
            element.x = parent < 0 ? 0 : elements[parent].x;
            element.y = parent < 0 ? 0 : elements[parent].y;
            if (element.get("position") == "absolute" && parent >= 0) {
                element.x += elements[parent].border[3];
                element.y += elements[parent].border[0];
            }
            element.x += element.relativeX;
            element.y += element.relativeY;
            if (element.get("position") == "relative") {
                element.x += element.get("left") != "auto" ? element.number("left") : (element.get("right") != "auto" ? -element.number("right") : 0);
                element.y += element.get("top") != "auto" ? element.number("top") : (element.get("bottom") != "auto" ? -element.number("bottom") : 0);
            }
        }
    }

    Rect rectangle(int index, const std::string& box) const {
        const Element& element = elements[index];
        Rect rect{element.x, element.y, element.width(), element.height()};
        if (box == "margin") {
            rect.x -= element.margin[3];
            rect.y -= element.margin[0];
            rect.width += element.margins(true);
            rect.height += element.margins(false);
        } else if (box == "padding" || box == "content") {
            rect.x += element.border[3];
            rect.y += element.border[0];
            rect.width -= element.border[1] + element.border[3];
            rect.height -= element.border[0] + element.border[2];
            if (box == "content") {
                rect.x += element.padding[3];
                rect.y += element.padding[0];
                rect.width = element.cw;
                rect.height = element.ch;
            }
        }
        return rect;
    }

    using Snapshot = std::vector<std::optional<std::array<int, 4>>>;
    Snapshot snapshot() const {
        Snapshot result;
        for (const Element& element : elements) {
            if (element.displayed) result.push_back(std::array<int, 4>{element.x, element.y, element.width(), element.height()});
            else result.push_back(std::nullopt);
        }
        return result;
    }

    std::string changed(const Snapshot& before) const {
        Snapshot after = snapshot();
        std::vector<std::string> names;
        for (std::size_t i = 0; i < before.size(); ++i) {
            if (before[i] != after[i]) names.push_back(elements[i].id);
        }
        return names.empty() ? "no change" : join(names);
    }

    void render() const {
        std::vector<std::string> screen(height, std::string(width, '.'));
        for (std::size_t i = 0; i < elements.size(); ++i) {
            const Element& element = elements[i];
            if (!element.displayed) continue;
            Rect border = rectangle(static_cast<int>(i), "border"), content = rectangle(static_cast<int>(i), "content");
            for (int y = std::max(0, border.y); y < std::min(height, border.y + border.height); ++y) {
                for (int x = std::max(0, border.x); x < std::min(width, border.x + border.width); ++x) {
                    bool horizontal = (element.border[0] && y == border.y) || (element.border[2] && y == border.y + border.height - 1);
                    bool vertical = (element.border[3] && x == border.x) || (element.border[1] && x == border.x + border.width - 1);
                    screen[y][x] = horizontal ? (vertical ? '+' : '-') : (vertical ? '|' : ' ');
                }
            }
            for (std::size_t row = 0; row < element.lines.size(); ++row) {
                int y = content.y + static_cast<int>(row);
                if (y < 0 || y >= height) continue;
                for (std::size_t column = 0; column < element.lines[row].size(); ++column) {
                    int x = content.x + static_cast<int>(column);
                    if (x >= 0 && x < width) screen[y][x] = element.lines[row][column];
                }
            }
        }
        std::string edge(width + 2, '#');
        std::cout << "render " << width << 'x' << height << '\n' << edge << '\n';
        for (const std::string& row : screen) std::cout << '#' << row << "#\n";
        std::cout << edge << '\n';
    }

    void execute(const std::string& line) {
        std::vector<std::string> parts = split(line, " ");
        const std::string& command = parts[0];
        if (command == "LAYOUT") {
            std::cout << "layout " << width << 'x' << height << '\n';
            for (const Element& element : elements) {
                std::cout << std::string(2 * element.depth, ' ') << element.id;
                if (!element.displayed) std::cout << " none\n";
                else std::cout << ' ' << element.x << ' ' << element.y << ' ' << element.width() << ' ' << element.height() << '\n';
            }
        } else if (command == "BOX") {
            auto found = ids.find(parts[1]);
            if (found == ids.end()) {
                std::cout << "error: unknown element " << parts[1] << '\n';
                return;
            }
            const Element& element = elements[found->second];
            if (!element.displayed) std::cout << "box " << parts[1] << ": none\n";
            else {
                std::cout << "box " << parts[1] << '\n';
                for (const std::string& box : {"margin", "border", "padding", "content"}) {
                    Rect rect = rectangle(found->second, box);
                    std::cout << box << ' ' << rect.x << ' ' << rect.y << ' ' << rect.width << ' ' << rect.height << '\n';
                }
            }
        } else if (command == "RENDER") render();
        else if (command == "HIT") {
            int x = std::stoi(parts[1]), y = std::stoi(parts[2]);
            if (x >= width || y >= height) {
                std::cout << "error: point " << x << ' ' << y << " outside viewport\n";
                return;
            }
            int found = -1;
            for (std::size_t i = 0; i < elements.size(); ++i) {
                if (elements[i].displayed && rectangle(static_cast<int>(i), "border").contains(x, y)) found = static_cast<int>(i);
            }
            std::vector<std::string> path;
            for (int i = found; i >= 0; i = elements[i].parent) path.push_back(elements[i].id);
            std::reverse(path.begin(), path.end());
            std::cout << "hit " << x << ' ' << y << ": " << (path.empty() ? "none" : join(path, " > ")) << '\n';
        } else if (command == "SET") {
            auto found = ids.find(parts[1]);
            if (found == ids.end()) {
                std::cout << "error: unknown element " << parts[1] << '\n';
                return;
            }
            if (!known(parts[2])) {
                std::cout << "error: unknown property " << parts[2] << '\n';
                return;
            }
            std::string value = join(std::vector<std::string>(parts.begin() + 3, parts.end()));
            std::optional<Declarations> declarations = declaration(parts[2], value);
            if (!declarations) {
                std::cout << "error: invalid value for " << parts[2] << ": " << value << '\n';
                return;
            }
            Snapshot before = snapshot();
            for (const auto& [property, text] : *declarations) elements[found->second].overrides[property] = text;
            recompute();
            std::cout << "set " << parts[1] << ' ' << parts[2] << ' ' << value << ": " << changed(before) << '\n';
        } else if (command == "VIEWPORT") {
            int w = std::stoi(parts[1]), h = std::stoi(parts[2]);
            if (w < 1 || w > 80 || h < 1 || h > 40) {
                std::cout << "error: invalid viewport " << w << ' ' << h << '\n';
                return;
            }
            Snapshot before = snapshot();
            width = w;
            height = h;
            recompute();
            std::cout << "viewport " << w << ' ' << h << ": " << changed(before) << '\n';
        } else if (command == "OVERFLOW") {
            std::vector<std::string> names;
            for (std::size_t i = 0; i < elements.size(); ++i) {
                const Element& element = elements[i];
                if (!element.displayed) continue;
                bool overflowing = false;
                if (element.text) {
                    overflowing = static_cast<int>(element.lines.size()) > element.ch;
                    for (const std::string& text : element.lines) overflowing = overflowing || static_cast<int>(text.size()) > element.cw;
                } else {
                    Rect content = rectangle(static_cast<int>(i), "content");
                    for (int child : children(static_cast<int>(i))) {
                        Rect margin = rectangle(child, "margin");
                        if (margin.x < content.x || margin.y < content.y || margin.x + margin.width > content.x + content.width || margin.y + margin.height > content.y + content.height) overflowing = true;
                    }
                }
                if (overflowing) names.push_back(element.id);
            }
            std::cout << "overflow: " << (names.empty() ? "none" : join(names)) << '\n';
        } else std::cout << "error: unknown command " << command << '\n';
    }

public:
    void run() {
        std::cin >> width >> height;
        std::string line;
        std::getline(std::cin, line);
        while (std::getline(std::cin, line) && line != "---") {
            std::size_t brace = line.find('{');
            StyleRule rule{split(trim(line.substr(0, brace)), ", "), {}};
            for (const std::string& text : split(trim(line.substr(brace + 1, line.size() - brace - 2)), "; ")) {
                std::size_t colon = text.find(": ");
                std::optional<Declarations> declarations = declaration(text.substr(0, colon), text.substr(colon + 2));
                if (declarations) rule.declarations.insert(rule.declarations.end(), declarations->begin(), declarations->end());
            }
            rules.push_back(std::move(rule));
        }
        std::vector<int> ancestors;
        while (std::getline(std::cin, line) && line != "===") {
            std::size_t first = line.find_first_not_of(' '), space = line.find(' ', first);
            std::string head = line.substr(first, space == std::string::npos ? space : space - first);
            std::size_t hash = head.find('#');
            std::vector<std::string> names = split(head.substr(hash + 1), ".");
            Element element;
            element.type = head.substr(0, hash);
            element.id = names[0];
            element.depth = static_cast<int>(first / 2);
            element.classes.insert(names.begin() + 1, names.end());
            if (space != std::string::npos) element.text = line.substr(space + 2, line.size() - space - 3);
            if (element.depth > 0) element.parent = ancestors[element.depth - 1];
            int index = static_cast<int>(elements.size());
            if (element.parent >= 0) elements[element.parent].children.push_back(index);
            ids[element.id] = index;
            elements.push_back(std::move(element));
            ancestors.resize(elements.back().depth + 1);
            ancestors.back() = index;
        }
        recompute();
        while (std::getline(std::cin, line) && line != "END") execute(line);
    }
};

int main() {
    Layout layout;
    layout.run();
}
