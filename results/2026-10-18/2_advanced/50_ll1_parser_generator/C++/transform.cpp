#include "parser.hpp"
static std::string fresh(const Grammar &grammar, const std::string &base) {
    std::string out = base;
    do {
        out.insert(out.size() - 1, "'");
    } while (grammar.rules.count(out));
    return out;
}
static bool leading_reachable(const Grammar &grammar, const std::string &source, const std::string &target) {
    std::queue<std::string> queue;
    std::set<std::string> visited{source};
    queue.push(source);
    while (!queue.empty()) {
        const std::string current = queue.front();
        queue.pop();
        for (const Sequence &alternative : grammar.rules.at(current))
            if (!alternative.empty() && nonterminal(alternative[0])) {
                const std::string &next = alternative[0];
                if (next == target)
                    return true;
                if (visited.insert(next).second)
                    queue.push(next);
            }
    }
    return false;
}
static Alternatives deduplicate(const Alternatives &alternatives) {
    Alternatives out;
    std::set<Sequence> seen;
    for (const Sequence &alternative : alternatives)
        if (seen.insert(alternative).second)
            out.push_back(alternative);
    return out;
}
Lines eliminate_recursion(Grammar &grammar) {
    Lines logs;
    const Lines original = grammar.order;
    for (std::size_t i = 0; i < original.size(); ++i) {
        const std::string &current = original[i];
        for (std::size_t j = 0; j < i; ++j) {
            const std::string &earlier = original[j];
            bool present = false;
            for (const Sequence &alternative : grammar.rules[current])
                present = present || (!alternative.empty() && alternative[0] == earlier);
            if (!present || !leading_reachable(grammar, earlier, current))
                continue;
            Alternatives replacement;
            for (const Sequence &alternative : grammar.rules[current])
                if (!alternative.empty() && alternative[0] == earlier) {
                    for (const Sequence &prefix : grammar.rules[earlier]) {
                        Sequence combined = prefix;
                        combined.insert(combined.end(), alternative.begin() + 1, alternative.end());
                        replacement.push_back(std::move(combined));
                    }
                } else
                    replacement.push_back(alternative);
            grammar.rules[current] = deduplicate(replacement);
            logs.push_back("substitute " + earlier + " into " + current);
        }
        Alternatives remaining;
        for (const Sequence &alternative : grammar.rules[current])
            if (alternative.size() == 1 && alternative[0] == current)
                logs.push_back("remove cycle " + current + " -> " + current);
            else
                remaining.push_back(alternative);
        grammar.rules[current] = remaining;
        bool recursive = false;
        for (const Sequence &alternative : remaining)
            recursive = recursive || (!alternative.empty() && alternative[0] == current);
        if (!recursive)
            continue;
        const std::string created = fresh(grammar, current);
        Alternatives base, tail;
        for (const Sequence &alternative : remaining) {
            Sequence rhs;
            if (!alternative.empty() && alternative[0] == current) {
                rhs.assign(alternative.begin() + 1, alternative.end());
                rhs.push_back(created);
                tail.push_back(std::move(rhs));
            } else {
                rhs = alternative;
                rhs.push_back(created);
                base.push_back(std::move(rhs));
            }
        }
        tail.push_back({});
        grammar.rules[current] = std::move(base);
        grammar.rules[created] = std::move(tail);
        const auto position = std::find(grammar.order.begin(), grammar.order.end(), current);
        grammar.order.insert(position + 1, created);
        logs.push_back("eliminate left recursion in " + current + " with " + created);
    }
    return logs;
}
Lines left_factor(Grammar &grammar) {
    Lines logs;
    for (std::size_t position = 0; position < grammar.order.size(); ++position) {
        const std::string current = grammar.order[position];
        const Alternatives old = grammar.rules[current];
        Alternatives replacement;
        Lines created;
        std::set<std::string> processed;
        for (const Sequence &alternative : old) {
            if (alternative.empty()) {
                replacement.push_back(alternative);
                continue;
            }
            if (!processed.insert(alternative[0]).second)
                continue;
            Alternatives group;
            for (const Sequence &other : old)
                if (!other.empty() && other[0] == alternative[0])
                    group.push_back(other);
            if (group.size() == 1) {
                replacement.push_back(alternative);
                continue;
            }
            Sequence prefix = group[0];
            for (const Sequence &other : group) {
                std::size_t count = 0;
                while (count < prefix.size() && count < other.size() && prefix[count] == other[count])
                    ++count;
                prefix.resize(count);
            }
            const std::string name = fresh(grammar, current);
            Alternatives remainders;
            for (const Sequence &other : group)
                remainders.emplace_back(other.begin() + prefix.size(), other.end());
            grammar.rules[name] = std::move(remainders);
            created.push_back(name);
            Sequence factored = prefix;
            factored.push_back(name);
            replacement.push_back(std::move(factored));
            logs.push_back("left factor " + current + " on " + notation(prefix) + " with " + name);
        }
        grammar.rules[current] = std::move(replacement);
        grammar.order.insert(grammar.order.begin() + position + 1, created.begin(), created.end());
    }
    return logs;
}
