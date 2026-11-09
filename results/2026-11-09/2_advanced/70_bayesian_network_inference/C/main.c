#include "bayes.h"
#define V(value) ((long long)(value))
static char *formatted(const char *pattern, va_list args) {
    va_list copy;
    va_copy(copy, args);
    int count = vsnprintf(NULL, 0, pattern, copy);
    va_end(copy);
    char *out = malloc((size_t)count + 1);
    vsnprintf(out, (size_t)count + 1, pattern, args);
    return out;
}
char *format(const char *pattern, ...) {
    va_list args;
    va_start(args, pattern);
    char *out = formatted(pattern, args);
    va_end(args);
    return out;
}
void text(Text *out, const char *pattern, ...) {
    va_list args;
    va_start(args, pattern);
    char *part = formatted(pattern, args);
    va_end(args);
    size_t count = strlen(part);
    if (out->length + count + 1 > out->capacity) {
        out->capacity = 2 * (out->length + count + 1);
        out->data = realloc(out->data, out->capacity);
    }
    memcpy(out->data + out->length, part, count + 1);
    out->length += count;
    free(part);
}
void line(Lines *out, const char *pattern, ...) {
    if (out->count == out->capacity) {
        out->capacity = out->capacity ? out->capacity * 2 : 32;
        out->values = realloc(out->values, (size_t)out->capacity * sizeof(char *));
    }
    va_list args;
    va_start(args, pattern);
    out->values[out->count++] = formatted(pattern, args);
    va_end(args);
}
static char *real(double value) {
    char *out = format("%.4f", value);
    if (!strcmp(out, "-0.0000"))
        memmove(out, out + 1, strlen(out));
    return out;
}
static const char *yes(int value) { return value ? "yes" : "no"; }
static void append(Lines *out, const Lines *other) {
    for (int i = 0; i < other->count; ++i)
        line(out, "%s", other->values[i]);
}
static void block(Lines *out, const Lines *other) {
    if (out->count)
        line(out, "");
    append(out, other);
}
static Vars one(int variable) {
    Vars out = {0};
    out.values[out.count++] = variable;
    return out;
}
typedef struct {
    char *values[64];
    int count;
    char *buffer;
} Words;
static Words words(const char *value) {
    Words out = {0};
    out.buffer = format("%s", value);
    char *token = strtok(out.buffer, " ");
    while (token) {
        out.values[out.count++] = token;
        token = strtok(NULL, " ");
    }
    return out;
}
typedef struct {
    double alpha;
    int given, sources[15];
    Vars order;
    I limit, seed;
} Params;
static Params parameters(const Input *input) {
    Params out = {0};
    Words row = words(input->settings[0]);
    out.alpha = strtod(row.values[1], NULL);
    row = words(input->settings[1]);
    out.given = !strcmp(row.values[1], "GIVEN");
    row = words(input->settings[2]);
    for (int i = 1; i < row.count; ++i)
        out.order.values[out.order.count++] = variable_id(&input->network, row.values[i]);
    row = words(input->settings[3]);
    out.limit = strtoll(row.values[1], NULL, 10);
    row = words(input->settings[4]);
    out.seed = strtoll(row.values[1], NULL, 10);
    for (int i = 0; i < input->network.count; ++i) {
        row = words(input->settings[5 + i]);
        out.sources[i] = !strcmp(row.values[2], "GIVEN");
    }
    return out;
}
typedef struct {
    int variable;
    Vars parents;
    double score;
} Family;
typedef struct {
    Input *input;
    Network *network;
    Params p;
    Minstd random;
    Vars variables, topological, children[15], ancestors[15], descendants[15], spouses[15],
        blankets[15];
    int depths[15];
    Counts counts[15];
    CPT learned[15], cpts[15];
    double likelihoods[15];
    I parameter_counts[15];
    Factors factors;
    Family families[160];
    int family_count;
} Study;
static Vars closure(Vars initial, const Vars links[15], int count) {
    unsigned reached = 0;
    int pending[15], length = 0;
    for (int i = 0; i < initial.count; ++i) {
        int v = initial.values[i];
        if (!(reached & (1u << v))) {
            reached |= 1u << v;
            pending[length++] = v;
        }
    }
    while (length) {
        int v = pending[--length];
        for (int i = 0; i < links[v].count; ++i) {
            int neighbor = links[v].values[i];
            if (!(reached & (1u << neighbor))) {
                reached |= 1u << neighbor;
                pending[length++] = neighbor;
            }
        }
    }
    Vars out = {0};
    for (int v = 0; v < count; ++v)
        if (reached & (1u << v))
            out.values[out.count++] = v;
    return out;
}
static char *sequence(const Study *s, Vars variables) {
    Text out = {0};
    if (!variables.count)
        text(&out, "-");
    for (int i = 0; i < variables.count; ++i)
        text(&out, "%s%s", i ? " " : "", s->network->names[variables.values[i]]);
    return out.data;
}
static char *assignment_text(const Study *s, const Assignment *assignment, Vars variables) {
    Text out = {0};
    if (!variables.count)
        text(&out, "-");
    for (int i = 0; i < variables.count; ++i) {
        int v = variables.values[i];
        text(&out, "%s%s=%s", i ? " " : "", s->network->names[v],
             s->network->states[v][assignment->values[v]]);
    }
    return out.data;
}
static void initialize(Study *s) {
    s->input = read_inputs();
    s->network = &s->input->network;
    s->p = parameters(s->input);
    s->random.state = s->p.seed;
    int count = s->network->count;
    for (int v = 0; v < count; ++v) {
        s->variables.values[s->variables.count++] = v;
        for (int child = 0; child < count; ++child)
            if (contains(&s->network->parents[child], v))
                s->children[v].values[s->children[v].count++] = child;
    }
    unsigned selected = 0;
    while (s->topological.count < count) {
        for (int v = 0; v < count; ++v)
            if (!(selected & (1u << v))) {
                int ready = 1;
                for (int i = 0; i < s->network->parents[v].count; ++i)
                    if (!(selected & (1u << s->network->parents[v].values[i])))
                        ready = 0;
                if (ready) {
                    selected |= 1u << v;
                    s->topological.values[s->topological.count++] = v;
                    break;
                }
            }
    }
    for (int i = 0; i < s->topological.count; ++i) {
        int v = s->topological.values[i];
        for (int j = 0; j < s->network->parents[v].count; ++j) {
            int depth = s->depths[s->network->parents[v].values[j]] + 1;
            if (depth > s->depths[v])
                s->depths[v] = depth;
        }
    }
    for (int v = 0; v < count; ++v) {
        s->ancestors[v] = closure(s->network->parents[v], s->network->parents, count);
        s->descendants[v] = closure(s->children[v], s->children, count);
        Vars immediate = vars_union(s->network->parents[v], s->children[v]), parents = {0};
        for (int i = 0; i < s->children[v].count; ++i)
            parents = vars_union(parents, s->network->parents[s->children[v].values[i]]);
        s->spouses[v] = vars_difference(vars_difference(parents, immediate), one(v));
        s->blankets[v] = vars_union(immediate, s->spouses[v]);
        s->counts[v] = count_samples(v, &s->network->parents[v], s->input->samples,
                                     s->input->sample_count, s->network);
        s->learned[v] = learn(&s->counts[v], s->p.alpha);
        s->cpts[v] = s->p.sources[v] ? s->network->expert[v] : s->learned[v];
        s->likelihoods[v] = log_likelihood(&s->counts[v], &s->cpts[v]);
        s->parameter_counts[v] = parameter_count(&s->counts[v]);
        s->factors.values[s->factors.count++] =
            cpt_factor(v, &s->network->parents[v], &s->cpts[v], s->network);
    }
}
static Evidence parse_evidence(const Study *s, const Words *fields, int start, int end) {
    Evidence out = {0};
    for (int i = start; i < end; ++i) {
        char *equal = strchr(fields->values[i], '=');
        char name[17];
        size_t length = (size_t)(equal - fields->values[i]);
        memcpy(name, fields->values[i], length);
        name[length] = 0;
        int variable = variable_id(s->network, name);
        out.values[out.count++] =
            (Observation){variable, state_id(s->network, variable, equal + 1)};
    }
    return out;
}
typedef struct {
    Vars query;
    Evidence evidence;
} Query;
static Query query_parts(const Study *s, const Words *fields, int start, int end) {
    Query out = {0};
    int separator = start;
    while (separator < end && strcmp(fields->values[separator], "|"))
        ++separator;
    for (int i = start; i < separator; ++i)
        out.query.values[out.query.count++] = variable_id(s->network, fields->values[i]);
    if (separator < end)
        out.evidence = parse_evidence(s, fields, separator + 1, end);
    return out;
}
typedef struct {
    Factor distribution;
    double probability, marginals[15][4];
} SumResult;
typedef struct {
    Vars relevant, eliminate;
    Factors initial;
    Plan plans[2];
    SumResult result;
} Posterior;
static void plans(const Study *s, const Factors *initial, const Vars *eliminate, Plan out[2]) {
    out[0] = make_plan(initial, eliminate, 0, &s->p.order, s->network);
    out[1] = make_plan(initial, eliminate, 1, &s->p.order, s->network);
}
static SumResult sum_result(const Study *s, const Factors *initial, const Plan *plan, Vars query) {
    Execution executed = execute(initial, plan, s->network, 0);
    SumResult out = {0};
    out.distribution = executed.final;
    out.probability = total(executed.final.values, executed.final.count);
    out.distribution.values = malloc((size_t)out.distribution.count * sizeof(double));
    for (I i = 0; i < out.distribution.count; ++i)
        out.distribution.values[i] = executed.final.values[i] / out.probability;
    for (I i = 0; i < out.distribution.count; ++i) {
        Assignment initial_assignment = {0}, assignment = decode(i, &out.distribution.variables,
                                                                 s->network, initial_assignment);
        for (int j = 0; j < query.count; ++j) {
            int v = query.values[j];
            out.marginals[v][assignment.values[v]] += out.distribution.values[i];
        }
    }
    return out;
}
static Posterior posterior(const Study *s, Vars query, Evidence evidence) {
    Posterior out = {0};
    Vars evidence_variables = observed(&evidence);
    out.relevant =
        closure(vars_union(query, evidence_variables), s->network->parents, s->network->count);
    out.eliminate = vars_difference(vars_difference(out.relevant, query), evidence_variables);
    for (int i = 0; i < out.relevant.count; ++i) {
        int variable = out.relevant.values[i];
        out.initial.values[out.initial.count++] = reduced(&s->factors.values[variable], &evidence);
    }
    plans(s, &out.initial, &out.eliminate, out.plans);
    out.result = sum_result(s, &out.initial, &out.plans[s->p.given], query);
    return out;
}
static double joint(const Study *s, const Assignment *assignment, Vars scope) {
    double probability = 1;
    for (int i = 0; i < scope.count; ++i) {
        int v = scope.values[i];
        probability *= s->cpts[v].values[parent_row(&s->network->parents[v], assignment,
                                                    s->network)][assignment->values[v]];
    }
    return probability;
}
typedef struct {
    I count;
    const char *verdict;
} Enumeration;
static Enumeration query_enumeration(const Study *s, const Posterior *result, Vars query,
                                     Evidence evidence) {
    Vars free_variables = vars_difference(result->relevant, observed(&evidence));
    Enumeration out = {entry_count(&free_variables, s->network), "skipped"};
    if (out.count > s->p.limit)
        return out;
    query = canonical(query);
    I count = entry_count(&query, s->network);
    double *values = calloc((size_t)count, sizeof(double));
    Assignment initial = {0};
    for (int i = 0; i < evidence.count; ++i)
        initial.values[evidence.values[i].variable] = evidence.values[i].state;
    for (I row = 0; row < out.count; ++row) {
        Assignment assignment = decode(row, &free_variables, s->network, initial);
        values[parent_row(&query, &assignment, s->network)] +=
            joint(s, &assignment, result->relevant);
    }
    double probability = total(values, count);
    int agreement = fabs(log(probability) - log(result->result.probability)) <= 1e-9;
    for (I i = 0; i < count; ++i)
        if (fabs(values[i] / probability - result->result.distribution.values[i]) > 1e-9)
            agreement = 0;
    out.verdict = agreement ? "agree" : "disagree";
    free(values);
    return out;
}
static Lines elimination_lines(const Study *s, Vars relevant, Vars eliminate, const Plan plans[2],
                               int agreement, Enumeration enumeration) {
    Lines out = {0};
    line(&out, "relevant %s", sequence(s, relevant));
    line(&out, "pruned %s", sequence(s, vars_difference(s->variables, relevant)));
    line(&out, "eliminate %s", sequence(s, eliminate));
    for (int method = 0; method < 2; ++method) {
        line(&out, "order %s", method ? "given" : "minfill");
        for (int i = 0; i < plans[method].count; ++i) {
            Step step = plans[method].steps[i];
            line(&out, "step %s fill %d scope %s entries %lld", s->network->names[step.variable],
                 step.fill, sequence(s, step.scope), V(step.size));
        }
        line(&out, "cost max %lld total %lld", V(plans[method].maximum), V(plans[method].total));
    }
    line(&out, "used %s", s->p.given ? "given" : "minfill");
    line(&out, "orders_agree %s", yes(agreement));
    line(&out, "enumeration %lld %s", V(enumeration.count), enumeration.verdict);
    return out;
}
static Lines marginal_lines(const Study *s, const char *prefix, Vars query,
                            const double marginals[15][4]) {
    Lines out = {0};
    for (int i = 0; i < query.count; ++i) {
        int v = query.values[i];
        Text row = {0};
        text(&row, "%s %s", prefix, s->network->names[v]);
        for (int state = 0; state < s->network->sizes[v]; ++state)
            text(&row, " %s %s", s->network->states[v][state], real(marginals[v][state]));
        line(&out, "%s", row.data);
        free(row.data);
    }
    return out;
}
typedef struct {
    Lines answer, elimination;
} Answer;
static Answer answer_query(const Study *s, Query query) {
    Answer out = {0};
    Posterior result = posterior(s, query.query, query.evidence);
    line(&out.answer, "log_evidence %s", real(log(result.result.probability)));
    if (query.evidence.count) {
        double conflict = 0;
        for (int i = 0; i < query.evidence.count; ++i) {
            Evidence single = {0};
            single.values[single.count++] = query.evidence.values[i];
            Posterior only = posterior(s, (Vars){0}, single);
            conflict += log(only.result.probability);
        }
        conflict -= log(result.result.probability);
        line(&out.answer, "conflict %s", real(conflict));
    }
    if (query.query.count >= 2)
        for (I i = 0; i < result.result.distribution.count; ++i) {
            Assignment initial = {0}, assignment = decode(i, &result.result.distribution.variables,
                                                          s->network, initial);
            line(&out.answer, "joint %s %s",
                 assignment_text(s, &assignment, result.result.distribution.variables),
                 real(result.result.distribution.values[i]));
        }
    Lines marginals = marginal_lines(s, "marginal", query.query, result.result.marginals);
    append(&out.answer, &marginals);
    for (int removed = 0; removed < query.evidence.count; ++removed) {
        Evidence reduced = {0};
        for (int i = 0; i < query.evidence.count; ++i)
            if (i != removed)
                reduced.values[reduced.count++] = query.evidence.values[i];
        Posterior without = posterior(s, query.query, reduced);
        double shift = 0;
        for (int i = 0; i < query.query.count; ++i) {
            int v = query.query.values[i];
            for (int state = 0; state < s->network->sizes[v]; ++state) {
                double change =
                    fabs(result.result.marginals[v][state] - without.result.marginals[v][state]);
                if (change > shift)
                    shift = change;
            }
        }
        Observation removed_value = query.evidence.values[removed];
        line(&out.answer, "drop %s=%s shift %s", s->network->names[removed_value.variable],
             s->network->states[removed_value.variable][removed_value.state], real(shift));
    }
    SumResult first = sum_result(s, &result.initial, &result.plans[0], query.query),
              second = sum_result(s, &result.initial, &result.plans[1], query.query);
    int agreement = fabs(log(first.probability) - log(second.probability)) <= 1e-9;
    for (I i = 0; i < first.distribution.count; ++i)
        if (fabs(first.distribution.values[i] - second.distribution.values[i]) > 1e-9)
            agreement = 0;
    out.elimination =
        elimination_lines(s, result.relevant, result.eliminate, result.plans, agreement,
                          query_enumeration(s, &result, query.query, query.evidence));
    return out;
}
static int assignment_equal(const Study *s, const Assignment *first, const Assignment *second) {
    for (int v = 0; v < s->network->count; ++v)
        if (first->values[v] != second->values[v])
            return 0;
    return 1;
}
static Answer answer_mpe(const Study *s, Evidence evidence) {
    Answer out = {0};
    Factors initial = {0};
    for (int i = 0; i < s->factors.count; ++i)
        initial.values[initial.count++] = reduced(&s->factors.values[i], &evidence);
    Vars eliminate = vars_difference(s->variables, observed(&evidence));
    Plan orders[2];
    plans(s, &initial, &eliminate, orders);
    double maxima[2];
    Assignment assignments[2];
    for (int method = 0; method < 2; ++method) {
        Execution result = execute(&initial, &orders[method], s->network, 1);
        maxima[method] = result.final.values[0];
        assignments[method] = traceback(&result, s->network);
        for (int i = 0; i < evidence.count; ++i)
            assignments[method].values[evidence.values[i].variable] = evidence.values[i].state;
    }
    double maximum = maxima[s->p.given], probability = 1;
    if (evidence.count) {
        Posterior result = posterior(s, (Vars){0}, evidence);
        probability = result.result.probability;
    }
    Assignment assignment = assignments[s->p.given];
    line(&out.answer, "assignment %s", assignment_text(s, &assignment, s->variables));
    line(&out.answer, "log_joint %s", real(log(maximum)));
    line(&out.answer, "log_evidence %s", real(log(probability)));
    line(&out.answer, "posterior %s", real(maximum / probability));
    for (int i = 0; i < eliminate.count; ++i) {
        int v = eliminate.values[i];
        Vars free_variables = vars_difference(eliminate, one(v));
        Plan plan = make_plan(&initial, &free_variables, s->p.given, &s->p.order, s->network);
        Execution result = execute(&initial, &plan, s->network, 1);
        int alternative = -1;
        for (int state = 0; state < s->network->sizes[v]; ++state)
            if (state != assignment.values[v] &&
                (alternative < 0 || result.final.values[state] > result.final.values[alternative]))
                alternative = state;
        line(&out.answer, "margin %s %s %s", s->network->names[v],
             s->network->states[v][alternative],
             real(log(maximum) - log(result.final.values[alternative])));
    }
    int agreement = assignment_equal(s, &assignments[0], &assignments[1]) &&
                    fabs(log(maxima[0]) - log(maxima[1])) <= 1e-9;
    Enumeration enumeration = {entry_count(&eliminate, s->network), "skipped"};
    if (enumeration.count <= s->p.limit) {
        double best = -1;
        Assignment best_assignment = {0}, initial_assignment = {0};
        for (int i = 0; i < evidence.count; ++i)
            initial_assignment.values[evidence.values[i].variable] = evidence.values[i].state;
        for (I row = 0; row < enumeration.count; ++row) {
            Assignment candidate = decode(row, &eliminate, s->network, initial_assignment);
            double value = joint(s, &candidate, s->variables);
            if (value > best) {
                best = value;
                best_assignment = candidate;
            }
        }
        enumeration.verdict = assignment_equal(s, &best_assignment, &assignment) &&
                                      fabs(log(best) - log(maximum)) <= 1e-9
                                  ? "agree"
                                  : "disagree";
    }
    out.elimination = elimination_lines(s, s->variables, eliminate, orders, agreement, enumeration);
    return out;
}
typedef struct {
    Lines answer, csv;
} SampleAnswer;
static SampleAnswer answer_sample(Study *s, int number, Query query, const I *counts,
                                  int count_length) {
    SampleAnswer out = {0};
    Posterior exact = posterior(s, query.query, query.evidence);
    out.answer = marginal_lines(s, "exact", query.query, exact.result.marginals);
    double weights[15][4] = {{0}}, weight = 0, squared_weight = 0;
    int checkpoint = 0;
    for (I index = 1; index <= counts[count_length - 1]; ++index) {
        Weighted current =
            weighted_sample(&s->topological, s->network, s->cpts, &query.evidence, &s->random);
        weight += current.weight;
        squared_weight += current.weight * current.weight;
        for (int i = 0; i < query.query.count; ++i) {
            int v = query.query.values[i];
            weights[v][current.assignment.values[v]] += current.weight;
        }
        if (index != counts[checkpoint])
            continue;
        double maximum_error = 0;
        for (int i = 0; i < query.query.count; ++i) {
            int v = query.query.values[i];
            for (int state = 0; state < s->network->sizes[v]; ++state) {
                double estimate = weights[v][state] / weight,
                       probability = exact.result.marginals[v][state],
                       error = fabs(estimate - probability);
                if (error > maximum_error)
                    maximum_error = error;
                line(&out.csv, "%d,%lld,%s,%s,%s,%s,%s", number, V(index), s->network->names[v],
                     s->network->states[v][state], real(estimate), real(probability), real(error));
            }
        }
        line(&out.answer, "after %lld weight %s ess %s max_error %s", V(index), real(weight),
             real(weight * weight / squared_weight), real(maximum_error));
        ++checkpoint;
    }
    return out;
}
static Lines answer_predict(const Study *s, int variable) {
    int count = s->network->sizes[variable];
    I confusion[4][4] = {{0}};
    double likelihood = 0;
    for (int i = 0; i < s->input->sample_count; ++i) {
        Assignment assignment = s->input->samples[i];
        double probabilities[4];
        for (int state = 0; state < count; ++state) {
            assignment.values[variable] = state;
            double value = s->cpts[variable].values[parent_row(&s->network->parents[variable],
                                                               &assignment, s->network)][state];
            for (int j = 0; j < s->children[variable].count; ++j) {
                int child = s->children[variable].values[j];
                value *= s->cpts[child].values[parent_row(&s->network->parents[child], &assignment,
                                                          s->network)][assignment.values[child]];
            }
            probabilities[state] = value;
        }
        double denominator = total(probabilities, count);
        int predicted = 0;
        for (int state = 0; state < count; ++state) {
            probabilities[state] /= denominator;
            if (probabilities[state] > probabilities[predicted])
                predicted = state;
        }
        int actual = s->input->samples[i].values[variable];
        ++confusion[actual][predicted];
        likelihood += log(probabilities[actual]);
    }
    I correct = 0;
    for (int state = 0; state < count; ++state)
        correct += confusion[state][state];
    Lines out = {0};
    line(&out, "blanket %s", sequence(s, s->blankets[variable]));
    line(&out, "accuracy %lld/%d %s", V(correct), s->input->sample_count,
         real((double)correct / s->input->sample_count));
    line(&out, "log_loss %s", real(-likelihood / s->input->sample_count));
    Text row = {0};
    text(&row, "predicted");
    for (int state = 0; state < count; ++state)
        text(&row, " %s", s->network->states[variable][state]);
    line(&out, "%s", row.data);
    free(row.data);
    for (int actual = 0; actual < count; ++actual) {
        row = (Text){0};
        text(&row, "actual %s", s->network->states[variable][actual]);
        for (int state = 0; state < count; ++state)
            text(&row, " %lld", V(confusion[actual][state]));
        line(&out, "%s", row.data);
        free(row.data);
    }
    return out;
}
static Vars reachable(const Study *s, Vars x, Vars z) {
    Vars ancestors = closure(z, s->network->parents, s->network->count);
    typedef struct {
        int variable, direction;
    } Position;
    Position pending[30];
    int count = 0, front = 0, visited[15][2] = {{0}};
    for (int i = 0; i < x.count; ++i) {
        int v = x.values[i];
        if (!visited[v][0]) {
            visited[v][0] = 1;
            pending[count++] = (Position){v, 0};
        }
    }
    while (front < count) {
        Position position = pending[front++];
        int v = position.variable;
        Vars up = {0}, down = {0};
        if (position.direction == 0 && !contains(&z, v)) {
            up = s->network->parents[v];
            down = s->children[v];
        } else if (position.direction == 1) {
            if (!contains(&z, v))
                down = s->children[v];
            if (contains(&ancestors, v))
                up = s->network->parents[v];
        }
        for (int direction = 0; direction < 2; ++direction) {
            Vars next = direction ? down : up;
            for (int i = 0; i < next.count; ++i) {
                int variable = next.values[i];
                if (!visited[variable][direction]) {
                    visited[variable][direction] = 1;
                    pending[count++] = (Position){variable, direction};
                }
            }
        }
    }
    Vars out = {0};
    for (int v = 0; v < s->network->count; ++v)
        if ((visited[v][0] || visited[v][1]) && !contains(&x, v) && !contains(&z, v))
            out.values[out.count++] = v;
    return out;
}
typedef struct {
    I key, count;
} CountEntry;
typedef struct {
    CountEntry *values;
    int count;
} CountMap;
static int count_order(const void *left, const void *right) {
    I a = ((const CountEntry *)left)->key, b = ((const CountEntry *)right)->key;
    return (a > b) - (a < b);
}
static CountMap count_assignments(const Study *s, Vars scope) {
    CountMap out = {0};
    int count = s->input->sample_count;
    out.values = malloc((size_t)count * sizeof(CountEntry));
    for (int i = 0; i < count; ++i)
        out.values[i] = (CountEntry){parent_row(&scope, &s->input->samples[i], s->network), 1};
    qsort(out.values, (size_t)count, sizeof(CountEntry), count_order);
    for (int i = 0; i < count; ++i) {
        CountEntry value = out.values[i];
        if (out.count && out.values[out.count - 1].key == value.key)
            ++out.values[out.count - 1].count;
        else
            out.values[out.count++] = value;
    }
    return out;
}
static I lookup(const CountMap *map, I key) {
    int first = 0, last = map->count;
    while (first < last) {
        int middle = first + (last - first) / 2;
        if (map->values[middle].key < key)
            first = middle + 1;
        else
            last = middle;
    }
    return map->values[first].count;
}
static Lines answer_dsep(const Study *s, Vars x, Vars y, Vars z) {
    Vars reached = reachable(s, x, z);
    int separated = 1;
    for (int i = 0; i < y.count; ++i)
        if (contains(&reached, y.values[i]))
            separated = 0;
    Vars scope = vars_union(vars_union(x, y), z), xz = vars_union(x, z), yz = vars_union(y, z);
    z = canonical(z);
    CountMap whole = count_assignments(s, scope), count_xz = count_assignments(s, xz),
             count_yz = count_assignments(s, yz), count_z = count_assignments(s, z);
    double information = 0;
    for (int i = 0; i < whole.count; ++i) {
        Assignment initial = {0},
                   assignment = decode(whole.values[i].key, &scope, s->network, initial);
        I observed = whole.values[i].count,
          nxz = lookup(&count_xz, parent_row(&xz, &assignment, s->network)),
          nyz = lookup(&count_yz, parent_row(&yz, &assignment, s->network)),
          nz = lookup(&count_z, parent_row(&z, &assignment, s->network));
        double argument = (double)(observed * nz) / (double)(nxz * nyz);
        information += ((double)observed / s->input->sample_count) * log(argument);
    }
    I degrees = (entry_count(&x, s->network) - 1) * (entry_count(&y, s->network) - 1) *
                entry_count(&z, s->network);
    Lines out = {0};
    line(&out, "result %s", separated ? "separated" : "connected");
    line(&out, "reachable %s", sequence(s, reached));
    line(&out, "data cmi %s g2 %s df %lld", real(information),
         real(2 * s->input->sample_count * information), V(degrees));
    free(whole.values);
    free(count_xz.values);
    free(count_yz.values);
    free(count_z.values);
    return out;
}
static Lines answer_blanket(const Study *s, int variable) {
    Vars rest = vars_difference(s->variables, vars_union(s->blankets[variable], one(variable))),
         reached = reachable(s, one(variable), s->blankets[variable]);
    int separated = 1;
    for (int i = 0; i < rest.count; ++i)
        if (contains(&reached, rest.values[i]))
            separated = 0;
    Lines out = {0};
    line(&out, "parents %s", sequence(s, s->network->parents[variable]));
    line(&out, "children %s", sequence(s, s->children[variable]));
    line(&out, "spouses %s", sequence(s, s->spouses[variable]));
    line(&out, "blanket %s", sequence(s, s->blankets[variable]));
    line(&out, "rest %s", sequence(s, rest));
    line(&out, "rest_separated %s", yes(separated));
    return out;
}
static int path(const Study *s, int start, int finish, int ignore_from, int ignore_to,
                Vars *result) {
    int previous[15], visited[15] = {0}, pending[15], count = 1, front = 0;
    for (int i = 0; i < 15; ++i)
        previous[i] = -1;
    visited[start] = 1;
    pending[0] = start;
    while (front < count) {
        int v = pending[front++];
        for (int i = 0; i < s->children[v].count; ++i) {
            int child = s->children[v].values[i];
            if ((v == ignore_from && child == ignore_to) || visited[child])
                continue;
            visited[child] = 1;
            previous[child] = v;
            if (child == finish) {
                result->count = 0;
                for (int at = finish; at >= 0; at = previous[at])
                    result->values[result->count++] = at;
                for (int j = 0; j < result->count / 2; ++j) {
                    int value = result->values[j];
                    result->values[j] = result->values[result->count - j - 1];
                    result->values[result->count - j - 1] = value;
                }
                return 1;
            }
            pending[count++] = child;
        }
    }
    return 0;
}
static double family(Study *s, int variable, Vars parents) {
    parents = canonical(parents);
    for (int i = 0; i < s->family_count; ++i) {
        Family *entry = &s->families[i];
        if (entry->variable == variable && entry->parents.count == parents.count &&
            !memcmp(entry->parents.values, parents.values, (size_t)parents.count * sizeof(int)))
            return entry->score;
    }
    double value = family_score(variable, parents, s->input->samples, s->input->sample_count,
                                s->network, s->p.alpha);
    s->families[s->family_count++] = (Family){variable, parents, value};
    return value;
}
static Lines answer_edge(Study *s, const char *operation, int x, int y) {
    Lines out = {0};
    int exists = contains(&s->network->parents[y], x);
    if (!strcmp(operation, "ADD") && exists) {
        line(&out, "result exists");
        return out;
    }
    if (strcmp(operation, "ADD") && !exists) {
        line(&out, "result missing");
        return out;
    }
    Vars route = {0};
    int cycle = 0, first = -1;
    if (!strcmp(operation, "ADD")) {
        cycle = path(s, y, x, -1, -1, &route);
        first = x;
    } else if (!strcmp(operation, "REVERSE")) {
        cycle = path(s, x, y, x, y, &route);
        first = y;
    }
    if (cycle) {
        Text row = {0};
        text(&row, "result cycle %s", s->network->names[first]);
        for (int i = 0; i < route.count; ++i)
            text(&row, " -> %s", s->network->names[route.values[i]]);
        line(&out, "%s", row.data);
        free(row.data);
        return out;
    }
    double before_y = family(s, y, s->network->parents[y]);
    Vars parents_y = !strcmp(operation, "ADD") ? vars_union(s->network->parents[y], one(x))
                                               : vars_difference(s->network->parents[y], one(x));
    double after_y = family(s, y, parents_y), change = after_y - before_y;
    line(&out, "result ok");
    line(&out, "family %s before %s after %s", s->network->names[y], real(before_y), real(after_y));
    if (!strcmp(operation, "REVERSE")) {
        double before_x = family(s, x, s->network->parents[x]),
               after_x = family(s, x, vars_union(s->network->parents[x], one(y)));
        change = (after_y - before_y) + (after_x - before_x);
        line(&out, "family %s before %s after %s", s->network->names[x], real(before_x),
             real(after_x));
    }
    line(&out, "delta %s %s", real(change), change > 0 ? "improves" : "worsens");
    return out;
}
static Lines cpt_lines(const Study *s) {
    Lines out = {0};
    double likelihood = 0;
    I parameters = 0;
    for (int v = 0; v < s->network->count; ++v) {
        line(&out, "variable %s source %s", s->network->names[v],
             s->p.sources[v] ? "GIVEN" : "LEARNED");
        Text row = {0};
        text(&row, "states");
        for (int state = 0; state < s->network->sizes[v]; ++state)
            text(&row, " %s", s->network->states[v][state]);
        line(&out, "%s", row.data);
        free(row.data);
        line(&out, "parents %s", sequence(s, s->network->parents[v]));
        for (int r = 0; r < s->counts[v].rows; ++r) {
            Assignment initial = {0},
                       assignment = decode(r, &s->network->parents[v], s->network, initial);
            row = (Text){0};
            text(&row, "row %s counts", assignment_text(s, &assignment, s->network->parents[v]));
            for (int state = 0; state < s->network->sizes[v]; ++state)
                text(&row, " %lld", V(s->counts[v].values[r][state]));
            text(&row, " probs");
            for (int state = 0; state < s->network->sizes[v]; ++state)
                text(&row, " %s", real(s->cpts[v].values[r][state]));
            line(&out, "%s", row.data);
            free(row.data);
        }
        double bic = s->likelihoods[v] -
                     (double)s->parameter_counts[v] * log((double)s->input->sample_count) / 2;
        line(&out, "loglik %s parameters %lld bic %s", real(s->likelihoods[v]),
             V(s->parameter_counts[v]), real(bic));
        Posterior model = posterior(s, one(v), (Evidence){0});
        row = (Text){0};
        text(&row, "marginal model");
        for (int state = 0; state < s->network->sizes[v]; ++state)
            text(&row, " %s", real(model.result.marginals[v][state]));
        text(&row, " data");
        for (int state = 0; state < s->network->sizes[v]; ++state) {
            I count = 0;
            for (int r = 0; r < s->counts[v].rows; ++r)
                count += s->counts[v].values[r][state];
            text(&row, " %s", real((double)count / s->input->sample_count));
        }
        line(&out, "%s", row.data);
        free(row.data);
        if (!s->p.sources[v]) {
            char *difference = "-";
            if (s->network->has_expert[v]) {
                double maximum = 0;
                for (int r = 0; r < s->learned[v].rows; ++r)
                    for (int state = 0; state < s->network->sizes[v]; ++state) {
                        double change = fabs(s->learned[v].values[r][state] -
                                             s->network->expert[v].values[r][state]);
                        if (change > maximum)
                            maximum = change;
                    }
                difference = real(maximum);
            }
            line(&out, "given_difference %s", difference);
        }
        line(&out, "");
        likelihood += s->likelihoods[v];
        parameters += s->parameter_counts[v];
    }
    line(&out, "network samples %d pseudocount %s loglik %s parameters %lld bic %s",
         s->input->sample_count, real(s->p.alpha), real(likelihood), V(parameters),
         real(likelihood - (double)parameters * log((double)s->input->sample_count) / 2));
    return out;
}
static Lines structure_summary(const Study *s) {
    Plan orders[2];
    plans(s, &s->factors, &s->variables, orders);
    int widths[2] = {0};
    for (int method = 0; method < 2; ++method)
        for (int i = 0; i < orders[method].count; ++i)
            if (orders[method].steps[i].scope.count - 1 > widths[method])
                widths[method] = orders[method].steps[i].scope.count - 1;
    Graph graph = interaction_graph(&s->factors);
    int moral_edges = 0, edges = 0;
    Vars roots = {0}, leaves = {0};
    for (int v = 0; v < s->network->count; ++v) {
        edges += s->network->parents[v].count;
        if (!s->network->parents[v].count)
            roots.values[roots.count++] = v;
        if (!s->children[v].count)
            leaves.values[leaves.count++] = v;
        for (int w = v + 1; w < s->network->count; ++w)
            moral_edges += (graph.neighbors[v] & (1u << w)) != 0;
    }
    Lines out = {0};
    line(&out, "variables %d edges %d", s->network->count, edges);
    line(&out, "topological_order %s", sequence(s, s->topological));
    line(&out, "roots %s", sequence(s, roots));
    line(&out, "leaves %s", sequence(s, leaves));
    line(&out, "moral_edges %d width minfill %d given %d", moral_edges, widths[0], widths[1]);
    for (int v = 0; v < s->network->count; ++v)
        line(
            &out,
            "variable %s states %d parents %d children %d depth %d ancestors %d descendants %d blanket %d",
            s->network->names[v], s->network->sizes[v], s->network->parents[v].count,
            s->children[v].count, s->depths[v], s->ancestors[v].count, s->descendants[v].count,
            s->blankets[v].count);
    return out;
}
static void save(const char *name, const Lines *lines) {
    char *path = format("output/%s", name);
    FILE *out = fopen(path, "w");
    for (int i = 0; i < lines->count; ++i)
        fprintf(out, "%s\n", lines->values[i]);
    fclose(out);
    free(path);
}
int main(void) {
    Study *s = calloc(1, sizeof(Study));
    initialize(s);
    Lines cpts = cpt_lines(s), answers = {0}, elimination = {0}, structure = structure_summary(s),
          sampling = {0};
    line(&sampling, "query,samples,variable,state,estimate,exact,abs_error");
    for (int number = 0; number < s->input->query_count; ++number) {
        const char *query_line = s->input->queries[number];
        Words fields = words(query_line);
        Lines heading = {0};
        line(&heading, "query %d %s", number + 1, query_line);
        const char *kind = fields.values[0];
        if (!strcmp(kind, "QUERY")) {
            Answer result = answer_query(s, query_parts(s, &fields, 1, fields.count));
            Lines answer = {0}, steps = {0};
            append(&answer, &heading);
            append(&answer, &result.answer);
            append(&steps, &heading);
            append(&steps, &result.elimination);
            block(&answers, &answer);
            block(&elimination, &steps);
        } else if (!strcmp(kind, "MPE")) {
            Answer result = answer_mpe(s, parse_evidence(s, &fields, 1, fields.count));
            Lines answer = {0}, steps = {0};
            append(&answer, &heading);
            append(&answer, &result.answer);
            append(&steps, &heading);
            append(&steps, &result.elimination);
            block(&answers, &answer);
            block(&elimination, &steps);
        } else if (!strcmp(kind, "SAMPLE")) {
            int separator = 1;
            while (strcmp(fields.values[separator], "COUNTS"))
                ++separator;
            Query query = query_parts(s, &fields, 1, separator);
            I counts[5];
            int count = 0;
            for (int i = separator + 1; i < fields.count; ++i)
                counts[count++] = strtoll(fields.values[i], NULL, 10);
            SampleAnswer result = answer_sample(s, number + 1, query, counts, count);
            append(&heading, &result.answer);
            block(&answers, &heading);
            append(&sampling, &result.csv);
        } else if (!strcmp(kind, "PREDICT")) {
            Lines result = answer_predict(s, variable_id(s->network, fields.values[1]));
            append(&heading, &result);
            block(&answers, &heading);
        } else {
            Lines result;
            if (!strcmp(kind, "DSEP")) {
                Vars groups[3] = {{0}};
                int group = 0;
                for (int i = 1; i < fields.count; ++i)
                    if (!strcmp(fields.values[i], "|"))
                        ++group;
                    else
                        groups[group].values[groups[group].count++] =
                            variable_id(s->network, fields.values[i]);
                result = answer_dsep(s, groups[0], groups[1], groups[2]);
            } else if (!strcmp(kind, "BLANKET"))
                result = answer_blanket(s, variable_id(s->network, fields.values[1]));
            else
                result = answer_edge(s, fields.values[1], variable_id(s->network, fields.values[2]),
                                     variable_id(s->network, fields.values[3]));
            append(&heading, &result);
            block(&structure, &heading);
        }
        free(fields.buffer);
    }
    mkdir("output", 0777);
    save("cpts.txt", &cpts);
    save("structure.txt", &structure);
    save("answers.txt", &answers);
    save("elimination.txt", &elimination);
    save("sampling.csv", &sampling);
    return 0;
}
