#include <ctype.h>
#include <setjmp.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef int64_t Int;
typedef struct {
    Int n, d;
} Rational;
typedef struct {
    Int atoms[54], charge;
} Formula;
typedef struct {
    Formula formula;
    char name[128], core[128], state[8];
    Int coefficient;
} Species;
typedef struct {
    Species species[64];
    int count, reactants, signs[64];
} Equation;
typedef struct {
    char name[128];
    Int value;
} Heat;

static const char *symbols[] = {"H",  "He", "Li", "Be", "B",  "C",  "N",  "O",  "F",  "Ne", "Na",
                                "Mg", "Al", "Si", "P",  "S",  "Cl", "Ar", "K",  "Ca", "Sc", "Ti",
                                "V",  "Cr", "Mn", "Fe", "Co", "Ni", "Cu", "Zn", "Ga", "Ge", "As",
                                "Se", "Br", "Kr", "Rb", "Sr", "Y",  "Zr", "Nb", "Mo", "Tc", "Ru",
                                "Rh", "Pd", "Ag", "Cd", "In", "Sn", "Sb", "Te", "I",  "Xe"};
static const Int weights[] = {
    1008,   4003,   6941,   9012,   10811,  12011,  14007,  15999,  18998,  20180, 22990,
    24305,  26982,  28086,  30974,  32065,  35453,  39948,  39098,  40078,  44956, 47867,
    50942,  51996,  54938,  55845,  58933,  58693,  63546,  65380,  69723,  72630, 74922,
    78971,  79904,  83798,  85468,  87620,  88906,  91224,  92906,  95950,  98000, 101070,
    102906, 106420, 107868, 112414, 114818, 118710, 121760, 127600, 126904, 131293};
static Heat heats[500];
static int heat_count;
static jmp_buf command_end;
static char output[65536];
static size_t output_size;

static void append(const char *format, ...) {
    va_list args;
    va_start(args, format);
    output_size +=
        (size_t)vsnprintf(output + output_size, sizeof output - output_size, format, args);
    va_end(args);
}

static void fail(const char *format, ...) {
    va_list args;
    output_size = 0;
    append("error: ");
    va_start(args, format);
    output_size +=
        (size_t)vsnprintf(output + output_size, sizeof output - output_size, format, args);
    va_end(args);
    append("\n");
    longjmp(command_end, 1);
}

static Int gcd_int(Int a, Int b) {
    if (a < 0)
        a = -a;
    if (b < 0)
        b = -b;
    while (b) {
        Int r = a % b;
        a = b;
        b = r;
    }
    return a;
}

static Rational rational(Int n, Int d) {
    if (d < 0) {
        n = -n;
        d = -d;
    }
    Int g = gcd_int(n, d);
    return (Rational){n / g, d / g};
}

static Rational subtract(Rational a, Rational b) {
    return rational(a.n * b.d - b.n * a.d, a.d * b.d);
}

static Rational multiply(Rational a, Rational b) {
    Int g = gcd_int(a.n, b.d), h = gcd_int(b.n, a.d);
    return rational((a.n / g) * (b.n / h), (a.d / h) * (b.d / g));
}

static Rational divide(Rational a, Rational b) {
    return multiply(a, rational(b.d, b.n));
}

static int element(const char *s) {
    for (int i = 0; i < 54; ++i)
        if (!strcmp(s, symbols[i]))
            return i;
    return -1;
}

static int name_compare(const void *a, const void *b) {
    return strcmp(symbols[*(const int *)a], symbols[*(const int *)b]);
}

static int hill_order(const Int *atoms, int *order) {
    int n = 0;
    for (int i = 0; i < 54; ++i)
        if (atoms[i])
            order[n++] = i;
    qsort(order, (size_t)n, sizeof *order, name_compare);
    if (atoms[5]) {
        int sorted[54], k = 0;
        sorted[k++] = 5;
        if (atoms[0])
            sorted[k++] = 0;
        for (int i = 0; i < n; ++i)
            if (order[i] != 5 && order[i] != 0)
                sorted[k++] = order[i];
        memcpy(order, sorted, (size_t)n * sizeof *order);
    }
    return n;
}

static void decimal(Int n, int digits) {
    Int scale = 1;
    for (int i = 0; i < digits; ++i)
        scale *= 10;
    if (n < 0) {
        append("-");
        n = -n;
    }
    append("%lld.%0*lld", (long long)(n / scale), digits, (long long)(n % scale));
}

static void signed_number(Int n) {
    append(n > 0 ? "+%lld" : "%lld", (long long)n);
}

