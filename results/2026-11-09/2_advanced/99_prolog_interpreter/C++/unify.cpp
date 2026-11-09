#include "prolog.hpp"
namespace prolog {
    void Trail::undo(std::size_t mark) {
        while (bindings.size() > mark) {
            bindings.back()->binding.reset();
            bindings.pop_back();
        }
    }
    bool Trail::unify(Term a, Term b) {
        std::vector<std::pair<Term, Term>> pending = { {a, b} };
        while (!pending.empty()) {
            std::pair<Term, Term> pair = pending.back();
            pending.pop_back();
            a = dereference(pair.first);
            b = dereference(pair.second);
            if (a == b) continue;
            if (is_variable(a)) {
                a->binding = b;
                bindings.push_back(a);
            } else if (is_variable(b)) {
                b->binding = a;
                bindings.push_back(b);
            } else if (a->kind != b->kind) return false;
            else if (is_integer(a)) {
                if (a->integer != b->integer) return false;
            } else if (is_atom(a)) {
                if (a->name != b->name) return false;
            } else {
                if (a->name != b->name || a->args.size() != b->args.size()) return false;
                for (std::size_t i = a->args.size();i > 0;--i) pending.emplace_back(a->args[i - 1], b->args[i - 1]);
            }
        }
        return true;
    }
    bool identical(Term a, Term b) {
        std::vector<std::pair<Term, Term>> pending = { {a, b} };
        while (!pending.empty()) {
            std::pair<Term, Term> pair = pending.back();
            pending.pop_back();
            a = dereference(pair.first);
            b = dereference(pair.second);
            if (a == b) continue;
            if (is_variable(a) || is_variable(b) || a->kind != b->kind) return false;
            if (is_integer(a)) {
                if (a->integer != b->integer) return false;
            } else if (is_atom(a)) {
                if (a->name != b->name) return false;
            } else {
                if (a->name != b->name || a->args.size() != b->args.size()) return false;
                for (std::size_t i = a->args.size();i > 0;--i) pending.emplace_back(a->args[i - 1], b->args[i - 1]);
            }
        }
        return true;
    }
}
