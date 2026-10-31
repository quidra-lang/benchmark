#include "chemistry.h"
#include <stdlib.h>
#include <string.h>
bool digit(char c) { return c >= '0' && c <= '9'; }
bool organic_atom(const char *source, size_t at, const Elements *elements, Atom *atom,
                  size_t *next) {
    *atom = (Atom){0};
    char symbol[3] = {source[at], 0, 0};
    if (source[at + 1] && ((source[at] == 'C' && source[at + 1] == 'l') ||
                           (source[at] == 'B' && source[at + 1] == 'r'))) {
        symbol[1] = source[at + 1];
        *next = at + 2;
    } else if (strchr("BCNOPSFI", source[at]))
        *next = at + 1;
    else if (strchr("bcnops", source[at])) {
        symbol[0] = (char)(source[at] - 'a' + 'A');
        atom->aromatic = true;
        *next = at + 1;
    } else
        return false;
    atom->element = element_index(elements, symbol);
    return true;
}
const char *bracket_atom(const char *content, const Elements *elements, Atom *atom) {
    *atom = (Atom){.bracket = true};
    size_t i = 0;
    while (digit(content[i]))
        ++i;
    if (i >= 4 || (i && content[0] == '0'))
        return "bad bracket atom";
    if (i)
        atom->mass = atoi(content);
    if (!content[i])
        return "bad bracket atom";
    char c = content[i], symbol[3] = {c, 0, 0};
    if (strchr("bcnops", c)) {
        symbol[0] = (char)(c - 'a' + 'A');
        atom->aromatic = true;
        ++i;
        atom->element = element_index(elements, symbol);
    } else if (c >= 'A' && c <= 'Z') {
        if (content[i + 1] >= 'a' && content[i + 1] <= 'z')
            symbol[1] = content[i + 1];
        int element = element_index(elements, symbol);
        if (symbol[1] && element >= 0) {
            atom->element = element;
            i += 2;
        } else {
            symbol[1] = 0;
            element = element_index(elements, symbol);
            if (element < 0)
                return "unknown element";
            atom->element = element;
            ++i;
        }
    } else
        return "bad bracket atom";
    if (content[i] == '@') {
        ++i;
        if (content[i] == '@')
            ++i;
    }
    if (content[i] == 'H') {
        atom->hydrogens = 1;
        ++i;
        if (digit(content[i]))
            atom->hydrogens = content[i++] - '0';
    }
    if (content[i] == '+' || content[i] == '-') {
        int sign = content[i++] == '+' ? 1 : -1, magnitude = 1;
        if (content[i] >= '1' && content[i] <= '9')
            magnitude = content[i++] - '0';
        atom->charge = sign * magnitude;
    }
    return content[i] ? "bad bracket atom" : NULL;
}
int symbol_type(char c) {
    if (c == '-' || c == '/' || c == '\\')
        return 1;
    if (c == '=')
        return 2;
    if (c == '#')
        return 3;
    if (c == ':')
        return 4;
    if (c == '~')
        return 5;
    return 0;
}
static void add_bond(Molecule *m, int a, int b, char symbol, bool pattern) {
    if (a > b) {
        int t = a;
        a = b;
        b = t;
    }
    Bond bond = {.a = a, .b = b, .symbol = symbol};
    if (pattern) {
        int kind = symbol_type(symbol);
        bond.match = kind == 0   ? (1 << 1) | (1 << 4)
                     : kind == 5 ? (1 << 1) | (1 << 2) | (1 << 3) | (1 << 4)
                                 : 1 << kind;
    }
    molecule_add_bond(m, bond);
}
Molecule *parse_smiles(const char *source, const Elements *elements, bool pattern,
                       ParseError *error) {
    typedef struct {
        int atom, column;
        char symbol;
        bool active;
    } Open;
    typedef struct {
        int atom, column;
    } Branch;
    Molecule *m = molecule_new();
    int current = -1, pending_column = 0, stack_count = 0;
    char pending = 0;
    size_t length = strlen(source);
    Branch *stack = allocate((length + 1) * sizeof(Branch));
    Open open[100] = {{0}};
    *error = (ParseError){0};
    for (size_t i = 0; i < length;) {
        char c = source[i];
        int column = (int)i + 1;
        const char *symbols = pattern ? "-=#:~" : "-/\\=#:";
        if (strchr(symbols, c)) {
            if (current < 0 || pending) {
                *error = (ParseError){"misplaced bond", column};
                goto fail;
            }
            pending = c;
            pending_column = column;
            ++i;
        } else if (c == '(') {
            if (current < 0 || pending || (i && source[i - 1] == '(')) {
                *error = (ParseError){"misplaced branch", column};
                goto fail;
            }
            stack[stack_count++] = (Branch){current, column};
            ++i;
        } else if (c == ')') {
            if (!stack_count) {
                *error = (ParseError){"unmatched parenthesis", column};
                goto fail;
            }
            if (pending) {
                *error = (ParseError){"dangling bond", pending_column};
                goto fail;
            }
            if (i && source[i - 1] == '(') {
                *error = (ParseError){"empty branch", column};
                goto fail;
            }
            current = stack[--stack_count].atom;
            ++i;
        } else if (digit(c) || c == '%') {
            if (current < 0) {
                *error = (ParseError){"misplaced ring closure", column};
                goto fail;
            }
            int number;
            if (c == '%') {
                if (i + 2 >= length || !digit(source[i + 1]) || !digit(source[i + 2])) {
                    *error = (ParseError){"bad ring number", column};
                    goto fail;
                }
                number = 10 * (source[i + 1] - '0') + source[i + 2] - '0';
                i += 3;
            } else {
                number = c - '0';
                ++i;
            }
            char symbol = pending;
            pending = 0;
            if (!open[number].active)
                open[number] = (Open){current, column, symbol, true};
            else {
                Open old = open[number];
                if (old.atom == current) {
                    *error = (ParseError){"self bond", column};
                    goto fail;
                }
                if (old.symbol && symbol &&
                    (pattern ? old.symbol != symbol
                             : symbol_type(old.symbol) != symbol_type(symbol))) {
                    *error = (ParseError){"ring bond mismatch", column};
                    goto fail;
                }
                for (int e = 0; e < m->bond_count; ++e)
                    if ((m->bonds[e].a == old.atom && m->bonds[e].b == current) ||
                        (m->bonds[e].a == current && m->bonds[e].b == old.atom)) {
                        *error = (ParseError){"duplicate bond", column};
                        goto fail;
                    }
                add_bond(m, old.atom, current, symbol ? symbol : old.symbol, pattern);
                open[number].active = false;
            }
        } else {
            Atom atom = {0};
            size_t next = i;
            const char *reason = NULL;
            if (pattern)
                reason = pattern_atom(source, i, elements, &atom, &next);
            else if (c == '[') {
                const char *end = strchr(source + i + 1, ']');
                if (!end) {
                    *error = (ParseError){"unclosed bracket", column};
                    goto fail;
                }
                size_t size = (size_t)(end - (source + i + 1));
                char *content = allocate(size + 1);
                memcpy(content, source + i + 1, size);
                content[size] = 0;
                reason = bracket_atom(content, elements, &atom);
                free(content);
                next = (size_t)(end - source) + 1;
            } else if (!organic_atom(source, i, elements, &atom, &next))
                reason = "unexpected character";
            if (reason) {
                free(atom.choices);
                *error = (ParseError){reason, column};
                goto fail;
            }
            atom.column = column;
            molecule_add_atom(m, atom);
            int index = m->atom_count - 1;
            if (current >= 0)
                add_bond(m, current, index, pending, pattern);
            current = index;
            pending = 0;
            i = next;
        }
    }
    if (pending) {
        *error = (ParseError){"dangling bond", pending_column};
        goto fail;
    }
    if (stack_count) {
        *error = (ParseError){"unmatched parenthesis", stack[0].column};
        goto fail;
    }
    int earliest = (int)length + 1;
    for (int i = 0; i < 100; ++i)
        if (open[i].active && open[i].column < earliest)
            earliest = open[i].column;
    if (earliest <= (int)length) {
        *error = (ParseError){"unclosed ring", earliest};
        goto fail;
    }
    free(stack);
    molecule_build(m);
    return m;
fail:
    free(stack);
    molecule_free(m);
    return NULL;
}
