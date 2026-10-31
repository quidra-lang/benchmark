#include "raster.hpp"
#include <algorithm>
#include <cctype>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <map>
#include <sstream>

template<class... Args> static std::string line(const Args&... args) { std::ostringstream out; bool first = true; ((out << (first ? "" : " ") << args,first = false),...); return out.str(); }
static std::string join(const Lines& values) { std::string result; for (const std::string& value : values) { if (!result.empty()) result += ' '; result += value; } return result; }
static Lines words(const std::string& text) { Lines result; std::istringstream input(text); std::string word; while (input >> word) result.push_back(word); return result; }
static Lines readLines(const std::string& name) { std::ifstream input("input/" + name); Lines result; std::string text; while (std::getline(input,text)) result.push_back(text); return result; }
static void writeLines(const std::string& name, const Lines& values) { std::ofstream output("output/" + name); for (const std::string& value : values) output << value << '\n'; }
bool Rect::empty() const { return x0 > x1 || y0 > y1; }
bool Rect::contains(Point point) const { return x0 <= point.x && point.x <= x1 && y0 <= point.y && point.y <= y1; }
Rect Rect::intersect(Rect other) const { return {std::max(x0,other.x0),std::max(y0,other.y0),std::min(x1,other.x1),std::min(y1,other.y1)}; }
static Pixels rectPixels(Rect rect) { Pixels result; for (int y = rect.y0; y <= rect.y1; ++y) for (int x = rect.x0; x <= rect.x1; ++x) result.insert({x,y}); return result; }
static std::optional<Rect> bounds(const Pixels& pixels) { if (pixels.empty()) return std::nullopt; Point first = *pixels.begin(); Rect box{first.x,first.y,first.x,first.y}; for (Point point : pixels) { box.x0 = std::min(box.x0,point.x); box.y0 = std::min(box.y0,point.y); box.x1 = std::max(box.x1,point.x); box.y1 = std::max(box.y1,point.y); } return box; }
static std::string boxText(const std::optional<Rect>& box) { return box ? line(box->x0,box->y0,box->x1,box->y1) : "none"; }
template<std::size_t N> static std::string colorText(const std::array<int, N>& color) { Lines values; for (int component : color) values.push_back(std::to_string(component)); return join(values); }
template<class ColorType> static std::vector<std::pair<ColorType, int>> ranked(const std::map<ColorType, int>& counts) {
    std::vector<std::pair<ColorType, int>> result(counts.begin(),counts.end()); std::sort(result.begin(),result.end(),[](const auto& a, const auto& b) { return a.second != b.second ? a.second > b.second : a.first < b.first; }); return result;
}
static bool integerWord(const std::string& text) { std::size_t first = !text.empty() && text[0] == '-' ? 1 : 0; return first < text.size() && std::all_of(text.begin() + first,text.end(),[](char c) { return c >= '0' && c <= '9'; }); }
static bool allIntegers(const Lines& values, std::size_t first) { return std::all_of(values.begin() + first,values.end(),integerWord); }
struct Pen { int width; std::string color; int on, off; };
struct Brush { Lines colors; std::string axis, rule; };
struct Styles { std::map<std::string, Color> colors; std::map<std::string, Pen> pens; std::map<std::string, Brush> brushes; };
struct Font { int width, height; std::map<char, Points> glyphs; };
struct Node { bool repeat = false; int line = 0, count = 0, dx = 0, dy = 0; std::string keyword; Lines arguments; std::vector<Node> body; };
struct Block { std::string name; int opacity = 0; std::string mode; int endLine = 0; std::vector<Node> body; };
struct Scene { int width = 0, height = 0; std::string background; std::vector<Block> layers; std::map<std::string, Block> symbols; };
struct Probe { std::string kind; std::vector<int> values; };
struct PathCommand { char letter; std::vector<int> values; };
struct Subpath { Points points; bool closed = false; };
struct Execution { int sequence, layer; const Node* command; std::string kind, error; int pixels = 0; std::optional<Rect> box; };
static const std::set<std::string> PenCommands{"LINE","RECT","CIRCLE","ELLIPSE","POLYLINE","POLYGON","PATH"};
static const std::set<std::string> BrushCommands{"FILLRECT","FILLCIRCLE","FILLELLIPSE","FILLPOLYGON","FILLPATH","FLOOD","TEXT"};
static const std::set<std::string> StateCommands{"TRANSLATE","SCALE","ROTATE","SAVE","RESTORE","CLIP","NOCLIP","USE"};
static const Lines ErrorNames{"unknown_command","bad_arguments","unknown_style","unknown_symbol","unknown_glyph","bad_value","stack_empty"};
static std::optional<std::vector<PathCommand>> parsePath(const Lines& values, std::size_t first) {
    const std::map<char, int> arities{{'M',2},{'L',2},{'H',1},{'V',1},{'Q',4},{'C',6},{'Z',0}}; std::vector<PathCommand> result;
    for (std::size_t i = first; i < values.size();) {
        if (values[i].size() != 1) return std::nullopt; char letter = values[i][0], upper = std::toupper(static_cast<unsigned char>(letter)); auto found = arities.find(upper);
        if (found == arities.end() || (letter != upper && letter != static_cast<char>(std::tolower(upper)))) return std::nullopt;
        if ((result.empty() || std::toupper(result.back().letter) == 'Z') && upper != 'M') return std::nullopt;
        if (i + found->second >= values.size()) return std::nullopt; PathCommand command{letter,{}};
        for (int j = 1; j <= found->second; ++j) { if (!integerWord(values[i + j])) return std::nullopt; command.values.push_back(std::stoi(values[i + j])); } result.push_back(command); i += 1 + found->second;
    } return result.empty() ? std::nullopt : std::optional<std::vector<PathCommand>>(result);
}
static bool validForm(const std::string& keyword, const Lines& arguments) {
    const std::map<std::string, std::pair<int, int>> fixed{{"LINE",{5,1}},{"RECT",{5,1}},{"FILLRECT",{5,1}},{"CIRCLE",{4,1}},{"FILLCIRCLE",{4,1}},{"ELLIPSE",{5,1}},{"FILLELLIPSE",{5,1}},{"FLOOD",{3,1}},{"ERASE",{4,0}},{"TRANSLATE",{2,0}},{"SCALE",{2,0}},{"ROTATE",{1,0}},{"SAVE",{0,0}},{"RESTORE",{0,0}},{"NOCLIP",{0,0}},{"CLIP",{4,0}},{"USE",{3,1}}};
    auto found = fixed.find(keyword); if (found != fixed.end()) return static_cast<int>(arguments.size()) == found->second.first && allIntegers(arguments,found->second.second);
    if (keyword == "TEXT") return arguments.size() == 5 && integerWord(arguments[1]) && integerWord(arguments[2]);
    if (keyword == "POLYLINE" || keyword == "POLYGON" || keyword == "FILLPOLYGON") return arguments.size() >= 2 && allIntegers(arguments,1) && static_cast<int>(arguments.size()) == 2 + 2 * std::stoi(arguments[1]);
    return arguments.size() >= 2 && integerWord(arguments[1]) && parsePath(arguments,2).has_value();
}
using Matrix = std::array<int, 6>;
struct DrawingState {
    Rect screen, clip;
    Matrix matrix{1,0,0,1,0,0};
    std::vector<std::pair<Matrix, Rect>> stack;
    explicit DrawingState(Rect screen) : screen(screen), clip(screen) {}
    Point transform(int x, int y) const { return {matrix[0] * x + matrix[1] * y + matrix[4],matrix[2] * x + matrix[3] * y + matrix[5]}; }
    Rect deviceRect(int x0, int y0, int x1, int y1) const { Point a = transform(x0,y0), b = transform(x1,y1); return {std::min(a.x,b.x),std::min(a.y,b.y),std::max(a.x,b.x),std::max(a.y,b.y)}; }
    Point radii(int rx, int ry) const { return {std::abs(matrix[0]) * rx + std::abs(matrix[1]) * ry,std::abs(matrix[2]) * rx + std::abs(matrix[3]) * ry}; }
    void translate(int dx, int dy) { matrix[4] += matrix[0] * dx + matrix[1] * dy; matrix[5] += matrix[2] * dx + matrix[3] * dy; }
    void scale(int sx, int sy) { matrix[0] *= sx; matrix[2] *= sx; matrix[1] *= sy; matrix[3] *= sy; }
    void rotate(int turns) { for (int q = (turns % 4 + 4) % 4; q > 0; --q) { Matrix m = matrix; matrix = {m[1],-m[0],m[3],-m[2],m[4],m[5]}; } }
};
static Segments segments(const Points& points, bool closed) { Segments result; for (std::size_t i = 1; i < points.size(); ++i) result.push_back({points[i - 1],points[i]}); if (closed && !points.empty()) result.push_back({points.back(),points.front()}); return result; }
class Renderer {
    const Scene& scene;
    const Styles& styles;
    const Font& font;
    Rect screen;
    DrawingState state;
    Layer* layer = nullptr;
    void executeBody(const std::vector<Node>& body) {
        for (const Node& node : body) if (node.repeat) { DrawingState saved = state; for (int k = 0; k < node.count; ++k) { state = saved; state.translate(k * node.dx,k * node.dy); executeBody(node.body); } state = saved; } else execute(node);
    }
    std::string check(const Node& command) const {
        const std::string& k = command.keyword; const Lines& a = command.arguments;
        if (!PenCommands.count(k) && !BrushCommands.count(k) && !StateCommands.count(k) && k != "ERASE") return "unknown_command";
        if (!validForm(k,a)) return "bad_arguments";
        if ((PenCommands.count(k) && !styles.pens.count(a[0])) || (BrushCommands.count(k) && !styles.brushes.count(a[0]))) return "unknown_style";
        if (k == "USE") { auto found = scene.symbols.find(a[0]); if (found == scene.symbols.end() || found->second.endLine >= command.line) return "unknown_symbol"; }
        if (k == "TEXT") for (char c : a[4]) if (c != '_' && !font.glyphs.count(c)) return "unknown_glyph";
        if (k == "RESTORE" && state.stack.empty()) return "stack_empty";
        auto n = [&](int index) { return std::stoi(a[index]); }; bool valid = true;
        if (k == "CIRCLE" || k == "FILLCIRCLE") valid = n(3) >= 1;
        else if (k == "ELLIPSE" || k == "FILLELLIPSE") valid = n(3) >= 1 && n(4) >= 1;
        else if (k == "POLYLINE") valid = n(1) >= 2;
        else if (k == "POLYGON" || k == "FILLPOLYGON") valid = n(1) >= 3;
        else if (k == "PATH" || k == "FILLPATH") valid = n(1) >= 1 && n(1) <= 32;
        else if (k == "FLOOD") valid = state.clip.contains(state.transform(n(1),n(2)));
        else if (k == "TEXT") valid = a[3] == "left" || a[3] == "center" || a[3] == "right";
        else if (k == "SCALE") valid = n(0) != 0 && n(1) != 0;
        else if (k == "CLIP") valid = !state.deviceRect(n(0),n(1),n(2),n(3)).intersect(state.clip).empty();
        return valid ? "" : "bad_value";
    }
    void applyState(const Node& command) {
        const std::string& k = command.keyword; const Lines& a = command.arguments; auto n = [&](int index) { return std::stoi(a[index]); };
        if (k == "TRANSLATE") state.translate(n(0),n(1)); else if (k == "SCALE") state.scale(n(0),n(1)); else if (k == "ROTATE") state.rotate(n(0));
        else if (k == "SAVE") state.stack.push_back({state.matrix,state.clip}); else if (k == "RESTORE") { auto saved = state.stack.back(); state.stack.pop_back(); state.matrix = saved.first; state.clip = saved.second; }
        else if (k == "CLIP") state.clip = state.deviceRect(n(0),n(1),n(2),n(3)).intersect(state.clip); else if (k == "NOCLIP") state.clip = screen;
        else { DrawingState saved = state; state.translate(n(1),n(2)); executeBody(scene.symbols.at(a[0]).body); state = saved; }
    }
    Pixels expand(const Points& points, int width) const { Pixels result; for (Point point : points) for (Point pixel : expandSquare(point,width)) if (state.clip.contains(pixel)) result.insert(pixel); return result; }
    Pixels stroke(const Pen& pen, const Segments& edges) const {
        Points points; for (const Segment& edge : edges) { auto clipped = clipSegment(edge.first,edge.second,state.clip); if (clipped) { Points line = bresenham(clipped->first,clipped->second); points.insert(points.end(),line.begin(),line.end()); } }
        if (pen.off) { Points kept; for (std::size_t i = 0; i < points.size(); ++i) if (i % (pen.on + pen.off) < static_cast<std::size_t>(pen.on)) kept.push_back(points[i]); points = std::move(kept); } return expand(points,pen.width);
    }
    Points vertices(const Lines& a) const { Points result; for (std::size_t i = 2; i < a.size(); i += 2) result.push_back(state.transform(std::stoi(a[i]),std::stoi(a[i + 1]))); return result; }
    std::pair<Point, Pixels> shape(const std::string& keyword, const Lines& a) const {
        Point center = state.transform(std::stoi(a[1]),std::stoi(a[2])); bool circle = keyword == "CIRCLE" || keyword == "FILLCIRCLE"; Point r = state.radii(std::stoi(a[3]),std::stoi(a[circle ? 3 : 4])); return {center,circle && r.x == r.y ? circlePoints(r.x) : ellipsePoints(r.x,r.y)};
    }
    std::vector<Subpath> subpaths(const Lines& a) const {
        std::vector<Subpath> paths; Point current{0,0}, start{0,0}; int divisions = std::stoi(a[1]); auto parsed = parsePath(a,2);
        for (const PathCommand& command : *parsed) {
            char kind = std::toupper(command.letter); if (kind == 'Z') { paths.back().closed = true; current = start; continue; }
            bool relative = std::islower(command.letter); int ox = relative ? current.x : 0, oy = relative ? current.y : 0; Points user;
            if (kind == 'H') user.push_back({command.values[0] + ox,current.y}); else if (kind == 'V') user.push_back({current.x,command.values[0] + oy});
            else for (std::size_t i = 0; i < command.values.size(); i += 2) user.push_back({command.values[i] + ox,command.values[i + 1] + oy});
            Points device; for (Point point : user) device.push_back(state.transform(point.x,point.y));
            if (kind == 'M') { paths.push_back({{device[0]},false}); start = user[0]; }
            else if (kind == 'L' || kind == 'H' || kind == 'V') paths.back().points.push_back(device[0]);
            else { Points controls{paths.back().points.back()}; controls.insert(controls.end(),device.begin(),device.end()); Points curve = bezierPoints(controls,divisions); paths.back().points.insert(paths.back().points.end(),curve.begin() + 1,curve.end()); } current = user.back();
        } return paths;
    }
    Pixels textCoverage(const Lines& a) const {
        int x = std::stoi(a[1]), y = std::stoi(a[2]), advance = font.width + 1, extent = a[4].size() * advance - 1; int left = a[3] == "left" ? x : a[3] == "center" ? x - extent / 2 : x - extent + 1; Pixels result;
        for (int i = 0; i < static_cast<int>(a[4].size()); ++i) if (a[4][i] != '_') for (Point dot : font.glyphs.at(a[4][i])) { Rect rect = state.deviceRect(left + i * advance + dot.x,y + dot.y,left + i * advance + dot.x + 1,y + dot.y + 1); --rect.x1; --rect.y1; Pixels pixels = rectPixels(rect.intersect(state.clip)); result.insert(pixels.begin(),pixels.end()); } return result;
    }
    Pixels coverage(const Node& command) const {
        const std::string& k = command.keyword; const Lines& a = command.arguments;
        if (k == "ERASE") { Rect rect = state.deviceRect(std::stoi(a[0]),std::stoi(a[1]),std::stoi(a[2]),std::stoi(a[3])).intersect(state.clip); Pixels result; for (Point pixel : rectPixels(rect)) if (layer->erase(pixel)) result.insert(pixel); return result; }
        if (k == "CIRCLE" || k == "ELLIPSE" || k == "FILLCIRCLE" || k == "FILLELLIPSE") { auto value = shape(k,a); if (BrushCommands.count(k)) return fillShape(value.first,value.second,state.clip); Points points; for (Point offset : value.second) points.push_back({value.first.x + offset.x,value.first.y + offset.y}); return expand(points,styles.pens.at(a[0]).width); }
        if (k == "FILLRECT") return rectPixels(state.deviceRect(std::stoi(a[1]),std::stoi(a[2]),std::stoi(a[3]),std::stoi(a[4])).intersect(state.clip));
        if (k == "FLOOD") return floodFill(*layer,state.transform(std::stoi(a[1]),std::stoi(a[2])),state.clip); if (k == "TEXT") return textCoverage(a);
        if (k == "FILLPOLYGON") return fillPolygons({clipPolygon(vertices(a),state.clip)},styles.brushes.at(a[0]).rule,state.clip);
        if (k == "FILLPATH") { std::vector<Points> sequences; for (const Subpath& path : subpaths(a)) sequences.push_back(clipPolygon(path.points,state.clip)); return fillPolygons(sequences,styles.brushes.at(a[0]).rule,state.clip); }
        Segments edges;
        if (k == "LINE") edges.push_back({state.transform(std::stoi(a[1]),std::stoi(a[2])),state.transform(std::stoi(a[3]),std::stoi(a[4]))});
        else if (k == "RECT") { Rect r = state.deviceRect(std::stoi(a[1]),std::stoi(a[2]),std::stoi(a[3]),std::stoi(a[4])); edges = segments({{r.x0,r.y0},{r.x1,r.y0},{r.x1,r.y1},{r.x0,r.y1}},true); }
        else if (k == "POLYGON" || k == "POLYLINE") edges = segments(vertices(a),k == "POLYGON");
        else for (const Subpath& path : subpaths(a)) { Segments next = segments(path.points,path.closed); edges.insert(edges.end(),next.begin(),next.end()); } return stroke(styles.pens.at(a[0]),edges);
    }
    void execute(const Node& command) {
        std::size_t index = executions.size(); executions.push_back({static_cast<int>(index) + 1,static_cast<int>(layers.size()),&command,"","",0,std::nullopt}); std::string error = check(command);
        if (!error.empty()) { executions[index].kind = "error"; executions[index].error = error; return; }
        if (StateCommands.count(command.keyword)) { executions[index].kind = "state"; applyState(command); return; }
        Pixels pixels = coverage(command); executions[index].kind = "drawing"; executions[index].pixels = pixels.size(); executions[index].box = bounds(pixels); if (command.keyword == "ERASE") return;
        if (PenCommands.count(command.keyword)) { Color color = styles.colors.at(styles.pens.at(command.arguments[0]).color); for (Point pixel : pixels) layer->paint(pixel,color,command.line); }
        else { const Brush& brush = styles.brushes.at(command.arguments[0]); Color first = styles.colors.at(brush.colors[0]); auto box = bounds(pixels); for (Point pixel : pixels) { Color color = first; if (!brush.axis.empty()) { const Color& second = styles.colors.at(brush.colors[1]); int offset = brush.axis == "x" ? pixel.x - box->x0 : pixel.y - box->y0, length = brush.axis == "x" ? box->x1 - box->x0 : box->y1 - box->y0; if (length) for (int c = 0; c < 4; ++c) color[c] += roundRatio((second[c] - first[c]) * offset,length); } layer->paint(pixel,color,command.line); } }
    }
public:
    std::vector<Layer> layers;
    std::vector<Execution> executions;
    Renderer(const Scene& scene, const Styles& styles, const Font& font) : scene(scene), styles(styles), font(font), screen{0,0,scene.width - 1,scene.height - 1}, state(screen) {}
    void run() { for (const Block& block : scene.layers) { layers.emplace_back(scene.width,scene.height,block.opacity,block.mode); layer = &layers.back(); state = DrawingState(screen); executeBody(block.body); } }
};
static Styles readStyles() {
    Styles styles; for (const std::string& text : readLines("styles.txt")) {
        if (text.empty() || text[0] == '#') continue; Lines p = words(text);
        if (p[0] == "color") styles.colors[p[1]] = {std::stoi(p[2]),std::stoi(p[3]),std::stoi(p[4]),std::stoi(p[5])};
        else if (p[0] == "pen") styles.pens[p[1]] = {std::stoi(p[2]),p[3],std::stoi(p[4]),std::stoi(p[5])};
        else if (p[0] == "brush") styles.brushes[p[1]] = {{p[2]},"",p[3]}; else styles.brushes[p[1]] = {{p[2],p[3]},p[4],p[5]};
    } return styles;
}
static Font readFont() {
    Lines input = readLines("font.txt"), header = words(input[0]); Font font{std::stoi(header[1]),std::stoi(header[2]),{}};
    for (int i = 1; i < static_cast<int>(input.size()); i += font.height + 1) { Points dots; for (int y = 0; y < font.height; ++y) for (int x = 0; x < font.width; ++x) if (input[i + 1 + y][x] == '#') dots.push_back({x,y}); font.glyphs[words(input[i])[1][0]] = dots; } return font;
}
static Scene readScene() {
    Scene scene; Lines input = readLines("scene.txt"); Block* block = nullptr; std::vector<std::vector<Node>*> bodies;
    for (int i = 0; i < static_cast<int>(input.size()); ++i) {
        Lines p = words(input[i]); if (p.empty() || p[0][0] == '#') continue; const std::string& k = p[0];
        if (k == "CANVAS") { scene.width = std::stoi(p[1]); scene.height = std::stoi(p[2]); scene.background = p[3]; }
        else if (k == "LAYER") { scene.layers.push_back({p[1],std::stoi(p[2]),p[3],0,{}}); block = &scene.layers.back(); bodies = {&block->body}; }
        else if (k == "SYMBOL") { block = &scene.symbols[p[1]]; block->name = p[1]; bodies = {&block->body}; }
        else if (k == "END") { block->endLine = i + 1; bodies.clear(); }
        else if (k == "REPEAT") { bodies.back()->push_back({true,i + 1,std::stoi(p[1]),std::stoi(p[2]),std::stoi(p[3]),"",{},{}}); bodies.push_back(&bodies.back()->back().body); }
        else if (k == "ENDREPEAT") bodies.pop_back(); else bodies.back()->push_back({false,i + 1,0,0,0,k,Lines(p.begin() + 1,p.end()),{}});
    } return scene;
}
static std::vector<Probe> readProbes() { Lines input = readLines("probes.txt"); std::vector<Probe> probes; for (int i = 1; i <= std::stoi(input[0]); ++i) { Lines p = words(input[i]); Probe probe{p[0],{}}; for (std::size_t j = 1; j < p.size(); ++j) probe.values.push_back(std::stoi(p[j])); probes.push_back(probe); } return probes; }
static Lines commandLines(const std::vector<Execution>& executions) {
    Lines result; for (const Execution& execution : executions) { std::string head = line("cmd",execution.sequence,"line",execution.command->line,execution.command->keyword); if (execution.kind == "error") result.push_back(head + " error " + execution.error); else if (execution.kind == "drawing") result.push_back(head + " " + line("pixels",execution.pixels,"box",boxText(execution.box))); else result.push_back(head + " ok"); } return result;
}
static Lines layerLines(const Scene& scene, const std::vector<Layer>& layers, const std::vector<Execution>& executions) {
    std::vector<int> visible(layers.size()); for (int y = 0; y < scene.height; ++y) for (int x = 0; x < scene.width; ++x) { bool covered = false; for (int i = static_cast<int>(layers.size()) - 1; i >= 0; --i) { int alpha = layers[i].alphaAt({x,y}); if (alpha > 0 && !covered) ++visible[i]; if (alpha == 255) covered = true; } }
    Lines result{line("layers",layers.size())}; for (int i = 0; i < static_cast<int>(layers.size()); ++i) {
        const Block& block = scene.layers[i]; const Layer& layer = layers[i]; int commands = 0, errors = 0; for (const Execution& execution : executions) if (execution.layer == i + 1) { ++commands; if (execution.kind == "error") ++errors; }
        Pixels painted; std::map<Color, int> counts; for (int y = 0; y < scene.height; ++y) for (int x = 0; x < scene.width; ++x) { const auto& color = layer.colorAt({x,y}); if (color) { painted.insert({x,y}); ++counts[*color]; } }
        result.push_back(line("layer",i + 1,block.name,"opacity",block.opacity,"mode",block.mode,"commands",commands,"errors",errors,"pixels",painted.size(),"box",boxText(bounds(painted)),"visible",visible[i],"colors",counts.size())); auto colors = ranked(counts);
        for (int j = 0; j < std::min<int>(5,colors.size()); ++j) result.push_back(line("color",colorText(colors[j].first),"pixels",colors[j].second));
    } return result;
}
static Lines summaryLines(const Scene& scene, const Styles& styles, const std::vector<Execution>& executions, const Image& image) {
    std::map<std::string, int> kinds, errors, uses; std::map<std::string, std::array<int, 3>> keywords; std::set<std::string> usedPens, usedBrushes, usedColors{scene.background}; int painted = 0, erased = 0;
    for (const auto& symbol : scene.symbols) uses[symbol.first] = 0;
    for (const Execution& execution : executions) {
        const Node& command = *execution.command; ++kinds[execution.kind]; auto& tally = keywords[command.keyword]; ++tally[0];
        if (execution.kind == "error") { ++errors[execution.error]; ++tally[1]; }
        else if (execution.kind == "drawing") { tally[2] += execution.pixels; if (command.keyword == "ERASE") erased += execution.pixels; else painted += execution.pixels; if (PenCommands.count(command.keyword)) usedPens.insert(command.arguments[0]); else if (BrushCommands.count(command.keyword)) usedBrushes.insert(command.arguments[0]); }
        else if (command.keyword == "USE") ++uses[command.arguments[0]];
    }
    for (const std::string& name : usedPens) usedColors.insert(styles.pens.at(name).color); for (const std::string& name : usedBrushes) for (const std::string& color : styles.brushes.at(name).colors) usedColors.insert(color);
    const Color& background = styles.colors.at(scene.background); Lines result{line("canvas",scene.width,scene.height),line("background",background[0],background[1],background[2]),line("layers",scene.layers.size()),line("symbols",scene.symbols.size()),line("commands",executions.size()),line("drawing",kinds["drawing"]),line("state",kinds["state"]),line("errors",kinds["error"])};
    for (const std::string& error : ErrorNames) result.push_back(line("error",error,errors[error])); result.push_back(line("painted",painted)); result.push_back(line("erased",erased)); std::map<Rgb, int> counts; for (const auto& row : image) for (Rgb color : row) ++counts[color]; result.push_back(line("colors",counts.size())); auto colors = ranked(counts);
    for (int i = 0; i < std::min<int>(8,colors.size()); ++i) result.push_back(line("top",i + 1,colorText(colors[i].first),"pixels",colors[i].second)); for (const auto& symbol : uses) result.push_back(line("symbol",symbol.first,"uses",symbol.second));
    for (const auto& keyword : keywords) result.push_back(line("keyword",keyword.first,"executed",keyword.second[0],"errors",keyword.second[1],"pixels",keyword.second[2]));
    Lines unused; for (const auto& color : styles.colors) if (!usedColors.count(color.first)) unused.push_back(line("unused","color",color.first)); for (const auto& pen : styles.pens) if (!usedPens.count(pen.first)) unused.push_back(line("unused","pen",pen.first)); for (const auto& brush : styles.brushes) if (!usedBrushes.count(brush.first)) unused.push_back(line("unused","brush",brush.first)); for (const auto& symbol : uses) if (!symbol.second) unused.push_back(line("unused","symbol",symbol.first)); result.push_back(line("unused",unused.size())); result.insert(result.end(),unused.begin(),unused.end()); return result;
}
static Lines probeLines(const std::vector<Probe>& probes, const Image& image, const std::vector<Layer>& layers) {
    Lines result; for (int i = 0; i < static_cast<int>(probes.size()); ++i) {
        const Probe& probe = probes[i]; const auto& v = probe.values;
        if (probe.kind == "point") { Point point{v[0],v[1]}; Lines stack; for (int j = 0; j < static_cast<int>(layers.size()); ++j) if (layers[j].alphaAt(point) > 0) stack.push_back(std::to_string(j + 1) + ":" + std::to_string(layers[j].lineAt(point))); result.push_back(line("point",i + 1,point.x,point.y,"rgb",colorText(image[point.y][point.x]),"layers",stack.size(),"stack",stack.empty() ? "none" : join(stack))); }
        else { std::array<int, 3> totals{}; std::set<Rgb> colors; std::vector<int> cover(layers.size()); int count = (v[2] - v[0] + 1) * (v[3] - v[1] + 1);
            for (int y = v[1]; y <= v[3]; ++y) for (int x = v[0]; x <= v[2]; ++x) { const Rgb& color = image[y][x]; colors.insert(color); for (int c = 0; c < 3; ++c) totals[c] += color[c]; for (int j = 0; j < static_cast<int>(layers.size()); ++j) if (layers[j].alphaAt({x,y}) > 0) ++cover[j]; }
            Lines covers; for (int value : cover) covers.push_back(std::to_string(value)); result.push_back(line("area",i + 1,v[0],v[1],v[2],v[3],"pixels",count,"mean",totals[0] / count,totals[1] / count,totals[2] / count,"colors",colors.size(),"cover",join(covers)));
        }
    } return result;
}
int main() {
    Styles styles = readStyles(); Font font = readFont(); Scene scene = readScene(); std::vector<Probe> probes = readProbes(); Renderer renderer(scene,styles,font); renderer.run(); Image image = composite(renderer.layers,styles.colors.at(scene.background),scene.width,scene.height);
    std::filesystem::create_directories("output"); writePpm("output/image.ppm",image); writePreview("output/preview.txt",image); writeLines("commands.txt",commandLines(renderer.executions)); writeLines("layers.txt",layerLines(scene,renderer.layers,renderer.executions)); writeLines("summary.txt",summaryLines(scene,styles,renderer.executions,image)); writeLines("probes.txt",probeLines(probes,image,renderer.layers));
}
