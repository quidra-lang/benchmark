#include "awk.hpp"
namespace awk {
    struct Analysis {
        std::vector<NodePtr> items, functions, rules, nodes;
        std::map<std::string, int> function_table;
        std::set<Binding> bindings, arrays;
        std::set<std::string> globals = {"FILENAME", "FNR", "FS", "NF", "NR", "OFS", "ORS", "SUBSEP"};
        std::set<int> lines;
        struct Error {
            Position position;
            int priority;
            std::string text;
        };
        std::vector<Error> errors;
        explicit Analysis(std::vector<NodePtr> values) : items(std::move(values)) {
            for (const std::string& name : globals) bindings.emplace(-1, name);
            for (const NodePtr& item : items) if (item->kind == "function") {
                int id = static_cast<int>(functions.size());
                if (function_table.count(item->text)) errors.push_back({item->name_position, 0, "function " + item->text + " redefined"});
                else function_table[item->text] = id;
                functions.push_back(item);
                std::set<std::string> names;
                for (const NodePtr& p : item->nodes) if (!names.insert(p->text).second) errors.push_back({p->position, 1, "duplicate parameter " + p->text});
            } else rules.push_back(item);
            const std::set<std::string> statements = {"if", "while", "do", "for", "for_in", "print", "printf", "delete", "next", "break", "continue", "exit", "return", "expression_statement"};
            int function_id = 0;
            for (const NodePtr& item : items) {
                int scope = -1;
                std::set<std::string> parameters;
                if (item->kind == "function") {
                    scope = function_id++;
                    for (const NodePtr& p : item->nodes) parameters.insert(p->text);
                }
                std::vector<NodePtr> pending = {item};
                while (!pending.empty()) {
                    NodePtr n = pending.back();
                    pending.pop_back();
                    nodes.push_back(n);
                    if (statements.count(n->kind)) lines.insert(n->position.line);
                    if (n->kind == "name" || n->kind == "array" || n->kind == "parameter") {
                        int resolved = scope >= 0 && parameters.count(n->text) ? scope : -1;
                        n->binding = {resolved, n->text};
                        bindings.insert(n->binding);
                        if (resolved < 0) globals.insert(n->text);
                        if (function_table.count(n->text)) errors.push_back({n->position, 2, "function " + n->text + " used as variable"});
                    }
                    if (n->kind == "call") {
                        if (!function_table.count(n->text)) errors.push_back({n->position, 3, "undefined function " + n->text});
                        else {
                            n->target = function_table[n->text];
                            if (n->nodes.size() > functions[n->target]->nodes.size()) errors.push_back({n->position, 4, "too many arguments to " + n->text});
                        }
                    }
                    std::vector<NodePtr> cs = children(n);
                    pending.insert(pending.end(), cs.rbegin(), cs.rend());
                }
            }
            if (!errors.empty()) {
                std::sort(errors.begin(), errors.end(),[](const Error& a, const Error& b) {
                    return std::tie(a.position.line, a.position.column, a.priority) < std::tie(b.position.line, b.position.column, b.priority);
                });
                throw Issue {errors[0].position, errors[0].text, 1};
            }
            std::vector<std::pair<Binding, Binding>> links;
            for (const NodePtr& n : nodes) {
                if (n->kind == "array") arrays.insert(n->binding);
                else if (n->kind == "membership" || n->kind == "delete") arrays.insert(n->a->binding);
                else if (n->kind == "for_in") arrays.insert(n->b->binding);
                else if (n->kind == "builtin" && n->text == "split") arrays.insert(n->nodes[1]->binding);
                else if (n->kind == "call") for (std::size_t i = 0;i < n->nodes.size();++i) if (n->nodes[i]->kind == "name") links.emplace_back(n->nodes[i]->binding, functions[n->target]->nodes[i]->binding);
            }
            bool changed = true;
            while (changed) {
                changed = false;
                for (const auto& link : links) if (arrays.count(link.first) || arrays.count(link.second)) {
                    changed = arrays.insert(link.first).second || changed;
                    changed = arrays.insert(link.second).second || changed;
                }
            }
        }
    };
    using Array = std::map<std::string, Value>;
    struct Cell {
        Value scalar;
        std::shared_ptr < Array > array;
    };
    using CellPtr = std::shared_ptr < Cell >;
    struct Location {
        CellPtr cell;
        std::shared_ptr < Array > array;
        std::string key;
        Integer field = -1;
        bool nf = false;
    };
    struct Transfer {
        std::string kind;
        Value value;
    };
    class Engine {
        Analysis& analysis;
        Arguments arguments;
        std::map<std::string, CellPtr> globals;
        std::vector<std::map<std::string, CellPtr>> locals;
        std::map<int, Integer> line_counts;
        Record record;
        Streams streams;
        std::string phase = "BEGIN";
        Integer exit_status = 0;
        std::optional<Issue> error;
        std::size_t operand_position = 0, input_position = 0;
        InputOperand* current = nullptr;
        std::vector<std::string> input_lines;
        CellPtr cell(const Binding& binding) {
            if (binding.first >= 0) return locals.back().at(binding.second);
            CellPtr& value = globals[binding.second];
            if (!value) value = std::make_shared < Cell >();
            return value;
        }
        Value global(const std::string& name) {
            return name == "NF" ? Value::number(static_cast<Integer>(record.fields.size())) : cell({-1, name})->scalar;
        }
        std::shared_ptr < Array > array(const Binding& binding) {
            CellPtr value = cell(binding);
            if (!value->array) value->array = std::make_shared < Array >();
            return value->array;
        }
        void assign_input(const std::string& name, const std::string& text) {
            analysis.globals.insert(name);
            cell({-1, name})->scalar = Value::input(text);
        }
        std::string subscript(const std::vector<NodePtr>& expressions) {
            std::vector<std::string> values;
            for (const NodePtr& e : expressions) values.push_back(evaluate(e).to_string());
            std::string separator = global("SUBSEP").to_string(), key;
            for (std::size_t i = 0;i < values.size();++i) {
                if (i) key += separator;
                key += values[i];
            }
            return key;
        }
        Location location(const NodePtr& n) {
            Location result;
            if (n->kind == "name") {
                result.cell = cell(n->binding);
                result.nf = n->binding.first < 0 && n->text == "NF";
            } else if (n->kind == "array") {
                result.key = subscript(n->nodes);
                result.array = array(n->binding);
            } else {
                result.field = evaluate(n->a).to_number();
                if (result.field < 0) throw Issue {n->position, "negative field index", 2};
            }
            return result;
        }
        Value read(const Location& l) {
            if (l.field >= 0) return record.read(l.field);
            if (l.array) return(*l.array)[l.key];
            if (l.nf) return global("NF");
            return l.cell->scalar;
        }
        void store(const Location& l, const Value& value, Position position) {
            if (l.field >= 0) record.write(l.field, value);
            else if (l.array)(*l.array)[l.key] = value;
            else if (l.nf) {
                Integer size = value.to_number();
                if (size < 0) throw Issue {position, "negative NF", 2};
                record.resize(size);
            } else l.cell->scalar = value;
        }
        Value call(const NodePtr& n) {
            NodePtr f = analysis.functions[n->target];
            std::map<std::string, CellPtr> frame;
            for (std::size_t i = 0;i < f->nodes.size();++i) {
                NodePtr p = f->nodes[i];
                CellPtr value = std::make_shared < Cell >();
                if (analysis.arrays.count(p->binding)) value->array = i < n->nodes.size() ? array(n->nodes[i]->binding) : std::make_shared < Array >();
                else if (i < n->nodes.size()) value->scalar = evaluate(n->nodes[i]);
                frame[p->text] = value;
            }
            ++f->calls;
            ++f->active;
            f->depth = std::max(f->depth, f->active);
            locals.push_back(std::move(frame));
            Value result;
            try {
                statement(f->a);
            } catch (const Transfer& transfer) {
                locals.pop_back();
                --f->active;
                if (transfer.kind == "return") return transfer.value;
                throw;
            } catch (...) {
                locals.pop_back();
                --f->active;
                throw;
            }
            locals.pop_back();
            --f->active;
            return result;
        }
        Value builtin(const NodePtr& n) {
            const std::vector<NodePtr>& args = n->nodes;
            if (n->text == "length") {
                if (args.empty()) return Value::number(record.zero.to_string().size());
                if (args[0]->kind == "name" && analysis.arrays.count(args[0]->binding)) return Value::number(array(args[0]->binding)->size());
                return Value::number(evaluate(args[0]).to_string().size());
            }
            if (n->text == "split") {
                std::string text = evaluate(args[0]).to_string();
                std::string separator = args.size() == 3 ? evaluate(args[2]).to_string() : global("FS").to_string();
                std::shared_ptr < Array > destination = array(args[1]->binding);
                destination->clear();
                std::vector<std::string> pieces = split_pieces(text, separator);
                for (std::size_t i = 0;i < pieces.size();++i)(*destination)[std::to_string(i + 1)] = Value::input(pieces[i]);
                return Value::number(pieces.size());
            }
            if (n->text == "close") {
                std::string filename = evaluate(args[0]).to_string();
                return Value::number(streams.close(filename));
            }
            std::vector<Value> values;
            for (const NodePtr& arg : args) values.push_back(evaluate(arg));
            return invoke(n->text, values, n->position);
        }
        Value getline(const NodePtr& n) {
            std::pair<int, std::string> result;
            if (n->b) {
                std::string filename = evaluate(n->b).to_string();
                result = streams.getline(filename);
            } else if (phase == "END") return Value::number(0);
            else {
                std::optional<std::string> line = next_record();
                result = {line ? 1 : 0, line ? *line : ""};
            }
            if (result.first == 1) {
                if (n->a) {
                    Location target = location(n->a);
                    store(target, Value::input(result.second), n->position);
                } else record.set(result.second);
            }
            return Value::number(result.first);
        }
        Value evaluate(const NodePtr& n) {
            const std::string& kind = n->kind;
            if (kind == "number") return Value::number(n->number);
            if (kind == "string") return Value::string(n->text);
            if (is_lvalue(n)) return read(location(n));
            if (kind == "paren") return evaluate(n->a);
            if (kind == "assignment") {
                Location target = location(n->a);
                Value value = evaluate(n->b);
                if (n->text != "=") value = arithmetic(n->text.substr(0, 1), read(target), value, n->position);
                store(target, value, n->position);
                return read(target);
            }
            if (kind == "increment") {
                Location target = location(n->a);
                Integer old = read(target).to_number(), value = old + n->number;
                store(target, Value::number(value), n->position);
                return Value::number(n->flag ? value : old);
            }
            if (kind == "conditional") {
                bool condition = evaluate(n->a).truth();
                return evaluate(condition ? n->b : n->c);
            }
            if (kind == "unary") {
                Value value = evaluate(n->a);
                if (n->text == "!") return Value::number(!value.truth());
                return Value::number(n->text == "-" ? -value.to_number() : value.to_number());
            }
            if (kind == "membership") {
                std::string key = subscript(n->nodes);
                return Value::number(array(n->a->binding)->count(key));
            }
            if (kind == "binary") {
                Value a = evaluate(n->a);
                const std::string& op = n->text;
                if (op == "||" && a.truth()) return Value::number(1);
                if (op == "&&" && !a.truth()) return Value::number(0);
                Value b = evaluate(n->b);
                if (op == "&&" || op == "||") return Value::number(b.truth());
                if (op == "concat") return Value::string(a.to_string() + b.to_string());
                int order = compare(a, b);
                if (op == "<") return Value::number(order < 0);
                if (op == "<=") return Value::number(order <= 0);
                if (op == "==") return Value::number(order == 0);
                if (op == "!=") return Value::number(order != 0);
                if (op == ">=") return Value::number(order >= 0);
                if (op == ">") return Value::number(order > 0);
                return arithmetic(op, a, b, n->position);
            }
            if (kind == "call") return call(n);
            if (kind == "builtin") return builtin(n);
            return getline(n);
        }
        void output(const NodePtr& n) {
            std::vector<Value> values;
            for (const NodePtr& e : n->nodes) values.push_back(evaluate(e));
            std::string text;
            if (n->kind == "print") {
                if (values.empty()) values.push_back(record.zero);
                std::string separator = global("OFS").to_string();
                for (std::size_t i = 0;i < values.size();++i) {
                    if (i) text += separator;
                    text += values[i].to_string();
                }
                text += global("ORS").to_string();
            } else text = format_output(values, n->position);
            std::optional<std::string> filename;
            if (n->a) filename = evaluate(n->a).to_string();
            streams.write(text, filename, n->redirect, n->redirect_position);
        }
        bool loop_body(const NodePtr& body) {
            try {
                statement(body);
            } catch (const Transfer& t) {
                if (t.kind == "break") return false;
                if (t.kind != "continue") throw;
            }
            return true;
        }
        void statement(const NodePtr& n) {
            const std::string& kind = n->kind;
            if (kind == "block") {
                for (const NodePtr& s : n->nodes) statement(s);
                return;
            }
            if (kind == "empty") return;
            ++line_counts[n->position.line];
            if (kind == "expression_statement") evaluate(n->a);
            else if (kind == "print" || kind == "printf") output(n);
            else if (kind == "if") {
                NodePtr branch = evaluate(n->a).truth() ? n->b : n->c;
                if (branch) statement(branch);
            } else if (kind == "while") {
                while (evaluate(n->a).truth()) if (!loop_body(n->b)) break;
            } else if (kind == "do") {
                do {
                    if (!loop_body(n->b)) break;
                } while (evaluate(n->a).truth());
            } else if (kind == "for") {
                if (n->a) evaluate(n->a);
                while (!n->b || evaluate(n->b).truth()) {
                    if (!loop_body(n->d)) break;
                    if (n->c) evaluate(n->c);
                }
            } else if (kind == "for_in") {
                std::vector<std::string> keys;
                for (const auto& entry : *array(n->b->binding)) keys.push_back(entry.first);
                std::sort(keys.begin(), keys.end(), subscript_less);
                for (const std::string& key : keys) {
                    Location target = location(n->a);
                    store(target, Value::input(key), n->a->position);
                    if (!loop_body(n->c)) break;
                }
            } else if (kind == "delete") {
                std::shared_ptr < Array > values = array(n->a->binding);
                if (n->flag) {
                    std::string key = subscript(n->nodes);
                    values->erase(key);
                } else values->clear();
            } else if (kind == "next") {
                if (phase == "BEGIN" || phase == "END") throw Issue {n->position, "next used in BEGIN or END", 2};
                throw Transfer {"next", {} };
            } else if (kind == "exit") {
                if (n->a) exit_status = evaluate(n->a).to_number();
                throw Transfer {"exit", {} };
            } else if (kind == "return") {
                Value value = n->a ? evaluate(n->a) : Value {};
                throw Transfer {"return", value};
            } else throw Transfer {kind, {} };
        }
        std::optional<std::string> next_record() {
            while (true) {
                if (input_position < input_lines.size()) {
                    std::string line = input_lines[input_position++];
                    ++current->records;
                    cell({-1, "NR"})->scalar = Value::number(global("NR").to_number() + 1);
                    cell({-1, "FNR"})->scalar = Value::number(global("FNR").to_number() + 1);
                    return line;
                }
                if (operand_position == arguments.operands.size()) return std::nullopt;
                InputOperand& operand = arguments.operands[operand_position++];
                if (!operand.file) assign_input(operand.name, operand.value);
                else {
                    current = &operand;
                    input_lines = read_records(operand.name);
                    input_position = 0;
                    cell({-1, "FILENAME"})->scalar = Value::string(operand.name);
                    cell({-1, "FNR"})->scalar = Value::number(0);
                }
            }
        }
        void actions(const std::string& stage) {
            phase = stage;
            for (const NodePtr& rule : analysis.rules) if (rule->flavor == stage) {
                ++rule->count;
                statement(rule->a);
            }
        }
        bool matches(const NodePtr& rule) {
            if (rule->flavor == "all") return true;
            if (rule->flavor == "pattern") return evaluate(rule->nodes[0]).truth();
            if (!rule->inside && evaluate(rule->nodes[0]).truth()) rule->inside = true;
            if (!rule->inside) return false;
            if (evaluate(rule->nodes[1]).truth()) rule->inside = false;
            return true;
        }
        void records() {
            bool needed = false;
            for (const NodePtr& rule : analysis.rules) if (rule->flavor != "BEGIN") needed = true;
            if (!needed) return;
            phase = "records";
            while (true) {
                std::optional<std::string> line = next_record();
                if (!line) return;
                record.set(*line);
                try {
                    for (const NodePtr& rule : analysis.rules) if (rule->flavor != "BEGIN" && rule->flavor != "END" && matches(rule)) {
                        ++rule->count;
                        if (rule->a) statement(rule->a);
                        else streams.write(record.zero.to_string() + global("ORS").to_string());
                    }
                } catch (const Transfer& t) {
                    if (t.kind != "next") throw;
                }
            }
        }
        public:
        Engine(Analysis& a, Arguments args) : analysis(a), arguments(std::move(args)), record([this](const std::string& name) {
            return global(name);
        }) {
            for (const std::string& name : analysis.globals) {
                CellPtr value = cell({-1, name});
                if (analysis.arrays.count({-1, name})) value->array = std::make_shared < Array >();
            }
            for (const std::string& name : std::vector<std::string> {"FNR", "NR"}) cell({-1, name})->scalar = Value::number(0);
            cell({-1, "FILENAME"})->scalar = Value::string("");
            cell({-1, "FS"})->scalar = Value::string(" ");
            cell({-1, "OFS"})->scalar = Value::string(" ");
            cell({-1, "ORS"})->scalar = Value::string("\n");
            cell({-1, "SUBSEP"})->scalar = Value::string(std::string(1, 28));
            for (int line : analysis.lines) line_counts[line] = 0;
        }
        void execute() {
            try {
                for (const auto& option : arguments.options) assign_input(option.first, option.second);
                try {
                    actions("BEGIN");
                    records();
                } catch (const Transfer& t) {
                    if (t.kind != "exit") throw;
                }
                try {
                    actions("END");
                } catch (const Transfer& t) {
                    if (t.kind != "exit") throw;
                }
            } catch (const Issue& issue) {
                error = issue;
            }
        }
        void save() {
            streams.save();
            std::ofstream out("output/stats.txt");
            if (error) out << "status: runtime error at " << error->position.text() << ": " << error->message << '\n';
            else out << "status: exit " << exit_status << '\n';
            out << "[inputs]\n";
            for (const InputOperand& operand : arguments.operands) if (operand.file) out << operand.name << " records=" << operand.records << '\n';
            out << "[getline]\n";
            for (const std::string& name : streams.input_order) {
                const GetlineInput& source = streams.inputs.at(name);
                out << name << ' ' <<(source.ever ? "reads=" + std::to_string(source.reads) : "missing") << '\n';
            }
            out << "[rules]\n";
            for (const NodePtr& rule : analysis.rules) out << rule->position.text() << ' ' << rule->flavor << " count=" << rule->count << '\n';
            out << "[functions]\n";
            for (const NodePtr& f : analysis.functions) out << f->text << " calls=" << f->calls << " depth=" << f->depth << '\n';
            out << "[outputs]\nstdout.txt writes=" << streams.standard.writes << " bytes=" << streams.standard.content.size() << '\n';
            for (const std::string& name : streams.output_order) {
                const Output& output = streams.outputs.at(name);
                out << name << " writes=" << output.writes << " bytes=" << output.content.size() << '\n';
            }
            out << "[lines]\n";
            for (const auto& entry : line_counts) out << entry.first << " count=" << entry.second << '\n';
            out << "[globals]\n";
            for (const std::string& name : analysis.globals) {
                out << name << " = ";
                if (analysis.arrays.count({-1, name})) out << "array (" << array({-1, name})->size() << ')';
                else out << global(name).describe();
                out << '\n';
            }
        }
    };
}
int main() {
    using namespace awk;
    Arguments args = parse_arguments(read_file("input/args.txt"));
    try {
        std::vector<NodePtr> items = Parser(tokenize(read_file("input/program.awk"))).parse();
        Analysis analysis(std::move(items));
        Engine engine(analysis, std::move(args));
        engine.execute();
        engine.save();
    } catch (const Issue& issue) {
        std::ofstream standard("output/stdout.txt");
        std::ofstream out("output/stats.txt");
        if (issue.kind == 0) out << "status: syntax error at " << issue.position.text() << '\n';
        else out << "status: error at " << issue.position.text() << ": " << issue.message << '\n';
    }
}
