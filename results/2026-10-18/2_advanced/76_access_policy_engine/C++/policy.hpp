#ifndef POLICY_HPP
#define POLICY_HPP
#include <algorithm>
#include <array>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <functional>
#include <map>
#include <memory>
#include <set>
#include <sstream>
#include <string>
#include <tuple>
#include <utility>
#include <vector>
using Names = std::vector<std::string>;
using Lines = Names;
using Roles = std::uint64_t;
using Days = std::array<bool, 366>;
Names split(const std::string &text, const std::string &separator = " ");
std::string join(const Names &values, const std::string &separator);
std::string trim(std::string text);
Lines read_lines(const std::string &path);
template <class... T> std::string text(const T &...values) {
    std::ostringstream out;
    (out << ... << values);
    return out.str();
}
template <class... T> void line(Lines &lines, const T &...values) {
    lines.push_back(text(values...));
}
struct Value {
    enum class Kind { Integer, String, Boolean, Bag, Error } kind = Kind::Boolean;
    int integer = 0;
    bool boolean = false;
    std::string string;
    Names bag;
    static Value number(int n) {
        Value v;
        v.kind = Kind::Integer;
        v.integer = n;
        return v;
    }
    static Value word(std::string s) {
        Value v;
        v.kind = Kind::String;
        v.string = std::move(s);
        return v;
    }
    static Value truth(bool b) {
        Value v;
        v.boolean = b;
        return v;
    }
    static Value collection(Names a) {
        Value v;
        v.kind = Kind::Bag;
        v.bag = std::move(a);
        return v;
    }
    static Value error(std::string s) {
        Value v;
        v.kind = Kind::Error;
        v.string = std::move(s);
        return v;
    }
};
using Attributes = std::map<std::string, Value>;
struct Expression {
    std::string operation;
    Value literal;
    std::vector<std::shared_ptr<Expression>> arguments;
};
using Expr = std::shared_ptr<Expression>;
Expr parse_expression(const std::string &source);
struct Clause {
    std::string reference, operation;
    bool mandatory;
    Expr literal;
};
using Alternative = std::vector<Clause>;
using TargetLine = std::vector<Alternative>;
struct Attachment {
    std::string effect, identifier;
    std::vector<std::pair<std::string, Expr>> arguments;
};
struct Element {
    std::string kind, identifier, behavior;
    Element *parent = nullptr;
    int index;
    std::vector<Element *> children;
    std::vector<TargetLine> targets;
    Expr condition;
    std::vector<Attachment> obligations, advice;
};
struct Policies {
    std::vector<std::unique_ptr<Element>> elements;
    Element *root;
};
Policies read_policies();
struct Grant {
    int role;
    std::string action, type;
};
struct Constraint {
    std::string name;
    int cardinality;
    Roles roles;
};
struct Assignment {
    std::string user;
    int role, first, last;
};
struct Diagnostic {
    int number;
    std::string keyword, message;
};
struct RBAC {
    Names roles;
    std::array<Roles, 40> inherits{};
    std::vector<Grant> grants;
    std::vector<Constraint> ssd, dsd;
    std::vector<Assignment> assignments;
    std::vector<Diagnostic> diagnostics;
    int find(const std::string &name) const;
    Roles closure(Roles source) const, assigned(const std::string &user, int day) const,
        authorized(const std::string &user, int day) const;
    std::vector<int> ordered(Roles source) const;
    Names names(Roles source) const;
    bool permits(int role, const std::string &action, const std::string &type) const;
    std::string path(int from, int to) const, accept(const Names &fields);
    void read();
};
Roles bit(int role);
int cardinality(Roles roles);
enum class Decision { Permit, Deny, NA, IP, ID, IDP };
bool definite(Decision d), indeterminate(Decision d);
std::string decision_name(Decision d), notation(Decision d, const std::string &reason);
enum class TargetKind { Match, NoMatch, Indeterminate };
struct TargetResult {
    TargetKind kind = TargetKind::Match;
    std::string reason;
};
std::string target_name(TargetKind kind);
struct Evaluation;
using Eval = std::shared_ptr<Evaluation>;
struct ChildState {
    enum class Kind { Skipped, Checked, Evaluated } kind = Kind::Skipped;
    TargetResult checked;
    Eval evaluation;
};
struct Evaluation {
    Element *element;
    TargetResult target;
    Decision decision = Decision::NA;
    std::string reason;
    Element *decisive = nullptr;
    Value condition;
    std::vector<ChildState> children;
    std::vector<std::pair<std::string, std::string>> obligations, advice;
};
struct Combined {
    Decision decision = Decision::NA;
    std::string reason;
    std::vector<ChildState> children;
};
Combined combine(const Element &element, const std::function<Eval(Element *)> &evaluate,
                 const std::function<TargetResult(Element *)> &target);
struct Domain {
    std::string reference;
    std::vector<Value> candidates;
};
std::vector<Attributes> points(const std::vector<Domain> &domains);
std::string day_notation(const Days &days);
Element *blocker(Element *rule, const std::array<Decision, 100> &standalone);
Element *conflict_winner(Element *policy, Element *earlier, Element *later);
#endif