static void signed_rational(Rational x) {
    signed_number(x.n);
    if (x.d != 1)
        append("/%lld", (long long)x.d);
}

static void hill(Formula f, int include_charge) {
    int order[54], n = hill_order(f.atoms, order);
    for (int i = 0; i < n; ++i) {
        int e = order[i];
        append("%s", symbols[e]);
        if (f.atoms[e] > 1)
            append("%lld", (long long)f.atoms[e]);
    }
    if (include_charge && f.charge) {
        append("^");
        if (llabs(f.charge) > 1)
            append("%lld", (long long)llabs(f.charge));
        append(f.charge > 0 ? "+" : "-");
    }
}

typedef struct {
    const char *text;
    int pos, valid;
    char unknown[3];
} Parser;

static Int number(Parser *p) {
    if (!isdigit((unsigned char)p->text[p->pos]))
        return 1;
    if (p->text[p->pos] == '0')
        p->valid = 0;
    Int n = 0;
    while (isdigit((unsigned char)p->text[p->pos]))
        n = n * 10 + p->text[p->pos++] - '0';
    return n;
}

static void add_atoms(Formula *a, Formula b, Int factor) {
    for (int i = 0; i < 54; ++i) {
        Int value = b.atoms[i] * factor + a->atoms[i];
        a->atoms[i] = value > 1000000000 ? 1000000000 : value;
    }
}

static Formula sequence(Parser *p) {
    Formula result = {0};
    int count = 0;
    for (;;) {
        char c = p->text[p->pos];
        Formula item = {0};
        if (c >= 'A' && c <= 'Z') {
            char sym[3] = {c, 0, 0};
            ++p->pos;
            c = p->text[p->pos];
            if (c >= 'a' && c <= 'z')
                sym[1] = p->text[p->pos++];
            int e = element(sym);
            if (e >= 0)
                item.atoms[e] = 1;
            else if (!p->unknown[0])
                strcpy(p->unknown, sym);
        } else if (c == '(' || c == '[') {
            ++p->pos;
            item = sequence(p);
            if (p->text[p->pos] != (c == '(' ? ')' : ']')) {
                p->valid = 0;
                break;
            }
            ++p->pos;
        } else
            break;
        ++count;
        Int k = number(p);
        add_atoms(&result, item, k);
    }
    if (!count)
        p->valid = 0;
    return result;
}

static Formula read_formula(const char *text, const char *word) {
    Parser p = {text, 0, 1, {0}};
    Formula result = sequence(&p);
    while (text[p.pos] == '.') {
        ++p.pos;
        Int k = number(&p);
        Formula part = sequence(&p);
        add_atoms(&result, part, k);
    }
    if (text[p.pos] == '^') {
        ++p.pos;
        Int k = number(&p);
        if (text[p.pos] == '+' || text[p.pos] == '-') {
            result.charge = text[p.pos++] == '+' ? k : -k;
        } else
            p.valid = 0;
    }
    if (!p.valid || text[p.pos])
        fail("invalid formula %s", word);
    if (p.unknown[0])
        fail("unknown element %s", p.unknown);
    return result;
}

static Int molar_mass(Formula f) {
    Int m = 0;
    for (int i = 0; i < 54; ++i)
        m += f.atoms[i] * weights[i];
    return m;
}

static Species read_species(const char *word, int coefficients) {
    Species s = {0};
    char text[128];
    strcpy(text, word);
    const char *states[] = {"(s)", "(l)", "(g)", "(aq)"};
    size_t n = strlen(text);
    for (int i = 0; i < 4; ++i) {
        size_t k = strlen(states[i]);
        if (n >= k && !strcmp(text + n - k, states[i])) {
            strcpy(s.state, states[i]);
            text[n - k] = 0;
            break;
        }
    }
    char *core = text;
    s.coefficient = 1;
    if (coefficients && isdigit((unsigned char)*core)) {
        if (*core == '0')
            fail("invalid formula %s", word);
        s.coefficient = strtoll(core, &core, 10);
    }
    s.formula = read_formula(core, word);
    strcpy(s.core, core);
    snprintf(s.name, sizeof s.name, "%s%s", core, s.state);
    return s;
}

