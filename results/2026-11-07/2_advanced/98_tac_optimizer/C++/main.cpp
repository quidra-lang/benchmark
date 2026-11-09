#include "tac.hpp"
namespace tac {
    static std::set<int> reaching_numbers(const DataFlow& flow, int n, const std::string& v) {
        std::set<int> result;
        for (const Definition& d : flow.reaching_before[n]) if (d.first == v) result.insert(d.second);
        return result;
    }
    static std::optional<Integer> constant(const CFG& g, const std::set<int>& definitions) {
        if (definitions.empty() || definitions.count(0)) return std::nullopt;
        std::optional<Integer> result;
        for (int n : definitions) {
            const Instruction& s = g.instructions[n];
            if (s.kind != "copy" || !s.a.constant ||(result && *result != s.a.number)) return std::nullopt;
            result = s.a.number;
        }
        return result;
    }
    struct PassResult {
        int changes = 0;
        std::vector<std::string> records;
    };
    static PassResult propagation(Function& f, const CFG& g, const DataFlow& flow, bool constants) {
        PassResult result;
        Replacements edits;
        for (std::size_t n = 1;n < g.instructions.size();++n) if (g.reachable.count(g.block_of[n])) {
            Instruction s = g.instructions[n];
            for (Operand* operand : s.operands()) if (!operand->constant) {
                std::string variable = operand->variable;
                std::optional<Operand> replacement;
                if (constants) {
                    std::optional<Integer> c = constant(g, reaching_numbers(flow, static_cast<int>(n), variable));
                    if (c) replacement = Operand::value(*c);
                } else for (const Copy& pair : flow.copy_before[n]) if (pair.first == variable) {
                    replacement = Operand::parse(pair.second);
                    break;
                }
                if (replacement) {
                    result.records.push_back("#" + std::to_string(n) + ": " + variable + " -> " + replacement->text());
                    * operand = *replacement;
                }
            }
            if (constants) {
                std::optional<Instruction> folded = fold(s);
                if (!folded) {
                    result.records.push_back("#" + std::to_string(n) + ": delete " + s.text());
                    edits[static_cast<int>(n)] = {};
                    continue;
                }
                if (folded->text() != s.text()) result.records.push_back("#" + std::to_string(n) + ": fold " + folded->text());
                s = *folded;
            }
            edits[static_cast<int>(n)] = {Line::code(s)};
        }
        rewrite(f, edits);
        result.changes = static_cast<int>(result.records.size());
        return result;
    }
    static std::set<int> expression_sources(const CFG& g, const Expression& e, int candidate) {
        int b = g.block_of[candidate];
        std::set<int> sources, seen;
        const std::vector<int>& ns = g.blocks[b].instructions;
        for (std::vector<int>::const_reverse_iterator it = ns.rbegin();it != ns.rend();++it) if (*it < candidate && g.instructions[*it].expression() == std::optional<Expression>(e)) return {*it};
        std::vector<int> pending = g.blocks[b].reachable_predecessors;
        while (!pending.empty()) {
            int p = pending.back();
            pending.pop_back();
            if (!seen.insert(p).second) continue;
            bool found = false;
            const std::vector<int>& numbers = g.blocks[p].instructions;
            for (std::vector<int>::const_reverse_iterator it = numbers.rbegin();it != numbers.rend();++it) if (g.instructions[*it].expression() == std::optional<Expression>(e)) {
                sources.insert(*it);
                found = true;
                break;
            }
            if (!found) pending.insert(pending.end(), g.blocks[p].reachable_predecessors.begin(), g.blocks[p].reachable_predecessors.end());
        }
        return sources;
    }
    static PassResult cse(Function& f, const CFG& g, const DataFlow& flow) {
        std::map<Expression, std::vector<int>> groups;
        for (std::size_t n = 1;n < g.instructions.size();++n) if (g.reachable.count(g.block_of[n])) {
            std::optional<Expression> e = g.instructions[n].expression();
            if (e && flow.expression_before[n].count(*e)) groups[*e].push_back(static_cast<int>(n));
        }
        std::vector<std::pair<Expression, std::vector<int>>> ordered(groups.begin(), groups.end());
        std::sort(ordered.begin(), ordered.end(),[](const auto& a, const auto& b) {
            return a.second[0] < b.second[0];
        });
        PassResult result;
        Replacements edits;
        for (const std::pair<Expression, std::vector<int>>& group : ordered) {
            std::set<int> sources;
            for (int n : group.second) {
                std::set<int> found = expression_sources(g, group.first, n);
                sources.insert(found.begin(), found.end());
            }
            for (int n : group.second) sources.erase(n);
            std::string temporary = "_t" + std::to_string(++f.temporary_serial);
            for (int n : sources) {
                Instruction s = g.instructions[n], copy;
                copy.kind = "copy";
                copy.destination = s.destination;
                copy.a = Operand::parse(temporary);
                s.destination = temporary;
                edits[n] = {Line::code(s), Line::code(copy)};
            }
            for (int n : group.second) {
                Instruction s;
                s.kind = "copy";
                s.destination = g.instructions[n].destination;
                s.a = Operand::parse(temporary);
                edits[n] = {Line::code(s)};
            }
            result.changes += static_cast<int>(group.second.size());
            result.records.push_back(group.first.text() + ": " + temporary + " sources=" + numbers(sources, "#") + " replaced=" + numbers(group.second, "#"));
        }
        rewrite(f, edits);
        return result;
    }
    static PassResult dce(Function& f, const CFG& g, const DataFlow& flow) {
        Replacements edits;
        std::map<int, std::string> records;
        for (int b : g.reachable) {
            Variables state = flow.live_out[b];
            const std::vector<int>& ns = g.blocks[b].instructions;
            for (std::vector<int>::const_reverse_iterator it = ns.rbegin();it != ns.rend();++it) {
                int n = *it;
                Instruction s = g.instructions[n];
                if ((s.kind == "copy" && !s.a.constant && s.destination == s.a.variable) ||((s.kind == "copy" || s.kind == "bin" || s.kind == "load") && !state.count(s.destination))) {
                    edits[n] = {};
                    records[n] = "#" + std::to_string(n) + ": delete " + s.text();
                    continue;
                }
                if (s.kind == "call" && !s.destination.empty() && !state.count(s.destination)) {
                    records[n] = "#" + std::to_string(n) + ": unused result " + s.text();
                    s.destination.clear();
                    edits[n] = {Line::code(s)};
                }
                state = live_transfer(s, state);
            }
        }
        rewrite(f, edits);
        PassResult result;
        for (const std::pair<const int, std::string>& record : records) result.records.push_back(record.second);
        result.changes = static_cast<int>(result.records.size());
        return result;
    }
    static std::set<int> inside(const CFG& g, const Loop& loop, const std::set<int>& definitions) {
        std::set<int> result;
        for (int n : definitions) if (n && loop.blocks.count(g.block_of[n])) result.insert(n);
        return result;
    }
    static PassResult licm(Function& f, const CFG& g, const DataFlow& flow) {
        std::vector<Loop> loops = g.loops;
        std::sort(loops.begin(), loops.end(),[](const Loop& a, const Loop& b) {
            return a.blocks.size() != b.blocks.size() ? a.blocks.size() < b.blocks.size() : a.header < b.header;
        });
        for (const Loop& loop : loops) {
            std::vector<int> ns;
            std::set<std::string> stores;
            bool calls = false;
            for (int b : loop.blocks) for (int n : g.blocks[b].instructions) {
                ns.push_back(n);
                if (g.instructions[n].kind == "store") stores.insert(g.instructions[n].name);
                if (g.instructions[n].kind == "call") calls = true;
            }
            std::sort(ns.begin(), ns.end());
            std::set<int> marked;
            std::vector<int> order;
            bool changed = true;
            while (changed) {
                changed = false;
                for (int n : ns) {
                    const Instruction& s = g.instructions[n];
                    if (marked.count(n) ||(s.kind != "copy" && s.kind != "bin" && s.kind != "load") ||(s.kind == "load" &&(calls || stores.count(s.name)))) continue;
                    bool invariant = true;
                    for (const std::string& v : s.uses()) {
                        std::set<int> ds = reaching_numbers(flow, n, v), local = inside(g, loop, ds);
                        if (!local.empty() && !(ds.size() == 1 && marked.count(*local.begin()))) invariant = false;
                    }
                    if (invariant) {
                        marked.insert(n);
                        order.push_back(n);
                        changed = true;
                    }
                }
            }
            std::map<std::string, int> definition_counts;
            for (int n : ns) if (!g.instructions[n].destination.empty())++definition_counts[g.instructions[n].destination];
            std::vector<int> moves;
            std::set<int> moved;
            for (int n : order) {
                const Instruction& s = g.instructions[n];
                const std::string& x = s.destination;
                if (definition_counts[x] != 1 || flow.live_in[loop.header].count(x)) continue;
                bool dominates = true, dead = true;
                for (int exit : loop.exits) if (!g.dominators[exit].count(g.block_of[n])) dominates = false;
                for (int outside : loop.outside) if (flow.live_in[outside].count(x)) dead = false;
                bool dangerous = s.kind == "load" ||(s.kind == "bin" &&(s.operation == "/" || s.operation == "%") &&(!s.b.constant || s.b.number == 0));
                if (!dominates &&(dangerous || !dead)) continue;
                bool ready = true;
                for (const std::string& v : s.uses()) for (int d : inside(g, loop, reaching_numbers(flow, n, v))) if (!moved.count(d)) ready = false;
                if (ready) {
                    moves.push_back(n);
                    moved.insert(n);
                }
            }
            if (!moves.empty()) {
                std::string destination = hoist(f, g, loop, moves);
                return {static_cast<int>(moves.size()), {"B" + std::to_string(loop.header) + ": hoist " + numbers(moves, "#") + " to " + destination} };
            }
        }
        return {};
    }
    static PassResult apply(Function& f, const std::string& pass) {
        CFG graph(f);
        DataFlow flow(f, graph);
        if (pass == "constprop" || pass == "copyprop") return propagation(f, graph, flow, pass == "constprop");
        if (pass == "cse") return cse(f, graph, flow);
        if (pass == "dce") return dce(f, graph, flow);
        if (pass == "licm") return licm(f, graph, flow);
        PassResult result;
        result.records = remove_unreachable(f, graph);
        result.changes = static_cast<int>(result.records.size());
        return result;
    }
    struct CallGraph {
        std::map<std::string, std::vector<std::string>> callees;
        Variables reached, recursive;
        explicit CallGraph(const Program& p) {
            for (const Function& f : p.functions) {
                Variables called;
                for (const Line& l : f.code) if (!l.is_label() && l.instruction.kind == "call") called.insert(l.instruction.name);
                for (const Function& target : p.functions) if (called.count(target.name)) callees[f.name].push_back(target.name);
                callees[f.name];
            }
            std::function<Variables(std::vector<std::string>)> closure =[&](std::vector<std::string> pending) {
                Variables result;
                while (!pending.empty()) {
                    std::string name = pending.back();
                    pending.pop_back();
                    if (result.insert(name).second) pending.insert(pending.end(), callees[name].begin(), callees[name].end());
                }
                return result;
            };
            reached = closure({"main"});
            for (const Function& f : p.functions) if (closure(callees[f.name]).count(f.name)) recursive.insert(f.name);
        }
    };
    static void graph_report(std::vector<std::string>& out, const Program& p, const std::string& heading) {
        CallGraph g(p);
        out.push_back("== call graph (" + heading + ") ==");
        std::vector<std::string> missing;
        for (const Function& f : p.functions) {
            out.push_back(f.name + " -> " + join(g.callees[f.name]) +(g.recursive.count(f.name) ? " (recursive)" : ""));
            if (!g.reached.count(f.name)) missing.push_back(f.name);
        }
        out.push_back("unreachable functions: " + join(missing));
    }
    static std::string variables_text(const Variables& values) {
        return join(std::vector<std::string>(values.begin(), values.end()));
    }
    static std::string definitions_text(const Definitions& state) {
        std::vector<Definition> sorted(state.begin(), state.end());
        std::sort(sorted.begin(), sorted.end(),[](const Definition& a, const Definition& b) {
            return std::tie(a.second, a.first) < std::tie(b.second, b.first);
        });
        std::vector<std::string> result;
        for (const Definition& d : sorted) result.push_back(d.first + ":" + std::to_string(d.second));
        return join(result);
    }
    static std::string expressions_text(const Expressions& state) {
        Variables strings;
        for (const Expression& e : state) strings.insert(e.text());
        return variables_text(strings);
    }
    static void analysis_report(std::vector<std::string>& out, const Function& f, const std::string& heading) {
        CFG g(f);
        DataFlow flow(f, g);
        out.push_back("== " + f.name + " (" + heading + ") ==");
        out.push_back("code:");
        int n = 0;
        for (const Line& l : f.code) {
            if (l.is_label()) {
                out.push_back(l.label + ":");
                continue;
            }
            ++n;
            std::string text = "  #" + std::to_string(n) + " " + l.instruction.text();
            std::vector<std::string> chains;
            Variables seen;
            if (g.reachable.count(g.block_of[n])) for (const std::string& v : l.instruction.uses()) if (seen.insert(v).second) chains.push_back(v + ":" + numbers(reaching_numbers(flow, n, v)));
            if (!chains.empty()) text += " | " + join(chains, " ");
            out.push_back(text);
        }
        out.push_back("blocks: " + std::to_string(g.blocks.size() - 1));
        std::vector<int> unreachable;
        for (int b = 1;b < static_cast<int>(g.blocks.size());++b) {
            const Block& block = g.blocks[b];
            out.push_back("B" + std::to_string(b) + " " + std::to_string(block.instructions.front()) + "-" + std::to_string(block.instructions.back()) + " labels=" + join(block.labels) + " preds=" + numbers(block.predecessors, "B") + " succs=" + numbers(block.successors, "B"));
            if (!g.reachable.count(b)) unreachable.push_back(b);
        }
        out.push_back("unreachable: " + numbers(unreachable, "B"));
        out.push_back("order: " + numbers(g.reverse_postorder, "B"));
        out.push_back("dominators:");
        for (int b : g.reachable) out.push_back("B" + std::to_string(b) + " idom=" +(g.immediate[b] ? "B" + std::to_string(g.immediate[b]) : "-") + " dom=" + numbers(g.dominators[b], "B"));
        out.push_back("dominator tree:");
        std::function<void(int, int)> tree =[&](int b, int depth) {
            out.push_back(std::string(depth * 2, ' ') + "B" + std::to_string(b));
            for (int child : g.reachable) if (g.immediate[child] == b) tree(child, depth + 1);
        };
        tree(1, 0);
        out.push_back("loops: " + std::to_string(g.loops.size()));
        for (const Loop& loop : g.loops) out.push_back("header=B" + std::to_string(loop.header) + " latches=" + numbers(loop.latches, "B") + " depth=" + std::to_string(loop.depth) + " blocks=" + numbers(loop.blocks, "B") + " exits=" + numbers(loop.exits, "B"));
        out.push_back("reaching definitions: iterations=" + std::to_string(flow.reaching_iterations));
        for (int b : g.reachable) out.push_back("B" + std::to_string(b) + " in=" + definitions_text(flow.reaching_in[b]) + " out=" + definitions_text(flow.reaching_out[b]));
        out.push_back("liveness: iterations=" + std::to_string(flow.live_iterations));
        for (int b : g.reachable) out.push_back("B" + std::to_string(b) + " in=" + variables_text(flow.live_in[b]) + " out=" + variables_text(flow.live_out[b]));
        out.push_back("available expressions: iterations=" + std::to_string(flow.expression_iterations));
        for (int b : g.reachable) out.push_back("B" + std::to_string(b) + " in=" + expressions_text(flow.expression_in[b]) + " out=" + expressions_text(flow.expression_out[b]));
    }
    static Function allocation_report(std::vector<std::string>& out, const Function& f, int registers) {
        CFG graph(f);
        DataFlow flow(f, graph);
        Allocation allocation(f, graph, flow, registers);
        Function allocated = f;
        allocated.code.clear();
        int moves = 0, edges = 0, pressure = 0, spill_uses = 0, spill_defs = 0;
        std::set<int> used;
        std::function<std::string(const std::string&)> rename =[&](const std::string& name) {
            std::map<std::string, int>::const_iterator it = allocation.colors.find(name);
            return it != allocation.colors.end() && it->second >= 0 ? "R" + std::to_string(it->second) : name;
        };
        for (std::string& p : allocated.parameters) p = rename(p);
        for (const Line& line : f.code) {
            if (line.is_label()) {
                allocated.code.push_back(line);
                continue;
            }
            Instruction s = line.instruction;
            if (!s.destination.empty()) s.destination = rename(s.destination);
            for (Operand* o : s.operands()) if (!o->constant) o->variable = rename(o->variable);
            if (s.kind == "copy" && !s.a.constant && s.destination == s.a.variable)++moves;
            else allocated.code.push_back(Line::code(s));
            for (const std::string& v : line.instruction.uses()) spill_uses += allocation.spills.count(v);
            spill_defs += allocation.spills.count(line.instruction.destination);
        }
        for (const std::string& p : f.parameters) spill_defs += allocation.spills.count(p);
        for (const Variables& state : flow.live_before) pressure = std::max(pressure, static_cast<int>(state.size()));
        for (const Variables& state : flow.live_after) pressure = std::max(pressure, static_cast<int>(state.size()));
        for (const auto& entry : allocation.neighbors) edges += static_cast<int>(entry.second.size());
        out.push_back("== " + f.name + " ==");
        out.push_back("nodes=" + std::to_string(allocation.neighbors.size()) + " edges=" + std::to_string(edges/2) + " registers=" + std::to_string(registers));
        for (const auto& entry : allocation.neighbors) out.push_back(entry.first + " degree=" + std::to_string(entry.second.size()) + " cost=" + allocation.costs[entry.first].text() + " neighbors=" + variables_text(entry.second));
        out.push_back("simplify: " + join(allocation.order));
        std::vector<std::string> potential;
        for (const std::pair<std::string, int>& p : allocation.potential) potential.push_back(p.first + "(" + allocation.costs[p.first].text() + "/" + std::to_string(p.second) + ")");
        out.push_back("potential spills: " + join(potential));
        for (const std::pair<const std::string, int>& p : allocation.colors) {
            out.push_back(p.first + " -> " +(p.second < 0 ? "spill" : "R" + std::to_string(p.second)));
            if (p.second >= 0) used.insert(p.second);
        }
        out.push_back("summary: pressure=" + std::to_string(pressure) + " used=" + std::to_string(used.size()) + " spilled=" + std::to_string(allocation.spills.size()) + " moves=" + std::to_string(moves) + " spill_uses=" + std::to_string(spill_uses) + " spill_defs=" + std::to_string(spill_defs));
        std::vector<std::string> lines = function_lines(allocated);
        out.insert(out.end(), lines.begin(), lines.end());
        return allocated;
    }
    struct Execution {
        const Program& program;
        std::map<std::string, std::vector<Integer>> arrays;
        const std::vector<Integer>& inputs;
        std::size_t input_position = 0;
        std::vector<Integer> output;
        std::map<std::string, Integer> steps, calls, dynamic;
        Execution(const Program& p, const std::vector<Integer>& values) : program(p), inputs(values) {
            for (const auto& a : p.arrays) arrays[a.first].resize(a.second);
        }
        Integer call(const std::string& name, const std::vector<Integer>& args) {
            const Function* f = nullptr;
            for (const Function& candidate : program.functions) if (candidate.name == name) f = &candidate;
            std::map<std::string, Integer> vars;
            for (std::size_t i = 0;i < args.size();++i) vars[f->parameters[i]] = args[i];
            std::vector<Integer> pushed;
            std::map<std::string, int> labels;
            std::vector<Instruction> code;
            for (const Line& line : f->code) {
                if (line.is_label()) labels[line.label] = static_cast<int>(code.size());
                else code.push_back(line.instruction);
            }
            ++calls[name];
            int position = 0;
            std::function<Integer(const Operand&)> value =[&](const Operand& o) {
                return o.constant ? o.number : vars.at(o.variable);
            };
            while (true) {
                const Instruction& s = code[position++];
                ++steps[name];
                ++dynamic[s.kind];
                if (s.kind == "copy") vars[s.destination] = value(s.a);
                else if (s.kind == "bin") vars[s.destination] = calculate(s.operation, value(s.a), value(s.b));
                else if (s.kind == "load") vars[s.destination] = arrays.at(s.name).at(static_cast<std::size_t>(value(s.a)));
                else if (s.kind == "store") arrays.at(s.name).at(static_cast<std::size_t>(value(s.a))) = value(s.b);
                else if (s.kind == "goto") position = labels.at(s.name);
                else if (s.kind == "if") {
                    if (calculate(s.operation, value(s.a), value(s.b))) position = labels.at(s.name);
                } else if (s.kind == "param") pushed.push_back(value(s.a));
                else if (s.kind == "call") {
                    std::vector<Integer> arguments(pushed.end() - s.count, pushed.end());
                    pushed.erase(pushed.end() - s.count, pushed.end());
                    Integer result = call(s.name, arguments);
                    if (!s.destination.empty()) vars[s.destination] = result;
                } else if (s.kind == "return") return s.has_operand ? value(s.a) : 0;
                else if (s.kind == "read") vars[s.destination] = inputs.at(input_position++);
                else if (s.kind == "print") output.push_back(value(s.a));
            }
        }
    };
    static Integer sum(const std::map<std::string, Integer>& values) {
        Integer result = 0;
        for (const auto& entry : values) result += entry.second;
        return result;
    }
    static std::string integers(const std::vector<Integer>& values) {
        std::vector<std::string> strings;
        for (Integer v : values) strings.push_back(std::to_string(v));
        return join(strings);
    }
    static std::map<std::string, Integer> static_kinds(const Program& p) {
        std::map<std::string, Integer> counts;
        for (const Function& f : p.functions) for (const Line& l : f.code) if (!l.is_label())++counts[l.instruction.kind];
        return counts;
    }
    static std::vector<std::string> comparisons(const Program& original, const Program& optimized, const Program& allocated, const std::vector<std::vector<Integer>>& runs) {
        const std::array<const Program*, 3> programs = {&original, &optimized, &allocated};
        const std::array<std::string, 3> names = {"original", "optimized", "allocated"};
        std::array<std::map<std::string, Integer>, 3> profiles, dynamic;
        std::array<Integer, 3> total {};
        std::map<std::string, Integer> calls;
        int same = 0;
        std::vector<std::string> out;
        for (std::size_t i = 0;i < runs.size();++i) {
            out.push_back("run " + std::to_string(i + 1) + ": inputs=" + std::to_string(runs[i].size()));
            std::array<std::vector<Integer>, 3> results;
            for (int v = 0;v < 3;++v) {
                Execution execution(*programs[v], runs[i]);
                execution.call("main", {});
                Integer steps = sum(execution.steps);
                out.push_back("  " + names[v] + ": steps=" + std::to_string(steps) + " calls=" + std::to_string(sum(execution.calls)) + " output=" + integers(execution.output));
                results[v] = execution.output;
                total[v] += steps;
                for (const auto& entry : execution.steps) profiles[v][entry.first] += entry.second;
                for (const auto& entry : execution.dynamic) dynamic[v][entry.first] += entry.second;
                if (v == 0) for (const auto& entry : execution.calls) calls[entry.first] += entry.second;
            }
            bool equal = results[0] == results[1] && results[1] == results[2];
            same += equal;
            out.push_back(std::string("  result: ") +(equal ? "same" : "different"));
        }
        out.push_back("== profile ==");
        for (const Function& f : original.functions) out.push_back(f.name + ": calls=" + std::to_string(calls[f.name]) + " original=" + std::to_string(profiles[0][f.name]) + " optimized=" + std::to_string(profiles[1][f.name]) + " allocated=" + std::to_string(profiles[2][f.name]));
        std::map<std::string, Integer> a = static_kinds(original), b = static_kinds(optimized);
        out.push_back("== summary ==");
        out.push_back("runs=" + std::to_string(runs.size()) + " same=" + std::to_string(same) + " different=" + std::to_string(runs.size() - same));
        out.push_back("instructions: original=" + std::to_string(sum(a)) + " optimized=" + std::to_string(sum(b)));
        std::vector<std::string> counts;
        for (const std::string& kind : kinds) counts.push_back(kind + "=" + std::to_string(a[kind]) + "->" + std::to_string(b[kind]));
        out.push_back("kinds: " + join(counts, " "));
        out.push_back("steps: original=" + std::to_string(total[0]) + " optimized=" + std::to_string(total[1]) + " allocated=" + std::to_string(total[2]));
        for (int v = 0;v < 3;++v) {
            counts.clear();
            for (const std::string& kind : kinds) counts.push_back(kind + "=" + std::to_string(dynamic[v][kind]));
            out.push_back("dynamic " + names[v] + ": " + join(counts, " "));
        }
        return out;
    }
    static void write(const std::string& name, const std::vector<std::string>& lines) {
        std::ofstream out("output/" + name);
        for (const std::string& line : lines) out << line << '\n';
    }
}
int main() {
    using namespace tac;
    std::ifstream settings("input/params.txt");
    std::string word, line;
    int registers, max_rounds;
    settings >> word >> registers;
    std::getline(settings, line);
    std::getline(settings, line);
    std::istringstream passes_line(line);
    passes_line >> word;
    Variables enabled;
    while (passes_line >> word) enabled.insert(word);
    settings >> word >> max_rounds;
    std::vector<std::string> passes;
    for (const std::string& name : std::vector<std::string> {"constprop", "copyprop", "cse", "dce", "licm", "unreachable"}) if (enabled.count(name)) passes.push_back(name);
    std::ifstream input("input/input.txt");
    int count;
    input >> count;
    std::vector<std::vector<Integer>> runs;
    for (int i = 0;i < count;++i) {
        int n;
        input >> n;
        std::vector<Integer> values(n);
        for (Integer& value : values) input >> value;
        runs.push_back(values);
    }
    Program original = read_program("input/program.tac"), working = original;
    std::vector<std::string> analysis, pass_lines, allocation_lines;
    std::map<std::string, Integer> totals;
    graph_report(analysis, original, "original");
    for (const Function& f : original.functions) analysis_report(analysis, f, "original");
    for (Function& f : working.functions) {
        int before = f.instruction_count(), round = 0;
        pass_lines.push_back("== " + f.name + " ==");
        for (round = 1;round <= max_rounds;++round) {
            bool changed = false;
            std::vector<std::string> counts, records;
            for (const std::string& pass : passes) {
                PassResult result = apply(f, pass);
                changed = changed || result.changes != 0;
                totals[pass] += result.changes;
                counts.push_back(pass + "=" + std::to_string(result.changes));
                for (const std::string& record : result.records) records.push_back("  " + pass + " " + record);
            }
            pass_lines.push_back("round " + std::to_string(round) + ": " + join(counts, " "));
            pass_lines.insert(pass_lines.end(), records.begin(), records.end());
            if (!changed || round == max_rounds) break;
        }
        pass_lines.push_back("result: rounds=" + std::to_string(round) + " instructions=" + std::to_string(before) + "->" + std::to_string(f.instruction_count()));
    }
    graph_report(analysis, working, "optimized");
    CallGraph graph(working);
    Program optimized;
    optimized.arrays = working.arrays;
    std::vector<std::string> removed;
    for (const Function& f : working.functions) {
        if (enabled.count("unreachable") && !graph.reached.count(f.name)) removed.push_back(f.name);
        else optimized.functions.push_back(f);
    }
    pass_lines.insert(pass_lines.end(), {"== program ==", "removed functions: " + join(removed), "== total =="});
    std::vector<std::string> counts;
    for (const std::string& pass : passes) counts.push_back(pass + "=" + std::to_string(totals[pass]));
    pass_lines.push_back(join(counts, " "));
    Program allocated;
    allocated.arrays = optimized.arrays;
    for (const Function& f : optimized.functions) {
        analysis_report(analysis, f, "optimized");
        allocated.functions.push_back(allocation_report(allocation_lines, f, registers));
    }
    write("optimized.tac", program_lines(optimized));
    write("analysis.txt", analysis);
    write("passes.txt", pass_lines);
    write("regalloc.txt", allocation_lines);
    write("comparison.txt", comparisons(original, optimized, allocated, runs));
}
