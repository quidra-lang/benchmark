#include "tac.hpp"
namespace tac {
    const std::vector<std::string> kinds = {"copy", "bin", "load", "store", "goto", "if", "param", "call", "return", "read", "print"};
    Operand Operand::parse(const std::string& word) {
        Operand result;
        if (!word.empty() &&(word[0] == '-' ||(word[0] >= '0' && word[0] <= '9'))) {
            result.constant = true;
            result.number = std::stoll(word);
        } else result.variable = word;
        return result;
    }
    Operand Operand::value(Integer number) {
        Operand result;
        result.constant = true;
        result.number = number;
        return result;
    }
    std::string Operand::text() const {return constant ? std::to_string(number) : variable;
    } bool Operand::operator <(const Operand& other) const {return std::tie(constant, number, variable) < std::tie(other.constant, other.number, other.variable);
    } bool Operand::operator ==(const Operand& other) const {return constant == other.constant &&(constant ? number == other.number : variable == other.variable);
    } bool Expression::operator <(const Expression& other) const {return std::tie(kind, operation, a, b) < std::tie(other.kind, other.operation, other.a, other.b);
    } bool Expression::operator ==(const Expression& other) const {return kind == other.kind && operation == other.operation && a == other.a && b == other.b;
    } std::string Expression::text() const {return kind == "load" ? operation + "[" + a.text() + "]" : a.text() + operation + b.text();
    } bool Expression::uses(const std::string& v) const {return(!a.constant && a.variable == v) ||(kind == "bin" && !b.constant && b.variable == v);
    } std::vector<Operand*> Instruction::operands() {
        if (kind == "bin" || kind == "if" || kind == "store") return {&a, &b};
        if (kind == "copy" || kind == "load" || kind == "param" || kind == "print" ||(kind == "return" && has_operand)) return {&a};
        return {};
    }
    std::vector<Operand> Instruction::operands() const {Instruction copy = *this;
    std::vector<Operand> result;
    for (Operand* value : copy.operands()) result.push_back(*value);
    return result;
    } std::vector<std::string> Instruction::uses() const {std::vector<std::string> result;
    for (const Operand& value : operands()) if (!value.constant) result.push_back(value.variable);
    return result;
    } std::optional<Expression> Instruction::expression() const {if (kind == "bin") return Expression {kind, operation, a, b};
    if (kind == "load") return Expression {kind, name, a, {} };
    return std::nullopt;
    } std::string Instruction::text() const {if (kind == "copy") return destination + " = " + a.text();
    if (kind == "bin") return destination + " = " + a.text() + " " + operation + " " + b.text();
    if (kind == "load") return destination + " = " + name + "[" + a.text() + "]";
    if (kind == "store") return name + "[" + a.text() + "] = " + b.text();
    if (kind == "goto") return "goto " + name;
    if (kind == "if") return "if " + a.text() + " " + operation + " " + b.text() + " goto " + name;
    if (kind == "call") return(destination.empty() ? "" : destination + " = ") + "call " + name + " " + std::to_string(count);
    if (kind == "read") return "read " + destination;
    if (kind == "return" && !has_operand) return "return";
    return kind + " " + a.text();
    } int Function::instruction_count() const {return static_cast<int>(std::count_if(code.begin(), code.end(),[](const Line& line) {
        return !line.is_label();
    }));
    } static std::pair<std::string, Operand> array_operand(const std::string& word) {
        std::size_t bracket = word.find('[');
        return {word.substr(0, bracket), Operand::parse(word.substr(bracket + 1, word.size() - bracket - 2))};
    }
    static Instruction parse_instruction(const std::vector<std::string>& w) {
        Instruction s;
        const std::string& first = w[0];
        if (first == "goto") {
            s.kind = first;
            s.name = w[1];
        } else if (first == "if") {
            s.kind = first;
            s.a = Operand::parse(w[1]);
            s.operation = w[2];
            s.b = Operand::parse(w[3]);
            s.name = w[5];
        } else if (first == "param" || first == "print" || first == "return") {
            s.kind = first;
            s.has_operand = w.size() > 1;
            if (s.has_operand) s.a = Operand::parse(w[1]);
        } else if (first == "read") {
            s.kind = first;
            s.destination = w[1];
        } else if (first == "call") {
            s.kind = first;
            s.name = w[1];
            s.count = std::stoi(w[2]);
        } else if (first.find('[') != std::string::npos) {
            s.kind = "store";
            std::tie(s.name, s.a) = array_operand(first);
            s.b = Operand::parse(w[2]);
        } else {
            s.destination = first;
            if (w[2] == "call") {
                s.kind = "call";
                s.name = w[3];
                s.count = std::stoi(w[4]);
            } else if (w.size() == 5) {
                s.kind = "bin";
                s.a = Operand::parse(w[2]);
                s.operation = w[3];
                s.b = Operand::parse(w[4]);
            } else if (w[2].find('[') != std::string::npos) {
                s.kind = "load";
                std::tie(s.name, s.a) = array_operand(w[2]);
            } else {
                s.kind = "copy";
                s.a = Operand::parse(w[2]);
            }
        }
        return s;
    }
    Program read_program(const std::string& path) {
        Program result;
        std::ifstream input(path);
        std::string text;
        while (std::getline(input, text)) {
            std::istringstream stream(text);
            std::vector<std::string> words;
            std::string word;
            while (stream >> word) words.push_back(word);
            if (words.empty() || words[0][0] == '#') continue;
            if (words[0] == "array") result.arrays.emplace_back(words[1], std::stoi(words[2]));
            else if (words[0] == "func") {
                Function f;
                f.name = words[1];
                f.parameters.assign(words.begin() + 2, words.end());
                result.functions.push_back(f);
            } else if (words[0] == "end") continue;
            else if (words.size() == 1 && words[0].back() == ':') result.functions.back().code.push_back(Line::named(words[0].substr(0, words[0].size() - 1)));
            else result.functions.back().code.push_back(Line::code(parse_instruction(words)));
        }
        return result;
    }
    Integer calculate(const std::string& op, Integer a, Integer b) {
        if (op == "+") return a + b;
        if (op == "-") return a - b;
        if (op == "*") return a * b;
        if (op == "/") return a/b;
        if (op == "%") return a%b;
        if (op == "<") return a < b;
        if (op == "<=") return a <= b;
        if (op == ">") return a > b;
        if (op == ">=") return a >= b;
        if (op == "==") return a == b;
        return a != b;
    }
    std::string join(const std::vector<std::string>& values, const std::string& separator, const std::string& empty) {
        if (values.empty()) return empty;
        std::string result = values[0];
        for (std::size_t i = 1;i < values.size();++i) result += separator + values[i];
        return result;
    }
    std::string numbers(const std::vector<int>& values, const std::string& prefix) {
        std::vector<std::string> strings;
        for (int value : values) strings.push_back(prefix + std::to_string(value));
        return join(strings);
    }
    std::string numbers(const std::set<int>& values, const std::string& prefix) {
        return numbers(std::vector<int>(values.begin(), values.end()), prefix);
    }
    std::vector<std::string> function_lines(const Function& function) {
        std::vector<std::string> result;
        std::string first = "func " + function.name;
        for (const std::string& p : function.parameters) first += " " + p;
        result.push_back(first);
        for (const Line& line : function.code) result.push_back(line.is_label() ? line.label + ":" : "    " + line.instruction.text());
        result.push_back("end");
        return result;
    }
    std::vector<std::string> program_lines(const Program& program) {
        std::vector<std::string> result;
        for (const std::pair<std::string, int>& a : program.arrays) result.push_back("array " + a.first + " " + std::to_string(a.second));
        for (const Function& f : program.functions) {
            if (!result.empty()) result.push_back("");
            std::vector<std::string> lines = function_lines(f);
            result.insert(result.end(), lines.begin(), lines.end());
        }
        return result;
    }
}