static Equation read_equation(char **args, int n, int coefficients) {
    Equation e = {0};
    int arrow = -1;
    if (n < 3 || !(n % 2))
        fail("malformed equation");
    for (int i = 0; i < n; ++i) {
        if (i % 2) {
            if (!strcmp(args[i], "->")) {
                if (arrow >= 0)
                    fail("malformed equation");
                arrow = i;
            } else if (strcmp(args[i], "+"))
                fail("malformed equation");
        } else if (!strcmp(args[i], "+") || !strcmp(args[i], "->"))
            fail("malformed equation");
    }
    if (arrow < 0)
        fail("malformed equation");
    e.reactants = (arrow + 1) / 2;
    for (int i = 0; i < n; i += 2) {
        e.species[e.count] = read_species(args[i], coefficients);
        e.signs[e.count] = i < arrow ? 1 : -1;
        ++e.count;
    }
    return e;
}

static Int scaled_value(const char *word, int whole_digits, int fraction_digits, int signed_value,
                        int positive) {
    const char *p = word;
    int negative = signed_value && *p == '-';
    if (negative)
        ++p;
    const char *start = p;
    Int value = 0;
    while (isdigit((unsigned char)*p)) {
        if (p - start < whole_digits)
            value = value * 10 + *p - '0';
        ++p;
    }
    int n = (int)(p - start), valid = n >= 1 && n <= whole_digits && (n == 1 || *start != '0');
    int f = 0;
    if (*p == '.') {
        ++p;
        start = p;
        while (isdigit((unsigned char)*p)) {
            if (f < fraction_digits)
                value = value * 10 + *p - '0';
            ++p;
            ++f;
        }
        if (p == start || f > fraction_digits)
            valid = 0;
    }
    if (*p)
        valid = 0;
    while (f++ < fraction_digits)
        value *= 10;
    if (!valid || (positive && !value))
        fail("invalid %s %s", signed_value ? "enthalpy" : "quantity", word);
    return negative ? -value : value;
}

static Int quantity(const char *word) {
    return scaled_value(word, 4, 3, 0, 1);
}

static int composition_matrix(Equation e, Int matrix[55][13], int *labels) {
    Formula union_formula = {0};
    for (int j = 0; j < e.count; ++j)
        for (int i = 0; i < 54; ++i)
            if (e.species[j].formula.atoms[i])
                union_formula.atoms[i] = 1;
    int m = hill_order(union_formula.atoms, labels);
    labels[m] = -1;
    for (int i = 0; i <= m; ++i)
        for (int j = 0; j < e.count; ++j)
            matrix[i][j] = e.signs[j] * (i == m ? e.species[j].formula.charge
                                                : e.species[j].formula.atoms[labels[i]]);
    return m + 1;
}

static int null_space(Int matrix[55][13], int m, int n, Int basis[13][13], int *rank) {
    Rational a[55][13];
    int pivots[13], free_columns[13], free_count = 0, r = 0;
    for (int i = 0; i < m; ++i)
        for (int j = 0; j < n; ++j)
            a[i][j] = rational(matrix[i][j], 1);
    for (int j = 0; j < n; ++j) {
        int p = r;
        while (p < m && !a[p][j].n)
            ++p;
        if (p == m) {
            free_columns[free_count++] = j;
            continue;
        }
        for (int k = 0; k < n; ++k) {
            Rational t = a[r][k];
            a[r][k] = a[p][k];
            a[p][k] = t;
        }
        Rational divisor = a[r][j];
        for (int k = 0; k < n; ++k)
            a[r][k] = divide(a[r][k], divisor);
        for (int i = 0; i < m; ++i)
            if (i != r) {
                Rational factor = a[i][j];
                for (int k = 0; k < n; ++k)
                    a[i][k] = subtract(a[i][k], multiply(factor, a[r][k]));
            }
        pivots[r++] = j;
    }
    for (int b = 0; b < free_count; ++b) {
        Rational values[13];
        for (int j = 0; j < n; ++j)
            values[j] = rational(j == free_columns[b], 1);
        for (int i = 0; i < r; ++i)
            values[pivots[i]] = rational(-a[i][free_columns[b]].n, a[i][free_columns[b]].d);
        Int multiple = 1, divisor = 0;
        for (int j = 0; j < n; ++j)
            multiple = multiple / gcd_int(multiple, values[j].d) * values[j].d;
        for (int j = 0; j < n; ++j) {
            basis[b][j] = values[j].n * (multiple / values[j].d);
            divisor = gcd_int(divisor, basis[b][j]);
        }
        for (int j = 0; j < n; ++j)
            basis[b][j] /= divisor;
    }
    *rank = r;
    return free_count;
}

