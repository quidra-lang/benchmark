#include "prolog.hpp"
namespace prolog {
    const std::set<Indicator> deterministic = { {"true", 0}, {"fail", 0}, {"false", 0}, {"=", 2}, {"\\=", 2}, {"==", 2}, {"\\==", 2}, {"var", 1}, {"nonvar", 1}, {"atom", 1}, {"number", 1}, {"integer", 1}, {"atomic", 1}, {"compound", 1}, {"callable", 1}, {"is_list", 1}, {"is", 2}, {"=:=", 2}, {"=\\=", 2}, {"<", 2}, {">", 2}, {"=<", 2}, {">=", 2}, {"functor", 3}, {"arg", 3}, {"=..", 2}, {"copy_term", 2}, {"atom_length", 2}, {"atom_chars", 2}, {"write", 1}, {"writeq", 1}, {"nl", 0} };
    static Integer checked(Integer value) {
        if (value < -2147483648LL || value > 2147483647LL) throw Fault {compound("evaluation_error", {atom("int_overflow")})};
        return value;
    }
    Integer evaluate(const Term& term) {
        Term value = dereference(term);
        if (is_variable(value)) throw Fault {atom("instantiation_error")};
        if (is_integer(value)) return value->integer;
        const std::set<Indicator> supported = { {"+", 2}, {"-", 2}, {"*", 2}, {"//", 2}, {"mod", 2}, {"rem", 2}, {"-", 1}, {"abs", 1}, {"min", 2}, {"max", 2} };
        Indicator key = indicator(value);
        if (!supported.count(key)) throw Fault {type_error("evaluable", indicator_term(key))};
        Integer a = evaluate(value->args[0]);
        if (value->args.size() == 1) return checked(value->name == "-" ? -a : a < 0 ? -a : a);
        Integer b = evaluate(value->args[1]), result;
        if ((value->name == "//" || value->name == "mod" || value->name == "rem") && b == 0) throw Fault {compound("evaluation_error", {atom("zero_divisor")})};
        const std::string& name = value->name;
        if (name == "+") result = a + b;
        else if (name == "-") result = a - b;
        else if (name == "*") result = a * b;
        else if (name == "//") result = a/b;
        else if (name == "rem") result = a%b;
        else if (name == "mod") {
            result = a%b;
            if (result &&((result < 0) !=(b < 0))) result += b;
        } else if (name == "min") result = std::min(a, b);
        else result = std::max(a, b);
        return checked(result);
    }
    Integer require_integer(const Term& term) {
        Term value = dereference(term);
        if (is_variable(value)) throw Fault {atom("instantiation_error")};
        if (!is_integer(value)) throw Fault {type_error("integer", value)};
        return value->integer;
    }
    std::string require_atom(const Term& term) {
        Term value = dereference(term);
        if (is_variable(value)) throw Fault {atom("instantiation_error")};
        if (!is_atom(value)) throw Fault {type_error("atom", value)};
        return value->name;
    }
    std::vector<Term> require_list(const Term& term) {
        std::pair<std::vector<Term>, Term> parts = list_parts(term);
        if (is_variable(parts.second)) throw Fault {atom("instantiation_error")};
        if (!is_atom(parts.second, "[]")) throw Fault {type_error("list", term)};
        return parts.first;
    }
    static std::vector<Term> fresh(Integer count) {
        std::vector<Term> result;
        for (Integer i = 0;i < count;++i) result.push_back(variable());
        return result;
    }
    bool execute(const Term& goal, Trail& trail, const std::function<void(const Term&, bool)>& output) {
        Term value = dereference(goal);
        const std::string& name = value->name;
        std::vector<Term> args;
        for (const Term& argument : value->args) args.push_back(dereference(argument));
        if (name == "true") return true;
        if (name == "fail" || name == "false") return false;
        if (name == "=") return trail.unify(args[0], args[1]);
        if (name == "\\=") {
            std::size_t mark = trail.mark();
            bool result = trail.unify(args[0], args[1]);
            trail.undo(mark);
            return !result;
        }
        if (name == "==" || name == "\\==") {
            bool result = identical(args[0], args[1]);
            return name == "==" ? result : !result;
        }
        if (name == "var") return is_variable(args[0]);
        if (name == "nonvar") return !is_variable(args[0]);
        if (name == "atom") return is_atom(args[0]);
        if (name == "number" || name == "integer") return is_integer(args[0]);
        if (name == "atomic") return is_atom(args[0]) || is_integer(args[0]);
        if (name == "compound") return is_compound(args[0]);
        if (name == "callable") return is_atom(args[0]) || is_compound(args[0]);
        if (name == "is_list") return is_atom(list_parts(args[0]).second, "[]");
        if (name == "is") {
            Integer number = evaluate(args[1]);
            return trail.unify(args[0], integer(number));
        }
        if (name == "=:=" || name == "=\\=" || name == "<" || name == ">" || name == "=<" || name == ">=") {
            Integer a = evaluate(args[0]), b = evaluate(args[1]);
            if (name == "=:=") return a == b;
            if (name == "=\\=") return a != b;
            if (name == "<") return a < b;
            if (name == ">") return a > b;
            if (name == "=<") return a <= b;
            return a >= b;
        }
        if (name == "functor") {
            Term term = args[0], functor = args[1], count = args[2];
            if (!is_variable(term)) {
                if (is_compound(term)) return trail.unify(functor, atom(term->name)) && trail.unify(count, integer(term->args.size()));
                return trail.unify(functor, term) && trail.unify(count, integer(0));
            }
            if (is_variable(functor) || is_variable(count)) throw Fault {atom("instantiation_error")};
            if (is_compound(functor)) throw Fault {type_error("atomic", functor)};
            if (!is_integer(count)) throw Fault {type_error("integer", count)};
            if (count->integer < 0) throw Fault {domain_error("not_less_than_zero", count)};
            if (count->integer > 255) throw Fault {compound("representation_error", {atom("max_arity")})};
            if (count->integer == 0) return trail.unify(term, functor);
            if (is_integer(functor)) throw Fault {type_error("atom", functor)};
            return trail.unify(term, compound(functor->name, fresh(count->integer)));
        }
        if (name == "arg") {
            Term number = args[0], term = args[1];
            if (is_variable(number) || is_variable(term)) throw Fault {atom("instantiation_error")};
            if (!is_integer(number)) throw Fault {type_error("integer", number)};
            if (!is_compound(term)) throw Fault {type_error("compound", term)};
            return number->integer >= 1 && number->integer <= static_cast<Integer>(term->args.size()) && trail.unify(term->args[static_cast<std::size_t>(number->integer - 1)], args[2]);
        }
        if (name == "=..") {
            Term term = args[0], sequence = args[1];
            if (is_compound(term)) {
                std::vector<Term> elements = {atom(term->name)};
                elements.insert(elements.end(), term->args.begin(), term->args.end());
                return trail.unify(make_list(elements), sequence);
            }
            if (!is_variable(term)) return trail.unify(make_list({term}), sequence);
            std::vector<Term> elements = require_list(sequence);
            if (elements.empty()) throw Fault {domain_error("non_empty_list", atom("[]"))};
            Term head = dereference(elements[0]);
            if (is_variable(head)) throw Fault {atom("instantiation_error")};
            if (elements.size() == 1) {
                if (is_compound(head)) throw Fault {type_error("atomic", head)};
                return trail.unify(term, head);
            }
            if (!is_atom(head)) throw Fault {type_error("atom", head)};
            if (elements.size() > 256) throw Fault {compound("representation_error", {atom("max_arity")})};
            return trail.unify(term, compound(head->name, std::vector<Term>(elements.begin() + 1, elements.end())));
        }
        if (name == "copy_term") return trail.unify(copy_term(args[0]), args[1]);
        if (name == "atom_length") {
            std::string text = require_atom(args[0]);
            if (!is_variable(args[1]) && !is_integer(args[1])) throw Fault {type_error("integer", args[1])};
            return trail.unify(integer(text.size()), args[1]);
        }
        if (name == "atom_chars") {
            if (!is_variable(args[0])) {
                std::string text = require_atom(args[0]);
                std::vector<Term> elements;
                for (char c : text) elements.push_back(atom(std::string(1, c)));
                return trail.unify(args[1], make_list(elements));
            }
            std::vector<Term> elements = require_list(args[1]);
            std::string text;
            for (const Term& element : elements) {
                Term character = dereference(element);
                if (is_variable(character)) throw Fault {atom("instantiation_error")};
                if (!is_atom(character) || character->name.size() != 1) throw Fault {type_error("character", character)};
                text += character->name;
            }
            return trail.unify(args[0], atom(text));
        }
        if (name == "write" || name == "writeq") {
            output(args[0], name == "writeq");
            return true;
        }
        if (name == "nl") {
            output({}, false);
            return true;
        }
        return false;
    }
}
