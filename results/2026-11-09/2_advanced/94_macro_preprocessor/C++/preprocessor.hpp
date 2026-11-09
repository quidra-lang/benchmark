#ifndef MACRO_PREPROCESSOR_HPP
#define MACRO_PREPROCESSOR_HPP
#include <algorithm>
#include <cstdint>
#include <deque>
#include <filesystem>
#include <fstream>
#include <functional>
#include <iterator>
#include <map>
#include <memory>
#include <optional>
#include <set>
#include <sstream>
#include <string>
#include <utility>
#include <vector>
struct Position {
    std::string file;
    int line = 0;
};
std::string position_text(const Position &);
bool word_in(const std::string &, const std::string &);
struct PreprocessingError {
    std::string message;
};
struct Token {
    std::string kind, spelling;
    int line = 0;
    bool space = false;
    std::set<std::string> hide;
};
using Tokens = std::vector<Token>;
struct LogicalLine {
    Tokens tokens;
    int start, end;
};
struct ReadToken {
    std::string kind, spelling;
    size_t end;
};
ReadToken read_token(const std::string &, size_t, bool = false);
std::vector<LogicalLine> lex_source(const std::string &);
Tokens lex_definition(const std::string &, int);
std::string render(const Tokens &);
std::optional<std::string> single_token(const std::string &);
struct Macro {
    std::string name;
    bool function = false, variadic = false;
    std::vector<std::string> parameters;
    Tokens replacement;
    Position position;
    bool main_file = false;
    int expanded = 0, tested = 0;
    std::string signature() const;
    bool identical(const Macro &) const;
};
bool builtin(const std::string &);
void check_name(const Tokens &, const std::string &);
std::shared_ptr<Macro> parse_definition(Tokens, Position, bool);
struct FileData {
    std::string path, guard;
    std::vector<LogicalLine> lines;
    int physical_lines = 0, entered = 0, skipped = 0, output_lines = 0, skipped_lines = 0;
    bool once = false;
};
std::string directive_name(const Tokens &);
struct IncludeManager {
    std::map<std::string, std::unique_ptr<FileData>> files;
    std::vector<std::string> order;
    std::string search(const std::string &, bool) const;
    FileData *load(const std::string &);
};
struct ConditionalBlock {
    std::string kind;
    Position start;
    bool parent = false, chosen = false, active = false, else_seen = false;
    int skip_start = 0;
};
struct Inclusion {
    FileData *source;
    int depth = 0;
    std::string display_file;
    int offset = 0;
    std::vector<ConditionalBlock> stack;
    Tokens segment;
    Position position(int physical) const { return {display_file, physical + offset}; }
    bool skipping() const { return !stack.empty() && !stack.back().active; }
};
struct Header {
    std::string rendering, name;
    bool quoted;
    size_t next;
};
std::optional<Header> read_header(const Tokens &, size_t);
struct ConditionExpr {
    std::string kind, op, name;
    int64_t value = 0;
    std::vector<std::unique_ptr<ConditionExpr>> children;
};
std::unique_ptr<ConditionExpr> parse_condition(const Tokens &, const std::string &);
int64_t evaluate_condition(const ConditionExpr &, const std::function<void(const std::string &)> &);
struct TestResult {
    bool valid = false;
    int64_t value = 0;
    Tokens expanded;
    bool was_expanded = false;
};
struct Preprocessor {
    std::map<std::string, std::shared_ptr<Macro>> macros;
    std::set<std::string> ever_defined, poisoned;
    std::map<std::string, std::vector<std::shared_ptr<Macro>>> saved;
    IncludeManager manager;
    std::vector<std::string> output, history, diagnostics, tree = {"main.c"}, conditionals, regions;
    std::map<std::string, int> diagnostic_counts, condition_counts, builtin_counts;
    int counter = 0;
    Position previous;
    void diagnostic(Position, const std::string &, const std::string &);
    void event(Position, const std::string &);
    void poison_check(const Inclusion &, const Tokens &);
    void unused_check(const Macro &);
    void define(Tokens, Position, bool);
    void undefine(const Tokens &, Position);
    void process_defines();
    void marker(const std::string &, int, int = 0);
    void output_line(Inclusion &, int, const std::string &);
    void flush(Inclusion &);
    bool macro_defined(const std::string &);
    Tokens replace_operators(const Tokens &);
    TestResult test(Inclusion &, const LogicalLine &, const std::string &, const Tokens &);
    void close_region(Inclusion &, ConditionalBlock &, int);
    void conditional_record(Position, size_t, const std::string &, const Tokens &,
                            const std::string &);
    void conditional(Inclusion &, const LogicalLine &, const std::string &, const Tokens &);
    void include(Inclusion &, const LogicalLine &, Tokens);
    void line_directive(Inclusion &, const LogicalLine &, Tokens);
    void macro_pragma(Position, const Tokens &, const std::string &);
    void pragma(Inclusion &, const LogicalLine &, const Tokens &);
    void directive(Inclusion &, const LogicalLine &, const std::string &, const Tokens &);
    void process_file(const std::string &, int);
    void write_reports();
};
Tokens expand(Preprocessor &, const Inclusion &, const Tokens &);
#endif
