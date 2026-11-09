#include "tac.hpp"
namespace tac {
    Definitions reaching_transfer(const Instruction& s, int n, Definitions state) {
        if (!s.destination.empty()) {
            for (Definitions::iterator it = state.begin();it != state.end();) if (it->first == s.destination) it = state.erase(it);
            else ++it;
            state.emplace(s.destination, n);
        }
        return state;
    }
    Variables live_transfer(const Instruction& s, Variables state) {
        state.erase(s.destination);
        for (const std::string& v : s.uses()) state.insert(v);
        return state;
    }
    Expressions expression_transfer(const Instruction& s, int, Expressions state) {
        std::optional<Expression> e = s.expression();
        if (e) state.insert(*e);
        for (Expressions::iterator it = state.begin();it != state.end();) {
            if ((s.kind == "store" && it->kind == "load" && it->operation == s.name) ||(s.kind == "call" && it->kind == "load") ||(!s.destination.empty() && it->uses(s.destination))) it = state.erase(it);
            else ++it;
        }
        return state;
    }
    Copies copy_transfer(const Instruction& s, int, Copies state) {
        if (!s.destination.empty()) for (Copies::iterator it = state.begin();it != state.end();) {
            if (it->first == s.destination || it->second == s.destination) it = state.erase(it);
            else ++it;
        }
        if (s.kind == "copy" && !s.a.constant && s.a.variable != s.destination) state.emplace(s.destination, s.a.variable);
        return state;
    }
    template<class T, class Transfer> static void forward(const Function& f, const CFG& g, const std::set<T>& universe, Transfer transfer, bool reaching, std::vector<std::set<T>>& in, std::vector<std::set<T>>& out, std::vector<std::set<T>>& before, int& iterations) {
        in.resize(g.blocks.size());
        out.resize(g.blocks.size());
        before.resize(g.instructions.size());
        for (int b : g.reachable) out[b] = universe;
        bool changed = true;
        while (changed) {
            changed = false;
            ++iterations;
            for (int b : g.reverse_postorder) {
                std::set<T> state;
                if (reaching) {
                    for (int p : g.blocks[b].reachable_predecessors) state.insert(out[p].begin(), out[p].end());
                    if constexpr (std::is_same<T, Definition>::value) if (b == 1) for (const std::string& p : f.parameters) state.emplace(p, 0);
                } else if (b != 1) {
                    const std::vector<int>& preds = g.blocks[b].reachable_predecessors;
                    state = out[preds[0]];
                    for (std::size_t i = 1;i < preds.size();++i) state = intersection(state, out[preds[i]]);
                }
                in[b] = state;
                for (int n : g.blocks[b].instructions) state = transfer(g.instructions[n], n, state);
                if (state != out[b]) {
                    out[b] = state;
                    changed = true;
                }
            }
        }
        for (int b : g.reachable) {
            std::set<T> state = in[b];
            for (int n : g.blocks[b].instructions) {
                before[n] = state;
                state = transfer(g.instructions[n], n, state);
            }
        }
    }
    DataFlow::DataFlow(const Function& f, const CFG& g) {
        Expressions expressions;
        Copies copies;
        for (std::size_t n = 1;n < g.instructions.size();++n) if (g.reachable.count(g.block_of[n])) {
            const Instruction& s = g.instructions[n];
            std::optional<Expression> e = s.expression();
            if (e) expressions.insert(*e);
            if (s.kind == "copy" && !s.a.constant && s.destination != s.a.variable) copies.emplace(s.destination, s.a.variable);
        }
        forward(f, g, Definitions {}, reaching_transfer, true, reaching_in, reaching_out, reaching_before, reaching_iterations);
        forward(f, g, expressions, expression_transfer, false, expression_in, expression_out, expression_before, expression_iterations);
        forward(f, g, copies, copy_transfer, false, copy_in, copy_out, copy_before, copy_iterations);
        live_in.resize(g.blocks.size());
        live_out.resize(g.blocks.size());
        live_before.resize(g.instructions.size());
        live_after.resize(g.instructions.size());
        bool changed = true;
        while (changed) {
            changed = false;
            ++live_iterations;
            for (int b : g.postorder) {
                Variables state;
                for (int s : g.blocks[b].successors) state.insert(live_in[s].begin(), live_in[s].end());
                live_out[b] = state;
                const std::vector<int>& ns = g.blocks[b].instructions;
                for (std::vector<int>::const_reverse_iterator it = ns.rbegin();it != ns.rend();++it) state = live_transfer(g.instructions[*it], state);
                if (state != live_in[b]) {
                    live_in[b] = state;
                    changed = true;
                }
            }
        }
        for (int b : g.reachable) {
            Variables state = live_out[b];
            const std::vector<int>& ns = g.blocks[b].instructions;
            for (std::vector<int>::const_reverse_iterator it = ns.rbegin();it != ns.rend();++it) {
                live_after[*it] = state;
                state = live_transfer(g.instructions[*it], state);
                live_before[*it] = state;
            }
        }
    }
}
