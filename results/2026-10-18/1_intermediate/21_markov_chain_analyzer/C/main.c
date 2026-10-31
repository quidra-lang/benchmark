#include <ctype.h>
#include <inttypes.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

enum { MAX_STATES = 10, MAX_CHAINS = 500 };

typedef struct { int64_t numerator, denominator; } Fraction;
typedef struct { char text[64]; } Text;
typedef struct { Fraction value[MAX_STATES]; } Vector;
typedef struct {
    int rows, columns;
    Fraction value[MAX_STATES][2 * MAX_STATES];
} Matrix;
typedef struct {
    char name[9];
    int size;
    char states[MAX_STATES][18];
    Matrix transition;
} Chain;
typedef struct { Chain *chains[MAX_CHAINS]; int count; } Store;
typedef struct { unsigned states; bool closed; int period; } Class;
typedef struct {
    bool reachable[MAX_STATES][MAX_STATES];
    int class_of[MAX_STATES], level[MAX_STATES], count;
    Class classes[MAX_STATES];
} Graph;
typedef struct { Vector probability, time; bool finite[MAX_STATES]; } Hitting;
typedef struct {
    int transient[MAX_STATES], absorbing[MAX_STATES], t, a;
    Matrix fundamental, probability;
    Vector mean, variance;
} Absorption;

static const Fraction ZERO = {0, 1};
static const Fraction ONE = {1, 1};

static int64_t gcd(int64_t a, int64_t b) {
    if (a < 0) a = -a;
    if (b < 0) b = -b;
    while (b) {
        int64_t remainder = a % b;
        a = b;
        b = remainder;
    }
    return a;
}

static Fraction fraction(int64_t numerator, int64_t denominator) {
    if (!numerator) return ZERO;
    if (denominator < 0) {
        numerator = -numerator;
        denominator = -denominator;
    }
    int64_t divisor = gcd(numerator, denominator);
    return (Fraction){numerator / divisor, denominator / divisor};
}

static Fraction add(Fraction a, Fraction b) {
    return fraction(a.numerator * b.denominator + b.numerator * a.denominator,
                    a.denominator * b.denominator);
}

static Fraction subtract(Fraction a, Fraction b) {
    return fraction(a.numerator * b.denominator - b.numerator * a.denominator,
                    a.denominator * b.denominator);
}

static Fraction multiply(Fraction a, Fraction b) {
    return fraction(a.numerator * b.numerator, a.denominator * b.denominator);
}

static Fraction divide(Fraction a, Fraction b) {
    return fraction(a.numerator * b.denominator, a.denominator * b.numerator);
}

static bool equal(Fraction a, Fraction b) {
    return a.numerator == b.numerator && a.denominator == b.denominator;
}

static bool greater(Fraction a, Fraction b) {
    return a.numerator * b.denominator > b.numerator * a.denominator;
}

static Text fraction_text(Fraction value) {
    Text result;
    snprintf(result.text, sizeof result.text, "%" PRId64 "/%" PRId64,
             value.numerator, value.denominator);
    return result;
}

static Text value_text(Fraction value) {
    Text result;
    int64_t whole = value.numerator / value.denominator;
    int64_t decimal = (value.numerator % value.denominator) * 1000000 / value.denominator;
    snprintf(result.text, sizeof result.text, "%" PRId64 "/%" PRId64 "(%" PRId64 ".%06" PRId64 ")",
             value.numerator, value.denominator, whole, decimal);
    return result;
}

static void error(const char *format, ...) {
    va_list arguments;
    va_start(arguments, format);
    fputs("ERROR ", stdout);
    vprintf(format, arguments);
    putchar('\n');
    va_end(arguments);
}

static bool probability(const char *text, Fraction *result) {
    const char *slash = strchr(text, '/');
    int64_t numerator = strtoll(text, NULL, 10);
    int64_t denominator = slash ? strtoll(slash + 1, NULL, 10) : 1;
    if (!denominator || numerator > denominator) {
        error("BAD PROBABILITY");
        return false;
    }
    *result = fraction(numerator, denominator);
    return true;
}

static Vector zero_vector(void) {
    Vector result;
    for (int i = 0; i < MAX_STATES; ++i) result.value[i] = ZERO;
    return result;
}

static Matrix zero_matrix(int rows, int columns) {
    Matrix result = {.rows = rows, .columns = columns};
    for (int i = 0; i < rows; ++i)
        for (int j = 0; j < columns; ++j) result.value[i][j] = ZERO;
    return result;
}

static Matrix identity(int size) {
    Matrix result = zero_matrix(size, size);
    for (int i = 0; i < size; ++i) result.value[i][i] = ONE;
    return result;
}

static Matrix matrix_product(const Matrix *left, const Matrix *right) {
    Matrix result = zero_matrix(left->rows, right->columns);
    for (int i = 0; i < result.rows; ++i)
        for (int j = 0; j < result.columns; ++j)
            for (int k = 0; k < left->columns; ++k)
                result.value[i][j] = add(result.value[i][j], multiply(left->value[i][k], right->value[k][j]));
    return result;
}

