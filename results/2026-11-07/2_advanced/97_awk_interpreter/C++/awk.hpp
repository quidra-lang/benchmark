#ifndef AWK_HPP
#define AWK_HPP
#include <algorithm>
#include <cstdint>
#include <fstream>
#include <functional>
#include <iomanip>
#include <iterator>
#include <map>
#include <memory>
#include <optional>
#include <set>
#include <sstream>
#include <string>
#include <tuple>
#include <utility>
#include <vector>
namespace awk {
    using Integer = std::int64_t;
    struct Position {
        int line = 1, column = 1;
        bool operator <(const Position& other) const {return std::tie(line, column) < std::tie(other.line, other.column);
        } std::string text() const {return std::to_string(line) + ":" + std::to_string(column);
        }
    };
    struct Issue {
        Position position;
        std::string message;
        int kind = 0;
    };
    struct Token {
        std::string kind, text, value;
        Position position;
    };
    std::vector<Token> tokenize(const std::string& source);
    bool letter(char c);
    bool digit(char c);
    struct Value {
        enum class Kind {Uninitialized, Number, String, NumericString};
        Kind kind = Kind::Uninitialized;
        Integer numeric = 0;
        std::string text;
        static Value number(Integer number);
        static Value string(const std::string& text);
        static Value input(const std::string& text);
        Integer to_number() const;
        std::string to_string() const;
        bool truth() const;
        std::string describe() const;
    };
    int compare(const Value& a, const Value& b);
    bool subscript_less(const std::string& a, const std::string& b);
    std::vector<std::string> split_pieces(const std::string& text, const std::string& separator);
    struct Record {
        Value zero = Value::string("");
        std::vector<Value> fields;
        std::function<Value(const std::string&)> special;
        explicit Record(std::function<Value(const std::string&)> read) : special(std::move(read)) {
        }
        void set(const std::string& text);
        Value read(Integer index) const;
        void write(Integer index, const Value& value);
        void resize(Integer size);
        void rebuild();
    };
    using Binding = std::pair<int, std::string>;
    struct Node;
    using NodePtr = std::shared_ptr < Node >;
    struct Node {
        std::string kind, text, flavor, redirect;
        Position position, name_position, redirect_position;
        NodePtr a, b, c, d;
        std::vector<NodePtr> nodes;
        bool flag = false;
        Integer number = 0;
        Binding binding = {-1, ""};
        int target = -1;
        std::int64_t count = 0, calls = 0;
        int active = 0, depth = 0;
        bool inside = false;
    };
    NodePtr node(const std::string& kind, const Position& position);
    std::vector<NodePtr> children(const NodePtr& value);
    bool is_lvalue(const NodePtr& value);
    class Parser {
        std::vector<Token> tokens;
        std::size_t index = 0;
        bool in_function = false;
        std::string phase;
        int loop_depth = 0;
        const Token& peek() const;
        Token take();
        bool accept(const std::string& spelling);
        Token expect(const std::string& spelling);
        [[noreturn]]void fail() const;
        void newlines();
        NodePtr name();
        NodePtr block();
        NodePtr statement();
        NodePtr condition();
        NodePtr loop_body();
        void terminator();
        NodePtr output(Token token);
        bool parenthesized_output() const;
        std::vector<NodePtr> expression_list(bool greater = true);
        NodePtr expression(bool greater = true);
        NodePtr conditional(bool greater);
        NodePtr logical(int level, bool greater);
        NodePtr membership(bool greater);
        NodePtr comparison(bool greater);
        NodePtr concatenation();
        NodePtr additive();
        NodePtr multiplicative();
        NodePtr unary();
        NodePtr postfix();
        NodePtr prefix();
        NodePtr lvalue();
        NodePtr atom();
        NodePtr binary(Token op, NodePtr a, NodePtr b);
        public:
        explicit Parser(std::vector<Token> input) : tokens(std::move(input)) {
        }
        std::vector<NodePtr> parse();
    };
    Value arithmetic(const std::string& operation, const Value& a, const Value& b, Position position);
    std::string format_output(const std::vector<Value>& values, Position position);
    Value invoke(const std::string& name, const std::vector<Value>& values, Position position);
    struct InputOperand {
        bool file = false;
        std::string name, value;
        Integer records = 0;
    };
    struct Arguments {
        std::vector<std::pair<std::string, std::string>> options;
        std::vector<InputOperand> operands;
    };
    Arguments parse_arguments(const std::string& text);
    bool valid_filename(const std::string& name);
    std::vector<std::string> read_records(const std::string& name);
    std::string read_file(const std::string& path);
    struct Output {
        bool open = false;
        Integer writes = 0;
        std::string content;
    };
    struct GetlineInput {
        bool open = false, ever = false;
        std::vector<std::string> lines;
        std::size_t position = 0;
        Integer reads = 0;
    };
    struct Streams {
        Output standard;
        std::map<std::string, Output> outputs;
        std::map<std::string, GetlineInput> inputs;
        std::vector<std::string> output_order, input_order;
        void write(const std::string& text, const std::optional<std::string>& name = {}, const std::string& mode = "", Position position = {});
        std::pair<int, std::string> getline(const std::string& name);
        int close(const std::string& name);
        void save() const;
    };
}
#endif
