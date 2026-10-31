#include "regression.hpp"
static Lines split(const std::string &text, const std::string &delimiter) {
    Lines out;
    std::size_t first = 0;
    while (true) {
        const std::size_t next = text.find(delimiter, first);
        out.push_back(text.substr(first, next == std::string::npos ? next : next - first));
        if (next == std::string::npos)
            break;
        first = next + delimiter.size();
    }
    return out;
}
static Factor factor(const std::string &name, const Dataframe &data) {
    Factor out;
    out.name = name;
    std::string column = name;
    if (name.substr(0, 2) == "C(") {
        out.categorical = true;
        column = name.substr(2, name.size() - 3);
    } else if (name.substr(0, 2) == "I(") {
        const std::size_t caret = name.find('^');
        column = name.substr(2, caret - 2);
        out.power = std::stoi(name.substr(caret + 1, name.size() - caret - 2));
    }
    out.column = std::find(data.names.begin(), data.names.end(), column) - data.names.begin();
    return out;
}
static std::set<std::string> factor_set(const Term &term) {
    std::set<std::string> out;
    for (const Factor &factor_ : term.factors)
        out.insert(factor_.name);
    return out;
}
Formula parse_formula(const std::string &line, const Dataframe &data) {
    Formula out;
    const std::size_t weights = line.find(" weights=");
    out.raw = line.substr(0, weights);
    if (weights != std::string::npos) {
        const std::string name = line.substr(weights + 9);
        out.weight = std::find(data.names.begin(), data.names.end(), name) - data.names.begin();
    }
    const auto sides = split(out.raw, " ~ ");
    out.response = std::find(data.names.begin(), data.names.end(), sides[0]) - data.names.begin();
    for (const std::string &expression : split(sides[1], " + ")) {
        const bool star = expression.find('*') != std::string::npos;
        const Lines names_ = split(expression, star ? "*" : ":");
        std::vector<std::vector<int>> subsets;
        if (star) {
            for (int count = 1; count <= int(names_.size()); ++count)
                for (int mask = 1; mask < (1 << names_.size()); ++mask) {
                    std::vector<int> subset;
                    for (std::size_t j = 0; j < names_.size(); ++j)
                        if (mask & (1 << j))
                            subset.push_back(j);
                    if (int(subset.size()) == count)
                        subsets.push_back(subset);
                }
        } else {
            std::vector<int> subset(names_.size());
            std::iota(subset.begin(), subset.end(), 0);
            subsets.push_back(subset);
        }
        for (const auto &subset : subsets) {
            Term term;
            for (int j : subset) {
                term.factors.push_back(factor(names_[j], data));
                if (!term.name.empty())
                    term.name += ":";
                term.name += names_[j];
            }
            const auto key = factor_set(term);
            bool duplicate = false;
            for (const Term &earlier : out.terms)
                if (factor_set(earlier) == key)
                    duplicate = true;
            if (!duplicate)
                out.terms.push_back(term);
        }
    }
    return out;
}
bool contained(const Term &a, const Term &b) {
    const auto first = factor_set(a), second = factor_set(b);
    return first.size() < second.size() &&
           std::includes(second.begin(), second.end(), first.begin(), first.end());
}
std::string formula_text(const Formula &formula, const std::vector<int> &terms, const Dataframe &data) {
    std::string out = data.names[formula.response] + " ~ ";
    if (terms.empty())
        return out + "1";
    for (std::size_t i = 0; i < terms.size(); ++i) {
        if (i)
            out += " + ";
        out += formula.terms[terms[i]].name;
    }
    return out;
}
Vector record_values(const std::vector<Column> &columns, const Record &record) {
    Vector values;
    for (const Column &column : columns) {
        double value = 1;
        for (const Component &component : column.components) {
            double part = component.categorical ? (record[component.column].label == component.label ? 1 : 0)
                                                : record[component.column].number;
            if (!component.categorical) {
                if (component.power == 2)
                    part = part * part;
                else if (component.power == 3)
                    part = part * part * part;
            }
            value = value * part;
        }
        values.push_back(value);
    }
    return values;
}
Design build_design(const Formula &formula, const Dataframe &data) {
    Design out;
    out.formula = formula;
    std::set<int> variables = {formula.response};
    if (formula.weight >= 0)
        variables.insert(formula.weight);
    for (const Term &term : formula.terms)
        for (const Factor &factor_ : term.factors)
            variables.insert(factor_.column);
    for (std::size_t i = 0; i < data.rows.size(); ++i) {
        bool complete = true;
        for (int column : variables)
            if (data.rows[i][column].missing)
                complete = false;
        if (complete)
            out.used.push_back(i);
    }
    for (const Term &term : formula.terms)
        for (const Factor &factor_ : term.factors)
            if (factor_.categorical) {
                std::set<std::string> levels;
                for (int row : out.used)
                    levels.insert(data.rows[row][factor_.column].label);
                out.levels[factor_.column] = Lines(levels.begin(), levels.end());
            }
    out.columns.push_back({"(Intercept)", -1, {}});
    for (std::size_t t = 0; t < formula.terms.size(); ++t) {
        const Term &term = formula.terms[t];
        std::vector<std::vector<Component>> parts;
        std::size_t count = 1;
        for (const Factor &factor_ : term.factors) {
            std::vector<Component> components;
            if (factor_.categorical) {
                const Lines &levels = out.levels.at(factor_.column);
                for (std::size_t i = 1; i < levels.size(); ++i)
                    components.push_back({factor_.name + levels[i], levels[i], factor_.column, 1, true});
            } else
                components.push_back({factor_.name, "", factor_.column, factor_.power, false});
            count *= components.size();
            parts.push_back(components);
        }
        for (std::size_t index = 0; index < count; ++index) {
            std::size_t remainder = index;
            Column column;
            column.term = t;
            for (const auto &choices : parts) {
                const Component component = choices[remainder % choices.size()];
                remainder /= choices.size();
                column.components.push_back(component);
                if (!column.name.empty())
                    column.name += ":";
                column.name += component.name;
            }
            out.columns.push_back(column);
        }
    }
    for (int row : out.used) {
        out.x.push_back(record_values(out.columns, data.rows[row]));
        out.y.push_back(data.rows[row][formula.response].number);
        out.weights.push_back(formula.weight < 0 ? 1 : data.rows[row][formula.weight].number);
    }
    return out;
}
std::vector<int> selected_columns(const Design &design, const std::vector<int> &terms) {
    std::vector<int> out = {0};
    for (std::size_t column = 1; column < design.columns.size(); ++column)
        if (std::find(terms.begin(), terms.end(), design.columns[column].term) != terms.end())
            out.push_back(column);
    return out;
}
bool predictable(const Design &design, const Record &record) {
    for (const Term &term : design.formula.terms)
        for (const Factor &factor_ : term.factors) {
            if (record[factor_.column].missing)
                return false;
            if (factor_.categorical) {
                const Lines &levels = design.levels.at(factor_.column);
                if (std::find(levels.begin(), levels.end(), record[factor_.column].label) == levels.end())
                    return false;
            }
        }
    return true;
}