static void eliminate(Matrix *matrix) {
    for (int column = 0; column < matrix->rows; ++column) {
        int pivot_row = column;
        while (!matrix->value[pivot_row][column].numerator) ++pivot_row;
        for (int j = 0; j < matrix->columns; ++j) {
            Fraction temporary = matrix->value[column][j];
            matrix->value[column][j] = matrix->value[pivot_row][j];
            matrix->value[pivot_row][j] = temporary;
        }
        Fraction pivot = matrix->value[column][column];
        for (int j = 0; j < matrix->columns; ++j)
            matrix->value[column][j] = divide(matrix->value[column][j], pivot);
        for (int row = 0; row < matrix->rows; ++row) {
            if (row == column) continue;
            Fraction factor = matrix->value[row][column];
            if (!factor.numerator) continue;
            for (int j = 0; j < matrix->columns; ++j)
                matrix->value[row][j] = subtract(matrix->value[row][j], multiply(factor, matrix->value[column][j]));
        }
    }
}

static Chain new_chain(const char *name, int size) {
    Chain result = {.size = size};
    strcpy(result.name, name);
    result.transition = zero_matrix(size, size);
    return result;
}

static Chain *find_chain(const Store *store, const char *name) {
    for (int i = 0; i < store->count; ++i)
        if (!strcmp(store->chains[i]->name, name)) return store->chains[i];
    return NULL;
}

static void save_chain(Store *store, const Chain *chain) {
    Chain *destination = find_chain(store, chain->name);
    if (!destination) {
        destination = malloc(sizeof *destination);
        if (!destination) exit(EXIT_FAILURE);
        store->chains[store->count++] = destination;
    }
    *destination = *chain;
}

static int state_index(const Chain *chain, const char *name) {
    for (int i = 0; i < chain->size; ++i)
        if (!strcmp(chain->states[i], name)) return i;
    return -1;
}

static int require_state(const Chain *chain, const char *name) {
    int index = state_index(chain, name);
    if (index < 0) error("UNKNOWN STATE %s", name);
    return index;
}

static Fraction row_sum(const Chain *chain, int row, unsigned selected) {
    Fraction result = ZERO;
    for (int j = 0; j < chain->size; ++j)
        if (selected & (1u << j)) result = add(result, chain->transition.value[row][j]);
    return result;
}

static int members(unsigned selected, int size, int *indices) {
    int count = 0;
    for (int i = 0; i < size; ++i)
        if (selected & (1u << i)) indices[count++] = i;
    return count;
}

static void display_matrix(const Chain *chain, const Matrix *matrix, const char *label) {
    fputs("STATES", stdout);
    for (int i = 0; i < chain->size; ++i) printf(" %s", chain->states[i]);
    putchar('\n');
    for (int i = 0; i < matrix->rows; ++i) {
        printf("%s %s", label, chain->states[i]);
        for (int j = 0; j < matrix->columns; ++j) printf(" %s", fraction_text(matrix->value[i][j]).text);
        putchar('\n');
    }
}

static Graph analyze(const Chain *chain) {
    Graph graph = {0};
    int size = chain->size;
    for (int i = 0; i < size; ++i) {
        graph.class_of[i] = -1;
        graph.level[i] = -1;
        for (int j = 0; j < size; ++j)
            graph.reachable[i][j] = i == j || chain->transition.value[i][j].numerator > 0;
    }
    for (int k = 0; k < size; ++k)
        for (int i = 0; i < size; ++i)
            for (int j = 0; j < size; ++j)
                graph.reachable[i][j] |= graph.reachable[i][k] && graph.reachable[k][j];
    for (int root = 0; root < size; ++root) {
        if (graph.class_of[root] >= 0) continue;
        Class *group = &graph.classes[graph.count];
        group->closed = true;
        for (int i = 0; i < size; ++i) {
            if (graph.reachable[root][i] && graph.reachable[i][root]) {
                group->states |= 1u << i;
                graph.class_of[i] = graph.count;
            }
        }
        int queue[MAX_STATES], head = 0, tail = 0;
        queue[tail++] = root;
        graph.level[root] = 0;
        while (head < tail) {
            int current = queue[head++];
            for (int next = 0; next < size; ++next) {
                if (!chain->transition.value[current][next].numerator) continue;
                if (!(group->states & (1u << next))) {
                    group->closed = false;
                } else if (graph.level[next] < 0) {
                    graph.level[next] = graph.level[current] + 1;
                    queue[tail++] = next;
                }
            }
        }
        for (int i = 0; i < size; ++i)
            for (int j = 0; j < size; ++j)
                if ((group->states & (1u << i)) && (group->states & (1u << j)) && chain->transition.value[i][j].numerator)
                    group->period = (int)gcd(group->period, graph.level[i] + 1 - graph.level[j]);
        ++graph.count;
    }
    return graph;
}

static unsigned absorbing_states(const Chain *chain) {
    unsigned result = 0;
    for (int i = 0; i < chain->size; ++i)
        if (equal(chain->transition.value[i][i], ONE)) result |= 1u << i;
    return result;
}

static bool reaches(const Graph *graph, int source, unsigned target, int size) {
    for (int j = 0; j < size; ++j)
        if ((target & (1u << j)) && graph->reachable[source][j]) return true;
    return false;
}

static Vector stationary(const Chain *chain, unsigned selected) {
    int states[MAX_STATES];
    int count = members(selected, chain->size, states);
    Matrix equations = zero_matrix(count, count + 1);
    for (int i = 0; i < count - 1; ++i)
        for (int j = 0; j < count; ++j)
            equations.value[i][j] = subtract(chain->transition.value[states[j]][states[i]], i == j ? ONE : ZERO);
    for (int j = 0; j <= count; ++j) equations.value[count - 1][j] = ONE;
    eliminate(&equations);
    Vector result = zero_vector();
    for (int i = 0; i < count; ++i) result.value[states[i]] = equations.value[i][count];
    return result;
}

