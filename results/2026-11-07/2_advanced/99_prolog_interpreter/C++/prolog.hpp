#ifndef PROLOG_HPP
#define PROLOG_HPP
#include <algorithm>
#include <array>
#include <cstdint>
#include <deque>
#include <fstream>
#include <functional>
#include <iterator>
#include <initializer_list>
#include <map>
#include <memory>
#include <optional>
#include <set>
#include <sstream>
#include <string>
#include <tuple>
#include <utility>
#include <vector>
namespace prolog {
    using Integer = std::int64_t;
    struct TermData;
    using Term = std::shared_ptr < TermData >;
    struct TermData {
        enum class Kind {Variable, Integer, Atom, Compound};
        Kind kind = Kind::Variable;
        Integer integer = 0;
        std::string name;
        std::vector<Term> args;
        Term binding;
    };
    Term variable();
    Term integer(Integer value);
    Term atom(const std::string& name);
    Term compound(const std::string& name, std::vector<Term> args);
    Term dereference(Term term);
    bool is_variable(const Term& term);
    bool is_integer(const Term& term);
    bool is_atom(const Term& term);
    bool is_compound(const Term& term);
    bool is_atom(const Term& term, const std::string& name);
    using Indicator = std::pair<std::string, int>;
    Indicator indicator(const Term& term);
    Term indicator_term(const Indicator& key);
    Term make_list(const std::vector<Term>& elements, Term tail = {});
    std::pair<std::vector<Term>, Term> list_parts(Term term);
    std::vector<Term> copy_terms(const std::vector<Term>& terms);
    Term copy_term(const Term& term);
    std::vector<Term> variables_in(const std::vector<Term>& terms);
    bool same_kind(Term a, Term b);
    Term type_error(const std::string& kind, const Term& term);
    Term domain_error(const std::string& kind, const Term& term);
    struct Fault {
        Term term;
    };
    struct Ball {
        Term term;
    };
    class Trail {
        std::vector<Term> bindings;
        public:
        std::size_t mark() const {return bindings.size();
        } void undo(std::size_t mark);
        bool unify(Term a, Term b);
    };
    bool identical(Term a, Term b);
    struct Operator {
        int priority, left, right;
    };
    extern const std::string symbols;
    extern const std::map<std::string, Operator> infix;
    extern const std::map<std::string, int> prefix;
    struct Token {
        std::string kind, value, spelling;
        Integer integer = 0;
        int line = 1, column = 1;
        bool space = true;
        std::size_t index = 0;
    };
    struct SyntaxError {
        Token token;
        std::string message;
        explicit SyntaxError(const Token& token, const std::string& message = "");
    };
    std::vector<Token> tokenize(const std::string& source, int column = 1);
    class Reader {
        bool punctuation(const std::string& spelling) const;
        void expect(const std::string& spelling);
        bool can_start() const;
        std::pair<Term, int> term(int limit);
        std::pair<Term, int> primary(int limit);
        public:
        std::vector<Token> tokens;
        std::size_t position = 0;
        std::map<std::string, Term> names;
        std::map<std::string, int> counts;
        std::vector<std::string> name_order, count_order;
        explicit Reader(const std::string& source, int column = 1) : tokens(tokenize(source, column)) {
        }
        const Token& peek() const {return tokens[position];
        } Token take();
        Term clause(bool query = false);
    };
    struct Clause {
        Term head, body;
        std::string file;
        int line = 1;
        std::pair<Term, Term> copy() const;
    };
    struct Database {
        std::map<Indicator, std::vector<Clause>> predicates;
        std::vector<Indicator> order;
        void add(const Clause& clause);
        std::vector<const Clause*> candidates(const Term& goal) const;
    };
    extern const std::set<Indicator> deterministic;
    Integer require_integer(const Term& term);
    std::string require_atom(const Term& term);
    std::vector<Term> require_list(const Term& term);
    Integer evaluate(const Term& term);
    bool execute(const Term& goal, Trail& trail, const std::function<void(const Term&, bool)>& output);
}
#endif
