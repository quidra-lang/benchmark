#include "aligner.h"
#define V(value) ((long long)(value))
static const char bases[] = "ACGT", observed_bases[] = "ACGTN", alphabet[] = "$#ACGT";
static int smaller(int a, int b) { return a < b ? a : b; }
static int larger(int a, int b) { return a > b ? a : b; }
static void append(Lines *out, const Lines *other) {
    for (int i = 0; i < other->count; ++i)
        line(out, "%s", other->values[i]);
}
static Params parameters(const Input *in) {
    Params p = {0};
    p.mismatches = in->parameters[0][0];
    p.minimum_length = in->parameters[1][0];
    p.trim_quality = in->parameters[2][0];
    p.seed_length = in->parameters[3][0];
    p.seed_step = in->parameters[4][0];
    p.maximum_seed_hits = in->parameters[5][0];
    p.band_width = in->parameters[6][0];
    p.match = in->parameters[7][0];
    p.mismatch = in->parameters[7][1];
    p.gap_open = in->parameters[7][2];
    p.gap_extend = in->parameters[7][3];
    p.minimum_score = in->parameters[8][0];
    p.maximum_alternatives = in->parameters[9][0];
    p.occ_interval = in->parameters[10][0];
    p.sample_interval = in->parameters[11][0];
    p.direct_limit = in->parameters[12][0];
    p.coverage_window = in->parameters[13][0];
    p.coverage_mapq = in->parameters[14][0];
    p.variant_depth = in->parameters[15][0];
    p.variant_quality = in->parameters[15][1];
    p.variant_percent = in->parameters[15][2];
    p.homozygous_percent = in->parameters[15][3];
    return p;
}
typedef struct {
    const Input *input;
    char *text, *reverse;
    int offsets[10], size;
} ReferenceText;
static ReferenceText reference_text(const Input *input) {
    ReferenceText out = {0};
    out.input = input;
    Text text_value = {0};
    for (int r = 0; r < input->reference_count; ++r) {
        out.offsets[r] = (int)text_value.length;
        text(&text_value, "%s#", input->references[r].bases);
    }
    out.text = text_value.data;
    out.size = (int)text_value.length;
    out.text[out.size - 1] = '$';
    out.reverse = malloc((size_t)out.size + 1);
    for (int i = 0; i < out.size - 1; ++i)
        out.reverse[i] = out.text[out.size - i - 2];
    out.reverse[out.size - 1] = '$';
    out.reverse[out.size] = 0;
    return out;
}
static int text_position(const ReferenceText *reference, int position, int *offset) {
    int r = reference->input->reference_count - 1;
    while (r > 0 && reference->offsets[r] > position)
        --r;
    *offset = position - reference->offsets[r];
    return *offset < reference->input->references[r].length ? r : -1;
}
static char *position_label(const ReferenceText *reference, int position) {
    int offset, r = text_position(reference, position, &offset);
    return r < 0 ? "*" : format("%s:%d", reference->input->references[r].name, offset + 1);
}
static Alignment describe(int r, int position, int strand, const char *operations,
                          const Result *result, const Input *input) {
    Alignment out = {0};
    out.reference = r;
    out.position = position;
    out.strand = strand;
    out.operations = format("%s", operations);
    out.oriented = strand ? reverse_complement(result->core) : result->core;
    out.pairs = malloc((size_t)result->length * sizeof(AlignedPair));
    const char *sequence = input->references[r].bases;
    int i = 0, j = position, matches = 0;
    Text cigar = {0}, md = {0};
    for (int start = 0; operations[start];) {
        char operation = operations[start];
        int end = start + 1;
        while (operations[end] == operation)
            ++end;
        int count = end - start;
        text(&cigar, "%d%c", count, operation);
        if (operation == 'I') {
            i += count;
            out.nm += count;
        } else if (operation == 'D') {
            text(&md, "%d^%.*s", matches, count, sequence + j);
            matches = 0;
            j += count;
            out.nm += count;
        } else
            for (int k = 0; k < count; ++k) {
                out.pairs[out.pair_count++] = (AlignedPair){i, j};
                if (out.oriented[i] == sequence[j])
                    ++matches;
                else {
                    text(&md, "%d%c", matches, sequence[j]);
                    matches = 0;
                    ++out.nm;
                }
                ++i;
                ++j;
            }
        start = end;
    }
    text(&md, "%d", matches);
    if (result->trimmed) {
        char *next = strand ? format("%dS%s", result->trimmed, cigar.data)
                            : format("%s%dS", cigar.data, result->trimmed);
        free(cigar.data);
        cigar.data = next;
    }
    out.cigar = cigar.data;
    out.md = md.data;
    return out;
}
static const int unreachable = -1000000;
typedef struct {
    int first, last;
    int *values[3];
} BandRow;
static int cell(const BandRow *row, int state, int column) {
    return column < row->first || column > row->last ? unreachable
                                                     : row->values[state][column - row->first];
}
static int subtract(int value, int penalty) {
    return value == unreachable ? unreachable : value - penalty;
}
typedef struct {
    int exists, score, position;
    char *operations;
} Banded;
static Banded banded_alignment(const char *oriented, const Reference *reference, int center,
                               const Params *p) {
    int length = (int)strlen(oriented), reference_length = reference->length;
    BandRow rows[101];
    for (int i = 0; i <= length; ++i) {
        rows[i].first = larger(0, i + center - p->band_width);
        rows[i].last = smaller(reference_length, i + center + p->band_width);
        int count = larger(0, rows[i].last - rows[i].first + 1);
        for (int state = 0; state < 3; ++state) {
            rows[i].values[state] = malloc((size_t)count * sizeof(int));
            for (int j = 0; j < count; ++j)
                rows[i].values[state][j] = state == 0 && i == 0 ? 0 : unreachable;
        }
    }
    for (int i = 1; i <= length; ++i)
        for (int j = rows[i].first; j <= rows[i].last; ++j) {
            BandRow *row = &rows[i];
            int column = j - row->first;
            row->values[2][column] =
                larger(subtract(cell(&rows[i - 1], 0, j), p->gap_open + p->gap_extend),
                       subtract(cell(&rows[i - 1], 2, j), p->gap_extend));
            int diagonal = unreachable;
            if (j >= 1) {
                row->values[1][column] =
                    larger(subtract(cell(row, 0, j - 1), p->gap_open + p->gap_extend),
                           subtract(cell(row, 1, j - 1), p->gap_extend));
                int previous = cell(&rows[i - 1], 0, j - 1);
                if (previous != unreachable)
                    diagonal =
                        previous +
                        (oriented[i - 1] == reference->bases[j - 1] ? p->match : -p->mismatch);
            }
            row->values[0][column] =
                larger(diagonal, larger(row->values[1][column], row->values[2][column]));
        }
    Banded out = {0};
    out.score = unreachable;
    out.position = -1;
    for (int j = rows[length].first; j <= rows[length].last; ++j) {
        int value = cell(&rows[length], 0, j);
        if (value > out.score) {
            out.score = value;
            out.position = j;
        }
    }
    if (out.position >= 0) {
        int i = length, j = out.position, state = 0;
        Text backward = {0};
        while (1) {
            if (state == 0) {
                if (!i)
                    break;
                int previous = j >= 1 ? cell(&rows[i - 1], 0, j - 1) : unreachable;
                if (previous != unreachable &&
                    cell(&rows[i], 0, j) == previous + (oriented[i - 1] == reference->bases[j - 1]
                                                            ? p->match
                                                            : -p->mismatch)) {
                    text(&backward, "M");
                    --i;
                    --j;
                    continue;
                }
                state = cell(&rows[i], 2, j) != unreachable &&
                                cell(&rows[i], 0, j) == cell(&rows[i], 2, j)
                            ? 1
                            : 2;
            } else if (state == 1) {
                text(&backward, "I");
                int previous = cell(&rows[i - 1], 2, j);
                state = previous != unreachable && cell(&rows[i], 2, j) == previous - p->gap_extend
                            ? 1
                            : 0;
                --i;
            } else {
                text(&backward, "D");
                int previous = cell(&rows[i], 1, j - 1);
                state = previous != unreachable && cell(&rows[i], 1, j) == previous - p->gap_extend
                            ? 2
                            : 0;
                --j;
            }
        }
        for (size_t k = 0; k < backward.length / 2; ++k) {
            char value = backward.data[k];
            backward.data[k] = backward.data[backward.length - k - 1];
            backward.data[backward.length - k - 1] = value;
        }
        out.position = j;
        out.operations = backward.data;
        out.exists = 1;
    }
    for (int i = 0; i <= length; ++i)
        for (int state = 0; state < 3; ++state)
            free(rows[i].values[state]);
    return out;
}
typedef struct {
    I calls, nodes, leaves, positions;
} SearchTotals;
typedef struct {
    I reads, seeds, with_n, repetitive, without_hit, candidates, passing;
} SeedTotals;
typedef struct {
    const Input *input;
    const ReferenceText *reference;
    const Index *forward, *reverse;
    const Params *params;
    SearchTotals searches;
    SeedTotals seeds;
} Mapper;
typedef struct {
    int mismatches, reference, position, strand;
} Hit;
static int hit_order(const void *left, const void *right) {
    const Hit *a = left, *b = right;
    if (a->mismatches != b->mismatches)
        return a->mismatches - b->mismatches;
    if (a->reference != b->reference)
        return a->reference - b->reference;
    if (a->position != b->position)
        return a->position - b->position;
    return a->strand - b->strand;
}
typedef struct {
    int strand, reference, center;
} Candidate;
static int candidate_order(const void *left, const void *right) {
    const Candidate *a = left, *b = right;
    if (a->strand != b->strand)
        return a->strand - b->strand;
    if (a->reference != b->reference)
        return a->reference - b->reference;
    return a->center - b->center;
}
typedef struct {
    int score, reference, position, strand;
    char *operations;
} Accepted;
static int accepted_order(const void *left, const void *right) {
    const Accepted *a = left, *b = right;
    if (a->score != b->score)
        return b->score - a->score;
    if (a->reference != b->reference)
        return a->reference - b->reference;
    if (a->position != b->position)
        return a->position - b->position;
    return a->strand - b->strand;
}
static int locate_reference(const Mapper *mapper, int row, int *offset) {
    int steps, position = locate(mapper->forward, row, &steps);
    return text_position(mapper->reference, position, offset);
}
static Result map_read(Mapper *mapper, const Read *read) {
    const Params *p = mapper->params;
    Result out = {0};
    out.read = *read;
    out.reason = "SHORT";
    out.length = read->length;
    for (int i = 0; i < read->length; ++i)
        out.qualities[i] = (unsigned char)read->quality[i] - 33;
    while (out.length && out.qualities[out.length - 1] < p->trim_quality)
        --out.length;
    out.trimmed = read->length - out.length;
    out.core = format("%.*s", out.length, read->bases);
    if (out.length < p->minimum_length)
        return out;
    char *oriented[2] = {out.core, reverse_complement(out.core)};
    Interval exact[2] = {backward_search(mapper->forward, oriented[0]),
                         backward_search(mapper->forward, oriented[1])};
    int maximum =
        exact[0].lower < exact[0].upper || exact[1].lower < exact[1].upper ? 1 : p->mismatches;
    Hit *hits = NULL;
    int hit_count = 0, hit_capacity = 0;
    for (int strand = 0; strand < 2; ++strand) {
        Search search = backtrack(oriented[strand], maximum, mapper->forward, mapper->reverse);
        ++mapper->searches.calls;
        mapper->searches.nodes += search.nodes;
        mapper->searches.leaves += search.leaf_count;
        mapper->searches.positions += search.positions;
        for (int leaf = 0; leaf < search.leaf_count; ++leaf)
            for (int row = search.leaves[leaf].lower; row < search.leaves[leaf].upper; ++row) {
                int offset, r = locate_reference(mapper, row, &offset);
                if (hit_count == hit_capacity) {
                    hit_capacity = hit_capacity ? hit_capacity * 2 : 128;
                    hits = realloc(hits, (size_t)hit_capacity * sizeof(Hit));
                }
                hits[hit_count++] = (Hit){search.leaves[leaf].mismatches, r, offset, strand};
            }
        free(search.leaves);
    }
    if (hit_count) {
        qsort(hits, (size_t)hit_count, sizeof(Hit), hit_order);
        int best = hits[0].mismatches, eligible = 0;
        for (int i = 0; i < hit_count; ++i) {
            out.x0 += hits[i].mismatches == best;
            out.x1 += hits[i].mismatches == best + 1;
            eligible += hits[i].mismatches <= best + 1;
            if (hits[i].mismatches == best)
                out.targets |= 1u << hits[i].reference;
        }
        char *operations = malloc((size_t)out.length + 1);
        memset(operations, 'M', (size_t)out.length);
        operations[out.length] = 0;
        out.primary = describe(hits[0].reference, hits[0].position, hits[0].strand, operations,
                               &out, mapper->input);
        out.other_count = eligible - 1;
        if (out.other_count <= p->maximum_alternatives) {
            out.others = malloc((size_t)out.other_count * sizeof(Alignment));
            for (int i = 1; i < eligible; ++i)
                out.others[i - 1] = describe(hits[i].reference, hits[i].position, hits[i].strand,
                                             operations, &out, mapper->input);
        }
        out.mapped = 1;
        out.method = best == 0 ? "EXACT" : "MISMATCH";
        out.score = (out.length - best) * p->match - best * p->mismatch;
        out.mapq = out.x0 >= 2   ? 0
                   : out.x1 == 0 ? 60 - 12 * best
                                 : larger(30 - 12 * best - 3 * out.x1, 1);
        free(operations);
        free(hits);
        free(oriented[1]);
        return out;
    }
    free(hits);
    out.reason = "NOHIT";
    if (out.length < p->seed_length) {
        free(oriented[1]);
        return out;
    }
    ++mapper->seeds.reads;
    unsigned char *seen[2][10];
    int *accepted_index[2][10];
    for (int strand = 0; strand < 2; ++strand)
        for (int r = 0; r < mapper->input->reference_count; ++r) {
            seen[strand][r] = calloc((size_t)mapper->input->references[r].length + 101, 1);
            int size = mapper->input->references[r].length + 1;
            accepted_index[strand][r] = malloc((size_t)size * sizeof(int));
            for (int i = 0; i < size; ++i)
                accepted_index[strand][r][i] = -1;
        }
    Candidate *candidates = NULL;
    int candidate_count = 0, candidate_capacity = 0;
    for (int strand = 0; strand < 2; ++strand)
        for (int start = 0; start + p->seed_length <= out.length; start += p->seed_step) {
            ++mapper->seeds.seeds;
            char *seed = format("%.*s", p->seed_length, oriented[strand] + start);
            if (strchr(seed, 'N')) {
                ++mapper->seeds.with_n;
                free(seed);
                continue;
            }
            Interval interval = backward_search(mapper->forward, seed);
            free(seed);
            if (interval.upper - interval.lower > p->maximum_seed_hits) {
                ++mapper->seeds.repetitive;
                continue;
            }
            if (interval.lower >= interval.upper) {
                ++mapper->seeds.without_hit;
                continue;
            }
            for (int row = interval.lower; row < interval.upper; ++row) {
                int offset, r = locate_reference(mapper, row, &offset), center = offset - start;
                if (!seen[strand][r][center + 100]) {
                    seen[strand][r][center + 100] = 1;
                    if (candidate_count == candidate_capacity) {
                        candidate_capacity = candidate_capacity ? candidate_capacity * 2 : 32;
                        candidates =
                            realloc(candidates, (size_t)candidate_capacity * sizeof(Candidate));
                    }
                    candidates[candidate_count++] = (Candidate){strand, r, center};
                }
            }
        }
    mapper->seeds.candidates += candidate_count;
    if (candidate_count > 1)
        qsort(candidates, (size_t)candidate_count, sizeof(Candidate), candidate_order);
    Accepted *accepted = NULL;
    int accepted_count = 0, accepted_capacity = 0;
    for (int i = 0; i < candidate_count; ++i) {
        Candidate candidate = candidates[i];
        Banded alignment =
            banded_alignment(oriented[candidate.strand],
                             &mapper->input->references[candidate.reference], candidate.center, p);
        if (!alignment.exists || 100 * alignment.score < p->minimum_score * p->match * out.length) {
            free(alignment.operations);
            continue;
        }
        int *slot = &accepted_index[candidate.strand][candidate.reference][alignment.position];
        if (*slot < 0) {
            if (accepted_count == accepted_capacity) {
                accepted_capacity = accepted_capacity ? accepted_capacity * 2 : 16;
                accepted = realloc(accepted, (size_t)accepted_capacity * sizeof(Accepted));
            }
            *slot = accepted_count++;
            accepted[*slot] = (Accepted){alignment.score, candidate.reference, alignment.position,
                                         candidate.strand, alignment.operations};
        } else if (alignment.score > accepted[*slot].score) {
            free(accepted[*slot].operations);
            accepted[*slot].score = alignment.score;
            accepted[*slot].operations = alignment.operations;
        } else
            free(alignment.operations);
    }
    mapper->seeds.passing += accepted_count;
    free(candidates);
    for (int strand = 0; strand < 2; ++strand)
        for (int r = 0; r < mapper->input->reference_count; ++r) {
            free(seen[strand][r]);
            free(accepted_index[strand][r]);
        }
    if (accepted_count) {
        qsort(accepted, (size_t)accepted_count, sizeof(Accepted), accepted_order);
        out.score = accepted[0].score;
        int second = 0;
        for (int i = 0; i < accepted_count; ++i)
            if (accepted[i].score == out.score) {
                ++out.x0;
                out.targets |= 1u << accepted[i].reference;
            } else
                second = larger(second, accepted[i].score);
        out.x1 = accepted_count - out.x0;
        out.other_count = accepted_count - 1;
        out.primary = describe(accepted[0].reference, accepted[0].position, accepted[0].strand,
                               accepted[0].operations, &out, mapper->input);
        if (out.other_count <= p->maximum_alternatives) {
            out.others = malloc((size_t)out.other_count * sizeof(Alignment));
            for (int i = 1; i < accepted_count; ++i)
                out.others[i - 1] =
                    describe(accepted[i].reference, accepted[i].position, accepted[i].strand,
                             accepted[i].operations, &out, mapper->input);
        }
        out.mapped = 1;
        out.method = "SEED";
        out.mapq = out.x0 >= 2 ? 0 : 60 * (out.score - second) / out.score;
    }
    for (int i = 0; i < accepted_count; ++i)
        free(accepted[i].operations);
    free(accepted);
    free(oriented[1]);
    return out;
}
static int run_count(const char *value) {
    int count = 0;
    for (int i = 0; value[i]; ++i)
        count += !i || value[i] != value[i - 1];
    return count;
}
static Lines index_statistics(const ReferenceText *reference, const SuffixArray *suffixes,
                              const Index *forward, const SuffixArray *reverse_suffixes,
                              const Index *reverse, const Params *p) {
    Lines out = {0};
    const Input *input = reference->input;
    int size = reference->size;
    line(&out, "text length %d sequences %d", size, input->reference_count);
    for (int r = 0; r < input->reference_count; ++r) {
        const Reference *item = &input->references[r];
        int gc = 0;
        for (int i = 0; i < item->length; ++i)
            gc += item->bases[i] == 'G' || item->bases[i] == 'C';
        line(&out, "sequence %s length %d offset %d gc %s masked %d", item->name, item->length,
             reference->offsets[r], ratio(gc, item->length), item->masked);
    }
    int frequencies[6] = {0};
    for (int i = 0; i < size; ++i)
        ++frequencies[symbol_number(reference->text[i])];
    Text row = {0};
    text(&row, "symbols");
    for (int i = 0; i < 6; ++i)
        text(&row, " %c %d", alphabet[i], frequencies[i]);
    line(&out, "%s", row.data);
    free(row.data);
    line(&out, "");
    line(&out, "forward_index");
    line(&out, "suffix_array rounds %d", suffixes->class_count - 1);
    for (int t = 0; t < suffixes->class_count; ++t)
        line(&out, "round %d prefix_length %d classes %d", t, 1 << t, suffixes->classes[t]);
    Check checked = adjacent_check(reference->text, suffixes->order, size);
    line(&out, "sa_check pairs %d ordered %d lcp_sum %lld mean_lcp %s max_lcp %d", size - 1,
         checked.ordered, V(checked.lcp_sum), ratio(checked.lcp_sum, size - 1), checked.maximum);
    line(&out, "longest_repeat %d %s %s", checked.maximum,
         position_label(reference, suffixes->order[checked.row - 1]),
         position_label(reference, suffixes->order[checked.row]));
    int *base_runs = calloc((size_t)size + 1, sizeof(int));
    for (int i = size - 1; i >= 0; --i)
        if (reference->text[i] != '#' && reference->text[i] != '$')
            base_runs[i] = base_runs[i + 1] + 1;
    int occurrences = 0, distinct = 0, unique = 0, maximum = 0, group = 0, previous = -1;
    for (int row_number = 0; row_number < size; ++row_number) {
        int position = suffixes->order[row_number];
        if (base_runs[position] < p->seed_length)
            continue;
        ++occurrences;
        if (previous >= 0 &&
            !memcmp(reference->text + previous, reference->text + position, (size_t)p->seed_length))
            ++group;
        else {
            if (group) {
                ++distinct;
                unique += group == 1;
                maximum = larger(maximum, group);
            }
            group = 1;
        }
        previous = position;
    }
    if (group) {
        ++distinct;
        unique += group == 1;
        maximum = larger(maximum, group);
    }
    free(base_runs);
    line(
        &out,
        "kmers length %d occurrences %d distinct %d unique %d max_occurrence %d unique_fraction %s",
        p->seed_length, occurrences, distinct, unique, maximum, ratio(unique, occurrences));
    line(&out, "bwt runs %d head %.*s", run_count(forward->bwt), smaller(60, size), forward->bwt);
    row = (Text){0};
    text(&row, "c_array");
    for (int i = 0; i < 6; ++i)
        text(&row, " %c %d", alphabet[i], forward->C[i]);
    line(&out, "%s", row.data);
    free(row.data);
    line(&out, "occ interval %d checkpoints %d", forward->interval, forward->checkpoint_count);
    line(&out, "sa_sample interval %d samples %d", p->sample_interval, forward->sample_count);
    int correct = 0, max_steps = 0;
    I total_steps = 0;
    for (int i = 0; i < size; ++i) {
        int steps, position = locate(forward, i, &steps);
        correct += position == suffixes->order[i];
        total_steps += steps;
        max_steps = larger(max_steps, steps);
    }
    line(&out, "locate rows %d correct %d total_steps %lld max_steps %d mean_steps %s", size,
         correct, V(total_steps), max_steps, ratio(total_steps, size));
    char *reconstructed = inverse(forward);
    line(&out, "inverse_bwt identical %s", !strcmp(reconstructed, reference->text) ? "yes" : "no");
    free(reconstructed);
    line(&out, "");
    line(&out, "reverse_index");
    line(&out, "suffix_array rounds %d", reverse_suffixes->class_count - 1);
    Check reverse_check = adjacent_check(reference->reverse, reverse_suffixes->order, size);
    line(&out, "sa_check pairs %d ordered %d", size - 1, reverse_check.ordered);
    line(&out, "bwt runs %d head %.*s", run_count(reverse->bwt), smaller(60, size), reverse->bwt);
    reconstructed = inverse(reverse);
    line(&out, "inverse_bwt identical %s",
         !strcmp(reconstructed, reference->reverse) ? "yes" : "no");
    free(reconstructed);
    line(&out, "");
    line(&out, "direct_sort");
    int checks = 0;
    for (int r = 0; r < input->reference_count; ++r)
        if (input->references[r].length <= p->direct_limit) {
            char *sequence = format("%s$", input->references[r].bases);
            SuffixArray doubled = suffix_array(sequence);
            int *direct = direct_sort(sequence),
                identical = !memcmp(doubled.order, direct, (size_t)doubled.size * sizeof(int));
            line(&out, "%s length %d rounds %d identical %s", input->references[r].name,
                 doubled.size, doubled.class_count - 1, identical ? "yes" : "no");
            free(doubled.order);
            free(direct);
            free(sequence);
            ++checks;
        }
    if (!checks)
        line(&out, "none");
    I occurrence_bytes = 24 * (I)forward->checkpoint_count,
      sample_bytes = 4 * (I)forward->sample_count, bitmap_bytes = (size + 7) / 8,
      total_bytes = size + occurrence_bytes + sample_bytes + bitmap_bytes;
    line(&out, "");
    line(
        &out,
        "index_size bwt_bytes %d occ_bytes %lld sample_bytes %lld bitmap_bytes %lld total_bytes %lld full_bytes %d ratio %s",
        size, V(occurrence_bytes), V(sample_bytes), V(bitmap_bytes), V(total_bytes), 5 * size,
        ratio(total_bytes, 5 * size));
    return out;
}
typedef struct {
    Lines coverage, variants;
} PileupReports;
static PileupReports coverage_and_variants(const Result *results, const Input *input,
                                           const Params *p) {
    PileupReports out = {0};
    int *depths[10], *starts[10], (*pileups[10])[4][2];
    for (int r = 0; r < input->reference_count; ++r) {
        int length = input->references[r].length;
        depths[r] = calloc((size_t)length, sizeof(int));
        starts[r] = calloc((size_t)length, sizeof(int));
        pileups[r] = calloc((size_t)length, sizeof(*pileups[r]));
    }
    for (int read = 0; read < input->read_count; ++read) {
        const Result *result = &results[read];
        if (!result->mapped)
            continue;
        const Alignment *a = &result->primary;
        int r = a->reference;
        if (!result->mapq)
            ++starts[r][a->position];
        if (result->mapq < p->coverage_mapq)
            continue;
        for (int pair = 0; pair < a->pair_count; ++pair) {
            int i = a->pairs[pair].read, j = a->pairs[pair].reference;
            ++depths[r][j];
            char base = a->oriented[i];
            int cycle = a->strand ? result->length - i : i + 1;
            if (base != 'N' && result->qualities[cycle - 1] >= p->variant_quality)
                ++pileups[r][j][strchr(bases, base) - bases][a->strand];
        }
    }
    line(&out.coverage, "window %d min_mapq %d", p->coverage_window, p->coverage_mapq);
    line(&out.variants, "min_depth %d min_base_quality %d min_alt_percent %d hom_percent %d",
         p->variant_depth, p->variant_quality, p->variant_percent, p->homozygous_percent);
    int callable = 0, variants = 0, heterozygous = 0, homozygous = 0;
    for (int r = 0; r < input->reference_count; ++r) {
        const Reference *reference = &input->references[r];
        int length = reference->length, covered = 0, maximum = 0;
        I total = 0;
        for (int j = 0; j < length; ++j) {
            covered += depths[r][j] > 0;
            total += depths[r][j];
            maximum = larger(maximum, depths[r][j]);
        }
        line(&out.coverage,
             "reference %s length %d covered %d breadth %s mean_depth %s max_depth %d",
             reference->name, length, covered, ratio(covered, length), ratio(total, length),
             maximum);
        int histogram[401] = {0};
        for (int j = 0; j < length; ++j)
            ++histogram[depths[r][j]];
        Text row = {0};
        text(&row, "depth_histogram");
        for (int depth = 0; depth <= maximum; ++depth)
            text(&row, " %d:%d", depth, histogram[depth]);
        line(&out.coverage, "%s", row.data);
        free(row.data);
        for (int first = 0; first < length; first += p->coverage_window) {
            int last = smaller(first + p->coverage_window, length), size = last - first, gc = 0,
                zero = 0, mapq_zero = 0, largest = 0;
            I sum = 0;
            for (int j = first; j < last; ++j) {
                gc += reference->bases[j] == 'G' || reference->bases[j] == 'C';
                sum += depths[r][j];
                largest = larger(largest, depths[r][j]);
                zero += !depths[r][j];
                mapq_zero += starts[r][j];
            }
            int count = (int)(10 * sum / size);
            char *bar = malloc((size_t)count + 1);
            memset(bar, '#', (size_t)count);
            bar[count] = 0;
            line(&out.coverage, "%s %d %d gc %s sum %lld mean %s max %d zero %d mapq0 %d |%s",
                 reference->name, first + 1, last, ratio(gc, size), V(sum), ratio(sum, size),
                 largest, zero, mapq_zero, bar);
            free(bar);
        }
        for (int j = 0; j < length; ++j) {
            int counts[4], depth = 0;
            for (int base = 0; base < 4; ++base) {
                counts[base] = pileups[r][j][base][0] + pileups[r][j][base][1];
                depth += counts[base];
            }
            if (depth < p->variant_depth)
                continue;
            ++callable;
            int alternative = -1;
            for (int base = 0; base < 4; ++base)
                if (bases[base] != reference->bases[j] &&
                    (alternative < 0 || counts[base] > counts[alternative]))
                    alternative = base;
            int count = counts[alternative];
            if (count < 2 || 100 * count < p->variant_percent * depth)
                continue;
            int homo = 100 * count >= p->homozygous_percent * depth;
            homozygous += homo;
            heterozygous += !homo;
            ++variants;
            line(
                &out.variants,
                "%s %d %c>%c depth %d alt %d fraction %s genotype %s strands %d %d counts %d %d %d %d",
                reference->name, j + 1, reference->bases[j], bases[alternative], depth, count,
                ratio(count, depth), homo ? "1/1" : "0/1", pileups[r][j][alternative][0],
                pileups[r][j][alternative][1], counts[0], counts[1], counts[2], counts[3]);
        }
        free(depths[r]);
        free(starts[r]);
        free(pileups[r]);
    }
    line(&out.variants, "callable %d variants %d heterozygous %d homozygous %d", callable, variants,
         heterozygous, homozygous);
    return out;
}
static Lines error_statistics(const Result *results, const Input *input) {
    Lines out = {0};
    int maximum_cycle = 0, cycles[101][2] = {{0}}, substitutions[4][5] = {{0}},
        quality_bins[5][2] = {{0}};
    I quality_counts[2] = {0}, quality_sums[2] = {0}, operation_counts[4] = {0}, events[2] = {0},
      indel_bases[2] = {0};
    for (int read = 0; read < input->read_count; ++read) {
        const Result *result = &results[read];
        maximum_cycle = larger(maximum_cycle, result->read.length);
        if (!result->mapped)
            continue;
        const Alignment *a = &result->primary;
        for (int i = 0; a->operations[i]; ++i) {
            char op = a->operations[i];
            ++operation_counts[op == 'M' ? 0 : op == 'I' ? 1 : 2];
        }
        operation_counts[3] += result->trimmed;
        if (result->x0 != 1)
            continue;
        const char *reference = input->references[a->reference].bases;
        for (int pair = 0; pair < a->pair_count; ++pair) {
            int i = a->pairs[pair].read, j = a->pairs[pair].reference;
            char observed = a->oriented[i], expected = reference[j];
            int mismatch = observed != expected, cycle = a->strand ? result->length - i : i + 1,
                quality = result->qualities[cycle - 1];
            ++cycles[cycle][0];
            cycles[cycle][1] += mismatch;
            ++substitutions[strchr(bases, expected) - bases]
                           [strchr(observed_bases, observed) - observed_bases];
            ++quality_counts[mismatch];
            quality_sums[mismatch] += quality;
            int bin = smaller(quality / 10, 4);
            ++quality_bins[bin][0];
            quality_bins[bin][1] += mismatch;
        }
        for (int start = 0; a->operations[start];) {
            int end = start + 1;
            while (a->operations[end] == a->operations[start])
                ++end;
            char operation = a->operations[start];
            if (operation == 'I' || operation == 'D') {
                int kind = operation == 'I' ? 0 : 1;
                ++events[kind];
                indel_bases[kind] += end - start;
            }
            start = end;
        }
    }
    I aligned = quality_counts[0] + quality_counts[1], mismatches = quality_counts[1];
    line(&out, "error_profile aligned_bases %lld mismatches %lld rate %s", V(aligned),
         V(mismatches), ratio(mismatches, aligned));
    line(&out, "substitutions");
    line(&out, "ref A C G T N");
    for (int b = 0; b < 4; ++b)
        line(&out, "%c %d %d %d %d %d", bases[b], substitutions[b][0], substitutions[b][1],
             substitutions[b][2], substitutions[b][3], substitutions[b][4]);
    line(&out, "mismatch_by_cycle");
    for (int cycle = 1; cycle <= maximum_cycle; ++cycle)
        line(&out, "cycle %d aligned %d mismatches %d rate %s", cycle, cycles[cycle][0],
             cycles[cycle][1], ratio(cycles[cycle][1], cycles[cycle][0]));
    line(&out, "quality matched %lld mean %s mismatched %lld mean %s", V(quality_counts[0]),
         ratio(quality_sums[0], quality_counts[0]), V(quality_counts[1]),
         ratio(quality_sums[1], quality_counts[1]));
    line(&out, "quality_bins");
    const char *ranges[5] = {"0-9", "10-19", "20-29", "30-39", "40-"};
    for (int i = 0; i < 5; ++i)
        line(&out, "%s aligned %d mismatches %d rate %s", ranges[i], quality_bins[i][0],
             quality_bins[i][1], ratio(quality_bins[i][1], quality_bins[i][0]));
    line(&out, "cigar M %lld I %lld D %lld S %lld", V(operation_counts[0]), V(operation_counts[1]),
         V(operation_counts[2]), V(operation_counts[3]));
    line(&out, "indels insertions %lld %lld deletions %lld %lld", V(events[0]), V(indel_bases[0]),
         V(events[1]), V(indel_bases[1]));
    return out;
}
typedef struct {
    char *names;
    int count;
} MultiTarget;
static int target_order(const void *left, const void *right) {
    return strcmp(((const MultiTarget *)left)->names, ((const MultiTarget *)right)->names);
}
static Lines mapping_statistics(const Result *results, const Input *input,
                                const SearchTotals *search, const SeedTotals *seeds) {
    int mapped = 0, unique = 0, short_reads = 0, no_hit = 0, trimmed = 0, trimmed_bases = 0,
        forward = 0, reverse = 0, minimum_length = 101, maximum_length = 0, n_reads = 0,
        n_bases = 0, n_mapped = 0, method_counts[3] = {0}, reference_counts[10][4] = {{0}},
        length_bins[11][3] = {{0}}, mapq_counts[61] = {0}, maximum_nm = 0;
    MultiTarget targets[400];
    int target_count = 0;
    for (int read = 0; read < input->read_count; ++read) {
        const Result *result = &results[read];
        trimmed += result->trimmed > 0;
        trimmed_bases += result->trimmed;
        minimum_length = smaller(minimum_length, result->length);
        maximum_length = larger(maximum_length, result->length);
        int count = 0;
        for (int i = 0; i < result->read.length; ++i)
            count += result->read.bases[i] == 'N';
        if (count) {
            ++n_reads;
            n_bases += count;
            n_mapped += result->mapped;
        }
        int bin = result->length / 10;
        ++length_bins[bin][0];
        length_bins[bin][1] += result->mapped;
        length_bins[bin][2] += result->mapped && result->x0 == 1;
        if (!result->mapped) {
            short_reads += !strcmp(result->reason, "SHORT");
            no_hit += !strcmp(result->reason, "NOHIT");
            continue;
        }
        ++mapped;
        unique += result->x0 == 1;
        int method = !strcmp(result->method, "EXACT")      ? 0
                     : !strcmp(result->method, "MISMATCH") ? 1
                                                           : 2;
        ++method_counts[method];
        forward += result->primary.strand == 0;
        reverse += result->primary.strand == 1;
        ++mapq_counts[result->mapq];
        maximum_nm = larger(maximum_nm, result->primary.nm);
        int r = result->primary.reference;
        ++reference_counts[r][0];
        reference_counts[r][1] += result->x0 == 1;
        ++reference_counts[r][2 + result->primary.strand];
        if (result->x0 >= 2) {
            Text names = {0};
            for (int reference = 0; reference < input->reference_count; ++reference)
                if (result->targets & (1u << reference))
                    text(&names, "%s%s", names.length ? "+" : "",
                         input->references[reference].name);
            int i = 0;
            while (i < target_count && strcmp(targets[i].names, names.data))
                ++i;
            if (i == target_count)
                targets[target_count++] = (MultiTarget){names.data, 0};
            else
                free(names.data);
            ++targets[i].count;
        }
    }
    int *nm_counts = calloc((size_t)maximum_nm + 1, sizeof(int));
    for (int read = 0; read < input->read_count; ++read)
        if (results[read].mapped)
            ++nm_counts[results[read].primary.nm];
    Lines out = {0};
    line(&out, "reads total %d trimmed %d trimmed_bases %d short %d", input->read_count, trimmed,
         trimmed_bases, short_reads);
    line(&out, "mapped %d rate %s unique %d multi %d unmapped %d", mapped,
         ratio(mapped, input->read_count), unique, mapped - unique, input->read_count - mapped);
    line(&out, "unmapped short %d nohit %d", short_reads, no_hit);
    line(&out, "method exact %d mismatch %d seed %d", method_counts[0], method_counts[1],
         method_counts[2]);
    line(&out, "strand forward %d reverse %d", forward, reverse);
    for (int r = 0; r < input->reference_count; ++r)
        line(&out, "reference %s mapped %d unique %d forward %d reverse %d",
             input->references[r].name, reference_counts[r][0], reference_counts[r][1],
             reference_counts[r][2], reference_counts[r][3]);
    line(&out, "length_bins");
    for (int lower = minimum_length / 10 * 10; lower <= maximum_length / 10 * 10; lower += 10) {
        int bin = lower / 10;
        line(&out, "%d-%d reads %d mapped %d unique %d", lower, lower + 9, length_bins[bin][0],
             length_bins[bin][1], length_bins[bin][2]);
    }
    line(&out, "n_reads %d n_bases %d mapped %d", n_reads, n_bases, n_mapped);
    line(&out, "multi_targets");
    if (!target_count)
        line(&out, "none");
    else {
        qsort(targets, (size_t)target_count, sizeof(MultiTarget), target_order);
        for (int i = 0; i < target_count; ++i)
            line(&out, "%s %d", targets[i].names, targets[i].count);
    }
    line(&out, "mapq_histogram");
    for (int value = 60; value >= 0; --value)
        if (mapq_counts[value])
            line(&out, "%d %d", value, mapq_counts[value]);
    line(&out, "nm_histogram");
    for (int value = 0; value <= maximum_nm; ++value)
        if (nm_counts[value])
            line(&out, "%d %d", value, nm_counts[value]);
    free(nm_counts);
    Lines errors = error_statistics(results, input);
    append(&out, &errors);
    line(&out, "search dfs_calls %lld dfs_nodes %lld dfs_leaves %lld dfs_positions %lld",
         V(search->calls), V(search->nodes), V(search->leaves), V(search->positions));
    line(
        &out,
        "seeds reads %lld seeds %lld with_n %lld repetitive %lld without_hit %lld candidates %lld passing %lld",
        V(seeds->reads), V(seeds->seeds), V(seeds->with_n), V(seeds->repetitive),
        V(seeds->without_hit), V(seeds->candidates), V(seeds->passing));
    return out;
}
int main(void) {
    Input *input = read_inputs();
    Params p = parameters(input);
    ReferenceText reference = reference_text(input);
    SuffixArray suffixes = suffix_array(reference.text),
                reverse_suffixes = suffix_array(reference.reverse);
    Index forward = build_index(reference.text, suffixes.order, p.occ_interval, p.sample_interval),
          reverse = build_index(reference.reverse, reverse_suffixes.order, p.occ_interval, 0);
    Lines index =
        index_statistics(&reference, &suffixes, &forward, &reverse_suffixes, &reverse, &p);
    Mapper mapper = {0};
    mapper.input = input;
    mapper.reference = &reference;
    mapper.forward = &forward;
    mapper.reverse = &reverse;
    mapper.params = &p;
    Result *results = calloc((size_t)input->read_count, sizeof(Result));
    for (int read = 0; read < input->read_count; ++read)
        results[read] = map_read(&mapper, &input->reads[read]);
    Lines sam = sam_header(input);
    for (int read = 0; read < input->read_count; ++read)
        line(&sam, "%s", sam_record(&results[read], input, p.maximum_alternatives));
    PileupReports pileup = coverage_and_variants(results, input, &p);
    Lines summary = mapping_statistics(results, input, &mapper.searches, &mapper.seeds);
    mkdir("output", 0777);
    save("alignments.sam", &sam);
    save("coverage.txt", &pileup.coverage);
    save("variants.txt", &pileup.variants);
    save("index_stats.txt", &index);
    save("summary.txt", &summary);
    return 0;
}