static Hitting hitting(const Chain *chain, const Graph *graph, unsigned target, bool with_times) {
    Hitting result = {.probability = zero_vector(), .time = zero_vector()};
    int unknown[MAX_STATES], count = 0;
    for (int i = 0; i < chain->size; ++i) {
        if (target & (1u << i)) result.probability.value[i] = ONE;
        else if (reaches(graph, i, target, chain->size)) unknown[count++] = i;
    }
    if (count) {
        Matrix equations = zero_matrix(count, count + 1);
        for (int i = 0; i < count; ++i) {
            for (int j = 0; j < count; ++j)
                equations.value[i][j] = subtract(i == j ? ONE : ZERO, chain->transition.value[unknown[i]][unknown[j]]);
            equations.value[i][count] = row_sum(chain, unknown[i], target);
        }
        eliminate(&equations);
        for (int i = 0; i < count; ++i) result.probability.value[unknown[i]] = equations.value[i][count];
    }
    count = 0;
    for (int i = 0; i < chain->size; ++i) {
        result.finite[i] = equal(result.probability.value[i], ONE);
        if (result.finite[i] && !(target & (1u << i))) unknown[count++] = i;
    }
    if (with_times && count) {
        Matrix equations = zero_matrix(count, count + 1);
        for (int i = 0; i < count; ++i) {
            for (int j = 0; j < count; ++j)
                equations.value[i][j] = subtract(i == j ? ONE : ZERO, chain->transition.value[unknown[i]][unknown[j]]);
            equations.value[i][count] = ONE;
        }
        eliminate(&equations);
        for (int i = 0; i < count; ++i) result.time.value[unknown[i]] = equations.value[i][count];
    }
    return result;
}

static Absorption absorption(const Chain *chain) {
    Absorption result = {.mean = zero_vector(), .variance = zero_vector()};
    for (int i = 0; i < chain->size; ++i) {
        if (equal(chain->transition.value[i][i], ONE)) result.absorbing[result.a++] = i;
        else result.transient[result.t++] = i;
    }
    Matrix equations = zero_matrix(result.t, 2 * result.t);
    for (int i = 0; i < result.t; ++i) {
        for (int j = 0; j < result.t; ++j)
            equations.value[i][j] = subtract(i == j ? ONE : ZERO, chain->transition.value[result.transient[i]][result.transient[j]]);
        equations.value[i][result.t + i] = ONE;
    }
    eliminate(&equations);
    result.fundamental = zero_matrix(result.t, result.t);
    result.probability = zero_matrix(result.t, result.a);
    for (int i = 0; i < result.t; ++i)
        for (int j = 0; j < result.t; ++j) {
            result.fundamental.value[i][j] = equations.value[i][result.t + j];
            result.mean.value[i] = add(result.mean.value[i], result.fundamental.value[i][j]);
        }
    for (int i = 0; i < result.t; ++i) {
        Fraction second = ZERO;
        for (int j = 0; j < result.t; ++j) {
            Fraction coefficient = subtract(multiply(fraction(2, 1), result.fundamental.value[i][j]), i == j ? ONE : ZERO);
            second = add(second, multiply(coefficient, result.mean.value[j]));
        }
        result.variance.value[i] = subtract(second, multiply(result.mean.value[i], result.mean.value[i]));
        for (int j = 0; j < result.a; ++j)
            for (int k = 0; k < result.t; ++k)
                result.probability.value[i][j] = add(result.probability.value[i][j], multiply(result.fundamental.value[i][k], chain->transition.value[result.transient[k]][result.absorbing[j]]));
    }
    return result;
}

static bool target_set(const Chain *chain, char **names, int count, unsigned *selected) {
    *selected = 0;
    for (int i = 0; i < count; ++i) {
        int index = require_state(chain, names[i]);
        if (index < 0) return false;
        if (*selected & (1u << index)) {
            error("DUPLICATE STATE %s", names[i]);
            return false;
        }
        *selected |= 1u << index;
    }
    return true;
}

static int split(char *text, const char *separators, char **parts) {
    int count = 0;
    for (char *part = strtok(text, separators); part; part = strtok(NULL, separators)) parts[count++] = part;
    return count;
}

static void create_chain(Store *store, char **words, int count) {
    int size = count - 2;
    if (size > MAX_STATES) { error("TOO MANY STATES"); return; }
    Chain chain = new_chain(words[1], size);
    for (int i = 0; i < size; ++i) {
        for (int j = 0; j < i; ++j)
            if (!strcmp(words[i + 2], chain.states[j])) { error("DUPLICATE STATE %s", words[i + 2]); return; }
        strcpy(chain.states[i], words[i + 2]);
    }
    save_chain(store, &chain);
    printf("CHAIN %s states=%d\n", chain.name, size);
}

