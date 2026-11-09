#include "compiler.hpp"
static const std::array<std::string, 7> rule_names = {
    "const-jump", "not-compare", "not-jump", "invert-branch", "thread", "jump-next", "unreachable"};
struct Source {
    std::string name;
    int first_line;
    std::vector<std::string> lines;
};
struct Warning {
    Position position;
    std::string message;
};
static std::string join(const std::vector<std::string> &words, const std::string &separator) {
    std::string result;
    for (size_t i = 0; i < words.size(); ++i) {
        if (i)
            result += separator;
        result += words[i];
    }
    return result;
}
static std::set<Symbol *> reachable_functions(Program &program) {
    std::set<Symbol *> result;
    std::function<void(Symbol *)> visit = [&](Symbol *f) {
        if (!result.insert(f).second)
            return;
        for (Symbol *callee : f->calls)
            visit(callee);
    };
    visit(program.names.at("main"));
    return result;
}
static std::vector<Warning> collect_warnings(Program &program,
                                             const std::set<Symbol *> &reachable) {
    std::vector<Warning> result;
    for (Symbol *symbol : program.symbols)
        if (symbol->kind != "function" && symbol->reads == 0)
            result.push_back(
                {symbol->declaration->name.position,
                 "unused " + std::string(symbol->kind == "parameter" ? "parameter" : "variable") +
                     " '" + symbol->name + "'"});
    for (Declaration *function : program.functions) {
        if (!reachable.count(function->symbol))
            result.push_back({function->name.position,
                              "function '" + function->name.spelling + "' is never called"});
        walk_statements(function->body, [&](Statement *s) {
            if (s->kind == "block")
                for (size_t i = 0; i < s->statements.size(); ++i)
                    if (!can_complete(s->statements[i])) {
                        if (i + 1 < s->statements.size())
                            result.push_back(
                                {s->statements[i + 1]->token.position, "unreachable statement"});
                        break;
                    }
        });
    }
    std::sort(result.begin(), result.end(),
              [](const Warning &a, const Warning &b) { return earlier(a.position, b.position); });
    return result;
}
static bool literal(Expr *e) { return e->kind == "integer" || e->kind == "boolean"; }
static bool in_range(int64_t value) { return value >= -2147483648LL && value <= 2147483647LL; }
static Expr *folded_literal(Expr *e, int64_t value) {
    Expr *result = new_expr(e->type == "bool" ? "boolean" : "integer", e->token);
    result->type = e->type;
    result->value = value;
    return result;
}
static std::optional<int64_t> constant_binary(const std::string &op, int64_t a, int64_t b) {
    if (op == "+" || op == "-" || op == "*") {
        int64_t value = op == "+" ? a + b : op == "-" ? a - b : a * b;
        return in_range(value) ? std::optional<int64_t>(value) : std::nullopt;
    }
    if (op == "/" || op == "%") {
        if (b == 0)
            return std::nullopt;
        int64_t quotient = a / b;
        if (op == "/")
            return in_range(quotient) ? std::optional<int64_t>(quotient) : std::nullopt;
        return a - quotient * b;
    }
    bool answer = op == "<"    ? a < b
                  : op == "<=" ? a <= b
                  : op == ">"  ? a > b
                  : op == ">=" ? a >= b
                  : op == "==" ? a == b
                  : op == "!=" ? a != b
                  : op == "&&" ? (a != 0 && b != 0)
                               : (a != 0 || b != 0);
    return answer ? 1 : 0;
}
static Expr *fold_expression(Expr *e, int &count) {
    if (!e)
        return nullptr;
    for (Expr *&child : e->children)
        child = fold_expression(child, count);
    if (e->kind == "unary" && literal(e->children[0])) {
        int64_t value =
            e->token.spelling == "-" ? -e->children[0]->value : (e->children[0]->value == 0);
        if (!in_range(value))
            return e;
        ++count;
        return folded_literal(e, value);
    }
    if (e->kind != "binary")
        return e;
    Expr *left = e->children[0];
    Expr *right = e->children[1];
    const std::string &op = e->token.spelling;
    if (literal(left) && literal(right)) {
        std::optional<int64_t> value = constant_binary(op, left->value, right->value);
        if (value) {
            ++count;
            return folded_literal(e, *value);
        }
    }
    if (literal(left)) {
        if ((op == "&&" && left->value == 0) || (op == "||" && left->value != 0)) {
            ++count;
            return folded_literal(e, left->value);
        }
        if ((op == "&&" && left->value != 0) || (op == "||" && left->value == 0) ||
            (op == "+" && left->value == 0) || (op == "*" && left->value == 1)) {
            ++count;
            return right;
        }
    }
    if (literal(right) &&
        ((op == "+" && right->value == 0) || (op == "-" && right->value == 0) ||
         (op == "*" && right->value == 1) || (op == "/" && right->value == 1) ||
         (op == "&&" && right->value != 0) || (op == "||" && right->value == 0))) {
        ++count;
        return left;
    }
    return e;
}
static Statement *fold_statement(Statement *s, int &count) {
    if (!s)
        return nullptr;
    if (s->kind == "if") {
        s->condition = fold_expression(s->condition, count);
        if (literal(s->condition)) {
            Statement *replacement = s->condition->value ? fold_statement(s->yes, count)
                                     : s->no             ? fold_statement(s->no, count)
                                                         : new_statement("empty", s->token);
            ++count;
            return replacement;
        }
        s->yes = fold_statement(s->yes, count);
        s->no = fold_statement(s->no, count);
    } else if (s->kind == "while") {
        s->condition = fold_expression(s->condition, count);
        if (literal(s->condition) && !s->condition->value) {
            ++count;
            return new_statement("empty", s->token);
        }
        s->body = fold_statement(s->body, count);
    } else if (s->kind == "for") {
        s->init = fold_statement(s->init, count);
        s->condition = fold_expression(s->condition, count);
        s->update = fold_statement(s->update, count);
        s->body = fold_statement(s->body, count);
    } else if (s->kind == "block")
        for (Statement *&child : s->statements)
            child = fold_statement(child, count);
    else if (s->kind == "declaration")
        s->declaration->initializer = fold_expression(s->declaration->initializer, count);
    else if (s->kind == "assignment") {
        s->index = fold_expression(s->index, count);
        s->expr = fold_expression(s->expr, count);
    } else if (s->kind == "call" || s->kind == "return")
        s->expr = fold_expression(s->expr, count);
    else if (s->kind == "print")
        for (Expr *&e : s->expressions)
            e = fold_expression(e, count);
    return s;
}
static int fold_program(Program &program, const std::set<Symbol *> &reachable) {
    int count = 0;
    for (Declaration *global : program.globals)
        global->initializer = fold_expression(global->initializer, count);
    for (Declaration *function : program.functions)
        if (reachable.count(function->symbol))
            function->body = fold_statement(function->body, count);
    return count;
}
static std::string inverse(const std::string &op) { return op == "JUMPF" ? "JUMPT" : "JUMPF"; }
static bool branch_taken(const std::string &op, int64_t value) {
    return (op == "JUMPF" && value == 0) || (op == "JUMPT" && value != 0);
}
static void delete_instruction(Unit &unit, int index) {
    unit.code.erase(unit.code.begin() + index);
    for (Instruction &instruction : unit.code)
        if (jump(instruction.op) && instruction.a > index)
            --instruction.a;
}
static std::array<int, 7> optimize(Unit &unit) {
    std::array<int, 7> counts{};
    const std::map<std::string, std::string> negations = {{"LT", "GE"}, {"GE", "LT"}, {"LE", "GT"},
                                                          {"GT", "LE"}, {"EQ", "NE"}, {"NE", "EQ"}};
    while (true) {
        std::set<int> targets;
        for (const Instruction &instruction : unit.code)
            if (jump(instruction.op))
                targets.insert(static_cast<int>(instruction.a));
        bool applied = false;
        for (int i = 0; i < static_cast<int>(unit.code.size()); ++i) {
            Instruction a = unit.code[i], b;
            bool free = i + 1 < static_cast<int>(unit.code.size()) && !targets.count(i + 1);
            if (i + 1 < static_cast<int>(unit.code.size()))
                b = unit.code[i + 1];
            int rule = -1;
            if (a.op == "PUSH" && free && conditional(b.op)) {
                if (branch_taken(b.op, a.a)) {
                    unit.code[i] = {"JUMP", b.a, 0, b.position, nullptr};
                    delete_instruction(unit, i + 1);
                } else {
                    delete_instruction(unit, i + 1);
                    delete_instruction(unit, i);
                }
                rule = 0;
            } else if (negations.count(a.op) && free && b.op == "NOT") {
                unit.code[i].op = negations.at(a.op);
                delete_instruction(unit, i + 1);
                rule = 1;
            } else if (a.op == "NOT" && free && conditional(b.op)) {
                unit.code[i] = {inverse(b.op), b.a, 0, b.position, nullptr};
                delete_instruction(unit, i + 1);
                rule = 2;
            } else if (conditional(a.op) && a.a == i + 2 && free && b.op == "JUMP") {
                unit.code[i] = {inverse(a.op), b.a, 0, a.position, nullptr};
                delete_instruction(unit, i + 1);
                rule = 3;
            } else {
                if (jump(a.op) && a.a < static_cast<int64_t>(unit.code.size())) {
                    int t = static_cast<int>(a.a);
                    const Instruction &target = unit.code[t];
                    int new_target = -1;
                    if (target.op == "JUMP")
                        new_target = static_cast<int>(target.a);
                    else if (target.op == "PUSH" && t + 1 < static_cast<int>(unit.code.size()) &&
                             conditional(unit.code[t + 1].op))
                        new_target = branch_taken(unit.code[t + 1].op, target.a)
                                         ? static_cast<int>(unit.code[t + 1].a)
                                         : t + 2;
                    if (new_target >= 0 && new_target != t) {
                        unit.code[i].a = new_target;
                        rule = 4;
                    }
                }
                if (rule < 0 && jump(a.op) && a.a == i + 1) {
                    if (a.op == "JUMP")
                        delete_instruction(unit, i);
                    else
                        unit.code[i] = {"POP", 0, 0, a.position, nullptr};
                    rule = 5;
                }
                if (rule < 0 && transfer(a.op) && free) {
                    delete_instruction(unit, i + 1);
                    rule = 6;
                }
            }
            if (rule >= 0) {
                ++counts[rule];
                applied = true;
                break;
            }
        }
        if (!applied)
            return counts;
    }
}
static int arrange(std::vector<Unit> &units) {
    int start = 0;
    std::map<Declaration *, int> starts;
    for (Unit &unit : units) {
        unit.start = start;
        if (unit.function)
            starts[unit.function] = start;
        start += static_cast<int>(unit.code.size());
    }
    for (Unit &unit : units)
        for (Instruction &instruction : unit.code)
            if (instruction.op == "CALL")
                instruction.a = starts.at(instruction.callee);
    return start;
}
static int stack_effect(const Instruction &i) {
    if (word_in("PUSH LOADG LOADL READ", i.op))
        return 1;
    if (word_in("POP STOREG STOREL JUMPF JUMPT RETV ADD SUB MUL DIV MOD LT LE GT GE EQ NE", i.op))
        return -1;
    if (i.op == "STOREA")
        return -2;
    if (i.op == "CALL")
        return -static_cast<int>(i.b) + (i.callee->type != "void");
    if (i.op == "PRINT")
        return -static_cast<int>(i.a);
    return 0;
}
static void analyze_unit(Unit &unit) {
    int n = static_cast<int>(unit.code.size());
    std::set<int> leaders = {0};
    for (int i = 0; i < n; ++i) {
        const Instruction &instruction = unit.code[i];
        if (jump(instruction.op) && instruction.a < n)
            leaders.insert(static_cast<int>(instruction.a));
        if ((jump(instruction.op) || transfer(instruction.op)) && i + 1 < n)
            leaders.insert(i + 1);
    }
    std::vector<int> indices(leaders.begin(), leaders.end()), block_of(n);
    for (size_t k = 0; k < indices.size(); ++k) {
        int first = indices[k], last = k + 1 < indices.size() ? indices[k + 1] - 1 : n - 1;
        for (int i = first; i <= last; ++i)
            block_of[i] = static_cast<int>(k);
        unit.blocks.push_back({first, last, {}});
    }
    for (BasicBlock &block : unit.blocks) {
        const Instruction &last = unit.code[block.last];
        std::vector<int> successors;
        if (last.op == "JUMP")
            successors.push_back(static_cast<int>(last.a));
        else if (conditional(last.op))
            successors = {block.last + 1, static_cast<int>(last.a)};
        else if (!transfer(last.op))
            successors.push_back(block.last + 1);
        for (int index : successors)
            if (index < n && std::find(block.successors.begin(), block.successors.end(),
                                       block_of[index]) == block.successors.end())
                block.successors.push_back(block_of[index]);
    }
    std::vector<int> depths(n, -1), queue = {0};
    depths[0] = 0;
    for (size_t head = 0; head < queue.size(); ++head) {
        int i = queue[head];
        const Instruction &instruction = unit.code[i];
        int depth = depths[i] + stack_effect(instruction);
        unit.stack = std::max(unit.stack, depth);
        std::vector<int> next;
        if (!transfer(instruction.op) && i + 1 < n)
            next.push_back(i + 1);
        if (jump(instruction.op) && instruction.a < n)
            next.push_back(static_cast<int>(instruction.a));
        for (int index : next)
            if (depths[index] < 0) {
                depths[index] = depth;
                queue.push_back(index);
            }
    }
}
static bool recursive(Symbol *function) {
    std::set<Symbol *> seen;
    std::function<bool(Symbol *)> visit = [&](Symbol *current) {
        seen.insert(current);
        for (Symbol *callee : current->calls) {
            if (callee == function)
                return true;
            if (!seen.count(callee) && visit(callee))
                return true;
        }
        return false;
    };
    return visit(function);
}
static std::string spelling(const Instruction &instruction, int start = 0) {
    std::string text = instruction.op;
    int64_t a = instruction.a + (jump(instruction.op) ? start : 0);
    if (word_in("PUSH LOADG STOREG LOADL STOREL LOADA STOREA JUMP JUMPF JUMPT CALL ENTER PRINT",
                instruction.op))
        text += " " + std::to_string(a);
    if (instruction.op == "LOADA" || instruction.op == "STOREA" || instruction.op == "CALL")
        text += " " + std::to_string(instruction.b);
    return text;
}
static std::string callees(Symbol *symbol) {
    std::vector<std::string> names;
    for (Symbol *callee : symbol->calls)
        names.push_back(callee->name);
    std::sort(names.begin(), names.end());
    return names.empty() ? "-" : join(names, ",");
}
static void listing(std::ostream &output, Program &program, const std::vector<Unit> &before,
                    const std::vector<Unit> &after, int before_count, int after_count) {
    if (program.globals.empty())
        output << "globals: none\n";
    else {
        output << "globals:\n";
        for (Declaration *d : program.globals)
            output << "  " << d->symbol->address << " " << d->name.spelling << " "
                   << (d->array ? "int[" + std::to_string(d->size.integer) + "]" : d->type) << "\n";
    }
    output << "functions:\n";
    for (size_t i = 0; i < after.size(); ++i) {
        const Unit &unit = after[i];
        std::string signature, calls = "main", suffix;
        if (unit.function) {
            Declaration *f = unit.function;
            std::vector<std::string> parameters;
            for (Declaration *p : f->parameters)
                parameters.push_back(p->type);
            signature = " " + f->type + "(" + join(parameters, ",") + ")";
            calls = callees(f->symbol);
            if (recursive(f->symbol))
                suffix = " recursive";
        }
        output << "  " << unit.name << signature << " address=" << before[i].start << "->"
               << unit.start << " size=" << before[i].code.size() << "->" << unit.code.size()
               << " slots=" << unit.slots << " stack=" << unit.stack
               << " blocks=" << unit.blocks.size() << " calls=" << calls << suffix << "\n";
        if (unit.function)
            for (size_t slot = 0; slot < unit.function->slots.size(); ++slot) {
                Symbol *symbol = unit.function->slots[slot];
                output << "    slot " << slot << " " << symbol->name << " " << symbol->type << "\n";
            }
    }
    output << "references:\n";
    std::vector<Declaration *> declarations = program.globals;
    declarations.insert(declarations.end(), program.functions.begin(), program.functions.end());
    for (Declaration *d : declarations) {
        std::set<int> lines;
        for (Position p : d->symbol->references)
            lines.insert(p.line);
        output << "  " << d->name.spelling << " defined " << d->name.position.line << " used";
        if (lines.empty())
            output << " -";
        else
            for (int line : lines)
                output << " " << line;
        output << "\n";
    }
    for (int pass = 0; pass < 2; ++pass) {
        const std::vector<Unit> &units = pass ? after : before;
        output << (pass ? "after" : "before")
               << " peephole: " << (pass ? after_count : before_count) << " instructions\n";
        for (const Unit &unit : units) {
            output << unit.name << ":\n";
            for (size_t i = 0; i < unit.code.size(); ++i)
                output << std::right << std::setw(5) << unit.start + static_cast<int>(i) << "  "
                       << spelling(unit.code[i], unit.start) << "\n";
        }
    }
    output << "control flow:\n";
    for (const Unit &unit : after) {
        output << "  " << unit.name << "\n";
        for (size_t k = 0; k < unit.blocks.size(); ++k) {
            const BasicBlock &block = unit.blocks[k];
            output << "    B" << k << " " << unit.start + block.first << "-"
                   << unit.start + block.last;
            if (!block.successors.empty()) {
                output << " ->";
                for (int successor : block.successors)
                    output << " B" << successor;
            }
            output << "\n";
        }
    }
}
static std::vector<std::pair<std::string, int>>
sorted_counts(const std::map<std::string, int> &counts, bool positive) {
    std::vector<std::pair<std::string, int>> result;
    for (const auto &entry : counts)
        if (!positive || entry.second > 0)
            result.push_back(entry);
    std::sort(result.begin(), result.end(), [](const auto &a, const auto &b) {
        return a.second != b.second ? a.second > b.second : a.first < b.first;
    });
    return result;
}
static int sum_rules(const std::array<int, 7> &rules) {
    int total = 0;
    for (int count : rules)
        total += count;
    return total;
}
static void statistics(std::ostream &output, const std::vector<Unit> &units, int before_count,
                       int after_count, int folds, const std::array<int, 7> &rules, RunResult &run,
                       const RunResult &comparison) {
    bool same = run.error == comparison.error && run.output == comparison.output;
    output << "code: " << before_count << " -> " << after_count << "\nfolds: " << folds
           << "\npeephole: " << sum_rules(rules) << "\n";
    for (size_t i = 0; i < rules.size(); ++i)
        output << "  " << rule_names[i] << " " << rules[i] << "\n";
    output << "executed: " << run.executed << "\nexecuted before peephole: " << comparison.executed
           << "\nbehaviour: " << (same ? "same" : "different")
           << "\nmax call depth: " << run.maximum_depth << "\nmax stack: " << run.maximum_stack
           << "\nopcodes:\n";
    std::vector<Executable> code = flatten(units);
    std::map<std::string, int> opcodes, functions;
    std::map<int, int> line_counts;
    for (const Unit &unit : units)
        if (unit.function)
            functions[unit.name] = 0;
    for (size_t pc = 0; pc < code.size(); ++pc) {
        const Executable &current = code[pc];
        int count = run.counts[pc];
        opcodes[current.instruction.op] += count;
        if (units[current.unit].function)
            functions[units[current.unit].name] += count;
        line_counts[current.instruction.position.line] += count;
    }
    for (const auto &record : sorted_counts(opcodes, true))
        output << "  " << record.first << " " << record.second << "\n";
    output << "functions:\n";
    for (const auto &record : sorted_counts(functions, false))
        output << "  " << record.first << " calls=" << run.calls[record.first]
               << " executed=" << record.second << "\n";
    output << "calls:\n";
    std::vector<std::pair<std::pair<std::string, std::string>, int>> pairs(run.pairs.begin(),
                                                                           run.pairs.end());
    std::sort(pairs.begin(), pairs.end(), [](const auto &a, const auto &b) {
        return a.second != b.second ? a.second > b.second : a.first < b.first;
    });
    for (const auto &pair : pairs)
        output << "  " << pair.first.first << " -> " << pair.first.second << " " << pair.second
               << "\n";
    std::vector<int> positive, negative;
    for (const auto &entry : line_counts)
        (entry.second ? positive : negative).push_back(entry.first);
    std::sort(positive.begin(), positive.end(), [&](int a, int b) {
        return line_counts[a] != line_counts[b] ? line_counts[a] > line_counts[b] : a < b;
    });
    output << "hot lines:\n";
    for (size_t i = 0; i < std::min<size_t>(5, positive.size()); ++i)
        output << "  line " << positive[i] << ": " << line_counts[positive[i]] << "\n";
    output << "coverage: " << positive.size() << " of " << line_counts.size()
           << " lines\nnot executed:";
    if (negative.empty())
        output << " none";
    else
        for (int line : negative)
            output << " " << line;
    output << "\nhot spots:\n";
    std::vector<int> pcs;
    for (size_t pc = 0; pc < run.counts.size(); ++pc)
        if (run.counts[pc])
            pcs.push_back(static_cast<int>(pc));
    std::sort(pcs.begin(), pcs.end(), [&](int a, int b) {
        return run.counts[a] != run.counts[b] ? run.counts[a] > run.counts[b] : a < b;
    });
    for (size_t i = 0; i < std::min<size_t>(5, pcs.size()); ++i) {
        int pc = pcs[i];
        output << "  pc=" << pc << " count=" << run.counts[pc] << " "
               << spelling(code[pc].instruction) << "\n";
    }
}
static void position_display(std::ostream &output, Position position,
                             const std::vector<std::string> &lines) {
    output << "  " << lines[position.line - 1] << "\n"
           << std::string(position.column + 1, ' ') << "^\n";
}
static void runtime_diagnostics(std::ostream &output, const std::vector<Unit> &units,
                                const RunResult &run, const std::vector<std::string> &lines) {
    std::vector<Executable> code = flatten(units);
    const Executable &instruction = code[run.fault_pc];
    output << "runtime error " << position_text(instruction.instruction.position) << ": "
           << run.error << " in " << units[instruction.unit].name << "\n";
    position_display(output, instruction.instruction.position, lines);
    int count = std::max(0, static_cast<int>(run.frames.size()) - 1), shown = 0;
    for (int i = static_cast<int>(run.frames.size()) - 1; i >= 1 && shown < 5; --i) {
        const Executable &caller = code[run.frames[i].return_address - 1];
        output << "  called from " << units[caller.unit].name << " at "
               << position_text(caller.instruction.position) << "\n";
        ++shown;
    }
    if (count > shown)
        output << "  ... " << count - shown << " more\n";
}
static std::vector<std::string> read_lines(const std::string &path) {
    std::ifstream input(path);
    std::string line;
    std::vector<std::string> result;
    while (std::getline(input, line))
        result.push_back(line);
    return result;
}
int main() {
    std::vector<std::string> lines = read_lines("input/program.src");
    std::vector<Source> programs;
    for (size_t i = 0; i < lines.size(); ++i) {
        if (lines[i].compare(0, 9, "#program ") == 0)
            programs.push_back({lines[i].substr(9), static_cast<int>(i) + 2, {}});
        else
            programs.back().lines.push_back(lines[i]);
    }
    std::map<std::string, std::vector<int64_t>> inputs;
    std::string input_name;
    for (const std::string &line : read_lines("input/input.txt")) {
        if (line.compare(0, 7, "#input ") == 0) {
            input_name = line.substr(7);
            inputs[input_name] = {};
        } else {
            std::istringstream row(line);
            int64_t value;
            while (row >> value)
                inputs[input_name].push_back(value);
        }
    }
    std::filesystem::create_directories("output");
    std::ofstream listing_output("output/listing.txt"), value_output("output/output.txt"),
        diagnostics("output/diagnostics.txt"), stats("output/stats.txt");
    int compiled = 0, runtime_errors = 0, total_folds = 0, total_executed = 0;
    std::map<std::string, int> errors;
    std::array<int, 7> total_rules{};
    std::vector<std::array<std::string, 5>> table = {
        {{"program", "status", "code", "executed", "output"}}};
    for (const Source &source : programs) {
        std::string heading = "== program " + source.name + " ==\n";
        listing_output << heading;
        value_output << heading;
        diagnostics << heading;
        stats << heading;
        Program program;
        try {
            Parser parser{tokenize(source.lines, source.first_line)};
            program = parser.program();
            Semantics semantics{&program, {}, nullptr, 0};
            semantics.analyze();
        } catch (const CompileError &failure) {
            ++errors[failure.kind];
            listing_output << "not compiled\n";
            stats << "not compiled\n";
            diagnostics << failure.kind << " error " << position_text(failure.position) << ": "
                        << failure.message << "\n";
            position_display(diagnostics, failure.position, lines);
            diagnostics << "status: compile error\n";
            table.push_back({source.name, failure.kind + " error", "-", "-", "-"});
            continue;
        }
        ++compiled;
        std::set<Symbol *> reachable = reachable_functions(program);
        for (const Warning &warning : collect_warnings(program, reachable))
            diagnostics << "warning " << position_text(warning.position) << ": " << warning.message
                        << "\n";
        int folds = fold_program(program, reachable);
        auto generated = generate(program, reachable);
        std::vector<Unit> before = std::move(generated.first);
        int cells = generated.second, before_count = arrange(before);
        std::vector<Unit> after = before;
        std::array<int, 7> rules{};
        for (Unit &unit : after) {
            std::array<int, 7> counts = optimize(unit);
            for (size_t i = 0; i < rules.size(); ++i)
                rules[i] += counts[i];
            analyze_unit(unit);
        }
        int after_count = arrange(after);
        listing(listing_output, program, before, after, before_count, after_count);
        RunResult run = execute(after, cells, inputs[source.name]);
        RunResult comparison = execute(before, cells, inputs[source.name]);
        for (const std::string &line : run.output)
            value_output << line << "\n";
        std::string status = "ok";
        if (!run.error.empty()) {
            ++runtime_errors;
            status = "runtime error";
            runtime_diagnostics(diagnostics, after, run, lines);
        }
        diagnostics << "status: " << status << "\n";
        statistics(stats, after, before_count, after_count, folds, rules, run, comparison);
        total_folds += folds;
        total_executed += run.executed;
        for (size_t i = 0; i < rules.size(); ++i)
            total_rules[i] += rules[i];
        table.push_back({source.name, status, std::to_string(after_count),
                         std::to_string(run.executed), std::to_string(run.output.size())});
    }
    stats << "== summary ==\nprograms: " << programs.size() << "\ncompiled: " << compiled
          << "\ncompile errors: lexical " << errors["lexical"] << " syntax " << errors["syntax"]
          << " semantic " << errors["semantic"] << "\nruntime errors: " << runtime_errors
          << "\nfolds: " << total_folds << "\npeephole: " << sum_rules(total_rules) << "\n";
    for (size_t i = 0; i < rule_names.size(); ++i)
        stats << "  " << rule_names[i] << " " << total_rules[i] << "\n";
    stats << "executed: " << total_executed << "\n";
    std::array<size_t, 5> widths{};
    for (const auto &row : table)
        for (size_t i = 0; i < 5; ++i)
            widths[i] = std::max(widths[i], row[i].size());
    for (const auto &row : table) {
        stats << "  ";
        for (size_t i = 0; i < 5; ++i) {
            if (i)
                stats << "  ";
            size_t padding = widths[i] - row[i].size();
            if (i < 2)
                stats << row[i] << std::string(padding, ' ');
            else
                stats << std::string(padding, ' ') << row[i];
        }
        stats << "\n";
    }
}
