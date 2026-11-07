#include "prolog.hpp"
namespace prolog {
    Term variable() {
        return std::make_shared < TermData >();
    }
    Term integer(Integer value) {
        Term result = variable();
        result->kind = TermData::Kind::Integer;
        result->integer = value;
        return result;
    }
    Term atom(const std::string& name) {
        Term result = variable();
        result->kind = TermData::Kind::Atom;
        result->name = name;
        return result;
    }
    Term compound(const std::string& name, std::vector<Term> args) {
        Term result = variable();
        result->kind = TermData::Kind::Compound;
        result->name = name;
        result->args = std::move(args);
        return result;
    }
    Term dereference(Term term) {
        while (term && term->kind == TermData::Kind::Variable && term->binding) term = term->binding;
        return term;
    }
    bool is_variable(const Term& term) {
        return term && dereference(term)->kind == TermData::Kind::Variable;
    }
    bool is_integer(const Term& term) {
        return term && dereference(term)->kind == TermData::Kind::Integer;
    }
    bool is_atom(const Term& term) {
        return term && dereference(term)->kind == TermData::Kind::Atom;
    }
    bool is_compound(const Term& term) {
        return term && dereference(term)->kind == TermData::Kind::Compound;
    }
    bool is_atom(const Term& term, const std::string& name) {
        Term value = dereference(term);
        return value && value->kind == TermData::Kind::Atom && value->name == name;
    }
    Indicator indicator(const Term& term) {
        Term value = dereference(term);
        return {value->name, value->kind == TermData::Kind::Compound ? static_cast<int>(value->args.size()) : 0};
    }
    Term indicator_term(const Indicator& key) {
        return compound("/", {atom(key.first), integer(key.second)});
    }
    Term make_list(const std::vector<Term>& elements, Term tail) {
        if (!tail) tail = atom("[]");
        for (std::vector<Term>::const_reverse_iterator it = elements.rbegin();it != elements.rend();++it) tail = compound(".", {*it, tail});
        return tail;
    }
    std::pair<std::vector<Term>, Term> list_parts(Term term) {
        std::vector<Term> elements;
        term = dereference(term);
        while (is_compound(term) && term->name == "." && term->args.size() == 2) {
            elements.push_back(term->args[0]);
            term = dereference(term->args[1]);
        }
        return {elements, term};
    }
    std::vector<Term> copy_terms(const std::vector<Term>& terms) {
        std::map<const TermData*, Term> variables;
        std::function<Term(Term)> copy =[&](Term term)->Term {term = dereference(term);
        if (!term) return {};
        if (is_variable(term)) {
            Term& replacement = variables[term.get()];
            if (!replacement) replacement = variable();
            return replacement;
        }
        if (is_compound(term)) {
            std::vector<Term> args;
            for (const Term& argument : term->args) args.push_back(copy(argument));
            return compound(term->name, std::move(args));
        }
        return term;
        };
        std::vector<Term> result;
        for (const Term& term : terms) result.push_back(copy(term));
        return result;
    }
    Term copy_term(const Term& term) {
        return copy_terms({term})[0];
    }
    std::vector<Term> variables_in(const std::vector<Term>& terms) {
        std::vector<Term> pending(terms.rbegin(), terms.rend()), result;
        while (!pending.empty()) {
            Term term = dereference(pending.back());
            pending.pop_back();
            if (is_variable(term)) result.push_back(term);
            else if (is_compound(term)) pending.insert(pending.end(), term->args.rbegin(), term->args.rend());
        }
        return result;
    }
    bool same_kind(Term a, Term b) {
        a = dereference(a);
        b = dereference(b);
        if (is_variable(a) || is_variable(b)) return true;
        if (a->kind != b->kind) return false;
        if (is_integer(a)) return a->integer == b->integer;
        if (is_atom(a)) return a->name == b->name;
        return a->name == b->name && a->args.size() == b->args.size();
    }
    Term type_error(const std::string& kind, const Term& term) {
        return compound("type_error", {atom(kind), term});
    }
    Term domain_error(const std::string& kind, const Term& term) {
        return compound("domain_error", {atom(kind), term});
    }
}