static void build_chain(Store *store, char **words, int count) {
    int order = atoi(words[2]), tokens = count - 3;
    if (order != 1 && order != 2) { error("BAD ORDER"); return; }
    if (tokens <= order) { error("TOO FEW TOKENS"); return; }
    Chain chain = new_chain(words[1], 0);
    int observations[60], length = tokens - order + 1;
    for (int i = 0; i < length; ++i) {
        char name[18];
        if (order == 1) strcpy(name, words[i + 3]);
        else snprintf(name, sizeof name, "%s.%s", words[i + 3], words[i + 4]);
        int index = state_index(&chain, name);
        if (index < 0) {
            if (chain.size == MAX_STATES) { error("TOO MANY STATES"); return; }
            index = chain.size++;
            strcpy(chain.states[index], name);
        }
        observations[i] = index;
    }
    int transitions[MAX_STATES][MAX_STATES] = {0}, totals[MAX_STATES] = {0};
    for (int i = 1; i < length; ++i) {
        ++transitions[observations[i - 1]][observations[i]];
        ++totals[observations[i - 1]];
    }
    chain.transition = zero_matrix(chain.size, chain.size);
    for (int i = 0; i < chain.size; ++i) {
        if (!totals[i]) chain.transition.value[i][i] = ONE;
        else for (int j = 0; j < chain.size; ++j) chain.transition.value[i][j] = fraction(transitions[i][j], totals[i]);
    }
    save_chain(store, &chain);
    printf("BUILD %s order=%d states=%d transitions=%d\n", chain.name, order, chain.size, length - 1);
    for (int i = 0; i < chain.size; ++i) {
        printf("FROM %s total=%d", chain.states[i], totals[i]);
        if (!totals[i]) fputs(" absorbing", stdout);
        else for (int j = 0; j < chain.size; ++j)
            if (transitions[i][j]) printf(" %s:%d", chain.states[j], transitions[i][j]);
        putchar('\n');
    }
}

static void gambler(Store *store, char **words) {
    int goal = atoi(words[2]), start = atoi(words[3]);
    if (!goal || goal > 9) { error("BAD SIZE"); return; }
    if (start > goal) { error("BAD START"); return; }
    Fraction chance;
    if (!probability(words[4], &chance)) return;
    if (equal(chance, ZERO) || equal(chance, ONE)) { error("BAD PROBABILITY"); return; }
    Chain chain = new_chain(words[1], goal + 1);
    for (int i = 0; i <= goal; ++i) snprintf(chain.states[i], sizeof chain.states[i], "s%d", i);
    chain.transition.value[0][0] = chain.transition.value[goal][goal] = ONE;
    for (int i = 1; i < goal; ++i) {
        chain.transition.value[i][i + 1] = chance;
        chain.transition.value[i][i - 1] = subtract(ONE, chance);
    }
    Absorption result = absorption(&chain);
    Vector ruin = zero_vector(), duration = zero_vector();
    ruin.value[0] = ONE;
    for (int i = 0; i < result.t; ++i) {
        ruin.value[result.transient[i]] = result.probability.value[i][0];
        duration.value[result.transient[i]] = result.mean.value[i];
    }
    save_chain(store, &chain);
    printf("GAMBLER %s g=%d p=%s start=s%d ruin=%s duration=%s\n", chain.name, goal,
           fraction_text(chance).text, start, value_text(ruin.value[start]).text, value_text(duration.value[start]).text);
    for (int i = 0; i <= goal; ++i)
        printf("CAPITAL s%d ruin=%s win=%s duration=%s\n", i, value_text(ruin.value[i]).text,
               value_text(subtract(ONE, ruin.value[i])).text, value_text(duration.value[i]).text);
}

static void classify(const Chain *chain, const Graph *graph) {
    unsigned targets = absorbing_states(chain);
    int absorbing_count = 0;
    bool absorbing = targets != 0;
    bool edges[MAX_STATES][MAX_STATES] = {0}, current[MAX_STATES][MAX_STATES] = {0};
    for (int i = 0; i < chain->size; ++i) {
        if (targets & (1u << i)) ++absorbing_count;
        absorbing &= reaches(graph, i, targets, chain->size);
        for (int j = 0; j < chain->size; ++j)
            edges[i][j] = current[i][j] = chain->transition.value[i][j].numerator > 0;
    }
    int exponent = 0, bound = (chain->size - 1) * (chain->size - 1) + 1;
    for (int step = 1; step <= bound; ++step) {
        bool positive = true;
        for (int i = 0; i < chain->size; ++i)
            for (int j = 0; j < chain->size; ++j) positive &= current[i][j];
        if (positive) { exponent = step; break; }
        bool next[MAX_STATES][MAX_STATES] = {0};
        for (int i = 0; i < chain->size; ++i)
            for (int j = 0; j < chain->size; ++j)
                for (int k = 0; k < chain->size; ++k) next[i][j] |= current[i][k] && edges[k][j];
        memcpy(current, next, sizeof current);
    }
    printf("CLASSIFY %s absorbing_states=%d absorbing=%s ergodic=%s regular=%s exponent=",
           chain->name, absorbing_count, absorbing ? "yes" : "no", graph->count == 1 ? "yes" : "no", exponent ? "yes" : "no");
    if (exponent) printf("%d\n", exponent); else puts("-");
}

static void show_absorption(const Chain *chain, const Graph *graph) {
    unsigned targets = absorbing_states(chain);
    if (!targets) { error("NO ABSORBING STATE"); return; }
    for (int i = 0; i < chain->size; ++i)
        if (!reaches(graph, i, targets, chain->size)) { error("NOT ABSORBING %s", chain->states[i]); return; }
    Absorption result = absorption(chain);
    printf("ABSORB %s transient=%d absorbing=%d\n", chain->name, result.t, result.a);
    if (!result.t) return;
    fputs("TRANSIENT", stdout);
    for (int i = 0; i < result.t; ++i) printf(" %s", chain->states[result.transient[i]]);
    fputs("\nABSORBING", stdout);
    for (int i = 0; i < result.a; ++i) printf(" %s", chain->states[result.absorbing[i]]);
    putchar('\n');
    for (int i = 0; i < result.t; ++i) {
        printf("N %s", chain->states[result.transient[i]]);
        for (int j = 0; j < result.t; ++j) printf(" %s", fraction_text(result.fundamental.value[i][j]).text);
        putchar('\n');
    }
    for (int i = 0; i < result.t; ++i)
        printf("STEPS %s mean=%s var=%s\n", chain->states[result.transient[i]], value_text(result.mean.value[i]).text, value_text(result.variance.value[i]).text);
    for (int i = 0; i < result.t; ++i) {
        printf("B %s", chain->states[result.transient[i]]);
        for (int j = 0; j < result.a; ++j) printf(" %s", fraction_text(result.probability.value[i][j]).text);
        putchar('\n');
    }
}

