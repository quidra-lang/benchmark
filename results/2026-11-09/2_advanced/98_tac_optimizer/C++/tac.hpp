#ifndef TAC_HPP
#define TAC_HPP
#include <algorithm>
#include <array>
#include <cstdint>
#include <fstream>
#include <functional>
#include <iterator>
#include <map>
#include <numeric>
#include <optional>
#include <set>
#include <sstream>
#include <string>
#include <tuple>
#include <type_traits>
#include <utility>
#include <vector>
namespace tac {
    using Integer = std::int64_t;
    struct Operand {
        bool constant = false;
        Integer number = 0;
        std::string variable;
        static Operand parse(const std::string& word);
        static Operand value(Integer number);
        std::string text() const;
        bool operator <(const Operand& other) const;
        bool operator ==(const Operand& other) const;
    };
    struct Expression {
        std::string kind, operation;
        Operand a, b;
        bool operator <(const Expression& other) const;
        bool operator ==(const Expression& other) const;
        std::string text() const;
        bool uses(const std::string& variable) const;
    };
    struct Instruction {
        std::string kind, destination, operation, name;
        Operand a, b;
        bool has_operand = false;
        int count = 0;
        std::vector<Operand*> operands();
        std::vector<Operand> operands() const;
        std::vector<std::string> uses() const;
        std::optional<Expression> expression() const;
        std::string text() const;
    };
    struct Line {
        std::string label;
        Instruction instruction;
        bool is_label() const {return !label.empty();
        } static Line named(const std::string& name) {
            Line line;
            line.label = name;
            return line;
        }
        static Line code(const Instruction& value) {
            Line line;
            line.instruction = value;
            return line;
        }
    };
    struct Function {
        std::string name;
        std::vector<std::string> parameters;
        std::vector<Line> code;
        int temporary_serial = 0, preheader_serial = 0;
        int instruction_count() const;
    };
    struct Program {
        std::vector<std::pair<std::string, int>> arrays;
        std::vector<Function> functions;
    };
    extern const std::vector<std::string> kinds;
    Program read_program(const std::string& path);
    std::vector<std::string> function_lines(const Function& function);
    std::vector<std::string> program_lines(const Program& program);
    Integer calculate(const std::string& operation, Integer a, Integer b);
    std::string join(const std::vector<std::string>& values, const std::string& separator = ",", const std::string& empty = "-");
    std::string numbers(const std::vector<int>& values, const std::string& prefix = "");
    std::string numbers(const std::set<int>& values, const std::string& prefix = "");
    template<class T> std::set<T> intersection(const std::set<T>& a, const std::set<T>& b) {
        std::set<T> result;
        std::set_intersection(a.begin(), a.end(), b.begin(), b.end(), std::inserter(result, result.end()));
        return result;
    }
    struct Block {
        int start = 0, end = 0, depth = 0;
        std::vector<std::string> labels;
        std::vector<int> instructions, predecessors, successors, reachable_predecessors;
    };
    struct Loop {
        int header = 0, depth = 0;
        std::vector<int> latches;
        std::set<int> blocks, exits, outside;
    };
    struct CFG {
        std::vector<Block> blocks;
        std::vector<Instruction> instructions;
        std::vector<int> positions, block_of, postorder, reverse_postorder, immediate;
        std::set<int> reachable;
        std::vector<std::set<int>> dominators;
        std::vector<Loop> loops;
        explicit CFG(const Function& function);
    };
    using Definition = std::pair<std::string, int>;
    using Copy = std::pair<std::string, std::string>;
    using Definitions = std::set<Definition>;
    using Variables = std::set<std::string>;
    using Expressions = std::set<Expression>;
    using Copies = std::set<Copy>;
    Definitions reaching_transfer(const Instruction& instruction, int number, Definitions state);
    Variables live_transfer(const Instruction& instruction, Variables state);
    Expressions expression_transfer(const Instruction& instruction, int number, Expressions state);
    Copies copy_transfer(const Instruction& instruction, int number, Copies state);
    struct DataFlow {
        std::vector<Definitions> reaching_in, reaching_out, reaching_before;
        std::vector<Variables> live_in, live_out, live_before, live_after;
        std::vector<Expressions> expression_in, expression_out, expression_before;
        std::vector<Copies> copy_in, copy_out, copy_before;
        int reaching_iterations = 0, live_iterations = 0, expression_iterations = 0, copy_iterations = 0;
        DataFlow(const Function& function, const CFG& graph);
    };
    using Replacements = std::map<int, std::vector<Line>>;
    void rewrite(Function& function, const Replacements& replacements, const std::map<int, std::vector<Line>>& insertions = {});
    std::optional<Instruction> fold(const Instruction& instruction);
    std::string hoist(Function& function, const CFG& graph, const Loop& loop, const std::vector<int>& moves);
    std::vector<std::string> remove_unreachable(Function& function, const CFG& graph);
    class Cost {
        std::string digits = "0";
        public:
        static Cost power(int exponent);
        Cost times(int factor) const;
        Cost& operator +=(const Cost& other);
        bool operator <(const Cost& other) const;
        std::string text() const {return digits;
        }
    };
    struct Allocation {
        std::map<std::string, Variables> neighbors, partners;
        std::map<std::string, Cost> costs;
        std::vector<std::string> order;
        std::vector<std::pair<std::string, int>> potential;
        std::map<std::string, int> colors;
        Variables spills;
        Allocation(const Function& function, const CFG& graph, const DataFlow& flow, int registers);
    };
}
#endif
