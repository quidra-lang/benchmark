#include "formula.hpp"
const std::map<std::string, SymbolInfo> &symbolCommands() {
    static const std::map<std::string, SymbolInfo> table = [] {
        std::map<std::string, SymbolInfo> out;
        std::istringstream greek(
            "alpha beta gamma delta epsilon zeta eta theta iota kappa lambda mu nu xi pi rho sigma tau upsilon phi chi psi omega Gamma Delta Theta Lambda Xi Pi Sigma Upsilon Phi Psi Omega");
        for (std::string name; greek >> name;)
            out["\\" + name] = {name, Type::Ordinary};
        std::istringstream functions("sin cos tan log ln exp det lim max min sum prod int");
        for (std::string name; functions >> name;)
            out["\\" + name] = {name, Type::Operator};
        for (const auto &entry : std::map<std::string, std::string>{
                 {"cdot", "*"}, {"times", "x"}, {"pm", "+-"}, {"mp", "-+"}})
            out["\\" + entry.first] = {entry.second, Type::Binary};
        for (const auto &entry : std::map<std::string, std::string>{
                 {"leq", "<="}, {"geq", ">="}, {"neq", "!="}, {"approx", "~="}, {"to", "->"}})
            out["\\" + entry.first] = {entry.second, Type::Relation};
        for (const auto &entry : std::map<std::string, std::string>{
                 {"infty", "oo"}, {"ldots", "..."}, {"cdots", "..."}, {"quad", "  "}, {",", " "}})
            out["\\" + entry.first] = {entry.second, Type::Ordinary};
        out["\\{"] = {"{", Type::Open};
        out["\\}"] = {"}", Type::Close};
        return out;
    }();
    return table;
}
BoxPtr newBox(int width, int height, int baseline, std::string description) {
    BoxPtr out = std::make_shared<Box>();
    out->width = width;
    out->height = height;
    out->baseline = baseline;
    out->description = std::move(description);
    return out;
}
void Box::add(BoxPtr child, int x, int y, std::string role) {
    children.push_back({std::move(child), x, y, std::move(role)});
}
void Box::draw(std::string value, int x, int y) { drawn.push_back({std::move(value), x, y}); }
int center(const BoxPtr &box, int width) { return (width - box->width) / 2; }
void drawDelimiter(const BoxPtr &box, const std::string &value, int x, int height) {
    if (value == ".")
        return;
    char actual = value.back();
    for (int y = 0; y < height; ++y) {
        char glyph = actual;
        if (height >= 2 && std::string("(){}").find(actual) != std::string::npos) {
            glyph = '|';
            if (!y)
                glyph = (actual == '(' || actual == '{') ? '/' : '\\';
            if (y == height - 1)
                glyph = (actual == '(' || actual == '{') ? '\\' : '/';
            if (height >= 3 && y == (height - 1) / 2 && (actual == '{' || actual == '}'))
                glyph = actual == '{' ? '<' : '>';
        }
        box->draw(std::string(1, glyph), x, y);
    }
}
std::string delimiterString(const std::string &value) {
    return value == "." ? "" : value.substr(value.size() - 1);
}
BoxPtr delimit(BoxPtr body, const std::string &left, const std::string &right) {
    int wl = left == "." ? 0 : 1, wr = right == "." ? 0 : 1;
    BoxPtr out =
        newBox(wl + body->width + wr, body->height, body->baseline, "delim " + left + " " + right);
    out->add(body, wl, 0);
    drawDelimiter(out, left, 0, body->height);
    drawDelimiter(out, right, wl + body->width, body->height);
    return out;
}
BoxPtr atomBox(const Node &node, bool script,
               const std::map<std::string, std::string> &references) {
    std::string display = node.value, description = "atom \"" + node.value + "\"";
    if (node.kind == Kind::Text)
        description = "text \"" + node.value + "\"";
    if (node.kind == Kind::Reference) {
        description = "eqref \"" + node.value + "\"";
        auto found = references.find(node.value);
        display = found == references.end() ? "(??)" : found->second;
    }
    if (node.kind == Kind::Command) {
        display = symbolCommands().at(node.value).display;
        static const std::map<std::string, Lines> large{{"\\sum", {"\\--", " > ", "/--"}},
                                                        {"\\prod", {"___", "| |", "| |"}},
                                                        {"\\int", {" /", " |", "/ "}}};
        auto found = large.find(node.value);
        if (!script && found != large.end()) {
            BoxPtr out = newBox(static_cast<int>(found->second[0].size()), 3, 1, description);
            for (int y = 0; y < 3; ++y)
                out->draw(found->second[y], 0, y);
            return out;
        }
    }
    BoxPtr out = newBox(static_cast<int>(display.size()), 1, 0, description);
    out->draw(display, 0, 0);
    return out;
}