static void lump(Store *store, const Chain *chain, const char *destination, char *partition) {
    char *groups[12];
    int count = split(partition, "|", groups);
    unsigned blocks[12] = {0}, seen = 0;
    int representatives[12];
    for (int block = 0; block < count; ++block) {
        char *names[12];
        int length = split(groups[block], ",", names);
        for (int j = 0; j < length; ++j) {
            int index = require_state(chain, names[j]);
            if (index < 0) return;
            if (seen & (1u << index)) { error("BAD PARTITION"); return; }
            seen |= 1u << index;
            blocks[block] |= 1u << index;
        }
    }
    if (seen != (1u << chain->size) - 1) { error("BAD PARTITION"); return; }
    for (int i = 0; i < count; ++i) {
        representatives[i] = 0;
        while (!(blocks[i] & (1u << representatives[i]))) ++representatives[i];
    }
    for (int i = 1; i < count; ++i) {
        int representative = representatives[i], position = i;
        unsigned block = blocks[i];
        while (position > 0 && representatives[position - 1] > representative) {
            representatives[position] = representatives[position - 1];
            blocks[position] = blocks[position - 1];
            --position;
        }
        representatives[position] = representative;
        blocks[position] = block;
    }
    Chain result = new_chain(destination, count);
    for (int i = 0; i < count; ++i) {
        strcpy(result.states[i], chain->states[representatives[i]]);
        for (int j = 0; j < count; ++j) {
            Fraction expected = row_sum(chain, representatives[i], blocks[j]);
            result.transition.value[i][j] = expected;
            for (int state = 0; state < chain->size; ++state) {
                if (!(blocks[i] & (1u << state))) continue;
                Fraction actual = row_sum(chain, state, blocks[j]);
                if (!equal(expected, actual)) {
                    printf("LUMP %s not lumpable block=%s target=%s %s=%s %s=%s\n", chain->name,
                           chain->states[representatives[i]], chain->states[representatives[j]],
                           chain->states[representatives[i]], value_text(expected).text, chain->states[state], value_text(actual).text);
                    return;
                }
            }
        }
    }
    save_chain(store, &result);
    printf("LUMP %s %s blocks=%d\n", chain->name, destination, count);
    display_matrix(&result, &result.transition, "ROW");
}