static void coefficients(Equation e, int required, Int *values) {
    Int matrix[55][13], basis[13][13];
    int labels[55], rank;
    int m = composition_matrix(e, matrix, labels);
    int d = null_space(matrix, m, e.count, basis, &rank);
    if (d != 1) {
        if (d)
            append("AMBIGUOUS (nullity %d)\n", d);
        else
            append("IMPOSSIBLE\n");
        longjmp(command_end, 1);
    }
    Int sign = basis[0][0] < 0 ? -1 : 1;
    for (int i = 0; i < e.count; ++i)
        values[i] = basis[0][i] * sign;
    for (int i = 0; i < required; ++i)
        if (values[i] <= 0) {
            append("IMPOSSIBLE\n");
            longjmp(command_end, 1);
        }
}

static void term(Species s, Int count) {
    if (count != 1)
        append("%lld", (long long)count);
    append("%s", s.name);
}

static void equation_notation(Equation e, Int *values, int original) {
    for (int side = 1; side >= -1; side -= 2) {
        int count = 0;
        if (side == -1)
            append(" -> ");
        for (int i = 0; i < e.count; ++i) {
            Int c = i < original ? values[i] : llabs(values[i]);
            int s = i < original ? e.signs[i] : (values[i] > 0 ? 1 : -1);
            if (!c || s != side)
                continue;
            if (count++)
                append(" + ");
            term(e.species[i], c);
        }
    }
    append("\n");
}

static void ratio_report(Int *amounts) {
    int order[54], n = hill_order(amounts, order), f = order[0];
    for (int i = 1; i < n; ++i) {
        int e = order[i];
        if (amounts[e] * weights[f] < amounts[f] * weights[e])
            f = e;
    }
    for (int i = 0; i < n; ++i) {
        int e = order[i];
        append("%s ", symbols[e]);
        decimal(1000 * amounts[e] * weights[f] / (weights[e] * amounts[f]), 3);
        append("\n");
    }
    for (int k = 1; k <= 12; ++k) {
        Formula counts = {0};
        int valid = 1;
        for (int i = 0; i < n; ++i) {
            int e = order[i];
            Int a = k * amounts[e] * weights[f], b = weights[e] * amounts[f];
            counts.atoms[e] = (2 * a + b) / (2 * b);
            if (20 * llabs(a - counts.atoms[e] * b) > b)
                valid = 0;
        }
        if (valid) {
            hill(counts, 0);
            append(" (k = %d)\n", k);
            return;
        }
    }
    append("no simple ratio\n");
}

static int fixed_metal(int e) {
    if (e == 2 || e == 10 || e == 18 || e == 36)
        return 1;
    if (e == 3 || e == 11 || e == 19 || e == 37)
        return 2;
    return e == 12 ? 3 : 0;
}

static void oxidation(Formula f) {
    int order[54], n = hill_order(f.atoms, order), assigned[54] = {0}, last = -1;
    Rational values[54];
    for (int i = 0; i < 54; ++i)
        values[i] = rational(0, 1);
    if (n == 1) {
        assigned[order[0]] = 1;
        values[order[0]] = rational(f.charge, f.atoms[order[0]]);
    } else {
        int e = 8;
        if (f.atoms[e]) {
            assigned[e] = 1;
            values[e] = rational(-1, 1);
            last = e;
        }
        for (int i = 0; i < n; ++i) {
            e = order[i];
            int v = fixed_metal(e);
            if (v) {
                assigned[e] = 1;
                values[e] = rational(v, 1);
                last = e;
            }
        }
        if (f.atoms[0]) {
            int only_metals = 1;
            for (int i = 0; i < n; ++i)
                if (order[i] && !fixed_metal(order[i]))
                    only_metals = 0;
            assigned[0] = 1;
            values[0] = rational(only_metals ? -1 : 1, 1);
            last = 0;
        }
        if (f.atoms[7]) {
            assigned[7] = 1;
            values[7] = rational(-2, 1);
            last = 7;
        }
        if (!f.atoms[7] && !f.atoms[8]) {
            int halogens[] = {16, 34, 52};
            for (int i = 0; i < 3; ++i)
                if (f.atoms[halogens[i]]) {
                    e = halogens[i];
                    assigned[e] = 1;
                    values[e] = rational(-1, 1);
                    last = e;
                    break;
                }
        }
        int unknown = 0, missing = -1;
        Int sum = 0;
        for (int i = 0; i < n; ++i) {
            e = order[i];
            if (!assigned[e]) {
                ++unknown;
                missing = e;
            } else
                sum += f.atoms[e] * values[e].n;
        }
        if (unknown >= 2) {
            append("indeterminate:");
            for (int i = 0; i < n; ++i)
                if (!assigned[order[i]])
                    append(" %s", symbols[order[i]]);
            append("\n");
            return;
        }
        if (unknown == 1)
            values[missing] = rational(f.charge - sum, f.atoms[missing]);
        else if (sum != f.charge)
            values[last] = rational(f.charge - sum + f.atoms[last] * values[last].n, f.atoms[last]);
    }
    for (int i = 0; i < n; ++i) {
        if (i)
            append(", ");
        append("%s ", symbols[order[i]]);
        signed_rational(values[order[i]]);
    }
    append("\n");
}

