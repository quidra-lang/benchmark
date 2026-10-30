#include "planner.hpp"
struct Expression {
    std::string word;
    std::vector<Expression> list;
};
Lines readLines(const std::string &path) {
    std::ifstream input(path);
    if (!input)
        throw std::runtime_error("cannot read " + path);
    Lines out;
    for (std::string line; std::getline(input, line);)
        out.push_back(line);
    return out;
}
Lines splitWords(const std::string &text) {
    std::istringstream input(text);
    Lines out;
    for (std::string word; input >> word;)
        out.push_back(word);
    return out;
}
std::string join(const Lines &items, const std::string &separator) {
    std::string out;
    for (std::size_t i = 0; i < items.size(); ++i) {
        if (i)
            out += separator;
        out += items[i];
    }
    return out;
}
std::string intList(const Plan &items, const std::string &separator) {
    Lines out;
    for (int number : items)
        out.push_back(std::to_string(number));
    return join(out, separator);
}
static std::vector<Expression> expressions(const std::string &path) {
    Lines tokens;
    for (std::string line : readLines(path)) {
        line = line.substr(0, line.find(';'));
        std::string spaced;
        for (char c : line) {
            if (c == '(' || c == ')') {
                spaced += ' ';
                spaced += c;
                spaced += ' ';
            } else
                spaced += c;
        }
        Lines words = splitWords(spaced);
        tokens.insert(tokens.end(), words.begin(), words.end());
    }
    std::size_t at = 0;
    std::function<Expression()> read = [&]() {
        Expression out;
        std::string token = tokens.at(at++);
        if (token != "(") {
            out.word = token;
            return out;
        }
        while (tokens.at(at) != ")")
            out.list.push_back(read());
        ++at;
        return out;
    };
    std::vector<Expression> out;
    while (at < tokens.size())
        out.push_back(read());
    return out;
}
static Lines words(const std::vector<Expression> &items, std::size_t from = 0) {
    Lines out;
    for (std::size_t i = from; i < items.size(); ++i)
        out.push_back(items[i].word);
    return out;
}
static std::vector<Typed> typedList(const Lines &tokens) {
    std::vector<Typed> out;
    Lines pending;
    for (std::size_t i = 0; i < tokens.size(); ++i) {
        if (tokens[i] == "-") {
            const std::string type = tokens[++i];
            for (const std::string &name : pending)
                out.push_back({name, type});
            pending.clear();
        } else
            pending.push_back(tokens[i]);
    }
    for (const std::string &name : pending)
        out.push_back({name, "object"});
    return out;
}
std::string Atom::text() const {
    return "(" + predicate + (terms.empty() ? "" : " " + join(terms, " ")) + ")";
}
std::string Literal::text() const { return negative ? "(not " + atom.text() + ")" : atom.text(); }
static Atom parseAtom(const Expression &expression) {
    return {expression.list[0].word, words(expression.list, 1)};
}
static Literal literal(const Expression &expression) {
    if (expression.list[0].word == "not")
        return {parseAtom(expression.list[1]), true};
    return {parseAtom(expression), false};
}
static std::vector<Expression> conjunction(const Expression &expression) {
    if (!expression.list.empty() && expression.list[0].word == "and")
        return {expression.list.begin() + 1, expression.list.end()};
    return {expression};
}
Domain readDomain() {
    Expression root = expressions("input/domain.txt")[0];
    Domain domain;
    domain.name = root.list[1].list[1].word;
    for (std::size_t section = 2; section < root.list.size(); ++section) {
        const std::vector<Expression> &items = root.list[section].list;
        if (items[0].word == ":types") {
            Lines tokens = words(items, 1);
            for (const std::string &name : tokens) {
                if (name != "-" && std::find(domain.types.begin(), domain.types.end(), name) ==
                                       domain.types.end()) {
                    domain.types.push_back(name);
                    domain.parents[name] = "object";
                }
            }
            for (const Typed &type : typedList(tokens))
                domain.parents[type.name] = type.type;
        } else if (items[0].word == ":predicates") {
            for (std::size_t i = 1; i < items.size(); ++i) {
                Predicate predicate{items[i].list[0].word, {}};
                for (const Typed &type : typedList(words(items[i].list, 1)))
                    predicate.types.push_back(type.type);
                domain.predicateIndex[predicate.name] = static_cast<int>(domain.predicates.size());
                domain.predicates.push_back(std::move(predicate));
            }
        } else if (items[0].word == ":action") {
            Schema schema;
            schema.name = items[1].word;
            for (std::size_t i = 2; i < items.size(); i += 2) {
                if (items[i].word == ":parameters")
                    schema.parameters = typedList(words(items[i + 1].list));
                else if (items[i].word == ":precondition") {
                    for (const Expression &entry : conjunction(items[i + 1]))
                        schema.conditions.push_back(literal(entry));
                } else if (items[i].word == ":effect") {
                    for (const Expression &entry : conjunction(items[i + 1])) {
                        if (entry.list[0].word == "increase")
                            schema.cost = std::stoll(entry.list[2].word);
                        else
                            schema.effects.push_back(literal(entry));
                    }
                }
            }
            domain.actions.push_back(std::move(schema));
        }
    }
    return domain;
}
std::vector<Problem> readProblems() {
    std::vector<Problem> out;
    for (const Expression &root : expressions("input/problems.txt")) {
        Problem problem;
        problem.name = root.list[1].list[1].word;
        for (std::size_t section = 2; section < root.list.size(); ++section) {
            const std::vector<Expression> &items = root.list[section].list;
            if (items[0].word == ":objects")
                problem.objects = typedList(words(items, 1));
            else if (items[0].word == ":init") {
                for (std::size_t i = 1; i < items.size(); ++i)
                    problem.initial.push_back(parseAtom(items[i]));
            } else if (items[0].word == ":goal") {
                for (const Expression &entry : conjunction(items[1]))
                    problem.goals.push_back(parseAtom(entry));
            }
        }
        out.push_back(std::move(problem));
    }
    return out;
}
