#ifndef TOY_COMPILER_HPP
#define TOY_COMPILER_HPP
#include <algorithm>
#include <array>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <functional>
#include <iomanip>
#include <map>
#include <memory>
#include <optional>
#include <set>
#include <sstream>
#include <string>
#include <tuple>
#include <utility>
#include <vector>
struct Position {
    int line = 1, column = 1;
};
bool earlier(Position, Position);
std::string position_text(Position);
bool word_in(const std::string &, const std::string &);
struct Token {
    std::string kind, spelling;
    int64_t integer = 0;
    Position position;
};
struct CompileError {
    std::string kind, message;
    Position position;
};
std::vector<Token> tokenize(const std::vector<std::string> &, int);
struct Symbol;
struct Declaration;
struct Statement;
struct Expr {
    std::string kind, type;
    Token token;
    int64_t value = 0;
    std::vector<Expr *> children;
    Symbol *referent = nullptr;
};
struct Declaration {
    std::string type;
    Token name, size;
    bool array = false, function = false;
    Expr *initializer = nullptr;
    std::vector<Declaration *> parameters;
    Statement *body = nullptr;
    Symbol *symbol = nullptr;
    std::vector<Symbol *> slots;
};
struct Statement {
    std::string kind;
    Token token, close;
    Declaration *declaration = nullptr;
    Expr *expr = nullptr, *index = nullptr, *condition = nullptr;
    std::vector<Expr *> expressions;
    std::vector<Statement *> statements;
    Statement *yes = nullptr, *no = nullptr, *body = nullptr, *init = nullptr, *update = nullptr;
    Symbol *referent = nullptr;
};
struct Program {
    std::vector<Declaration *> declarations, globals, functions;
    Token end;
    std::map<std::string, Symbol *> names;
    std::vector<Symbol *> symbols;
};
Expr *new_expr(const std::string &, Token, std::vector<Expr *> = {});
Statement *new_statement(const std::string &, Token);
struct Parser {
    std::vector<Token> tokens;
    size_t index = 0;
    const Token &peek() const;
    void fail() const;
    Token take(const std::string &);
    bool accept(const std::string &);
    Declaration *declaration_start();
    Program program();
    Statement *block();
    Statement *statement();
    Statement *simple();
    Expr *call(Token);
    Expr *expression(int = 1);
    Expr *unary();
    Expr *primary();
};
struct Symbol {
    std::string name, type, kind;
    Declaration *declaration = nullptr;
    bool array = false;
    int size = 0, address = 0, slot = 0, reads = 0;
    std::vector<Position> references;
    std::set<Symbol *> calls;
};
struct Semantics {
    Program *program;
    std::vector<std::map<std::string, Symbol *>> scopes;
    Declaration *function = nullptr;
    int loops = 0;
    Symbol *symbol(Declaration *, const std::string &);
    Symbol *lookup(Token, bool);
    Symbol *variable(Token, bool, bool);
    std::string expression(Expr *, bool = false);
    void declaration(Declaration *);
    void statement(Statement *);
    void analyze();
};
bool can_complete(Statement *);
void walk_statements(Statement *, const std::function<void(Statement *)> &);
struct Instruction {
    std::string op;
    int64_t a = 0, b = 0;
    Position position;
    Declaration *callee = nullptr;
};
struct BasicBlock {
    int first, last;
    std::vector<int> successors;
};
struct Unit {
    std::string name;
    Declaration *function = nullptr;
    std::vector<Instruction> code;
    int start = 0, slots = 0, stack = 0;
    std::vector<BasicBlock> blocks;
};
bool jump(const std::string &);
bool conditional(const std::string &);
bool transfer(const std::string &);
struct Generator {
    Unit *unit;
    std::vector<int> labels;
    std::vector<std::pair<int, int>> loops;
    void emit(const std::string &, int64_t, int64_t, Position, Declaration * = nullptr);
    int label();
    void place(int);
    void to(const std::string &, int, Position);
    void patch();
    void expression(Expr *);
    void statement(Statement *);
};
std::pair<std::vector<Unit>, int> generate(Program &, const std::set<Symbol *> &);
struct Executable {
    Instruction instruction;
    int unit;
};
struct Frame {
    std::vector<int64_t> locals;
    int return_address;
};
struct RunResult {
    std::vector<std::string> output;
    int executed = 0, maximum_stack = 0, maximum_depth = 0, fault_pc = -1;
    std::vector<int> counts;
    std::map<std::string, int> calls;
    std::map<std::pair<std::string, std::string>, int> pairs;
    std::string error;
    std::vector<Frame> frames;
};
std::vector<Executable> flatten(const std::vector<Unit> &);
RunResult execute(const std::vector<Unit> &, int, const std::vector<int64_t> &);
#endif
