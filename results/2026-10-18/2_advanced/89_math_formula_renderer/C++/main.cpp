#include "formula.hpp"
std::string join(const Lines &items, const std::string &separator) {
    std::string out;
    for (std::size_t i = 0; i < items.size(); ++i) {
        if (i)
            out += separator;
        out += items[i];
    }
    return out;
}
void append(Lines &out, const Lines &items) { out.insert(out.end(), items.begin(), items.end()); }
std::string trimRight(std::string value) {
    while (!value.empty() && value.back() == ' ')
        value.pop_back();
    return value;
}
static Lines inputLines(const std::string &path) {
    std::ifstream input(path);
    if (!input)
        throw std::runtime_error("cannot read " + path);
    Lines out;
    for (std::string line; std::getline(input, line);)
        out.push_back(line);
    return out;
}
struct Formula {
    int number = 0;
    std::string source, tagString;
    std::vector<Token> tokens;
    Nodes nodes;
    std::optional<Token> tag, label;
    std::optional<Issue> error;
    std::vector<Issue> warnings;
};
struct Typesetter {
    Params params;
    std::map<std::string, std::string> references;
    BoxPtr typeset(const Node &node, bool script) const;
    std::vector<BoxPtr> boxes(const Nodes &nodes, bool script) const {
        std::vector<BoxPtr> out;
        for (const NodePtr &node : nodes)
            out.push_back(typeset(*node, script));
        return out;
    }
    std::string linear(const Node &node, bool script) const;
};
BoxPtr Typesetter::typeset(const Node &node, bool script) const {
    Kind kind = node.kind;
    if (kind == Kind::Identifier || kind == Kind::Number || kind == Kind::Symbol ||
        kind == Kind::Command || kind == Kind::Text || kind == Kind::Reference)
        return atomBox(node, script, references);
    if (kind == Kind::Row)
        return rowBox(boxes(node.items, script), spacing(node.items, script, params).gaps, "row");
    if (kind == Kind::Script) {
        BoxPtr base = typeset(*node.base, script), sub, sup;
        if (node.sub)
            sub = typeset(*node.sub, true);
        if (node.sup)
            sup = typeset(*node.sup, true);
        int sw = sub ? sub->width : 0, sh = sub ? sub->height : 0, pw = sup ? sup->width : 0,
            ph = sup ? sup->height : 0;
        bool stacked =
            !script && ((node.base->kind == Kind::Command &&
                         containsWord("\\sum \\prod \\lim \\max \\min", node.base->value)) ||
                        (node.base->kind == Kind::Accent &&
                         containsWord("overbrace underbrace", node.base->value)));
        if (stacked) {
            int width = std::max({base->width, sw, pw});
            BoxPtr out = newBox(width, ph + base->height + sh, ph + base->baseline, "limits");
            out->add(base, center(base, width), ph, "base: ");
            if (sub)
                out->add(sub, center(sub, width), ph + base->height, "sub: ");
            if (sup)
                out->add(sup, center(sup, width), 0, "sup: ");
            return out;
        }
        int topSup = (base->baseline ? 0 : -1) - ph + 1,
            topSub = base->height - (base->descent() > 0 ? 1 : 0),
            top = sup ? std::min(0, topSup) : 0,
            bottom = sub ? std::max(base->height - 1, topSub + sh - 1) : base->height - 1;
        BoxPtr out = newBox(base->width + std::max(sw, pw), bottom - top + 1, base->baseline - top,
                            "scripts");
        out->add(base, 0, -top, "base: ");
        if (sub)
            out->add(sub, base->width, topSub - top, "sub: ");
        if (sup)
            out->add(sup, base->width, topSup - top, "sup: ");
        return out;
    }
    if (kind == Kind::Fraction) {
        BoxPtr numerator = typeset(*node.items[0], script),
               denominator = typeset(*node.items[1], script);
        if (!script) {
            int width = std::max(numerator->width, denominator->width) + 2;
            BoxPtr out = newBox(width, numerator->height + 1 + denominator->height,
                                numerator->height, "frac");
            out->add(numerator, center(numerator, width), 0, "num: ");
            out->add(denominator, center(denominator, width), numerator->height + 1, "den: ");
            out->draw(std::string(width, '-'), 0, numerator->height);
            return out;
        }
        if (node.items[0]->kind == Kind::Row || node.items[0]->kind == Kind::Fraction)
            numerator = delimit(numerator, "(", ")");
        if (node.items[1]->kind == Kind::Row || node.items[1]->kind == Kind::Fraction)
            denominator = delimit(denominator, "(", ")");
        BoxPtr slash = newBox(1, 1, 0, "atom \"/\"");
        slash->draw("/", 0, 0);
        return rowBox({numerator, slash, denominator}, {0, 0}, "slash", {"num: ", "", "den: "});
    }
    if (kind == Kind::Binomial) {
        BoxPtr upper = typeset(*node.items[0], script), lower = typeset(*node.items[1], script);
        int width = std::max(upper->width, lower->width),
            height = upper->height + 1 + lower->height;
        BoxPtr out = newBox(width + 2, height, upper->height, "binom");
        out->add(upper, center(upper, width) + 1, 0, "upper: ");
        out->add(lower, center(lower, width) + 1, upper->height + 1, "lower: ");
        drawDelimiter(out, "(", 0, height);
        drawDelimiter(out, ")", width + 1, height);
        return out;
    }
    if (kind == Kind::Overset || kind == Kind::Underset) {
        BoxPtr placed = typeset(*node.items[0], true), base = typeset(*node.items[1], script);
        int width = std::max(placed->width, base->width);
        bool over = kind == Kind::Overset;
        BoxPtr out =
            newBox(width, placed->height + base->height,
                   base->baseline + (over ? placed->height : 0), over ? "overset" : "underset");
        if (over) {
            out->add(placed, center(placed, width), 0, "over: ");
            out->add(base, center(base, width), placed->height, "base: ");
        } else {
            out->add(base, center(base, width), 0, "base: ");
            out->add(placed, center(placed, width), base->height, "under: ");
        }
        return out;
    }
    if (kind == Kind::SquareRoot || kind == Kind::Root) {
        BoxPtr body = typeset(*node.items.back(), script), index;
        int extra = 0, top = 0;
        if (kind == Kind::Root) {
            index = typeset(*node.items[0], true);
            extra = std::max(0, index->width - 1);
            top = std::max(0, index->height - body->height);
        }
        int height = body->height;
        BoxPtr out = newBox(extra + height + 1 + body->width, height + 1 + top,
                            body->baseline + 1 + top, index ? "root" : "sqrt");
        out->draw(std::string(body->width, '_'), extra + height + 1, top);
        out->draw("\\", extra, height + top);
        for (int r = 1; r <= height; ++r)
            out->draw("/", extra + height - r + 1, r + top);
        if (index) {
            out->add(index, 0, height - index->height + top, "index: ");
            out->add(body, extra + height + 1, 1 + top, "body: ");
        } else
            out->add(body, extra + height + 1, 1 + top);
        return out;
    }
    if (kind == Kind::Delimited)
        return delimit(typeset(*node.items[0], script), node.left, node.right);
    if (kind == Kind::Matrix) {
        int rows = static_cast<int>(node.rows.size()),
            columns = static_cast<int>(node.rows[0].size());
        std::vector<std::vector<BoxPtr>> cells;
        std::vector<int> widths(columns), ascents(rows), descents(rows), xs(columns), ys(rows);
        for (int i = 0; i < rows; ++i) {
            cells.push_back(boxes(node.rows[i], script));
            for (int j = 0; j < columns; ++j) {
                const BoxPtr &box = cells[i][j];
                widths[j] = std::max(widths[j], box->width);
                ascents[i] = std::max(ascents[i], box->baseline);
                descents[i] = std::max(descents[i], box->descent());
            }
        }
        int bodyWidth = 0, bodyHeight = 0;
        for (int j = 0; j < columns; ++j) {
            xs[j] = bodyWidth;
            bodyWidth += widths[j] + (j + 1 < columns ? params.colGap : 0);
        }
        for (int i = 0; i < rows; ++i) {
            ys[i] = bodyHeight;
            bodyHeight += ascents[i] + descents[i] + 1 + (i + 1 < rows ? params.rowGap : 0);
        }
        int shift = node.value == "matrix" ? 0 : 2,
            width = bodyWidth + (node.value == "matrix"  ? 0
                                 : node.value == "cases" ? 2
                                                         : 4);
        BoxPtr out = newBox(width, bodyHeight, (bodyHeight - 1) / 2,
                            text(node.value, " rows=", rows, " cols=", columns));
        for (int i = 0; i < rows; ++i)
            for (int j = 0; j < columns; ++j) {
                BoxPtr box = cells[i][j];
                int offset = node.value == "cases" ? 0 : center(box, widths[j]);
                out->add(box, xs[j] + offset + shift, ys[i] + ascents[i] - box->baseline,
                         text("cell ", i + 1, ",", j + 1, ": "));
            }
        if (node.value == "pmatrix") {
            drawDelimiter(out, "(", 0, bodyHeight);
            drawDelimiter(out, ")", bodyWidth + 3, bodyHeight);
        } else if (node.value == "bmatrix") {
            drawDelimiter(out, "[", 0, bodyHeight);
            drawDelimiter(out, "]", bodyWidth + 3, bodyHeight);
        } else if (node.value == "vmatrix") {
            drawDelimiter(out, "|", 0, bodyHeight);
            drawDelimiter(out, "|", bodyWidth + 3, bodyHeight);
        } else if (node.value == "cases")
            drawDelimiter(out, "\\{", 0, bodyHeight);
        return out;
    }
    BoxPtr body = typeset(*node.items[0], script);
    int width = body->width, baseline = body->baseline + 1;
    if (containsWord("hat dot tilde", node.value))
        width = std::max(width, 1);
    else if (node.value == "vec")
        width = std::max(width, 2);
    else if (containsWord("overbrace underbrace", node.value))
        width += 2;
    if (node.value == "underbrace")
        baseline = body->baseline;
    BoxPtr out = newBox(width, body->height + 1, baseline, node.value);
    if (node.value == "overline") {
        out->draw(std::string(body->width, '_'), 0, 0);
        out->add(body, 0, 1);
    } else if (containsWord("hat dot tilde", node.value)) {
        out->draw(node.value == "hat" ? "^" : node.value == "dot" ? "." : "~", (width - 1) / 2, 0);
        out->add(body, 0, 1);
    } else if (node.value == "vec") {
        out->draw(std::string(width - 1, '-') + ">", 0, 0);
        out->add(body, 0, 1);
    } else if (node.value == "overbrace") {
        out->draw("/" + std::string(body->width, '-') + "\\", 0, 0);
        out->add(body, 1, 1);
    } else {
        out->add(body, 1, 0);
        out->draw("\\" + std::string(body->width, '-') + "/", 0, body->height);
    }
    return out;
}
static void walkNode(const NodePtr &node, const std::function<void(const Node &)> &visit) {
    if (!node)
        return;
    visit(*node);
    for (const NodePtr &child : node->items)
        walkNode(child, visit);
    walkNode(node->base, visit);
    walkNode(node->sub, visit);
    walkNode(node->sup, visit);
    for (const Nodes &row : node->rows)
        for (const NodePtr &child : row)
            walkNode(child, visit);
}
static void collectWarnings(Formula &formula,
                            const std::map<std::string, std::string> &references) {
    for (const NodePtr &node : formula.nodes)
        walkNode(node, [&](const Node &child) {
            if (child.kind == Kind::Identifier && commandName(child.value))
                formula.warnings.push_back(
                    {child.column, child.value + " is a command name; write \\" + child.value});
            if (child.kind == Kind::Reference && !references.count(child.value))
                formula.warnings.push_back(
                    {child.column, "undefined reference \"" + child.value + "\""});
            if (child.kind == Kind::Delimited && child.left != "." && child.right != ".") {
                const std::map<std::string, std::string> pairs{
                    {"(", ")"}, {"[", "]"}, {"|", "|"}, {"\\{", "\\}"}};
                auto found = pairs.find(child.left);
                if (found == pairs.end() || found->second != child.right)
                    formula.warnings.push_back(
                        {child.rightColumn,
                         "\\left" + child.left + " closed by \\right" + child.right});
            }
        });
    std::sort(formula.warnings.begin(), formula.warnings.end(),
              [](const Issue &a, const Issue &b) { return a.column < b.column; });
}
static std::string constructName(Kind kind) {
    if (kind == Kind::Row)
        return "row";
    if (kind == Kind::Fraction)
        return "frac";
    if (kind == Kind::Binomial)
        return "binom";
    if (kind == Kind::Overset)
        return "overset";
    if (kind == Kind::Underset)
        return "underset";
    if (kind == Kind::SquareRoot)
        return "sqrt";
    return "root";
}
static std::string tree(const Node &node) {
    Kind kind = node.kind;
    if (kind == Kind::Identifier || kind == Kind::Number || kind == Kind::Command)
        return node.value;
    if (kind == Kind::Symbol)
        return "'" + node.value + "'";
    if (kind == Kind::Text)
        return "\"" + node.value + "\"";
    if (kind == Kind::Reference)
        return "(eqref \"" + node.value + "\")";
    if (kind == Kind::Script) {
        std::string out = node.sub ? (node.sup ? "(subsup " : "(sub ") : "(sup ";
        out += tree(*node.base);
        if (node.sub)
            out += " " + tree(*node.sub);
        if (node.sup)
            out += " " + tree(*node.sup);
        return out + ")";
    }
    if (kind == Kind::Delimited) {
        const auto quote = [](const std::string &value) {
            return value.size() == 1 ? "'" + value + "'" : value;
        };
        return "(delim " + quote(node.left) + " " + quote(node.right) + " " + tree(*node.items[0]) +
               ")";
    }
    if (kind == Kind::Matrix) {
        std::string out = "(" + node.value;
        for (const Nodes &row : node.rows) {
            Lines cells;
            for (const NodePtr &cell : row)
                cells.push_back(tree(*cell));
            out += " [" + join(cells) + "]";
        }
        return out + ")";
    }
    std::string out = "(" + (kind == Kind::Accent ? node.value : constructName(kind));
    for (const NodePtr &child : node.items)
        out += " " + tree(*child);
    return out + ")";
}
std::string Typesetter::linear(const Node &node, bool script) const {
    const auto parenthesize = [&](const NodePtr &child, bool mode, bool includeScript = false) {
        std::string value = linear(*child, mode);
        if (child->kind == Kind::Row || child->kind == Kind::Fraction ||
            (includeScript && child->kind == Kind::Script))
            return "(" + value + ")";
        return value;
    };
    Kind kind = node.kind;
    if (kind == Kind::Identifier || kind == Kind::Number || kind == Kind::Symbol ||
        kind == Kind::Text)
        return node.value;
    if (kind == Kind::Reference) {
        auto found = references.find(node.value);
        return found == references.end() ? "(??)" : found->second;
    }
    if (kind == Kind::Command)
        return symbolCommands().at(node.value).display;
    if (kind == Kind::Row) {
        std::vector<int> gaps = spacing(node.items, script, params).gaps;
        std::string out;
        for (std::size_t i = 0; i < node.items.size(); ++i) {
            if (i)
                out += std::string(gaps[i - 1], ' ');
            out += linear(*node.items[i], script);
        }
        return out;
    }
    if (kind == Kind::Fraction)
        return parenthesize(node.items[0], script) + "/" + parenthesize(node.items[1], script);
    if (kind == Kind::Binomial)
        return "binom(" + linear(*node.items[0], script) + ", " + linear(*node.items[1], script) +
               ")";
    if (kind == Kind::Overset || kind == Kind::Underset)
        return constructName(kind) + "(" + linear(*node.items[0], true) + ", " +
               linear(*node.items[1], script) + ")";
    if (kind == Kind::Script) {
        std::string out = parenthesize(node.base, script, true);
        if (node.sub)
            out += "_" + parenthesize(node.sub, true);
        if (node.sup)
            out += "^" + parenthesize(node.sup, true);
        return out;
    }
    if (kind == Kind::SquareRoot)
        return "sqrt(" + linear(*node.items[0], script) + ")";
    if (kind == Kind::Root)
        return "root(" + linear(*node.items[0], true) + ", " + linear(*node.items[1], script) + ")";
    if (kind == Kind::Delimited)
        return delimiterString(node.left) + linear(*node.items[0], script) +
               delimiterString(node.right);
    if (kind == Kind::Matrix) {
        Lines rows;
        for (const Nodes &row : node.rows) {
            Lines cells;
            for (const NodePtr &cell : row)
                cells.push_back(linear(*cell, script));
            rows.push_back(join(cells, ", "));
        }
        return node.value + "[" + join(rows, "; ") + "]";
    }
    return node.value + "(" + linear(*node.items[0], script) + ")";
}
struct Line {
    int start, end, indent, width;
};
static int lineWidth(const std::vector<BoxPtr> &boxes, const std::vector<int> &gaps, int start,
                     int end) {
    int width = 0;
    for (int i = start; i < end; ++i) {
        width += boxes[i]->width;
        if (i + 1 < end)
            width += gaps[i];
    }
    return width;
}
static std::vector<Line> breakLines(const Nodes &nodes, const std::vector<BoxPtr> &boxes,
                                    const Spacing &space, const Params &params, int mode) {
    std::set<int> breaks;
    int count = static_cast<int>(nodes.size());
    for (int i = 1; i < count; ++i)
        if (space.types[i].left == Type::Relation ||
            (mode >= 2 && nodes[i]->kind == Kind::Symbol &&
             (nodes[i]->value == "+" || nodes[i]->value == "-") &&
             space.types[i].left == Type::Binary) ||
            (mode == 3 && space.types[i - 1].right == Type::Punctuation))
            breaks.insert(i);
    std::vector<Line> out;
    int alignment = -1, relationWidth = 0;
    for (int start = 0; start < count;) {
        int indent = 0;
        if (start) {
            indent = params.indent;
            if (alignment >= 0)
                indent = alignment + (space.types[start].left == Type::Relation
                                          ? 0
                                          : relationWidth + params.relSpace);
        }
        int shortest = -1, chosen = -1;
        for (int end = start + 1; end <= count; ++end)
            if (end == count || breaks.count(end)) {
                if (shortest < 0)
                    shortest = end;
                if (indent + lineWidth(boxes, space.gaps, start, end) <= params.width)
                    chosen = end;
            }
        if (chosen < 0)
            chosen = shortest;
        out.push_back({start, chosen, indent, lineWidth(boxes, space.gaps, start, chosen)});
        if (!start)
            for (int i = 0; i < chosen; ++i)
                if (space.types[i].left == Type::Relation) {
                    alignment = lineWidth(boxes, space.gaps, 0, i) + (i ? space.gaps[i - 1] : 0);
                    relationWidth = boxes[i]->width;
                    break;
                }
        start = chosen;
    }
    return out;
}
struct PlacedFormula {
    std::vector<Placement> roots;
    std::vector<Line> lines;
    int width = 0, height = 0;
};
static PlacedFormula placeFormula(const Typesetter &typesetter, const Formula &formula) {
    Spacing space = spacing(formula.nodes, false, typesetter.params);
    std::vector<BoxPtr> boxes = typesetter.boxes(formula.nodes, false);
    PlacedFormula out;
    for (int mode = 1; mode <= 3; ++mode) {
        out.lines = breakLines(formula.nodes, boxes, space, typesetter.params, mode);
        bool fits = true;
        for (const Line &line : out.lines)
            if (line.indent + line.width > typesetter.params.width)
                fits = false;
        if (fits || mode == 3)
            break;
    }
    for (std::size_t i = 0; i < out.lines.size(); ++i) {
        const Line &line = out.lines[i];
        std::vector<BoxPtr> children(boxes.begin() + line.start, boxes.begin() + line.end);
        std::vector<int> gaps;
        if (line.end - line.start > 1)
            gaps.assign(space.gaps.begin() + line.start, space.gaps.begin() + line.end - 1);
        BoxPtr box = rowBox(children, gaps, text("line ", i + 1));
        out.roots.push_back({box, line.indent, out.height, ""});
        out.width = std::max(out.width, line.indent + box->width);
        out.height += box->height;
    }
    if (!formula.tagString.empty()) {
        BoxPtr tag = newBox(static_cast<int>(formula.tagString.size()), 1, 0,
                            "tag \"" + formula.tagString + "\"");
        tag->draw(formula.tagString, 0, 0);
        int x = typesetter.params.width - tag->width;
        const Placement &last = out.roots.back();
        int y = last.y + last.box->baseline;
        if (x < last.x + last.box->width + 2)
            y = out.height++;
        out.roots.push_back({tag, x, y, ""});
        out.width = std::max(out.width, x + tag->width);
    }
    return out;
}
static void diagnostic(Lines &out, const Formula &formula, const Issue &issue, bool warning) {
    out.push_back(text("formula ", formula.number, ", column ", issue.column, ": ",
                       warning ? "warning: " : "", issue.message));
    out.push_back("  " + formula.source);
    out.push_back(std::string(issue.column + 1, ' ') + "^");
}
static void writeLines(const std::string &name, const Lines &lines) {
    std::ofstream output("output/" + name);
    if (!output)
        throw std::runtime_error("cannot write " + name);
    for (const std::string &line : lines)
        output << line << '\n';
    if (!output)
        throw std::runtime_error("cannot write " + name);
}
int main() {
    Params params;
    for (const std::string &line : inputLines("input/params.txt")) {
        std::istringstream input(line);
        std::string name;
        int value;
        input >> name >> value;
        if (name == "width")
            params.width = value;
        else if (name == "indent")
            params.indent = value;
        else if (name == "rel_space")
            params.relSpace = value;
        else if (name == "bin_space")
            params.binSpace = value;
        else if (name == "punct_space")
            params.punctSpace = value;
        else if (name == "col_gap")
            params.colGap = value;
        else
            params.rowGap = value;
    }
    std::vector<Formula> formulas;
    for (const std::string &source : inputLines("input/formulas.txt")) {
        Formula formula;
        formula.number = static_cast<int>(formulas.size() + 1);
        formula.source = source;
        Lexed lexed = tokenize(source);
        formula.tokens = std::move(lexed.tokens);
        formula.error = lexed.error;
        if (!formula.error)
            formula.error = checkBraces(formula.tokens);
        if (!formula.error) {
            Parser parser{formula.tokens, 0, static_cast<int>(source.size() + 1), {}, {}};
            try {
                formula.nodes = parser.elements(true, false);
                if (parser.peek().kind != Kind::Eof)
                    parser.unexpected(parser.peek());
                formula.tag = parser.tag;
                formula.label = parser.label;
            } catch (const Issue &issue) {
                formula.error = issue;
            }
        }
        formulas.push_back(std::move(formula));
    }
    int counter = 0;
    Typesetter typesetter;
    typesetter.params = params;
    for (Formula &formula : formulas)
        if (!formula.error) {
            if (formula.tag)
                formula.tagString = "(" + formula.tag->value + ")";
            else if (formula.label)
                formula.tagString = text("(", ++counter, ")");
        }
    for (Formula &formula : formulas)
        if (!formula.error && formula.label) {
            if (!typesetter.references.emplace(formula.label->value, formula.tagString).second)
                formula.warnings.push_back(
                    {formula.label->column, "duplicate label \"" + formula.label->value + "\""});
        }
    Lines rendered, boxesReport, trees, errors;
    int totalBoxes = 0, maxDepth = 0, valid = 0, warningCount = 0, overfullCount = 0;
    std::map<std::string, int> kinds;
    for (Formula &formula : formulas) {
        if (formula.number > 1)
            rendered.push_back("");
        rendered.push_back(text("formula ", formula.number));
        if (formula.error) {
            rendered.push_back("(error)");
            boxesReport.push_back(text("formula ", formula.number, ": error"));
            trees.push_back(text("formula ", formula.number, ": error"));
            diagnostic(errors, formula, *formula.error, false);
            continue;
        }
        ++valid;
        collectWarnings(formula, typesetter.references);
        warningCount += static_cast<int>(formula.warnings.size());
        for (const Issue &warning : formula.warnings)
            diagnostic(errors, formula, warning, true);
        PlacedFormula placed = placeFormula(typesetter, formula);
        append(rendered, drawCanvas(placed.roots, placed.width, placed.height));
        BoxDescription description = describeBoxes(placed.roots);
        totalBoxes += static_cast<int>(description.lines.size());
        maxDepth = std::max(maxDepth, description.depth);
        for (const auto &entry : description.kinds)
            kinds[entry.first] += entry.second;
        boxesReport.push_back(text("formula ", formula.number, ": lines=", placed.lines.size(),
                                   " width=", placed.width, " height=", placed.height, " boxes=",
                                   description.lines.size(), " depth=", description.depth));
        append(boxesReport, description.lines);
        Lines parts;
        for (const NodePtr &node : formula.nodes)
            parts.push_back(tree(*node));
        trees.push_back(text("formula ", formula.number, ": ", join(parts)));
        Node row;
        row.items = formula.nodes;
        std::string linear = trimRight(typesetter.linear(row, false));
        trees.push_back(linear.empty() ? "  linear:" : "  linear: " + linear);
        if (!formula.tagString.empty())
            trees.push_back("  tag: " + formula.tagString);
        for (std::size_t i = 0; i < placed.lines.size(); ++i) {
            const Line &line = placed.lines[i];
            if (line.indent + line.width > params.width) {
                ++overfullCount;
                errors.push_back(text("formula ", formula.number, ": line ", i + 1,
                                      " is overfull (width ", line.indent + line.width, " > ",
                                      params.width, ")"));
            }
        }
    }
    boxesReport.push_back(text("summary: boxes=", totalBoxes, " max_depth=", maxDepth));
    for (const auto &entry : kinds)
        boxesReport.push_back(text("  ", entry.first, ": ", entry.second));
    errors.push_back(text("formulas=", formulas.size(), " rendered=", valid,
                          " errors=", formulas.size() - valid, " warnings=", warningCount,
                          " overfull=", overfullCount));
    std::filesystem::create_directories("output");
    writeLines("rendered.txt", rendered);
    writeLines("boxes.txt", boxesReport);
    writeLines("trees.txt", trees);
    writeLines("errors.txt", errors);
}
