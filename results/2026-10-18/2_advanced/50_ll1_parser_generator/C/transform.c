#include "parser.h"
static const char *fresh(const Grammar *grammar, const char *base) {
    const char *out = base;
    do {
        out = format("%.*s'>", (int)strlen(out) - 1, out);
    } while (rule_index(grammar, out) >= 0);
    return out;
}
static bool leading_reachable(const Grammar *grammar, const char *source, const char *target) {
    const int n = grammar->n;
    bool *seen = allocate((size_t)n * sizeof *seen);
    int *queue = allocate((size_t)n * sizeof *queue);
    int head = 0, tail = 0;
    const int start = rule_index(grammar, source);
    queue[tail++] = start;
    seen[start] = true;
    while (head < tail) {
        const Rule *rule = &grammar->v[queue[head++]];
        for (int i = 0; i < rule->alternatives.n; ++i) {
            const Strings rhs = rule->alternatives.v[i];
            if (!rhs.n || !nonterminal(rhs.v[0]))
                continue;
            if (strcmp(rhs.v[0], target) == 0)
                return true;
            const int next = rule_index(grammar, rhs.v[0]);
            if (!seen[next]) {
                seen[next] = true;
                queue[tail++] = next;
            }
        }
    }
    return false;
}
Strings eliminate_recursion(Grammar *grammar) {
    Strings logs = {0}, original = {0};
    for (int i = 0; i < grammar->n; ++i)
        strings_add(&original, grammar->v[i].name);
    for (int i = 0; i < original.n; ++i) {
        const char *current = original.v[i];
        for (int j = 0; j < i; ++j) {
            const char *earlier = original.v[j];
            const int ci = rule_index(grammar, current);
            const Alternatives old = grammar->v[ci].alternatives;
            bool present = false;
            for (int a = 0; a < old.n; ++a)
                if (old.v[a].n && strcmp(old.v[a].v[0], earlier) == 0)
                    present = true;
            if (!present || !leading_reachable(grammar, earlier, current))
                continue;
            Alternatives replacement = {0};
            const Alternatives prefixes = grammar->v[rule_index(grammar, earlier)].alternatives;
            for (int a = 0; a < old.n; ++a) {
                const Strings rhs = old.v[a];
                if (rhs.n && strcmp(rhs.v[0], earlier) == 0) {
                    const Strings suffix = strings_slice(rhs, 1, rhs.n);
                    for (int b = 0; b < prefixes.n; ++b)
                        alternatives_unique(&replacement, strings_concat(prefixes.v[b], suffix));
                } else
                    alternatives_unique(&replacement, rhs);
            }
            grammar->v[ci].alternatives = replacement;
            strings_add(&logs, format("substitute %s into %s", earlier, current));
        }
        const int ci = rule_index(grammar, current);
        Alternatives remaining = {0};
        const Alternatives old = grammar->v[ci].alternatives;
        for (int a = 0; a < old.n; ++a) {
            const Strings rhs = old.v[a];
            if (rhs.n == 1 && strcmp(rhs.v[0], current) == 0)
                strings_add(&logs, format("remove cycle %s -> %s", current, current));
            else
                alternatives_add(&remaining, rhs);
        }
        grammar->v[ci].alternatives = remaining;
        bool recursive = false;
        for (int a = 0; a < remaining.n; ++a)
            if (remaining.v[a].n && strcmp(remaining.v[a].v[0], current) == 0)
                recursive = true;
        if (!recursive)
            continue;
        const char *created = fresh(grammar, current);
        Alternatives base = {0}, tail = {0};
        for (int a = 0; a < remaining.n; ++a) {
            const Strings rhs = remaining.v[a];
            if (rhs.n && strcmp(rhs.v[0], current) == 0) {
                Strings value = strings_slice(rhs, 1, rhs.n);
                strings_add(&value, created);
                alternatives_add(&tail, value);
            } else {
                Strings value = strings_slice(rhs, 0, rhs.n);
                strings_add(&value, created);
                alternatives_add(&base, value);
            }
        }
        alternatives_add(&tail, (Strings){0});
        grammar->v[ci].alternatives = base;
        rule_add(grammar, (Rule){created, tail}, ci + 1);
        strings_add(&logs, format("eliminate left recursion in %s with %s", current, created));
    }
    return logs;
}
Strings left_factor(Grammar *grammar) {
    Strings logs = {0};
    for (int position = 0; position < grammar->n; ++position) {
        const char *current = grammar->v[position].name;
        const Alternatives old = grammar->v[position].alternatives;
        Alternatives replacement = {0};
        Strings processed = {0};
        Rule *created = NULL;
        int ncreated = 0;
        for (int a = 0; a < old.n; ++a) {
            const Strings rhs = old.v[a];
            if (!rhs.n) {
                alternatives_add(&replacement, rhs);
                continue;
            }
            if (!strings_unique(&processed, rhs.v[0]))
                continue;
            Alternatives group = {0};
            for (int b = 0; b < old.n; ++b)
                if (old.v[b].n && strcmp(old.v[b].v[0], rhs.v[0]) == 0)
                    alternatives_add(&group, old.v[b]);
            if (group.n == 1) {
                alternatives_add(&replacement, rhs);
                continue;
            }
            Strings prefix = strings_slice(group.v[0], 0, group.v[0].n);
            for (int b = 0; b < group.n; ++b) {
                int count = 0;
                while (count < prefix.n && count < group.v[b].n &&
                       strcmp(prefix.v[count], group.v[b].v[count]) == 0)
                    ++count;
                prefix.n = count;
            }
            const char *name = fresh(grammar, current);
            Alternatives remainders = {0};
            for (int b = 0; b < group.n; ++b)
                alternatives_add(&remainders, strings_slice(group.v[b], prefix.n, group.v[b].n));
            rule_add(grammar, (Rule){name, remainders}, grammar->n);
            created =
                grow(created, (size_t)ncreated * sizeof *created, (size_t)(ncreated + 1) * sizeof *created);
            created[ncreated++] = (Rule){name, remainders};
            Strings factored = strings_slice(prefix, 0, prefix.n);
            strings_add(&factored, name);
            alternatives_add(&replacement, factored);
            strings_add(&logs, format("left factor %s on %s with %s", current, notation(prefix), name));
        }
        grammar->n -= ncreated;
        grammar->v[position].alternatives = replacement;
        for (int a = 0; a < ncreated; ++a)
            rule_add(grammar, created[a], position + 1 + a);
    }
    return logs;
}