static void ion_part(const char *formula, Int k) {
    char core[128];
    strcpy(core, formula);
    char *charge = strchr(core, '^');
    if (charge)
        *charge = 0;
    int single = core[0] >= 'A' && core[0] <= 'Z' &&
                 (core[1] == 0 || (core[1] >= 'a' && core[1] <= 'z' && core[2] == 0));
    int whole_bracket = 0;
    if (core[0] == '[') {
        int depth = 0;
        for (int i = 0; core[i]; ++i) {
            if (core[i] == '[')
                ++depth;
            if (core[i] == ']' && !--depth) {
                whole_bracket = core[i + 1] == 0;
                break;
            }
        }
    }
    if (k == 1)
        append("%s", core);
    else if (single || whole_bracket)
        append("%s%lld", core, (long long)k);
    else
        append("(%s)%lld", core, (long long)k);
}

static int heat_index(const char *name) {
    for (int i = 0; i < heat_count; ++i)
        if (!strcmp(heats[i].name, name))
            return i;
    return -1;
}

static int heat_compare(const void *a, const void *b) {
    return strcmp(heats[*(const int *)a].name, heats[*(const int *)b].name);
}

static int find_species(Equation e, const char *name, int start, int end) {
    for (int i = start; i < end; ++i)
        if (!strcmp(e.species[i].name, name))
            return i;
    return -1;
}

static void gas_volume(Species s, Int numerator, Int denominator) {
    if (!strcmp(s.state, "(g)")) {
        append(" ");
        decimal(numerator * 22414 / denominator, 3);
        append(" L");
    }
}

