#ifndef MINI_ML_HPP
#define MINI_ML_HPP
#include <algorithm>
#include <cstdint>
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
#include <tuple>
#include <utility>
#include <vector>
struct Position {
    std::string file;
    int line = 1, column = 1;
};
struct Token {
    std::string kind, spelling, value;
    Position position;
    int64_t integer = 0;
    bool name() const { return kind == "identifier" && spelling != "_"; }
};
std::vector<Token> lex(const std::string &, const std::vector<std::string> &);
bool word_in(const std::string &, const std::string &);
struct Type {
    std::string kind;
    std::vector<Type *> children;
    Type *binding = nullptr;
};
struct Scheme {
    Type *type = nullptr;
    std::set<Type *> quantified;
};
using TypeEnv = std::map<std::string, Scheme>;
Type *fresh();
Type *construct(const std::string &, std::vector<Type *> = {});
Type *primitive(const std::string &);
Type *resolve(Type *);
std::set<Type *> free_variables(Type *);
Scheme generalize(Type *, const TypeEnv &);
Type *instantiate(const Scheme &);
struct UnificationFailure {
    Type *expected;
    Type *found;
    bool infinite, nested;
};
std::optional<UnificationFailure> unify(Type *, Type *, bool = false);
struct Group;
struct Expr;
struct Arm {
    Expr *pattern;
    Expr *body;
};
struct Expr {
    std::string kind, value;
    Position position;
    int64_t integer = 0;
    std::vector<Expr *> children;
    Token token;
    Group *group = nullptr;
    std::vector<Arm> arms;
    Type *inferred = nullptr;
};
struct Binding {
    Token name;
    Expr *expr;
    Scheme scheme;
    std::string classification;
};
struct Group {
    std::vector<Binding *> bindings;
    std::optional<Position> rec;
};
struct Item {
    std::string kind;
    Token name;
    Expr *declared = nullptr;
    Group *group = nullptr;
    Expr *expr = nullptr;
};
struct SyntaxError {
    Token token;
};
struct Parser {
    std::vector<Token> tokens;
    size_t index = 0;
    const Token &peek() const;
    bool accept(const std::string &);
    Token take(const std::string &);
    Token name();
    void recover_item();
    Item item();
    Group *group();
    Binding *binding();
    Expr *expression();
    Arm arm();
    Expr *binary(int);
    Expr *unary();
    Expr *atom();
    Expr *pattern();
    Expr *pattern_atom();
    Expr *type_expression();
    Expr *list_type();
    Expr *type_atom();
};
std::pair<int, bool> operator_info(const std::string &);
struct TypeError {
    std::string kind, name;
    Position position;
    Type *expected = nullptr, *found = nullptr;
    std::optional<UnificationFailure> failure;
    std::vector<std::string> candidates;
};
struct Inferencer {
    std::vector<Binding *> locals;
    void check(Type *, Type *, const Position &);
    Type *expression(Expr *, const TypeEnv &);
    Type *pattern(Expr *, std::map<std::string, Type *> &);
    TypeEnv group(Group *, const TypeEnv &, bool);
};
struct Value;
struct ValueEnv {
    std::shared_ptr<const ValueEnv> parent;
    std::map<std::string, Value *> bindings;
};
using Environment = std::shared_ptr<const ValueEnv>;
struct Value {
    std::string kind, text, builtin;
    int64_t integer = 0;
    bool boolean = false;
    std::vector<Value *> items;
    Token parameter;
    Expr *body = nullptr;
    Environment environment;
};
Value *make_value(const std::string &);
Value *lookup(Environment, const std::string &);
Environment extend(Environment, std::map<std::string, Value *>);
struct RuntimeError {
    Position position;
    std::string message;
};
std::string print_value(Value *);
std::string quote_string(const std::string &);
Value *apply_builtin(const std::string &, Value *, const Position &);
struct Evaluator {
    int64_t calls = 0;
    Value *expression(Expr *, Environment);
    Environment group(Group *, Environment);
    Value *apply(Value *, Value *, const Position &);
    Value *integer(int64_t, const Position &);
    int compare(Value *, Value *, const Position &);
    bool pattern(Expr *, Value *, std::map<std::string, Value *> &);
};
#endif
