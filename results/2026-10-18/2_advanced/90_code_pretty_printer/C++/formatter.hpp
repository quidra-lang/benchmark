#pragma once
#include <algorithm>
#include <cstddef>
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
std::string trimRight(std::string value);
std::string join(const Lines &values, const std::string &separator = " ");
void append(Lines &to, const Lines &from);
bool wordIn(const std::string &words, const std::string &word);
struct Position {
    int line = 0, column = 0;
};
struct FileError {
    Position position;
    std::string message;
};
enum class TokenKind { Identifier, Keyword, Number, String, Symbol, End };
struct Comment {
    std::string value;
    bool line = false, own = false;
    Position position;
    int blank = 0;
};
struct Token {
    std::string value;
    TokenKind kind = TokenKind::End;
    Position position;
    int blank = 0, index = 0;
    std::vector<Comment *> leading, trailing;
    bool originalTrailing = false;
};
struct Lexeme {
    Token *token = nullptr;
    Comment *comment = nullptr;
    int line() const { return token ? token->position.line : comment->position.line; }
};
struct Lexed {
    std::vector<std::unique_ptr<Token>> tokens;
    std::vector<std::unique_ptr<Comment>> comments;
    std::vector<Lexeme> items;
};
Lexed lex(const Lines &source);
enum class NodeKind {
    Program,
    Function,
    Declaration,
    Parameter,
    List,
    Dimension,
    Block,
    If,
    While,
    For,
    Switch,
    SwitchBody,
    Clause,
    Return,
    Break,
    Continue,
    Simple,
    Assignment,
    Conditional,
    Binary,
    Unary,
    Atom,
    Parenthesized,
    Call,
    Index,
    Member
};
struct Node;
using NodePtr = std::shared_ptr<Node>;
using Nodes = std::vector<NodePtr>;
struct Node {
    NodeKind kind = NodeKind::Atom;
    std::string value;
    int first = 0, last = 0;
    Token *token = nullptr, *name = nullptr, *open = nullptr, *close = nullptr, *op = nullptr,
          *colon = nullptr, *elseToken = nullptr, *semi = nullptr, *semi2 = nullptr,
          *trailing = nullptr;
    NodePtr expr, left, right, thenPart, elsePart, body, init, condition, update;
    Nodes elements, dimensions;
    std::vector<Token *> commas;
};
Nodes nodeChildren(const Node &node);
bool typeName(const Token *token);
int precedence(const std::string &op);
int expressionLevel(const NodePtr &node);
struct Parser {
    const std::vector<std::unique_ptr<Token>> &tokens;
    int position = 0;
    Token *peek() const;
    Token *read();
    void fail(const std::string &expected) const;
    Token *take(const std::string &value);
    Token *takeType();
    Token *identifier();
    NodePtr mark(NodePtr node, int start) const;
    NodePtr program();
    NodePtr list(const std::string &kind, const std::string &open, const std::string &close,
                 bool trailing);
    NodePtr parameter();
    NodePtr declaration(Token *type, Token *name, int start, bool semi);
    NodePtr initializer();
    NodePtr block();
    NodePtr statement();
    NodePtr simple();
    NodePtr expression();
    NodePtr binary(int level);
    NodePtr unary();
};
enum class DocKind {
    Text,
    Line,
    Softline,
    Hardline,
    BreakParent,
    Suffix,
    IfBreak,
    Group,
    Nest,
    Align,
    Concat
};
enum class Mode { Flat, Break, Forced };
struct Doc;
using DocPtr = std::shared_ptr<Doc>;
using Docs = std::vector<DocPtr>;
struct Doc {
    DocKind kind = DocKind::Text;
    std::string value, other;
    Mode mode = Mode::Flat;
    int number = 0;
    Docs children;
    bool forced = false;
};
DocPtr stringDoc(std::string value);
DocPtr marker(DocKind kind);
DocPtr cat(const Docs &docs);
DocPtr group(const Docs &docs);
DocPtr nest(int amount, const Docs &docs);
DocPtr align(const Docs &docs);
DocPtr suffix(std::string value);
DocPtr ifBreak(std::string broken, std::string flat);
struct GroupMetrics {
    int groups = 0, broken = 0, forced = 0;
};
GroupMetrics groupMetrics(const DocPtr &doc);
Lines printDoc(const DocPtr &doc, int width, int commentColumn);
Lines docTree(const DocPtr &doc, int depth = 0);
Lines diffLines(const Lines &before, const Lines &after);
