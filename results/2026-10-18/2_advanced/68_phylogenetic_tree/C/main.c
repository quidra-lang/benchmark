#include "phylogeny.h"
static const char *models[3] = {"P", "JC", "K2P"},
                  *methods[6] = {"NJ_P", "NJ_JC", "NJ_K2P", "ME", "MP", "CONSENSUS"};
typedef struct {
    int model, replicates, maximum_missing, low_sites;
    int64_t seed;
    double saturation;
    char outgroup[21], exhaustive[7][21];
    int exhaustive_count;
} Params;
typedef struct {
    int taxon;
    Mask mask;
    int score, ties;
} Addition;
typedef struct {
    Tree tree;
    int initial, score, evaluated, taxa[16], taxon_count;
    Addition additions[13];
    int addition_count;
} Stepwise;
typedef struct {
    Mask mask;
    int swap;
    double value;
} Move;
typedef struct {
    Tree tree;
    double value;
    int evaluated;
    Move *moves;
    int move_count, move_capacity;
} Search;
typedef struct {
    Tree tree;
    int score;
    double bme;
    char *newick;
    Masks splits;
} ExhaustiveRecord;
typedef struct {
    int taxa[7], taxon_count;
    ExhaustiveRecord *records;
    int record_count, optimal[945], optimal_count, best_score, best_bme, heuristic;
    double second_bme;
    Tree strict;
} Exhaustive;
typedef struct Study {
    Params params;
    Records records;
    char names[16][21];
    char *sequences[16];
    Lines rejected;
    Patterns *patterns;
    int size, length, outgroup, taxa[16], minimum, maximum, minima[300], nj_scores[3];
    Pairs pairs, saturated[3];
    Matrix matrices[3], patristics[3];
    Tree trees[6];
    double site_logs[3][300];
    int support[65536];
    Stepwise initial;
    Search me, mp;
    Reconstruction *reconstruction;
    Exhaustive exhaustive;
    double me_start;
    Lines bootstrap_lines;
} Study;
static int bits(Mask mask) {
    int count = 0;
    while (mask) {
        count += (int)(mask & 1u);
        mask >>= 1;
    }
    return count;
}
static int mask_compare(Mask a, Mask b) {
    for (int t = 0; t < 16; ++t)
        if ((a & (1u << t)) != (b & (1u << t)))
            return a & (1u << t) ? -1 : 1;
    return 0;
}
static int mask_order(const void *left, const void *right) {
    return mask_compare(*(const Mask *)left, *(const Mask *)right);
}
static int has_mask(const Masks *masks, Mask mask) {
    for (int i = 0; i < masks->count; ++i)
        if (masks->values[i] == mask)
            return 1;
    return 0;
}
static void add_mask(Masks *masks, Mask mask) {
    if (!has_mask(masks, mask))
        masks->values[masks->count++] = mask;
}
static int rf(const Masks *a, const Masks *b) {
    int count = 0;
    for (int i = 0; i < a->count; ++i)
        count += !has_mask(b, a->values[i]);
    for (int i = 0; i < b->count; ++i)
        count += !has_mask(a, b->values[i]);
    return count;
}
static Masks splits_of(const Tree *tree, int outgroup) {
    Rooted root = rooted(tree, outgroup);
    return split_set(tree, &root);
}
static void append(Lines *out, const Lines *other) {
    for (int i = 0; i < other->count; ++i)
        line(out, "%s", other->values[i]);
}
static int taxon_id(const Study *s, const char *name) {
    for (int i = 0; i < s->size; ++i)
        if (!strcmp(s->names[i], name))
            return i;
    return -1;
}
static double total(const double *values, int count) {
    double result = 0;
    for (int i = 0; i < count; ++i)
        result += values[i];
    return result;
}
static double square(double value) { return value * value; }
static Params read_parameters(void) {
    Params out = {0};
    FILE *in = fopen("input/params.txt", "r");
    char *value;
    while ((value = read_line(in))) {
        char *key = strtok(value, " "), *token = strtok(NULL, " ");
        if (!strcmp(key, "model")) {
            for (int i = 0; i < 3; ++i)
                if (!strcmp(token, models[i]))
                    out.model = i;
        } else if (!strcmp(key, "outgroup"))
            strcpy(out.outgroup, token);
        else if (!strcmp(key, "replicates"))
            out.replicates = atoi(token);
        else if (!strcmp(key, "seed"))
            out.seed = strtoll(token, NULL, 10);
        else if (!strcmp(key, "max_missing_percent"))
            out.maximum_missing = atoi(token);
        else if (!strcmp(key, "saturation_distance"))
            out.saturation = strtod(token, NULL);
        else if (!strcmp(key, "low_sites"))
            out.low_sites = atoi(token);
        else
            do {
                strcpy(out.exhaustive[out.exhaustive_count++], token);
            } while ((token = strtok(NULL, " ")));
        free(value);
    }
    fclose(in);
    return out;
}
static void likelihood_sites(const Study *s, const Tree *tree, double *out) {
    Rooted root = rooted(tree, s->outgroup);
    double values[300];
    for (int p = 0; p < s->patterns->count; ++p) {
        double partial[32][4] = {{0}};
        for (int i = root.count - 1; i >= 0; --i) {
            int node = root.order[i];
            if (node < s->size) {
                for (int x = 0; x < 4; ++x)
                    partial[node][x] = (s->patterns->encoded[p][node] & (1u << x)) != 0;
            } else
                for (int x = 0; x < 4; ++x) {
                    double product = 1;
                    for (int j = 0; j < root.child_count[node]; ++j) {
                        int child = root.children[node][j];
                        double exponential = exp(-4 * tree->length[node][child] / 3), subtotal = 0;
                        for (int y = 0; y < 4; ++y) {
                            double probability =
                                x == y ? 0.25 + 0.75 * exponential : 0.25 - 0.25 * exponential;
                            subtotal += probability * partial[child][y];
                        }
                        product *= subtotal;
                    }
                    partial[node][x] = product;
                }
        }
        double probability = 0;
        for (int x = 0; x < 4; ++x)
            probability += 0.25 * partial[root.root][x];
        values[p] = log(probability);
    }
    for (int c = 0; c < s->length; ++c)
        out[c] = values[s->patterns->columns[c]];
}
static void initialize(Study *s) {
    s->params = read_parameters();
    s->records = read_fasta();
    s->length = (int)strlen(s->records.values[0].sequence);
    for (int i = 0; i < s->records.count; ++i) {
        Record *record = &s->records.values[i];
        char *reason = NULL;
        for (int j = 0; j < i; ++j)
            if (!strcmp(record->name, s->records.values[j].name)) {
                reason = "duplicate name";
                break;
            }
        if (!reason)
            for (int c = 0; record->sequence[c]; ++c)
                if (!base_set(record->sequence[c])) {
                    reason =
                        format("invalid character %c at column %d", record->sequence[c], c + 1);
                    break;
                }
        if (!reason && (int)strlen(record->sequence) != s->length)
            reason = format("length mismatch %zu", strlen(record->sequence));
        if (!reason) {
            int missing = 0;
            for (int c = 0; record->sequence[c]; ++c)
                missing += record->sequence[c] == '-' || record->sequence[c] == 'N';
            if (100 * missing > s->params.maximum_missing * s->length)
                reason = format("too many missing %d", missing);
        }
        if (reason)
            line(&s->rejected, "REJECT line %d %s %s", record->line, record->name, reason);
        else {
            strcpy(s->names[s->size], record->name);
            s->sequences[s->size++] = record->sequence;
        }
    }
    s->outgroup = taxon_id(s, s->params.outgroup);
    for (int t = 0; t < s->size; ++t)
        s->taxa[t] = t;
    s->patterns = compress_patterns(s->sequences, s->size, s->length);
    int weights[300];
    for (int c = 0; c < s->length; ++c)
        weights[c] = 1;
    s->pairs = all_pairs(s->sequences, s->size, s->length, weights);
    for (int m = 0; m < 3; ++m) {
        s->matrices[m] = build_matrix(&s->pairs, m, s->params.saturation, &s->saturated[m]);
        s->trees[m] = neighbor_joining(&s->matrices[m], s->size, s->taxa, s->size);
        s->patristics[m] = patristic(&s->trees[m]);
        s->nj_scores[m] = score(&s->trees[m], s->patterns, s->outgroup);
        likelihood_sites(s, &s->trees[m], s->site_logs[m]);
    }
}
static Lines summary(Study *s) {
    Lines out = {0};
    line(&out, "INPUT records %d accepted %d rejected %d columns %d", s->records.count, s->size,
         s->rejected.count, s->length);
    append(&out, &s->rejected);
    int columns[300][4] = {{0}}, composition[4] = {0};
    for (int c = 0; c < s->length; ++c)
        for (int t = 0; t < s->size; ++t) {
            int base = base_index(s->sequences[t][c]);
            if (base >= 0)
                ++columns[c][base];
        }
    for (int t = 0; t < s->size; ++t) {
        int counts[4] = {0}, ambiguous = 0, missing = 0, unique = 0;
        for (int c = 0; c < s->length; ++c) {
            char character = s->sequences[t][c];
            int base = base_index(character);
            if (base >= 0) {
                ++counts[base];
                int all = 0;
                for (int b = 0; b < 4; ++b)
                    all += columns[c][b];
                unique += columns[c][base] == 1 && all > 1;
            } else if (character == 'N' || character == '-')
                ++missing;
            else
                ++ambiguous;
        }
        int bases = 0;
        for (int b = 0; b < 4; ++b) {
            bases += counts[b];
            composition[b] += counts[b];
        }
        line(&out, "TAXON %s bases %d ambiguous %d missing %d unique %d gc %s", s->names[t], bases,
             ambiguous, missing, unique, real((double)(counts[1] + counts[2]) / bases, 4));
    }
    Classes classes = classify(s->sequences, s->size, s->length);
    line(&out, "COLUMNS constant %d variable %d informative %d gapped %d empty %d",
         classes.constant, classes.variable, classes.informative, classes.gapped, classes.empty);
    line(&out, "PATTERNS %d", s->patterns->count);
    int all = 0;
    for (int b = 0; b < 4; ++b)
        all += composition[b];
    line(&out, "COMPOSITION A %s C %s G %s T %s", real((double)composition[0] / all, 4),
         real((double)composition[1] / all, 4), real((double)composition[2] / all, 4),
         real((double)composition[3] / all, 4));
    return out;
}
static double bme(const Tree *tree, const Study *s) {
    double value = 0;
    for (int a = 0; a < s->size; ++a)
        if (tree->present[a]) {
            double steps[32];
            paths(tree, a, 1, steps);
            for (int b = a + 1; b < s->size; ++b)
                if (tree->present[b])
                    value += ldexp(s->matrices[s->params.model].values[a][b], 1 - (int)steps[b]);
        }
    return value;
}
static double parsimony_objective(const Tree *tree, const Study *s) {
    return score(tree, s->patterns, s->outgroup);
}
static Stepwise stepwise(const Study *s, const int *taxa, int count) {
    Stepwise out = {0};
    memcpy(out.taxa, taxa, (size_t)count * sizeof(int));
    out.taxon_count = count;
    out.tree = star(s->size, taxa, 3);
    out.initial = out.score = score(&out.tree, s->patterns, s->outgroup);
    for (int i = 3; i < count; ++i) {
        int best = INT_MAX, ties = 0;
        Mask chosen_mask = 0;
        Tree chosen;
        Branches edges = branches(&out.tree, s->outgroup);
        for (int j = 0; j < edges.count; ++j) {
            Branch branch = edges.values[j];
            Tree candidate = insert(&out.tree, branch.first, branch.second, taxa[i]);
            int value = score(&candidate, s->patterns, s->outgroup);
            ++out.evaluated;
            if (value < best) {
                best = value;
                chosen = candidate;
                chosen_mask = branch.mask;
                ties = 1;
            } else if (value == best)
                ++ties;
        }
        out.tree = chosen;
        out.score = best;
        out.additions[out.addition_count++] = (Addition){taxa[i], chosen_mask, best, ties};
    }
    return out;
}
static Search hill_climb(const Study *s, const Tree *start,
                         double (*objective)(const Tree *, const Study *), double value) {
    Search out = {0};
    out.tree = *start;
    out.value = value;
    while (1) {
        int moved = 0;
        Swaps candidates = nni_candidates(&out.tree, s->outgroup);
        for (int i = 0; i < candidates.count; ++i) {
            Swap *candidate = &candidates.values[i];
            double result = objective(&candidate->tree, s);
            ++out.evaluated;
            if (result < out.value) {
                out.tree = candidate->tree;
                out.value = result;
                if (out.move_count == out.move_capacity) {
                    out.move_capacity = out.move_capacity ? out.move_capacity * 2 : 16;
                    out.moves = realloc(out.moves, (size_t)out.move_capacity * sizeof(Move));
                }
                out.moves[out.move_count++] = (Move){candidate->mask, candidate->number, result};
                moved = 1;
                break;
            }
        }
        free(candidates.values);
        if (!moved)
            break;
    }
    return out;
}
static void consensus_fill(Tree *tree, int parent, Mask region, const Masks *clades,
                           const int *taxa, int count) {
    Mask covered = 0;
    for (int i = 0; i < clades->count; ++i) {
        Mask candidate = clades->values[i];
        if (candidate == region || (candidate & region) != candidate)
            continue;
        int maximal = 1;
        for (int j = 0; j < clades->count; ++j) {
            Mask other = clades->values[j];
            if (other != region && candidate != other && (other & region) == other &&
                (candidate & other) == candidate)
                maximal = 0;
        }
        if (maximal) {
            int node = tree_internal(tree);
            connect(tree, parent, node, 0);
            consensus_fill(tree, node, candidate, clades, taxa, count);
            covered |= candidate;
        }
    }
    for (int i = 0; i < count; ++i) {
        int taxon = taxa[i];
        if ((region & (1u << taxon)) && !(covered & (1u << taxon)))
            connect(tree, parent, taxon, 0);
    }
}
static Tree consensus(const Study *s, const int *taxa, int count, const Masks *clades) {
    Tree tree = tree_create(s->size);
    int root = tree_internal(&tree);
    connect(&tree, root, s->outgroup, 0);
    Mask ingroup = 0;
    for (int i = 0; i < count; ++i)
        if (taxa[i] != s->outgroup)
            ingroup |= 1u << taxa[i];
    consensus_fill(&tree, root, ingroup, clades, taxa, count);
    return tree;
}
static Exhaustive exhaustive_search(Study *s, const int *taxa, int count) {
    Exhaustive out = {0};
    memcpy(out.taxa, taxa, (size_t)count * sizeof(int));
    out.taxon_count = count;
    Tree *forest = malloc(sizeof(Tree));
    forest[0] = star(s->size, taxa, 3);
    int forest_count = 1;
    for (int i = 3; i < count; ++i) {
        Tree *expanded = malloc((size_t)forest_count * (size_t)(2 * i - 3) * sizeof(Tree));
        int expanded_count = 0;
        for (int t = 0; t < forest_count; ++t) {
            Branches edges = branches(&forest[t], s->outgroup);
            for (int b = 0; b < edges.count; ++b)
                expanded[expanded_count++] =
                    insert(&forest[t], edges.values[b].first, edges.values[b].second, taxa[i]);
        }
        free(forest);
        forest = expanded;
        forest_count = expanded_count;
    }
    out.records = malloc((size_t)forest_count * sizeof(ExhaustiveRecord));
    out.record_count = forest_count;
    out.best_score = INT_MAX;
    for (int i = 0; i < forest_count; ++i) {
        ExhaustiveRecord *r = &out.records[i];
        r->tree = forest[i];
        r->score = score(&r->tree, s->patterns, s->outgroup);
        r->bme = bme(&r->tree, s);
        r->newick = newick(&r->tree, s->names, s->outgroup, 0, NULL);
        r->splits = splits_of(&r->tree, s->outgroup);
        if (r->score < out.best_score)
            out.best_score = r->score;
    }
    free(forest);
    for (int i = 0; i < out.record_count; ++i)
        if (out.records[i].score == out.best_score)
            out.optimal[out.optimal_count++] = i;
    for (int i = 1; i < out.optimal_count; ++i) {
        int index = out.optimal[i], j = i;
        while (j > 0 &&
               strcmp(out.records[out.optimal[j - 1]].newick, out.records[index].newick) > 0) {
            out.optimal[j] = out.optimal[j - 1];
            --j;
        }
        out.optimal[j] = index;
    }
    Masks common = out.records[out.optimal[0]].splits;
    for (int i = 0; i < out.optimal_count; ++i) {
        Masks retained = {0};
        for (int j = 0; j < common.count; ++j)
            if (has_mask(&out.records[out.optimal[i]].splits, common.values[j]))
                add_mask(&retained, common.values[j]);
        common = retained;
    }
    out.strict = consensus(s, taxa, count, &common);
    Stepwise initial = stepwise(s, taxa, count);
    Search search = hill_climb(s, &initial.tree, parsimony_objective, initial.score);
    out.heuristic = (int)search.value;
    free(search.moves);
    for (int i = 1; i < out.record_count; ++i) {
        ExhaustiveRecord *a = &out.records[i], *b = &out.records[out.best_bme];
        if (a->bme < b->bme || (a->bme == b->bme && strcmp(a->newick, b->newick) < 0))
            out.best_bme = i;
    }
    out.second_bme = INFINITY;
    for (int i = 0; i < out.record_count; ++i)
        if (i != out.best_bme && out.records[i].bme < out.second_bme)
            out.second_bme = out.records[i].bme;
    return out;
}
static void bounds(Study *s) {
    int lower[300];
    for (int i = 0; i < s->patterns->count; ++i) {
        unsigned *pattern = s->patterns->encoded[i];
        int low = 4, high = s->size;
        for (Mask mask = 1; mask < 16; ++mask) {
            int covers = 1;
            for (int t = 0; t < s->size; ++t)
                if (!(mask & pattern[t]))
                    covers = 0;
            if (covers && bits(mask) - 1 < low)
                low = bits(mask) - 1;
        }
        for (int b = 0; b < 4; ++b) {
            int misses = 0;
            for (int t = 0; t < s->size; ++t)
                misses += !(pattern[t] & (1u << b));
            if (misses < high)
                high = misses;
        }
        lower[i] = low;
        s->maximum += high * s->patterns->weights[i];
    }
    for (int c = 0; c < s->length; ++c) {
        s->minima[c] = lower[s->patterns->columns[c]];
        s->minimum += s->minima[c];
    }
}
typedef struct {
    Mask mask;
    int count;
} Support;
static int support_order(const void *left, const void *right) {
    const Support *a = left, *b = right;
    return a->count != b->count ? b->count - a->count : mask_compare(a->mask, b->mask);
}
static void bootstrap(Study *s) {
    Masks main = splits_of(&s->trees[s->params.model], s->outgroup);
    int64_t state = s->params.seed;
    line(&s->bootstrap_lines, "BOOTSTRAP model %s replicates %d seed %lld", models[s->params.model],
         s->params.replicates, (long long)state);
    int identical = 0;
    for (int b = 1; b <= s->params.replicates; ++b) {
        int weights[300] = {0};
        for (int draw = 0; draw < s->length; ++draw) {
            state = (48271 * state) % 2147483647;
            ++weights[state % s->length];
        }
        Pairs pairs = all_pairs(s->sequences, s->size, s->length, weights), saturated;
        Matrix matrix = build_matrix(&pairs, s->params.model, s->params.saturation, &saturated);
        Tree tree = neighbor_joining(&matrix, s->size, s->taxa, s->size);
        Masks splits = splits_of(&tree, s->outgroup);
        for (int i = 0; i < splits.count; ++i)
            ++s->support[splits.values[i]];
        int difference = rf(&main, &splits), distinct = 0;
        identical += difference == 0;
        for (int c = 0; c < s->length; ++c)
            distinct += weights[c] > 0;
        line(&s->bootstrap_lines, "REPLICATE %d distinct %d rf %d", b, distinct, difference);
    }
    line(&s->bootstrap_lines, "IDENTICAL %d", identical);
    qsort(main.values, (size_t)main.count, sizeof(Mask), mask_order);
    for (int i = 0; i < main.count; ++i)
        line(&s->bootstrap_lines, "SUPPORT %s %d", symbols(main.values[i], s->size),
             s->support[main.values[i]]);
    Support ranked[650];
    int ranked_count = 0;
    Masks majority = {0};
    for (Mask mask = 0; mask < (1u << s->size); ++mask)
        if (s->support[mask]) {
            ranked[ranked_count++] = (Support){mask, s->support[mask]};
            if (2 * s->support[mask] > s->params.replicates)
                add_mask(&majority, mask);
        }
    qsort(ranked, (size_t)ranked_count, sizeof(Support), support_order);
    for (int i = 0; i < ranked_count; ++i)
        line(&s->bootstrap_lines, "SPLIT %s %d", symbols(ranked[i].mask, s->size), ranked[i].count);
    s->trees[5] = consensus(s, s->taxa, s->size, &majority);
    line(&s->bootstrap_lines, "CONSENSUS %s",
         newick(&s->trees[5], s->names, s->outgroup, 0, s->support));
    for (int removed = 0; removed < s->size; ++removed)
        if (removed != s->outgroup) {
            int kept[16], count = 0;
            for (int t = 0; t < s->size; ++t)
                if (t != removed)
                    kept[count++] = t;
            Tree tree = neighbor_joining(&s->matrices[s->params.model], s->size, kept, count);
            Masks reduced = {0}, splits = splits_of(&tree, s->outgroup);
            for (int i = 0; i < main.count; ++i) {
                Mask after = main.values[i] & ~(1u << removed);
                if (bits(after) >= 2 && bits(after) <= s->size - 3)
                    add_mask(&reduced, after);
            }
            line(&s->bootstrap_lines, "JACKKNIFE %s rf %d", s->names[removed],
                 rf(&splits, &reduced));
        }
}
static void matrix_lines(Lines *out, const Study *s, const Matrix *matrix) {
    int width = 0;
    for (int t = 0; t < s->size; ++t)
        if ((int)strlen(s->names[t]) > width)
            width = (int)strlen(s->names[t]);
    for (int a = 0; a < s->size; ++a) {
        Text row = {0};
        text(&row, "%-*s", width, s->names[a]);
        for (int b = 0; b < s->size; ++b)
            text(&row, " %s", real(matrix->values[a][b], 5));
        line(out, "%s", row.data);
        free(row.data);
    }
}
static Lines distances_report(const Study *s) {
    Lines out = {0};
    int sites = 0, transitions = 0, transversions = 0;
    for (int i = 0; i < s->pairs.count; ++i) {
        Pair p = s->pairs.values[i];
        line(&out, "PAIR %s %s sites %d transitions %d transversions %d", s->names[p.first],
             s->names[p.second], p.sites, p.transitions, p.transversions);
        sites += p.sites;
        transitions += p.transitions;
        transversions += p.transversions;
    }
    line(&out, "TOTAL sites %d transitions %d transversions %d", sites, transitions, transversions);
    for (int model = 0; model < 3; ++model) {
        line(&out, "");
        line(&out, "MODEL %s", models[model]);
        matrix_lines(&out, s, &s->matrices[model]);
        for (int i = 0; i < s->saturated[model].count; ++i) {
            Pair p = s->saturated[model].values[i];
            line(&out, "SATURATED %s %s sites %d", s->names[p.first], s->names[p.second], p.sites);
        }
    }
    line(&out, "");
    line(&out, "PATRISTIC %s", methods[s->params.model]);
    matrix_lines(&out, s, &s->patristics[s->params.model]);
    line(&out, "");
    line(&out, "ME start %s length %s", methods[s->params.model], real(s->me_start, 5));
    for (int i = 0; i < s->me.move_count; ++i) {
        Move move = s->me.moves[i];
        line(&out, "NNI edge %s swap %d length %s", symbols(move.mask, s->size), move.swap,
             real(move.value, 5));
    }
    line(&out, "ME moves %d evaluated %d length %s", s->me.move_count, s->me.evaluated,
         real(s->me.value, 5));
    ExhaustiveRecord *best = &s->exhaustive.records[s->exhaustive.best_bme];
    line(&out, "EXHAUSTIVE taxa %d trees %d best %s second %s", s->exhaustive.taxon_count,
         s->exhaustive.record_count, real(best->bme, 5), real(s->exhaustive.second_bme, 5));
    line(&out, "BEST %s parsimony %d", best->newick, best->score);
    return out;
}
static void score_line(Lines *out, const Study *s, const char *method, int score) {
    line(out, "TREE %s score %d ci %s ri %s", method, score, real((double)s->minimum / score, 4),
         real((double)(s->maximum - score) / (s->maximum - s->minimum), 4));
}
static Lines parsimony_report(Study *s) {
    Lines out = {0};
    line(&out, "BOUNDS minimum %d maximum %d", s->minimum, s->maximum);
    for (int i = 0; i < 3; ++i)
        score_line(&out, s, methods[i], s->nj_scores[i]);
    line(&out, "START %s %s %s score %d", s->names[s->initial.taxa[0]],
         s->names[s->initial.taxa[1]], s->names[s->initial.taxa[2]], s->initial.initial);
    for (int i = 0; i < s->initial.addition_count; ++i) {
        Addition add = s->initial.additions[i];
        line(&out, "ADD %s edge %s score %d ties %d", s->names[add.taxon],
             symbols(add.mask, s->size), add.score, add.ties);
    }
    line(&out, "STEPWISE score %d evaluated %d", s->initial.score, s->initial.evaluated);
    for (int i = 0; i < s->mp.move_count; ++i) {
        Move move = s->mp.moves[i];
        line(&out, "NNI edge %s swap %d score %d", symbols(move.mask, s->size), move.swap,
             (int)move.value);
    }
    line(&out, "SEARCH moves %d evaluated %d score %d", s->mp.move_count, s->mp.evaluated,
         (int)s->mp.value);
    score_line(&out, s, "MP", (int)s->mp.value);
    line(&out, "MP %s", newick(&s->trees[4], s->names, s->outgroup, 1, NULL));
    int histogram[16] = {0}, largest = 0, homoplasy = 0;
    for (int c = 0; c < s->length; ++c) {
        int changes = s->reconstruction->sites[c];
        ++histogram[changes];
        if (changes > largest)
            largest = changes;
        homoplasy += changes > s->minima[c];
    }
    for (int i = 0; i <= largest; ++i)
        line(&out, "CHANGES %d columns %d", i, histogram[i]);
    line(&out, "HOMOPLASY columns %d extra %d", homoplasy, (int)s->mp.value - s->minimum);
    Rooted root = rooted(&s->trees[4], s->outgroup);
    Masks ancestral = {0};
    int nodes[32];
    for (int node = s->size; node < s->trees[4].next; ++node) {
        Mask mask = node == root.root ? root.ingroup : root.masks[node];
        int index = ancestral.count;
        while (index > 0 && mask_compare(ancestral.values[index - 1], mask) > 0) {
            ancestral.values[index] = ancestral.values[index - 1];
            nodes[index] = nodes[index - 1];
            --index;
        }
        ancestral.values[index] = mask;
        nodes[index] = node;
        ++ancestral.count;
    }
    for (int i = 0; i < ancestral.count; ++i)
        line(&out, "ANCESTOR %s %s", symbols(ancestral.values[i], s->size),
             s->reconstruction->ancestors[nodes[i]]);
    line(&out, "");
    Exhaustive *ex = &s->exhaustive;
    line(&out, "EXHAUSTIVE taxa %d trees %d best %d optimal %d", ex->taxon_count, ex->record_count,
         ex->best_score, ex->optimal_count);
    int scores[4501] = {0};
    for (int i = 0; i < ex->record_count; ++i)
        ++scores[ex->records[i].score];
    for (int value = 0; value <= 4500; ++value)
        if (scores[value])
            line(&out, "SCORE %d trees %d", value, scores[value]);
    for (int i = 0; i < ex->optimal_count; ++i) {
        ExhaustiveRecord *record = &ex->records[ex->optimal[i]];
        line(&out, "OPTIMAL %s bme %s", record->newick, real(record->bme, 5));
    }
    line(&out, "STRICT %s", newick(&ex->strict, s->names, s->outgroup, 0, NULL));
    line(&out, "HEURISTIC score %d optimal %s", ex->heuristic,
         ex->heuristic == ex->best_score ? "yes" : "no");
    return out;
}
static Lines likelihood_report(const Study *s) {
    Lines out = {0};
    line(&out, "LIKELIHOOD columns %d patterns %d", s->length, s->patterns->count);
    for (int i = 0; i < 3; ++i) {
        double sum = total(s->site_logs[i], s->length);
        line(&out, "TREE %s loglik %s per_site %s", methods[i], real(sum, 4),
             real(sum / s->length, 4));
    }
    for (int a = 0; a < 3; ++a)
        for (int b = a + 1; b < 3; ++b) {
            double deltas[300];
            for (int c = 0; c < s->length; ++c)
                deltas[c] = s->site_logs[a][c] - s->site_logs[b][c];
            double difference = total(deltas, s->length), average = difference / s->length,
                   squares = 0;
            for (int c = 0; c < s->length; ++c)
                squares += square(deltas[c] - average);
            double error = sqrt((double)s->length / (s->length - 1) * squares);
            line(&out, "KH %s %s difference %s se %s z %s", methods[a], methods[b],
                 real(difference, 4), real(error, 4), real(difference / error, 4));
        }
    int order[300], changes[300];
    double rounded[300];
    for (int c = 0; c < s->length; ++c) {
        order[c] = c;
        rounded[c] = strtod(real(s->site_logs[s->params.model][c], 4), NULL);
    }
    for (int i = 1; i < s->length; ++i) {
        int column = order[i], j = i;
        while (j > 0 && (rounded[order[j - 1]] > rounded[column] ||
                         (rounded[order[j - 1]] == rounded[column] && order[j - 1] > column))) {
            order[j] = order[j - 1];
            --j;
        }
        order[j] = column;
    }
    pattern_scores(&s->trees[s->params.model], s->patterns, s->outgroup, changes);
    line(&out, "LOWEST %s sites %d", methods[s->params.model], s->params.low_sites);
    for (int i = 0; i < s->params.low_sites; ++i) {
        int c = order[i], p = s->patterns->columns[c];
        line(&out, "SITE %d loglik %s changes %d pattern %s", c + 1,
             real(s->site_logs[s->params.model][c], 4), changes[p], s->patterns->text[p]);
    }
    return out;
}
static Lines clock_report(const Study *s) {
    Lines pairs = {0}, out = {0};
    int rejected = 0;
    for (int a = 0; a < s->size; ++a)
        if (a != s->outgroup)
            for (int b = a + 1; b < s->size; ++b)
                if (b != s->outgroup) {
                    int m1 = 0, m2 = 0;
                    for (int c = 0; c < s->length; ++c) {
                        char x = s->sequences[a][c], y = s->sequences[b][c],
                             o = s->sequences[s->outgroup][c];
                        if (base_index(x) >= 0 && base_index(y) >= 0 && base_index(o) >= 0 &&
                            x != y) {
                            m1 += y == o;
                            m2 += x == o;
                        }
                    }
                    int difference = m1 - m2,
                        reject = 1000 * difference * difference > 3841 * (m1 + m2);
                    rejected += reject;
                    line(&pairs, "RRT %s %s m1 %d m2 %d chi2 %s %s", s->names[a], s->names[b], m1,
                         m2, m1 + m2 ? real((double)(difference * difference) / (m1 + m2), 4) : "-",
                         reject ? "reject" : "ok");
                }
    line(&out, "RELATIVE_RATE outgroup %s pairs %d rejected %d", s->names[s->outgroup], pairs.count,
         rejected);
    append(&out, &pairs);
    const Tree *tree = &s->trees[s->params.model];
    Rooted root = rooted(tree, s->outgroup);
    double distances[32];
    paths(tree, root.root, 0, distances);
    double average = 0;
    for (int t = 0; t < s->size; ++t)
        if (t != s->outgroup)
            average += distances[t];
    average /= s->size - 1;
    double deviation = 0;
    for (int t = 0; t < s->size; ++t)
        if (t != s->outgroup)
            deviation += square(distances[t] - average);
    deviation = sqrt(deviation / (s->size - 2));
    line(&out, "ROOT_TO_TIP %s mean %s sd %s cv %s", methods[s->params.model], real(average, 5),
         real(deviation, 5), real(deviation / average, 4));
    for (int t = 0; t < s->size; ++t)
        if (t != s->outgroup)
            line(&out, "TIP %s %s", s->names[t], real(distances[t], 5));
    return out;
}
static int quartet_topologies(const Masks *splits, int size, int *out) {
    int count = 0;
    for (int a = 0; a < size; ++a)
        for (int b = a + 1; b < size; ++b)
            for (int c = b + 1; c < size; ++c)
                for (int d = c + 1; d < size; ++d) {
                    Mask quartet = (1u << a) | (1u << b) | (1u << c) | (1u << d);
                    int topology = 0, others[3] = {b, c, d};
                    for (int i = 0; i < 3; ++i) {
                        Mask side = (1u << a) | (1u << others[i]);
                        for (int j = 0; j < splits->count; ++j) {
                            Mask intersection = splits->values[j] & quartet;
                            if (intersection == side || intersection == (quartet ^ side)) {
                                topology = i + 1;
                                break;
                            }
                        }
                        if (topology)
                            break;
                    }
                    out[count++] = topology;
                }
    return count;
}
static Lines comparison_report(const Study *s) {
    Lines out = {0};
    Masks splits[6], all = {0};
    int topologies[6][1820], quartet_count = 0;
    for (int i = 0; i < 6; ++i) {
        const Tree *tree = &s->trees[i];
        splits[i] = splits_of(tree, s->outgroup);
        quartet_count = quartet_topologies(&splits[i], s->size, topologies[i]);
        int supported = 0;
        for (int j = 0; j < splits[i].count; ++j) {
            Mask mask = splits[i].values[j];
            add_mask(&all, mask);
            supported += 2 * s->support[mask] > s->params.replicates;
        }
        char *parsimony = "-", *balanced = "-", *length = "-", *negative = "-", *residual = "-",
             *likelihood = "-";
        if (i != 5) {
            int value = i < 3    ? s->nj_scores[i]
                        : i == 4 ? (int)s->mp.value
                                 : score(tree, s->patterns, s->outgroup);
            parsimony = format("%d", value);
            balanced = real(bme(tree, s), 5);
        }
        if (i < 3) {
            double sum = 0, error = 0;
            Branches edges = branches(tree, s->outgroup);
            for (int j = 0; j < edges.count; ++j)
                sum += tree->length[edges.values[j].first][edges.values[j].second];
            for (int a = 0; a < s->size; ++a)
                for (int b = a + 1; b < s->size; ++b)
                    error += square(s->matrices[i].values[a][b] - s->patristics[i].values[a][b]);
            length = real(sum, 5);
            negative = format("%d", tree->negative);
            residual = real(error, 6);
            likelihood = real(total(s->site_logs[i], s->length), 4);
        } else if (i == 4)
            length = real(s->mp.value / s->length, 5);
        line(
            &out,
            "TREE %s splits %d supported %d parsimony %s bme %s length %s negative %s sse %s loglik %s",
            methods[i], splits[i].count, supported, parsimony, balanced, length, negative, residual,
            likelihood);
    }
    for (int type = 0; type < 2; ++type) {
        Text heading = {0};
        text(&heading, "%s", type ? "QUARTET" : "RF");
        for (int i = 0; i < 6; ++i)
            text(&heading, " %s", methods[i]);
        line(&out, "%s", heading.data);
        for (int a = 0; a < 6; ++a) {
            Text row = {0};
            text(&row, "%s", methods[a]);
            for (int b = 0; b < 6; ++b) {
                int difference = 0;
                if (type) {
                    for (int q = 0; q < quartet_count; ++q)
                        difference += topologies[a][q] != topologies[b][q];
                } else
                    difference = rf(&splits[a], &splits[b]);
                text(&row, " %d", difference);
            }
            line(&out, "%s", row.data);
            free(row.data);
        }
        free(heading.data);
    }
    double lengths[65536];
    unsigned char has_length[65536] = {0};
    int changes[65536];
    unsigned char has_change[65536] = {0};
    const Tree *main = &s->trees[s->params.model];
    Rooted root = rooted(main, s->outgroup);
    for (int i = 1; i < root.count; ++i) {
        int node = root.order[i];
        Mask mask = node == s->outgroup ? root.ingroup : root.masks[node];
        lengths[mask] = main->length[node][root.parent[node]];
        has_length[mask] = 1;
    }
    Branches edges = branches(&s->trees[4], s->outgroup);
    for (int i = 0; i < edges.count; ++i) {
        Branch edge = edges.values[i];
        int a = edge.first < edge.second ? edge.first : edge.second,
            b = edge.first < edge.second ? edge.second : edge.first;
        changes[edge.mask] = s->reconstruction->changes[a][b];
        has_change[edge.mask] = 1;
    }
    qsort(all.values, (size_t)all.count, sizeof(Mask), mask_order);
    for (int j = 0; j < all.count; ++j) {
        Mask mask = all.values[j];
        char marks[7];
        for (int i = 0; i < 6; ++i)
            marks[i] = has_mask(&splits[i], mask) ? '+' : '-';
        marks[6] = 0;
        line(&out, "CLADE %s support %d trees %s length %s changes %s", symbols(mask, s->size),
             s->support[mask], marks, has_length[mask] ? real(lengths[mask], 5) : "-",
             has_change[mask] ? format("%d", changes[mask]) : "-");
    }
    return out;
}
static Lines hypotheses_report(Study *s) {
    Lines out = {0};
    Masks splits[6];
    for (int i = 0; i < 6; ++i)
        splits[i] = splits_of(&s->trees[i], s->outgroup);
    Mask ingroup = ((1u << s->size) - 1) ^ (1u << s->outgroup), exhaustive_ingroup = 0;
    for (int i = 0; i < s->exhaustive.taxon_count; ++i)
        if (s->exhaustive.taxa[i] != s->outgroup)
            exhaustive_ingroup |= 1u << s->exhaustive.taxa[i];
    FILE *in = fopen("input/clades.txt", "r");
    char *value;
    while ((value = read_line(in))) {
        char *hypothesis = strtok(value, " "), *name, *unknown = NULL;
        Mask mask = 0;
        while ((name = strtok(NULL, " "))) {
            int t = taxon_id(s, name);
            if (t < 0) {
                if (!unknown)
                    unknown = name;
            } else
                mask |= 1u << t;
        }
        if (unknown) {
            line(&out, "INVALID %s unknown taxon %s", hypothesis, unknown);
            free(value);
            continue;
        }
        if (mask & (1u << s->outgroup)) {
            line(&out, "INVALID %s contains outgroup", hypothesis);
            free(value);
            continue;
        }
        line(&out, "CLADE %s taxa %d support %d", hypothesis, bits(mask), s->support[mask]);
        for (int i = 0; i < 6; ++i) {
            Mask common = ingroup;
            for (int j = 0; j < splits[i].count; ++j) {
                Mask clade = splits[i].values[j];
                if ((clade & mask) == mask && bits(clade) < bits(common))
                    common = clade;
            }
            Text intruders = {0};
            for (int t = 0; t < s->size; ++t)
                if ((common & ~mask) & (1u << t))
                    text(&intruders, "%s%s", intruders.length ? "," : "", s->names[t]);
            line(&out, "TEST %s %s monophyletic %s mrca %d intruders %s", hypothesis, methods[i],
                 common == mask ? "yes" : "no", bits(common),
                 intruders.length ? intruders.data : "-");
            free(intruders.data);
        }
        Mask subset = mask & exhaustive_ingroup;
        if (bits(subset) < 2 || bits(subset) >= bits(exhaustive_ingroup))
            line(&out, "SUBSET %s untestable", hypothesis);
        else {
            int scores[2] = {INT_MAX, INT_MAX};
            double balanced[2] = {INFINITY, INFINITY};
            for (int i = 0; i < s->exhaustive.record_count; ++i) {
                ExhaustiveRecord *record = &s->exhaustive.records[i];
                int side = has_mask(&record->splits, subset) ? 0 : 1;
                if (record->score < scores[side])
                    scores[side] = record->score;
                if (record->bme < balanced[side])
                    balanced[side] = record->bme;
            }
            line(&out, "SUBSET %s taxa %d with %d without %d bme_with %s bme_without %s",
                 hypothesis, bits(subset), scores[0], scores[1], real(balanced[0], 5),
                 real(balanced[1], 5));
        }
        free(value);
    }
    fclose(in);
    return out;
}
int main(void) {
    Study *s = calloc(1, sizeof(Study));
    initialize(s);
    s->me_start = bme(&s->trees[s->params.model], s);
    s->me = hill_climb(s, &s->trees[s->params.model], bme, s->me_start);
    s->trees[3] = s->me.tree;
    int order[16], count = 0;
    order[count++] = s->outgroup;
    for (int t = 0; t < s->size; ++t)
        if (t != s->outgroup)
            order[count++] = t;
    s->initial = stepwise(s, order, count);
    s->mp = hill_climb(s, &s->initial.tree, parsimony_objective, s->initial.score);
    s->trees[4] = s->mp.tree;
    s->reconstruction = reconstruct(&s->trees[4], s->patterns, s->outgroup);
    for (int a = 0; a < s->trees[4].next; ++a)
        for (int b = a + 1; b < s->trees[4].next; ++b)
            if (s->trees[4].adjacent[a][b])
                connect(&s->trees[4], a, b, (double)s->reconstruction->changes[a][b] / s->length);
    bounds(s);
    int exhaustive_taxa[7], exhaustive_count = 0;
    exhaustive_taxa[exhaustive_count++] = s->outgroup;
    for (int t = 0; t < s->size; ++t)
        if (t != s->outgroup)
            for (int i = 0; i < s->params.exhaustive_count; ++i)
                if (!strcmp(s->names[t], s->params.exhaustive[i]))
                    exhaustive_taxa[exhaustive_count++] = t;
    s->exhaustive = exhaustive_search(s, exhaustive_taxa, exhaustive_count);
    bootstrap(s);
    Lines newicks = {0}, diagrams = {0};
    for (int i = 0; i < 6; ++i) {
        line(&newicks, "%s %s", methods[i],
             newick(&s->trees[i], s->names, s->outgroup, i < 3 || i == 4,
                    i == 5 ? s->support : NULL));
        if (i)
            line(&diagrams, "");
        line(&diagrams, "TREE %s", methods[i]);
        Lines drawing = cladogram(&s->trees[i], s->names, s->outgroup, s->support);
        append(&diagrams, &drawing);
    }
    mkdir("output", 0777);
    Lines summary_lines = summary(s), distance_lines = distances_report(s),
          parsimony_lines = parsimony_report(s), likelihood_lines = likelihood_report(s),
          clock_lines = clock_report(s), comparison_lines = comparison_report(s),
          hypothesis_lines = hypotheses_report(s);
    save("summary.txt", &summary_lines);
    save("distances.txt", &distance_lines);
    save("trees.nwk", &newicks);
    save("cladograms.txt", &diagrams);
    save("parsimony.txt", &parsimony_lines);
    save("likelihood.txt", &likelihood_lines);
    save("bootstrap.txt", &s->bootstrap_lines);
    save("clock.txt", &clock_lines);
    save("comparison.txt", &comparison_lines);
    save("hypotheses.txt", &hypothesis_lines);
    return 0;
}