static void command(Store *store, char **words, int count) {
    const char *verb = words[0];
    if (!strcmp(verb, "CHAIN")) { create_chain(store, words, count); return; }
    if (!strcmp(verb, "BUILD")) { build_chain(store, words, count); return; }
    if (!strcmp(verb, "GAMBLER")) { gambler(store, words); return; }
    Chain *stored = find_chain(store, words[1]);
    if (!stored) { error("UNKNOWN CHAIN %s", words[1]); return; }
    Chain chain = *stored;
    int size = chain.size;
    unsigned all = (1u << size) - 1;
    if (!strcmp(verb, "P") || !strcmp(verb, "ROW")) {
        int row = require_state(&chain, words[2]);
        if (row < 0) return;
        if (!strcmp(verb, "P")) {
            int column = require_state(&chain, words[3]);
            if (column < 0 || !probability(words[4], &chain.transition.value[row][column])) return;
            printf("P %s %s %s %s rowsum=%s\n", chain.name, words[2], words[3], fraction_text(chain.transition.value[row][column]).text, fraction_text(row_sum(&chain, row, all)).text);
        } else {
            if (count - 3 != size) { error("BAD LENGTH"); return; }
            for (int j = 0; j < size; ++j)
                if (!probability(words[j + 3], &chain.transition.value[row][j])) return;
            printf("ROW %s %s rowsum=%s\n", chain.name, words[2], fraction_text(row_sum(&chain, row, all)).text);
        }
        save_chain(store, &chain);
        return;
    }
    if (!strcmp(verb, "SHOW")) {
        printf("MATRIX %s states=%d\n", chain.name, size);
        display_matrix(&chain, &chain.transition, "ROW");
        return;
    }
    Vector sums = zero_vector();
    int bad = 0;
    for (int i = 0; i < size; ++i) {
        sums.value[i] = row_sum(&chain, i, all);
        if (!equal(sums.value[i], ONE)) {
            if (strcmp(verb, "CHECK")) { error("NOT STOCHASTIC %s", chain.states[i]); return; }
            ++bad;
        }
    }
    if (!strcmp(verb, "CHECK")) {
        if (!bad) printf("CHECK %s ok\n", chain.name);
        else {
            printf("CHECK %s bad=%d\n", chain.name, bad);
            for (int i = 0; i < size; ++i)
                if (!equal(sums.value[i], ONE)) printf("BADROW %s sum=%s\n", chain.states[i], fraction_text(sums.value[i]).text);
        }
        return;
    }
    Graph graph = analyze(&chain);
    if (!strcmp(verb, "CLASSES")) {
        printf("CLASSES %s count=%d\n", chain.name, graph.count);
        for (int c = 0; c < graph.count; ++c) {
            Class group = graph.classes[c];
            int indices[MAX_STATES], length = members(group.states, size, indices);
            printf("CLASS %d %s period=%d size=%d", c + 1, group.closed ? "RECURRENT" : "TRANSIENT", group.period, length);
            for (int i = 0; i < length; ++i) printf(" %s", chain.states[indices[i]]);
            putchar('\n');
            if (group.period >= 2)
                for (int remainder = 0; remainder < group.period; ++remainder) {
                    printf("CYCLIC %d", remainder);
                    for (int i = 0; i < length; ++i)
                        if (graph.level[indices[i]] % group.period == remainder) printf(" %s", chain.states[indices[i]]);
                    putchar('\n');
                }
        }
    } else if (!strcmp(verb, "CLASSIFY")) {
        classify(&chain, &graph);
    } else if (!strcmp(verb, "STEP")) {
        Vector distribution = zero_vector();
        if (isdigit((unsigned char)words[2][0])) {
            char *values[12];
            int length = split(words[2], ",", values);
            if (length != size) { error("BAD LENGTH"); return; }
            for (int i = 0; i < size; ++i)
                if (!probability(values[i], &distribution.value[i])) return;
            Fraction sum = ZERO;
            for (int i = 0; i < size; ++i) sum = add(sum, distribution.value[i]);
            if (!equal(sum, ONE)) { error("BAD DISTRIBUTION"); return; }
        } else {
            int state = require_state(&chain, words[2]);
            if (state < 0) return;
            distribution.value[state] = ONE;
        }
        int steps = atoi(words[3]);
        for (int t = 0; t < steps; ++t) {
            Vector next = zero_vector();
            for (int j = 0; j < size; ++j)
                for (int i = 0; i < size; ++i) next.value[j] = add(next.value[j], multiply(distribution.value[i], chain.transition.value[i][j]));
            distribution = next;
        }
        printf("STEP %s k=%d\n", chain.name, steps);
        for (int i = 0; i < size; ++i) printf("PROB %s %s\n", chain.states[i], value_text(distribution.value[i]).text);
    } else if (!strcmp(verb, "POWER")) {
        int steps = atoi(words[2]);
        Matrix power = identity(size);
        for (int t = 0; t < steps; ++t) power = matrix_product(&power, &chain.transition);
        printf("POWER %s k=%d\n", chain.name, steps);
        display_matrix(&chain, &power, "ROW");
    } else if (!strcmp(verb, "STATIONARY")) {
        int closed = 0;
        for (int c = 0; c < graph.count; ++c) if (graph.classes[c].closed) ++closed;
        printf("STATIONARY %s count=%d\n", chain.name, closed);
        int number = 0;
        for (int c = 0; c < graph.count; ++c) {
            if (!graph.classes[c].closed) continue;
            int indices[MAX_STATES], length = members(graph.classes[c].states, size, indices);
            Vector distribution = stationary(&chain, graph.classes[c].states);
            printf("DIST %d class=%d size=%d\n", ++number, c + 1, length);
            for (int i = 0; i < length; ++i) printf("PI %s %s\n", chain.states[indices[i]], value_text(distribution.value[indices[i]]).text);
        }
    } else if (!strcmp(verb, "RECURRENCE")) {
        int state = require_state(&chain, words[2]);
        if (state < 0) return;
        Class group = graph.classes[graph.class_of[state]];
        if (!group.closed) { error("TRANSIENT STATE %s", words[2]); return; }
        Vector distribution = stationary(&chain, group.states);
        printf("RECURRENCE %s %s pi=%s mean=%s period=%d\n", chain.name, words[2], value_text(distribution.value[state]).text, value_text(divide(ONE, distribution.value[state])).text, group.period);
    } else if (!strcmp(verb, "ABSORB")) {
        show_absorption(&chain, &graph);
    } else if (!strcmp(verb, "HITTING") || !strcmp(verb, "RESTRICT")) {
        bool restrict_chain = !strcmp(verb, "RESTRICT");
        int first = restrict_chain ? 3 : 2;
        unsigned target;
        if (!target_set(&chain, words + first, count - first, &target)) return;
        if (restrict_chain) {
            for (int i = 0; i < size; ++i)
                for (int j = 0; j < size; ++j)
                    if ((target & (1u << i)) && !(target & (1u << j)) && chain.transition.value[i][j].numerator) { error("NOT CLOSED %s", chain.states[i]); return; }
            int indices[MAX_STATES], length = members(target, size, indices);
            Chain result = new_chain(words[2], length);
            for (int i = 0; i < length; ++i) {
                strcpy(result.states[i], chain.states[indices[i]]);
                for (int j = 0; j < length; ++j) result.transition.value[i][j] = chain.transition.value[indices[i]][indices[j]];
            }
            save_chain(store, &result);
            printf("RESTRICT %s %s states=%d\n", chain.name, words[2], length);
            display_matrix(&result, &result.transition, "ROW");
        } else {
            Hitting result = hitting(&chain, &graph, target, true);
            printf("HITTING %s targets=", chain.name);
            bool first_name = true;
            for (int i = 0; i < size; ++i)
                if (target & (1u << i)) { printf("%s%s", first_name ? "" : ",", chain.states[i]); first_name = false; }
            putchar('\n');
            for (int i = 0; i < size; ++i)
                printf("HIT %s prob=%s time=%s\n", chain.states[i], value_text(result.probability.value[i]).text, result.finite[i] ? value_text(result.time.value[i]).text : "inf");
        }
    } else if (!strcmp(verb, "FIRSTPASSAGE")) {
        int source = require_state(&chain, words[2]);
        if (source < 0) return;
        int target = require_state(&chain, words[3]);
        if (target < 0) return;
        int steps = atoi(words[4]);
        if (!steps) { error("BAD STEPS"); return; }
        Fraction first[30], cumulative[30], total = ZERO;
        Vector previous = zero_vector();
        for (int i = 0; i < size; ++i) previous.value[i] = chain.transition.value[i][target];
        for (int t = 0; t < steps; ++t) {
            if (t) {
                Vector next = zero_vector();
                for (int i = 0; i < size; ++i)
                    for (int j = 0; j < size; ++j)
                        if (j != target) next.value[i] = add(next.value[i], multiply(chain.transition.value[i][j], previous.value[j]));
                previous = next;
            }
            first[t] = previous.value[source];
            total = cumulative[t] = add(total, first[t]);
        }
        printf("FIRSTPASSAGE %s %s %s k=%d total=%s\n", chain.name, words[2], words[3], steps, value_text(total).text);
        for (int t = 0; t < steps; ++t) printf("FP %d %s cum=%s\n", t + 1, value_text(first[t]).text, value_text(cumulative[t]).text);
    } else if (!strcmp(verb, "PATHPROB")) {
        int path[30];
        for (int i = 2; i < count; ++i) {
            path[i - 2] = require_state(&chain, words[i]);
            if (path[i - 2] < 0) return;
        }
        Fraction chance = ONE;
        int zero_at = 0;
        for (int i = 1; i < count - 2; ++i) {
            chance = multiply(chance, chain.transition.value[path[i - 1]][path[i]]);
            if (!chance.numerator && !zero_at) zero_at = i;
        }
        printf("PATHPROB %s steps=%d prob=%s", chain.name, count - 3, value_text(chance).text);
        if (zero_at) printf(" zero_at=%d", zero_at);
        putchar('\n');
    } else if (!strcmp(verb, "MOSTLIKELY")) {
        int source = require_state(&chain, words[2]);
        if (source < 0) return;
        int steps = atoi(words[3]);
        if (!steps) { error("BAD STEPS"); return; }
        Fraction best[21][MAX_STATES];
        int choice[20][MAX_STATES];
        for (int i = 0; i < size; ++i) best[steps][i] = ONE;
        for (int t = steps - 1; t >= 0; --t)
            for (int i = 0; i < size; ++i) {
                best[t][i] = ZERO;
                choice[t][i] = 0;
                for (int j = 0; j < size; ++j) {
                    Fraction candidate = multiply(chain.transition.value[i][j], best[t + 1][j]);
                    if (greater(candidate, best[t][i])) { best[t][i] = candidate; choice[t][i] = j; }
                }
            }
        printf("MOSTLIKELY %s %s k=%d prob=%s\nPATH %s", chain.name, words[2], steps, value_text(best[0][source]).text, chain.states[source]);
        for (int t = 0; t < steps; ++t) { source = choice[t][source]; printf(" %s", chain.states[source]); }
        putchar('\n');
    } else if (!strcmp(verb, "LUMP")) {
        lump(store, &chain, words[2], words[3]);
    } else if (!strcmp(verb, "REWARD")) {
        if (count - 3 != size) { error("BAD LENGTH"); return; }
        Fraction gamma;
        if (!probability(words[2], &gamma)) return;
        if (equal(gamma, ONE)) { error("BAD DISCOUNT"); return; }
        Vector rewards = zero_vector(), gain = zero_vector();
        Matrix equations = zero_matrix(size, size + 1);
        for (int i = 0; i < size; ++i) {
            rewards.value[i] = fraction(atoi(words[i + 3]), 1);
            for (int j = 0; j < size; ++j) equations.value[i][j] = subtract(i == j ? ONE : ZERO, multiply(gamma, chain.transition.value[i][j]));
            equations.value[i][size] = rewards.value[i];
        }
        eliminate(&equations);
        for (int c = 0; c < graph.count; ++c) {
            if (!graph.classes[c].closed) continue;
            unsigned group = graph.classes[c].states;
            Vector distribution = stationary(&chain, group);
            Fraction average = ZERO;
            for (int i = 0; i < size; ++i)
                if (group & (1u << i)) average = add(average, multiply(distribution.value[i], rewards.value[i]));
            Hitting hit = hitting(&chain, &graph, group, false);
            for (int i = 0; i < size; ++i) gain.value[i] = add(gain.value[i], multiply(hit.probability.value[i], average));
        }
        printf("REWARD %s gamma=%s\n", chain.name, fraction_text(gamma).text);
        for (int i = 0; i < size; ++i) printf("VALUE %s discounted=%s gain=%s\n", chain.states[i], value_text(equations.value[i][size]).text, value_text(gain.value[i]).text);
    } else if (!strcmp(verb, "SIMULATE")) {
        int current = require_state(&chain, words[2]);
        if (current < 0) return;
        int steps = atoi(words[3]);
        if (!steps) { error("BAD STEPS"); return; }
        int64_t seed = strtoll(words[4], NULL, 10), random_value = seed;
        if (!seed || seed >= 2147483647) { error("BAD SEED"); return; }
        int path[61], visits[MAX_STATES] = {0};
        path[0] = current;
        ++visits[current];
        for (int t = 1; t <= steps; ++t) {
            int64_t common = 1;
            for (int j = 0; j < size; ++j) {
                int64_t denominator = chain.transition.value[current][j].denominator;
                common = common / gcd(common, denominator) * denominator;
            }
            random_value = 48271 * random_value % 2147483647;
            int64_t draw = random_value % common;
            Fraction cumulative = ZERO;
            for (int j = 0; j < size; ++j) {
                cumulative = add(cumulative, chain.transition.value[current][j]);
                if (cumulative.numerator * (common / cumulative.denominator) > draw) { current = j; break; }
            }
            path[t] = current;
            ++visits[current];
        }
        printf("SIMULATE %s %s steps=%d seed=%" PRId64 " end=%s\nPATH", chain.name, words[2], steps, seed, chain.states[current]);
        for (int t = 0; t <= steps; ++t) printf(" %s", chain.states[path[t]]);
        putchar('\n');
        for (int i = 0; i < size; ++i) printf("VISIT %s %d\n", chain.states[i], visits[i]);
    } else {
        int steps = 0;
        Fraction epsilon = ZERO;
        if (!strcmp(verb, "MIXING")) {
            steps = atoi(words[2]);
            if (!steps) { error("BAD STEPS"); return; }
            if (!probability(words[3], &epsilon)) return;
        }
        if (graph.count != 1) { error("NOT IRREDUCIBLE"); return; }
        Vector distribution = stationary(&chain, all);
        if (!strcmp(verb, "PASSAGE")) {
            Matrix passage = zero_matrix(size, size);
            for (int j = 0; j < size; ++j) {
                Hitting hit = hitting(&chain, &graph, 1u << j, true);
                for (int i = 0; i < size; ++i) passage.value[i][j] = i == j ? divide(ONE, distribution.value[j]) : hit.time.value[i];
            }
            Fraction kemeny = ZERO;
            for (int j = 1; j < size; ++j) kemeny = add(kemeny, multiply(distribution.value[j], passage.value[0][j]));
            printf("PASSAGE %s kemeny=%s\n", chain.name, value_text(kemeny).text);
            display_matrix(&chain, &passage, "M");
        } else if (!strcmp(verb, "REVERSE")) {
            Chain result = chain;
            strcpy(result.name, words[2]);
            bool reversible = true;
            for (int i = 0; i < size; ++i)
                for (int j = 0; j < size; ++j) {
                    result.transition.value[i][j] = divide(multiply(distribution.value[j], chain.transition.value[j][i]), distribution.value[i]);
                    reversible &= equal(result.transition.value[i][j], chain.transition.value[i][j]);
                }
            save_chain(store, &result);
            printf("REVERSE %s %s reversible=%s\n", chain.name, words[2], reversible ? "yes" : "no");
            display_matrix(&result, &result.transition, "ROW");
        } else if (!strcmp(verb, "REVERSIBLE")) {
            Fraction forward[MAX_STATES][MAX_STATES], backward[MAX_STATES][MAX_STATES];
            int violations = 0;
            for (int i = 0; i < size; ++i)
                for (int j = i + 1; j < size; ++j) {
                    forward[i][j] = multiply(distribution.value[i], chain.transition.value[i][j]);
                    backward[i][j] = multiply(distribution.value[j], chain.transition.value[j][i]);
                    if (!equal(forward[i][j], backward[i][j])) ++violations;
                }
            if (!violations) printf("REVERSIBLE %s yes\n", chain.name);
            else {
                printf("REVERSIBLE %s no violations=%d\n", chain.name, violations);
                for (int i = 0; i < size; ++i)
                    for (int j = i + 1; j < size; ++j)
                        if (!equal(forward[i][j], backward[i][j])) printf("VIOLATION %s %s %s %s\n", chain.states[i], chain.states[j], value_text(forward[i][j]).text, value_text(backward[i][j]).text);
            }
        } else {
            Fraction distances[20];
            int worst[20], mixing_time = 0;
            Matrix power = identity(size);
            for (int t = 0; t < steps; ++t) {
                power = matrix_product(&power, &chain.transition);
                distances[t] = ZERO;
                worst[t] = 0;
                for (int i = 0; i < size; ++i) {
                    Fraction distance = ZERO;
                    for (int j = 0; j < size; ++j) {
                        Fraction difference = subtract(power.value[i][j], distribution.value[j]);
                        if (difference.numerator < 0) difference.numerator = -difference.numerator;
                        distance = add(distance, difference);
                    }
                    distance = divide(distance, fraction(2, 1));
                    if (greater(distance, distances[t])) { distances[t] = distance; worst[t] = i; }
                }
                if (!mixing_time && !greater(distances[t], epsilon)) mixing_time = t + 1;
            }
            printf("MIXING %s k=%d eps=%s time=", chain.name, steps, fraction_text(epsilon).text);
            if (mixing_time) printf("%d\n", mixing_time); else puts("none");
            for (int t = 0; t < steps; ++t) printf("TV %d %s from=%s\n", t + 1, value_text(distances[t]).text, chain.states[worst[t]]);
        }
    }
}

int main(void) {
    Store store = {0};
    char line[1024];
    if (!fgets(line, sizeof line, stdin)) return 0;
    int count = atoi(line);
    for (int i = 0; i < count; ++i) {
        if (!fgets(line, sizeof line, stdin)) break;
        char *words[64];
        int length = split(line, " \r\n", words);
        command(&store, words, length);
    }
    for (int i = 0; i < store.count; ++i) free(store.chains[i]);
    return 0;
}
