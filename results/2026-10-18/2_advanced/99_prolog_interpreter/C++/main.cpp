#include "prolog.hpp"
namespace prolog {
    static const std::set<Indicator> controls =[] {
        std::set<Indicator> keys = { {",", 2}, {"!", 0}, {";", 2}, {"->", 2}, {"\\+", 1}, {"catch", 3} };
        for (int arity = 1;arity <= 8;++arity) keys.emplace("call", arity);
        return keys;
    }();
    static const std::set<Indicator>& builtin_indicators() {
        static const std::set<Indicator> keys =[] {
            std::set<Indicator> values = deterministic;
            values.insert({ {"findall", 3}, {"throw", 1}, {"between", 3}, {"length", 2} });
            return values;
        }();
        return keys;
    }
    static bool key_is(const Term& term, const std::string& name, int arity) {
        return term && !is_variable(term) && !is_integer(term) && indicator(term) == Indicator {name, arity};
    }
    static Term goal_conversion(Term term) {
        term = dereference(term);
        if (is_variable(term)) return compound("call", {term});
        if (is_integer(term)) return {};
        if (is_compound(term) && term->args.size() == 2 &&(term->name == "," || term->name == ";" || term->name == "->")) {
            Term left = goal_conversion(term->args[0]);
            if (!left) return {};
            Term right = goal_conversion(term->args[1]);
            if (!right) return {};
            return compound(term->name, {left, right});
        }
        return term;
    }
    static std::string join(const std::vector<std::string>& values, const std::string& separator = ",") {
        std::string result;
        for (std::size_t i = 0;i < values.size();++i) {
            if (i) result += separator;
            result += values[i];
        }
        return result;
    }
    static bool alphanumeric(char c) {
        return(c >= 'a' && c <= 'z') ||(c >= 'A' && c <= 'Z') ||(c >= '0' && c <= '9') || c == '_';
    }
    static std::string atom_name(const std::string& name, bool quoted) {
        bool word = !name.empty() && name[0] >= 'a' && name[0] <= 'z';
        for (char c : name) word = word && alphanumeric(c);
        bool symbolic = !name.empty() && name != ".";
        for (char c : name) symbolic = symbolic && symbols.find(c) != std::string::npos;
        if (!quoted || word || symbolic || name == "[]" || name == "!" || name == ";") return name;
        std::string result = "'";
        for (char c : name) {
            if (c == '\\') result += "\\\\";
            else if (c == '\'') result += "\\'";
            else if (c == '\n') result += "\\n";
            else if (c == '\t') result += "\\t";
            else result.push_back(c);
        }
        return result + "'";
    }
    class Writer {
        std::map<const TermData*, std::string> names;
        int next_name = 1;
        bool quoted = true;
        public:
        explicit Writer(bool style = true) : quoted(style) {
        }
        explicit Writer(std::map<const TermData*, std::string> supplied) : names(std::move(supplied)) {
        }
        std::string write(Term term, int limit = 1200, bool operand = false) {
            term = dereference(term);
            if (is_variable(term)) {
                if (!names.count(term.get())) names[term.get()] = "_G" + std::to_string(next_name++);
                return names.at(term.get());
            }
            if (is_integer(term)) return std::to_string(term->integer);
            if (is_atom(term)) {
                std::string text = atom_name(term->name, quoted);
                return operand &&(infix.count(term->name) || prefix.count(term->name)) ? "(" + text + ")" : text;
            }
            const std::string& name = term->name;
            const std::vector<Term>& args = term->args;
            if (name == "." && args.size() == 2) {
                std::pair<std::vector<Term>, Term> parts = list_parts(term);
                std::vector<std::string> elements;
                for (const Term& element : parts.first) elements.push_back(write(element, 999));
                std::string text = "[" + join(elements);
                if (!is_atom(parts.second, "[]")) text += "|" + write(parts.second, 999);
                return text + "]";
            }
            if (args.size() == 2 && infix.count(name)) {
                Operator op = infix.at(name);
                std::string left = write(args[0], op.left, true), right = write(args[1], op.right, true), text;
                if (name == ",") text = left + "," + right;
                else if (name[0] >= 'a' && name[0] <= 'z') text = left + " " + name + " " + right;
                else {
                    std::string before = !left.empty() && symbols.find(left.back()) != std::string::npos ? " " : "", after = !right.empty() && symbols.find(right.front()) != std::string::npos ? " " : "";
                    text = left + before + name + after + right;
                }
                return op.priority > limit ? "(" + text + ")" : text;
            }
            if (args.size() == 1 && prefix.count(name)) {
                int priority = prefix.at(name);
                std::string argument = write(args[0], priority, true);
                bool space = !argument.empty() &&(symbols.find(argument[0]) != std::string::npos ||(argument[0] >= '0' && argument[0] <= '9') || argument[0] == '(');
                std::string text = name +(space ? " " : "") + argument;
                return priority > limit ? "(" + text + ")" : text;
            }
            std::vector<std::string> arguments;
            for (const Term& argument : args) arguments.push_back(write(argument, 999));
            return atom_name(name, quoted) + "(" + join(arguments) + ")";
        }
    };
    static std::string predicate_name(const Indicator& key) {
        return Writer().write(indicator_term(key));
    }
    class Consultant {
        std::map<std::string, std::array<int, 3>> counts;
        std::map<std::string, Indicator> last;
        std::set<std::pair<std::string, Indicator>> discontiguous;
        void warning(const std::string& file, int line, const std::string& message) {
            reports.push_back(file + ":" + std::to_string(line) + ": warning: " + message);
            ++counts[file][2];
        }
        void add(const Term& term, const std::string& file, int line, const Reader& reader) {
            Term head = term, body;
            if (key_is(term, ":-", 2)) {
                head = term->args[0];
                body = term->args[1];
            }
            Term error;
            if (is_variable(head)) error = atom("instantiation_error");
            else if (is_integer(head)) error = type_error("callable", head);
            else if (controls.count(indicator(head)) || builtin_indicators().count(indicator(head))) error = compound("permission_error", {atom("modify"), atom("static_procedure"), indicator_term(indicator(head))});
            else if (body) {
                Term converted = goal_conversion(body);
                if (!converted) error = type_error("callable", body);
                else body = converted;
            }
            if (error) {
                reports.push_back(file + ":" + std::to_string(line) + ": error: " + Writer().write(error));
                ++counts[file][1];
                return;
            }
            Indicator key = indicator(head);
            std::map<Indicator, std::vector<Clause>>::iterator previous = database.predicates.find(key);
            if (file == "program.pl" && previous != database.predicates.end() && std::any_of(previous->second.begin(), previous->second.end(),[](const Clause& c) {
                return c.file == "prelude.pl";
            })) {
                warning(file, line, "redefining prelude procedure " + predicate_name(key));
                previous->second.clear();
            }
            if (previous != database.predicates.end() && std::any_of(previous->second.begin(), previous->second.end(),[&](const Clause& c) {
                return c.file == file;
            }) && last[file] != key && !discontiguous.count({file, key})) {
                warning(file, line, "clauses of " + predicate_name(key) + " are not together");
                discontiguous.emplace(file, key);
            }
            database.add({head, body, file, line});
            last[file] = key;
            ++counts[file][0];
            std::vector<std::string> singletons, repeated;
            for (const std::string& name : reader.count_order) {
                int count = reader.counts.at(name);
                if (name[0] != '_' && count == 1) singletons.push_back(name);
                if (name.size() > 1 && name[0] == '_' && count > 1) repeated.push_back(name);
            }
            if (!singletons.empty()) warning(file, line, "singleton variables: " + join(singletons, ", "));
            if (!repeated.empty()) warning(file, line, "variables starting with _ occur more than once: " + join(repeated, ", "));
        }
        public:
        Database database;
        std::vector<std::string> reports;
        void consult(const std::string& file, const std::string& source) {
            counts[file] = {0, 0, 0};
            Reader reader(source);
            std::vector<std::string> lines;
            std::istringstream stream(source);
            std::string text;
            while (std::getline(stream, text)) lines.push_back(text);
            while (reader.peek().kind != "eof") {
                int line = reader.peek().line;
                try {
                    Term term = reader.clause();
                    add(term, file, line, reader);
                } catch (const SyntaxError& error) {
                    const Token& token = error.token;
                    ++counts[file][1];
                    reports.push_back(file + ":" + std::to_string(token.line) + ":" + std::to_string(token.column) + ": syntax error: " + error.message);
                    if (token.kind != "eof") {
                        reports.push_back("    " + lines[token.line - 1]);
                        reports.push_back(std::string(token.column + 3, ' ') + "^");
                    }
                    reader.position = token.index;
                    while (reader.peek().kind != "end" && reader.peek().kind != "eof") reader.take();
                    if (reader.peek().kind == "end") reader.take();
                }
            }
        }
        void finish() {
            std::set<Indicator> reported;
            for (const Indicator& source : database.order) for (const Clause& clause : database.predicates.at(source)) {
                std::vector<Term> pending;
                if (clause.body) pending.push_back(clause.body);
                while (!pending.empty()) {
                    Term term = dereference(pending.back());
                    pending.pop_back();
                    if (is_variable(term) || is_integer(term)) continue;
                    Indicator key = indicator(term);
                    if (key == Indicator {",", 2} || key == Indicator {";", 2} || key == Indicator {"->", 2}) {
                        pending.push_back(term->args[1]);
                        pending.push_back(term->args[0]);
                    } else if (key == Indicator {"\\+", 1} || key == Indicator {"call", 1}) pending.push_back(term->args[0]);
                    else if (key == Indicator {"findall", 3}) pending.push_back(term->args[1]);
                    else if (key == Indicator {"catch", 3}) {
                        pending.push_back(term->args[2]);
                        pending.push_back(term->args[0]);
                    } else if (!controls.count(key) && !builtin_indicators().count(key) && !database.predicates.count(key) && reported.insert(key).second) warning(clause.file, clause.line, "undefined procedure " + predicate_name(key) + " called from " + predicate_name(source));
                }
            }
            for (const std::string& file : std::vector<std::string> {"prelude.pl", "program.pl"}) {
                const std::array<int, 3>& c = counts[file];
                reports.push_back(file + ": clauses=" + std::to_string(c[0]) + " errors=" + std::to_string(c[1]) + " warnings=" + std::to_string(c[2]));
            }
            std::size_t clauses = 0;
            for (const auto& entry : database.predicates) clauses += entry.second.size();
            reports.push_back("database: predicates=" + std::to_string(database.order.size()) + " clauses=" + std::to_string(clauses));
        }
    };
    static std::vector<std::string> listing(const Database& database) {
        std::vector<std::string> lines;
        for (const Indicator& key : database.order) {
            if (!lines.empty()) lines.push_back("");
            for (const Clause& clause : database.predicates.at(key)) {
                std::vector<Term> occurrences = variables_in({clause.head, clause.body});
                std::map<const TermData*, int> counts;
                for (const Term& v : occurrences)++counts[v.get()];
                std::map<const TermData*, std::string> names;
                int serial = 0;
                for (const Term& v : occurrences) if (!names.count(v.get())) {
                    if (counts[v.get()] == 1) names[v.get()] = "_";
                    else {
                        names[v.get()] = std::string(1, static_cast<char>('A' + serial%26)) +(serial < 26 ? "" : std::to_string(serial/26));
                        ++serial;
                    }
                }
                Writer writer(names);
                std::string head = writer.write(clause.head);
                if (!clause.body) {
                    lines.push_back(head + ".");
                    continue;
                }
                lines.push_back(head + " :-");
                std::vector<Term> goals;
                Term body = clause.body;
                while (key_is(body, ",", 2)) {
                    goals.push_back(body->args[0]);
                    body = body->args[1];
                }
                goals.push_back(body);
                for (std::size_t i = 0;i < goals.size();++i) lines.push_back("    " + writer.write(goals[i], 999) +(i + 1 == goals.size() ? "." : ","));
            }
        }
        return lines;
    }
    using QueryVariables = std::vector<std::pair<std::string, Term>>;
    static std::string answer(const QueryVariables& variables) {
        std::map<const TermData*, std::string> names, previous;
        for (const auto& entry : variables) {
            Term value = dereference(entry.second);
            if (is_variable(value) && !names.count(value.get())) names[value.get()] = entry.first;
        }
        Writer writer(names);
        std::vector<std::string> items;
        for (const auto& entry : variables) {
            Term value = dereference(entry.second);
            if (is_variable(value)) {
                if (previous.count(value.get())) items.push_back(previous[value.get()] + " = " + entry.first);
                previous[value.get()] = entry.first;
            } else items.push_back(entry.first + " = " + writer.write(value, 699, true));
        }
        return items.empty() ? "true" : join(items, ", ");
    }
    struct InferenceLimit {
    };
    struct Entry {
        Term goal;
        int barrier = 0, context = -1;
        std::string marker;
        int payload = 0;
    };
    struct GoalNode {
        Entry entry;
        int next = -1;
    };
    struct Choice {
        std::string kind;
        std::size_t mark = 0;
        int resume = -1, barrier = 0, context = -1, parent = -1;
        Term goal, catcher, recovery, template_term, result, target, tail, number;
        std::vector<const Clause*> candidates;
        std::size_t next_candidate = 0;
        std::vector<Term> results;
        Integer upper = 0, next = 0, count = 0;
    };
    class Engine {
        const Database& database;
        QueryVariables query_variables;
        int limit = 0;
        std::map<Indicator, Integer>& calls;
        std::map<Indicator, Integer>& tries;
        Trail trail;
        std::vector<GoalNode> goal_nodes;
        int goals = -1, context = -1;
        Indicator current_key;
        std::deque < Choice > choices;
        std::vector<int> stack;
        int prepend(int continuation, std::initializer_list<Entry> entries) {
            for (std::initializer_list<Entry>::const_iterator it = entries.end();it != entries.begin();) {
                --it;
                goal_nodes.push_back({*it, continuation});
                continuation = static_cast<int>(goal_nodes.size()) - 1;
            }
            return continuation;
        }
        int create(const std::string& kind, int resume) {
            Choice choice;
            choice.kind = kind;
            choice.resume = resume;
            choice.mark = trail.mark();
            choices.push_back(std::move(choice));
            int id = static_cast<int>(choices.size()) - 1;
            stack.push_back(id);
            ++choicepoints;
            return id;
        }
        void cut(int height) {
            if (height < static_cast<int>(stack.size())) stack.resize(height);
        }
        void infer(const Indicator& key) {
            if (inferences == 20000) throw InferenceLimit {};
            ++inferences;
            ++calls[key];
        }
        bool try_clause(const Clause& clause, const Term& goal, int barrier, int catch_context, int continuation) {
            ++tries[indicator(goal)];
            std::pair<Term, Term> copy = clause.copy();
            if (!trail.unify(copy.first, goal)) return false;
            goals = copy.second ? prepend(continuation, { {copy.second, barrier, catch_context, "", 0} }) : continuation;
            return true;
        }
        bool user_call(const Term& goal, int catch_context) {
            Indicator key = indicator(goal);
            if (!database.predicates.count(key)) throw Fault {compound("existence_error", {atom("procedure"), indicator_term(key)})};
            std::vector<const Clause*> candidates = database.candidates(goal);
            if (candidates.empty()) return false;
            int height = static_cast<int>(stack.size());
            if (candidates.size() > 1) {
                int id = create("CLAUSES", goals);
                Choice& choice = choices[id];
                choice.goal = goal;
                choice.candidates = candidates;
                choice.next_candidate = 1;
                choice.barrier = height;
                choice.context = catch_context;
            }
            return try_clause(*candidates[0], goal, height, catch_context, goals);
        }
        bool control(const Term& goal, int barrier, int catch_context) {
            Indicator key = indicator(goal);
            const std::vector<Term>& args = goal->args;
            int continuation = goals, height = static_cast<int>(stack.size());
            if (key == Indicator {",", 2}) goals = prepend(continuation, { {args[0], barrier, catch_context, "", 0}, {args[1], barrier, catch_context, "", 0} });
            else if (key == Indicator {"!", 0}) cut(barrier);
            else if (key == Indicator {";", 2}) {
                create("ALT", prepend(continuation, { {args[1], barrier, catch_context, "", 0} }));
                Term left = dereference(args[0]);
                if (key_is(left, "->", 2)) goals = prepend(continuation, { {left->args[0], height + 1, catch_context, "", 0}, { {}, barrier, catch_context, "ITE", height}, {left->args[1], barrier, catch_context, "", 0} });
                else goals = prepend(continuation, { {left, barrier, catch_context, "", 0} });
            } else if (key == Indicator {"->", 2}) goals = prepend(continuation, { {args[0], height, catch_context, "", 0}, { {}, barrier, catch_context, "ITE", height}, {args[1], barrier, catch_context, "", 0} });
            else if (key == Indicator {"\\+", 1}) {
                create("ALT", continuation);
                goals = prepend(continuation, { {compound("call", {args[0]}), barrier, catch_context, "", 0}, { {}, barrier, catch_context, "NAF", height} });
            } else if (key.first == "call") {
                Term target = dereference(args[0]);
                if (is_variable(target)) throw Fault {atom("instantiation_error")};
                if (is_integer(target)) throw Fault {type_error("callable", target)};
                if (args.size() > 1) {
                    std::vector<Term> parameters = target->args;
                    parameters.insert(parameters.end(), args.begin() + 1, args.end());
                    target = compound(target->name, std::move(parameters));
                }
                Term converted = goal_conversion(target);
                if (!converted) throw Fault {type_error("callable", target)};
                goals = prepend(continuation, { {converted, height, catch_context, "", 0} });
            } else if (key == Indicator {"catch", 3}) {
                int id = create("CATCH", continuation);
                Choice& choice = choices[id];
                choice.catcher = args[1];
                choice.recovery = args[2];
                choice.parent = catch_context;
                goals = prepend(continuation, { {compound("call", {args[0]}), barrier, id, "", 0}, { {}, barrier, catch_context, "EXIT", id} });
            }
            return true;
        }
        bool marker(const Entry& entry) {
            if (entry.marker == "ITE" || entry.marker == "NAF") {
                cut(entry.payload);
                return entry.marker == "ITE";
            }
            if (entry.marker == "EXIT") {
                if (!stack.empty() && stack.back() == entry.payload) stack.pop_back();
                return true;
            }
            Choice& frame = choices[entry.payload];
            frame.results.push_back(copy_term(frame.template_term));
            return false;
        }
        bool between(const std::vector<Term>& args) {
            Integer lower = require_integer(args[0]), upper = require_integer(args[1]);
            Term value = dereference(args[2]);
            if (!is_variable(value) && !is_integer(value)) throw Fault {type_error("integer", value)};
            if (is_integer(value)) return lower <= value->integer && value->integer <= upper;
            if (lower > upper) return false;
            if (lower < upper) {
                int id = create("BETWEEN", goals);
                Choice& choice = choices[id];
                choice.upper = upper;
                choice.target = value;
                choice.next = lower + 1;
            }
            return trail.unify(value, integer(lower));
        }
        static Term variable_list(Integer count) {
            std::vector<Term> elements;
            for (Integer i = 0;i < count;++i) elements.push_back(variable());
            return make_list(elements);
        }
        bool length(const std::vector<Term>& args) {
            Term sequence = args[0], number = dereference(args[1]);
            if (!is_variable(number) && !is_integer(number)) throw Fault {type_error("integer", number)};
            if (is_integer(number) && number->integer < 0) throw Fault {domain_error("not_less_than_zero", number)};
            std::pair<std::vector<Term>, Term> parts = list_parts(sequence);
            Integer count = static_cast<Integer>(parts.first.size());
            Term tail = parts.second;
            if (is_atom(tail, "[]")) return trail.unify(number, integer(count));
            if (!is_variable(tail)) throw Fault {type_error("list", sequence)};
            if (is_integer(number)) {
                if (number->integer < count) return false;
                return trail.unify(tail, variable_list(number->integer - count));
            }
            int id = create("LENGTH", goals);
            Choice& choice = choices[id];
            choice.tail = tail;
            choice.number = number;
            choice.count = count;
            choice.next = count + 1;
            return trail.unify(tail, atom("[]")) && trail.unify(number, integer(count));
        }
        bool step() {
            Entry entry = goal_nodes[goals].entry;
            goals = goal_nodes[goals].next;
            context = entry.context;
            if (!entry.marker.empty()) return marker(entry);
            Term goal = dereference(entry.goal);
            current_key = indicator(goal);
            if (controls.count(current_key)) return control(goal, entry.barrier, entry.context);
            infer(current_key);
            if (current_key == Indicator {"findall", 3}) {
                int id = create("FINDALL", goals);
                Choice& frame = choices[id];
                frame.template_term = goal->args[0];
                frame.result = goal->args[2];
                goals = prepend(-1, { {compound("call", {goal->args[1]}), entry.barrier, entry.context, "", 0}, { {}, entry.barrier, entry.context, "COLLECT", id} });
                return true;
            }
            if (current_key == Indicator {"throw", 1}) {
                Term ball = dereference(goal->args[0]);
                if (is_variable(ball)) throw Fault {atom("instantiation_error")};
                throw Ball {ball};
            }
            if (current_key == Indicator {"between", 3}) return between(goal->args);
            if (current_key == Indicator {"length", 2}) return length(goal->args);
            if (deterministic.count(current_key)) return execute(goal, trail,[this](const Term& term, bool quoted) {
                output += term ? Writer(quoted).write(term) : "\n";
            });
            return user_call(goal, entry.context);
        }
        bool backtrack() {
            while (true) {
                ++backtracks;
                while (!stack.empty()) {
                    Choice& top = choices[stack.back()];
                    trail.undo(top.mark);
                    if (top.kind != "CATCH") break;
                    stack.pop_back();
                }
                if (stack.empty()) return false;
                int id = stack.back();
                Choice& choice = choices[id];
                if (choice.kind == "ALT") {
                    stack.pop_back();
                    goals = choice.resume;
                    return true;
                }
                if (choice.kind == "CLAUSES") {
                    const Clause* clause = choice.candidates[choice.next_candidate];
                    if (choice.next_candidate + 1 == choice.candidates.size()) stack.pop_back();
                    else ++choice.next_candidate;
                    if (try_clause(*clause, choice.goal, choice.barrier, choice.context, choice.resume)) return true;
                } else if (choice.kind == "BETWEEN") {
                    infer({"between", 3});
                    Integer value = choice.next;
                    if (value == choice.upper) stack.pop_back();
                    else ++choice.next;
                    if (trail.unify(choice.target, integer(value))) {
                        goals = choice.resume;
                        return true;
                    }
                } else if (choice.kind == "LENGTH") {
                    infer({"length", 2});
                    Integer count = choice.next++;
                    if (trail.unify(choice.tail, variable_list(count - choice.count)) && trail.unify(choice.number, integer(count))) {
                        goals = choice.resume;
                        return true;
                    }
                } else if (choice.kind == "FINDALL") {
                    stack.pop_back();
                    if (trail.unify(make_list(choice.results), choice.result)) {
                        goals = choice.resume;
                        return true;
                    }
                }
            }
        }
        bool handle_exception(Term ball) {
            ball = copy_term(ball);
            int frame = context;
            while (frame >= 0) {
                Choice& choice = choices[frame];
                std::vector<int>::iterator found = std::find(stack.begin(), stack.end(), frame);
                stack.erase(found, stack.end());
                trail.undo(choice.mark);
                std::size_t mark = trail.mark();
                if (trail.unify(copy_term(ball), choice.catcher)) {
                    goals = prepend(choice.resume, { {compound("call", {choice.recovery}), static_cast<int>(stack.size()), choice.parent, "", 0} });
                    return true;
                }
                trail.undo(mark);
                frame = choice.parent;
            }
            answers.push_back("uncaught exception: " + Writer().write(ball));
            return false;
        }
        public:
        Integer solutions = 0, inferences = 0, choicepoints = 0, backtracks = 0;
        std::vector<std::string> answers;
        std::string output;
        Engine(const Database& db, Term query, QueryVariables variables, int maximum, std::map<Indicator, Integer>& call_counts, std::map<Indicator, Integer>& try_counts) : database(db), query_variables(std::move(variables)), limit(maximum), calls(call_counts), tries(try_counts) {
            goals = prepend(-1, { {compound("call", {query}), 0, -1, "", 0} });
        }
        std::array<Integer, 4> run() {
            while (true) {
                try {
                    bool success;
                    if (goals < 0) {
                        ++solutions;
                        std::string text = answer(query_variables);
                        if ((limit > 0 && solutions == limit) || stack.empty()) {
                            answers.push_back(text + ".");
                            break;
                        }
                        answers.push_back(text + " ;");
                        success = backtrack();
                    } else {
                        success = step();
                        if (!success) success = backtrack();
                    }
                    if (!success) {
                        answers.push_back("false.");
                        break;
                    }
                } catch (const Fault& error) {
                    if (!handle_exception(compound("error", {error.term, indicator_term(current_key)}))) break;
                } catch (const Ball& error) {
                    if (!handle_exception(error.term)) break;
                } catch (const InferenceLimit&) {
                    answers.push_back("inference limit exceeded");
                    break;
                }
            }
            return {solutions, inferences, choicepoints, backtracks};
        }
    };
    static std::string read_file(const std::string& path) {
        std::ifstream input(path);
        return std::string(std::istreambuf_iterator < char >(input), std::istreambuf_iterator < char >());
    }
    static void write_file(const std::string& path, const std::vector<std::string>& lines) {
        std::ofstream output("output/" + path);
        for (const std::string& line : lines) output << line << '\n';
    }
    static std::string statistics(const std::string& prefix, const std::array<Integer, 4>& counts) {
        return prefix + " solutions=" + std::to_string(counts[0]) + " inferences=" + std::to_string(counts[1]) + " choicepoints=" + std::to_string(counts[2]) + " backtracks=" + std::to_string(counts[3]);
    }
}
int main() {
    using namespace prolog;
    Consultant consultant;
    for (const std::string& file : std::vector<std::string> {"prelude.pl", "program.pl"}) consultant.consult(file, read_file("input/" + file));
    consultant.finish();
    std::vector<std::string> answers, stats;
    std::string writes;
    std::map<Indicator, Integer> calls, tries;
    std::array<Integer, 4> totals {};
    std::ifstream queries("input/queries.txt");
    std::string source;
    int number = 0;
    while (std::getline(queries, source)) {
        ++number;
        answers.push_back(source);
        writes += "== query " + std::to_string(number) + " ==\n";
        std::size_t marker = source.find("?- "), start = marker + 3;
        int limit = marker == 0 ? 0 : std::stoi(source.substr(0, marker));
        Reader reader(source.substr(start), static_cast<int>(start + 1));
        Term query;
        try {
            query = reader.clause(true);
        } catch (const SyntaxError& error) {
            answers.push_back("syntax error at column " + std::to_string(error.token.column) + ": " + error.message);
            stats.push_back("query " + std::to_string(number) + ": syntax error");
            continue;
        }
        QueryVariables variables;
        for (const std::string& name : reader.name_order) if (name[0] != '_') variables.emplace_back(name, reader.names.at(name));
        Engine engine(consultant.database, query, std::move(variables), limit, calls, tries);
        std::array<Integer, 4> counts = engine.run();
        for (int i = 0;i < 4;++i) totals[i] += counts[i];
        answers.insert(answers.end(), engine.answers.begin(), engine.answers.end());
        writes += engine.output;
        if (!engine.output.empty() && engine.output.back() != '\n') writes += '\n';
        stats.push_back(statistics("query " + std::to_string(number) + ":", counts));
    }
    stats.push_back(statistics("total:", totals));
    stats.push_back("== profile ==");
    std::vector<Indicator> keys;
    for (const auto& entry : calls) if (entry.second > 0) keys.push_back(entry.first);
    std::sort(keys.begin(), keys.end(),[&](const Indicator& a, const Indicator& b) {
        return calls[a] != calls[b] ? calls[a] > calls[b] : predicate_name(a) < predicate_name(b);
    });
    for (const Indicator& key : keys) {
        std::string text = predicate_name(key) + " calls=" + std::to_string(calls[key]);
        if (consultant.database.predicates.count(key)) text += " tries=" + std::to_string(tries[key]);
        stats.push_back(text);
    }
    write_file("consult.txt", consultant.reports);
    write_file("listing.txt", listing(consultant.database));
    write_file("answers.txt", answers);
    write_file("stats.txt", stats);
    std::ofstream output("output/write_output.txt");
    output << writes;
}