static void execute(char **words, int count) {
    const char *cmd = words[0];
    char **a = words + 1;
    int n = count - 1;
    const char *commands[] = {"ELEMENT", "PARSE",    "MASS",   "PERCENT",   "EMPIRICAL", "DBE",
                              "OXSTATE", "MOLES",    "GRAMS",  "MOLECULAR", "SALT",      "DERIVE",
                              "COMBUST", "BALANCE",  "MATRIX", "CHECK",     "REDOX",     "HALF",
                              "STOICH",  "LIMITING", "YIELD",  "HEAT",      "DELTAH",    "HEATS"};
    int id = -1;
    for (int i = 0; i < 24; ++i)
        if (!strcmp(cmd, commands[i]))
            id = i;
    if (id < 0)
        fail("unknown command %s", cmd);
    int valid = 1;
    if (id <= 6)
        valid = n == 1;
    else if (id <= 10 || id == 21)
        valid = n == 2;
    else if (id == 11)
        valid = n >= 2 && n % 2 == 0;
    else if (id == 12)
        valid = n == 3;
    else if ((id >= 13 && id <= 15) || id == 22)
        valid = n >= 1;
    else if (id == 16 || id == 17)
        valid = n >= 2;
    else if (id == 23)
        valid = n == 0;
    if (!valid)
        fail("wrong argument count for %s", cmd);
    if (id == 0) {
        int e = element(a[0]);
        if (e < 0)
            fail("unknown element %s", a[0]);
        append("%s (Z = %d) ", a[0], e + 1);
        decimal(weights[e], 3);
        append(" u\n");
    } else if (id >= 1 && id <= 10) {
        Formula f = read_formula(a[0], a[0]);
        Int mass = molar_mass(f);
        int order[54], m = hill_order(f.atoms, order);
        if (id == 1) {
            hill(f, 1);
            append(" (");
            for (int i = 0; i < m; ++i)
                append("%s%s %lld", i ? ", " : "", symbols[order[i]], (long long)f.atoms[order[i]]);
            append("; charge ");
            signed_number(f.charge);
            append(")\n");
        } else if (id == 2) {
            append("M(%s) = ", a[0]);
            decimal(mass, 3);
            append(" g/mol\n");
        } else if (id == 3) {
            for (int i = 0; i < m; ++i) {
                int e = order[i];
                append("%s ", symbols[e]);
                decimal(10000 * f.atoms[e] * weights[e] / mass, 2);
                append("%%\n");
            }
        } else if (id == 4) {
            Int g = 0;
            for (int i = 0; i < m; ++i)
                g = gcd_int(g, f.atoms[order[i]]);
            for (int i = 0; i < 54; ++i)
                f.atoms[i] /= g;
            hill(f, 0);
            append(" (n = %lld)\n", (long long)g);
        } else if (id == 5) {
            if (f.charge)
                fail("charged formula %s", a[0]);
            const char *groups[] = {"H F Cl Br I", "O S Se", "B N P As", "C Si Ge"};
            Int total = 2;
            for (int i = 0; i < m; ++i) {
                int e = order[i], valence = 0;
                for (int k = 0; k < 4; ++k) {
                    char group[64];
                    strcpy(group, groups[k]);
                    for (char *s = strtok(group, " "); s; s = strtok(NULL, " "))
                        if (!strcmp(s, symbols[e]))
                            valence = k + 1;
                }
                if (!valence)
                    fail("no valence for %s", symbols[e]);
                total += f.atoms[e] * (valence - 2);
            }
            append("DBE = %s%lld.%d\n", total < 0 ? "-" : "", (long long)(llabs(total) / 2),
                   total % 2 ? 5 : 0);
        } else if (id == 6)
            oxidation(f);
        else if (id == 10) {
            Formula g = read_formula(a[1], a[1]);
            if (f.charge <= 0)
                fail("not a cation %s", a[0]);
            if (g.charge >= 0)
                fail("not an anion %s", a[1]);
            if (strchr(a[0], '.'))
                fail("hydrate ion %s", a[0]);
            if (strchr(a[1], '.'))
                fail("hydrate ion %s", a[1]);
            Int divisor = gcd_int(f.charge, g.charge), x = -g.charge / divisor,
                y = f.charge / divisor;
            Formula salt = {0};
            add_atoms(&salt, f, x);
            add_atoms(&salt, g, y);
            ion_part(a[0], x);
            ion_part(a[1], y);
            append(" (");
            hill(salt, 0);
            append(", ");
            decimal(molar_mass(salt), 3);
            append(" g/mol)\n");
        } else {
            if (id == 9 && f.charge)
                fail("charged formula %s", a[0]);
            Int q = quantity(a[1]);
            if (id == 7 || id == 8) {
                decimal(q, 3);
                append(" %s %s = ", id == 7 ? "g" : "mol", a[0]);
                decimal(id == 7 ? q * 1000000 / mass : q * mass / 1000, id == 7 ? 6 : 3);
                append(" %s\n", id == 7 ? "mol" : "g");
            } else {
                Int k = (2 * q + mass) / (2 * mass);
                if (!k || 10 * llabs(q - k * mass) > mass) {
                    append("no integer multiple (ratio ");
                    decimal(1000 * q / mass, 3);
                    append(")\n");
                } else {
                    for (int i = 0; i < 54; ++i)
                        f.atoms[i] *= k;
                    hill(f, 0);
                    append(" (n = %lld, ", (long long)k);
                    decimal(k * mass, 3);
                    append(" g/mol)\n");
                }
            }
        }
    } else if (id == 11 || id == 12) {
        Int amounts[54] = {0};
        if (id == 11) {
            Int total = 0;
            for (int i = 0; i < n; i += 2) {
                int e = element(a[i]);
                if (e < 0)
                    fail("unknown element %s", a[i]);
                if (amounts[e])
                    fail("duplicate element %s", a[i]);
                Int q = quantity(a[i + 1]);
                if (q > 100000)
                    fail("invalid percentage %s", a[i + 1]);
                amounts[e] = q;
                total += q;
            }
            if (llabs(total - 100000) > 1000) {
                output_size = 0;
                append("error: percentages sum to ");
                decimal(total, 3);
                append("\n");
                longjmp(command_end, 1);
            }
        } else {
            Int sample = quantity(a[0]), carbon_dioxide = quantity(a[1]), water = quantity(a[2]);
            Int c = carbon_dioxide * 12011 / 44009, h = water * 2016 / 18015, o = sample - c - h;
            if (!c || !h || 100 * o < -sample)
                fail("inconsistent masses");
            amounts[5] = c;
            amounts[0] = h;
            if (100 * o > sample)
                amounts[7] = o;
            int elements[] = {5, 0, 7};
            for (int i = 0; i < 3; ++i)
                if (amounts[elements[i]]) {
                    append("mass %s ", symbols[elements[i]]);
                    decimal(amounts[elements[i]], 3);
                    append(" g\n");
                }
        }
        ratio_report(amounts);
    } else if (id == 21) {
        Species s = read_species(a[0], 0);
        Int h = scaled_value(a[1], 5, 2, 1, 0);
        int i = heat_index(s.name);
        append("dHf(%s) = ", s.name);
        decimal(h, 2);
        append(" kJ/mol");
        if (i >= 0) {
            append(" (was ");
            decimal(heats[i].value, 2);
            append(")");
        }
        append("\n");
        if (i < 0) {
            i = heat_count++;
            strcpy(heats[i].name, s.name);
        }
        heats[i].value = h;
    } else if (id == 23) {
        int order[500];
        for (int i = 0; i < heat_count; ++i)
            order[i] = i;
        qsort(order, (size_t)heat_count, sizeof *order, heat_compare);
        if (!heat_count)
            append("no enthalpies\n");
        for (int j = 0; j < heat_count; ++j) {
            int i = order[j];
            append("%s ", heats[i].name);
            decimal(heats[i].value, 2);
            append(" kJ/mol\n");
        }
    } else {
        int separator = -1, tail_count = 0;
        char **tail = NULL;
        if (id >= 18 && id <= 20) {
            for (int i = 0; i < n; ++i)
                if (!strcmp(a[i], ":")) {
                    if (separator >= 0)
                        fail("invalid separator");
                    separator = i;
                }
            if (separator < 0)
                fail("invalid separator");
            tail = a + separator + 1;
            tail_count = n - separator - 1;
            n = separator;
            if ((id == 18 && tail_count != 2) || (id == 20 && tail_count != 4))
                fail("wrong argument count for %s", cmd);
        }
        int redox = id == 16 || id == 17;
        if (redox) {
            if (strcmp(a[0], "acidic") && strcmp(a[0], "basic"))
                fail("invalid medium %s", a[0]);
            ++a;
            --n;
        }
        Equation e = read_equation(a, n, id == 15);
        Int values[13];
        if (id == 14 || id == 15) {
            Int matrix[55][13], basis[13][13];
            int labels[55], rank;
            int m = composition_matrix(e, matrix, labels);
            if (id == 14) {
                append("columns:");
                for (int j = 0; j < e.count; ++j)
                    append(" %s", e.species[j].name);
                append("\n");
                for (int i = 0; i < m; ++i) {
                    append("%s:", labels[i] < 0 ? "charge" : symbols[labels[i]]);
                    for (int j = 0; j < e.count; ++j)
                        append(" %lld", (long long)matrix[i][j]);
                    append("\n");
                }
                int d = null_space(matrix, m, e.count, basis, &rank);
                append("rank %d, nullity %d\n", rank, d);
                for (int b = 0; b < d; ++b) {
                    append("null:");
                    for (int j = 0; j < e.count; ++j)
                        append(" %lld", (long long)basis[b][j]);
                    append("\n");
                }
            } else {
                int different = 0;
                for (int i = 0; i < m; ++i) {
                    Int left = 0, right = 0;
                    for (int j = 0; j < e.count; ++j) {
                        Int amount = matrix[i][j] * e.species[j].coefficient;
                        if (j < e.reactants)
                            left += amount;
                        else
                            right -= amount;
                    }
                    if (left == right)
                        continue;
                    if (!different++)
                        append("not balanced\n");
                    append("%s: ", labels[i] < 0 ? "charge" : symbols[labels[i]]);
                    if (labels[i] < 0)
                        signed_number(left);
                    else
                        append("%lld", (long long)left);
                    append(" != ");
                    if (labels[i] < 0)
                        signed_number(right);
                    else
                        append("%lld", (long long)right);
                    append("\n");
                }
                if (!different) {
                    Int g = 0;
                    for (int j = 0; j < e.count; ++j)
                        g = gcd_int(g, e.species[j].coefficient);
                    append("balanced");
                    if (g > 1)
                        append(", not in lowest terms (gcd %lld)", (long long)g);
                    append("\n");
                }
            }
            return;
        }
        int original = e.count, first = -1, second = -1;
        Int q[13] = {0};
        if (redox) {
            for (int i = 0; i < original; ++i)
                if (!strcmp(e.species[i].core, "H^+") || !strcmp(e.species[i].core, "OH^-") ||
                    !strcmp(e.species[i].core, "H2O"))
                    fail("reserved species %s", e.species[i].name);
            e.species[e.count] = read_species(!strcmp(a[-1], "acidic") ? "H^+" : "OH^-", 0);
            e.signs[e.count++] = 1;
            e.species[e.count] = read_species("H2O", 0);
            e.signs[e.count++] = 1;
            if (id == 17) {
                Species electron = {0};
                strcpy(electron.name, "e^-");
                electron.formula.charge = -1;
                e.species[e.count] = electron;
                e.signs[e.count++] = 1;
            }
        } else if (id == 18) {
            first = find_species(e, tail[0], 0, e.count);
            if (first < 0)
                fail("species %s not in equation", tail[0]);
            q[0] = quantity(tail[1]);
        } else if (id == 19) {
            if (tail_count != e.reactants)
                fail("expected %d masses, got %d", e.reactants, tail_count);
            for (int i = 0; i < tail_count; ++i)
                q[i] = quantity(tail[i]);
        } else if (id == 20) {
            first = find_species(e, tail[0], 0, e.reactants);
            if (first < 0)
                fail("%s is not a reactant", tail[0]);
            second = find_species(e, tail[2], e.reactants, e.count);
            if (second < 0)
                fail("%s is not a product", tail[2]);
            q[0] = quantity(tail[1]);
            q[1] = quantity(tail[3]);
        } else if (id == 22) {
            for (int i = 0; i < e.count; ++i)
                if (heat_index(e.species[i].name) < 0)
                    fail("no enthalpy for %s", e.species[i].name);
        }
        coefficients(e, original, values);
        equation_notation(e, values, original);
        if (id == 17)
            append(values[e.count - 1] > 0   ? "reduction\n"
                   : values[e.count - 1] < 0 ? "oxidation\n"
                                             : "no electron transfer\n");
        if (id == 18) {
            Int d = values[first] * molar_mass(e.species[first].formula);
            for (int i = 0; i < e.count; ++i) {
                Int amount = q[0] * values[i];
                append("%s ", e.species[i].name);
                decimal(amount * 1000000 / d, 6);
                append(" mol ");
                decimal(amount * molar_mass(e.species[i].formula) / d, 3);
                append(" g");
                gas_volume(e.species[i], amount, d);
                append("\n");
            }
        } else if (id == 19) {
            int limiting = 0;
            for (int i = 1; i < e.reactants; ++i)
                if (q[i] * values[limiting] * molar_mass(e.species[limiting].formula) <
                    q[limiting] * values[i] * molar_mass(e.species[i].formula))
                    limiting = i;
            Int d = values[limiting] * molar_mass(e.species[limiting].formula),
                amount = q[limiting];
            append("limiting %s\nextent ", e.species[limiting].name);
            decimal(amount * 1000000 / d, 6);
            append(" mol\n");
            for (int i = e.reactants; i < e.count; ++i) {
                append("product %s ", e.species[i].name);
                decimal(amount * values[i] * molar_mass(e.species[i].formula) / d, 3);
                append(" g");
                gas_volume(e.species[i], amount * values[i], d);
                append("\n");
            }
            for (int i = 0; i < e.reactants; ++i)
                if (i != limiting) {
                    append("remaining %s ", e.species[i].name);
                    decimal((q[i] * d - amount * values[i] * molar_mass(e.species[i].formula)) / d,
                            3);
                    append(" g\n");
                }
        } else if (id == 20) {
            Int theoretical = q[0] * values[second] * molar_mass(e.species[second].formula) /
                              (values[first] * molar_mass(e.species[first].formula));
            append("theoretical ");
            decimal(theoretical, 3);
            append(" g\nactual ");
            decimal(q[1], 3);
            append(" g\nyield ");
            if (!theoretical)
                append("undefined\n");
            else {
                decimal(q[1] * 10000 / theoretical, 2);
                append("%%\n");
            }
        } else if (id == 22) {
            Int dh = 0;
            for (int i = 0; i < e.count; ++i)
                dh -= e.signs[i] * values[i] * heats[heat_index(e.species[i].name)].value;
            append("dH = ");
            decimal(dh, 2);
            append(" kJ (%s)\n", dh < 0 ? "exothermic" : dh > 0 ? "endothermic" : "thermoneutral");
        }
    }
}

int main(void) {
    char line[128];
    if (!fgets(line, sizeof line, stdin))
        return 0;
    int commands = atoi(line);
    for (int i = 0; i < commands && fgets(line, sizeof line, stdin); ++i) {
        char *words[64];
        int count = 0;
        for (char *word = strtok(line, " \r\n"); word; word = strtok(NULL, " \r\n"))
            words[count++] = word;
        output_size = 0;
        if (!setjmp(command_end))
            execute(words, count);
        fputs(output, stdout);
    }
    return 0;
}
