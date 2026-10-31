#pragma once
#include <algorithm>
#include <array>
#include <filesystem>
#include <fstream>
#include <functional>
#include <map>
#include <memory>
#include <optional>
#include <set>
#include <sstream>
#include <stdexcept>
#include <string>
#include <utility>
#include <vector>
using Lines = std::vector<std::string>;
template <class... Parts> std::string text(const Parts &...parts) {
    std::ostringstream out;
    (out << ... << parts);
    return out.str();
}
std::string join(const Lines &items, const std::string &separator = " ");
void append(Lines &out, const Lines &items);
std::string trimRight(std::string value);
enum class Kind {
    Identifier,
    Number,
    Symbol,
    Command,
    Text,
    Eqref,
    OpenBrace,
    CloseBrace,
    Sup,
    Sub,
    Amp,
    Newline,
    Begin,
    End,
    Tag,
    Label,
    Fraction,
    Binomial,
    Overset,
    Underset,
    SquareRoot,
    Left,
    Right,
    Accent,
    Eof,
    Row,
    Reference,
    Script,
    Root,
    Delimited,
    Matrix
};
enum class Type { Ordinary, Operator, Binary, Relation, Open, Close, Punctuation };
struct SymbolInfo {
    std::string display;
    Type type = Type::Ordinary;
};
const std::map<std::string, SymbolInfo> &symbolCommands();
bool greekName(const std::string &name);
bool commandName(const std::string &name);
bool containsWord(const std::string &words, const std::string &value);
struct Token {
    Kind kind = Kind::Eof;
    std::string value;
    int column = 0;
};
struct Issue {
    int column = 0;
    std::string message;
};
struct Lexed {
    std::vector<Token> tokens;
    std::optional<Issue> error;
};
Lexed tokenize(const std::string &line);
struct Node;
using NodePtr = std::shared_ptr<Node>;
using Nodes = std::vector<NodePtr>;
struct Node {
    Kind kind = Kind::Row;
    std::string value, left, right;
    int column = 0, rightColumn = 0;
    Nodes items;
    std::vector<Nodes> rows;
    NodePtr base, sub, sup;
};
NodePtr emptyRow();
std::optional<Issue> checkBraces(const std::vector<Token> &tokens);
struct Parser {
    const std::vector<Token> &tokens;
    std::size_t position = 0;
    int end = 0;
    std::optional<Token> tag, label;
    Token peek() const;
    Token read();
    void unexpected(Token token) const;
    Nodes elements(bool top = false, bool index = false);
    NodePtr element();
    NodePtr argument(const std::string &name);
    NodePtr nucleus();
    std::string delimiter();
};
struct Box;
using BoxPtr = std::shared_ptr<Box>;
struct Placement {
    BoxPtr box;
    int x = 0, y = 0;
    std::string role;
};
struct Drawn {
    std::string value;
    int x, y;
};
struct Box {
    int width = 0, height = 1, baseline = 0;
    std::string description;
    std::vector<Placement> children;
    std::vector<Drawn> drawn;
    void add(BoxPtr child, int x, int y, std::string role = "");
    void draw(std::string value, int x, int y);
    int descent() const { return height - 1 - baseline; }
};
BoxPtr newBox(int width, int height, int baseline, std::string description);
void drawDelimiter(const BoxPtr &box, const std::string &value, int x, int height);
std::string delimiterString(const std::string &value);
BoxPtr delimit(BoxPtr body, const std::string &left, const std::string &right);
BoxPtr atomBox(const Node &node, bool script, const std::map<std::string, std::string> &references);
int center(const BoxPtr &box, int width);
struct Params {
    int width = 0, indent = 0, relSpace = 0, binSpace = 0, punctSpace = 0, colGap = 0, rowGap = 0;
};
struct ElementTypes {
    Type left = Type::Ordinary, right = Type::Ordinary;
};
struct Spacing {
    std::vector<ElementTypes> types;
    std::vector<int> gaps;
};
Spacing spacing(const Nodes &nodes, bool script, const Params &params);
BoxPtr rowBox(const std::vector<BoxPtr> &children, const std::vector<int> &gaps,
              const std::string &description, const Lines &roles = {});
Lines drawCanvas(const std::vector<Placement> &roots, int width, int height);
struct BoxDescription {
    Lines lines;
    int depth = 0;
    std::map<std::string, int> kinds;
};
BoxDescription describeBoxes(const std::vector<Placement> &roots);
