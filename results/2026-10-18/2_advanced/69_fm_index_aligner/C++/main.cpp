#include "aligner.hpp"
static const std::string bases = "ACGT", alphabet = "$#ACGT";
Params::Params(const Input &input) {
    auto value = [&](const std::string &key) { return input.parameters.at(key)[0]; };
    mismatches = value("MAX_MISMATCHES");
    minimum_length = value("MIN_READ_LENGTH");
    trim_quality = value("TRIM_QUALITY");
    seed_length = value("SEED_LENGTH");
    seed_step = value("SEED_STEP");
    maximum_seed_hits = value("MAX_SEED_HITS");
    band_width = value("BAND_WIDTH");
    const std::vector<int> &scores = input.parameters.at("SCORES");
    match = scores[0];
    mismatch = scores[1];
    gap_open = scores[2];
    gap_extend = scores[3];
    minimum_score = value("MIN_SCORE_PERCENT");
    maximum_alternatives = value("MAX_ALT_HITS");
    occ_interval = value("OCC_INTERVAL");
    sample_interval = value("SA_SAMPLE_INTERVAL");
    direct_limit = value("DIRECT_SORT_LIMIT");
    coverage_window = value("COVERAGE_WINDOW");
    coverage_mapq = value("COVERAGE_MIN_MAPQ");
    const std::vector<int> &variants = input.parameters.at("VARIANTS");
    variant_depth = variants[0];
    variant_quality = variants[1];
    variant_percent = variants[2];
    homozygous_percent = variants[3];
}
static void append(Lines &out, const Lines &other) {
    out.insert(out.end(), other.begin(), other.end());
}
struct ReferenceText {
    const std::vector<Reference> &references;
    std::vector<int> offsets;
    std::string text, reverse;
    explicit ReferenceText(const std::vector<Reference> &references) : references(references) {
        for (const Reference &reference : references) {
            offsets.push_back(int(text.size()));
            text += reference.bases;
            text += '#';
        }
        text.back() = '$';
        reverse = std::string(text.rbegin() + 1, text.rend()) + "$";
    }
    std::optional<std::pair<int, int>> position(int text_position) const {
        int r =
            int(std::upper_bound(offsets.begin(), offsets.end(), text_position) - offsets.begin()) -
            1;
        int offset = text_position - offsets[r];
        if (offset >= int(references[r].bases.size()))
            return {};
        return {{r, offset}};
    }
    std::string label(int p) const {
        auto located = position(p);
        return located ? references[located->first].name + ":" + std::to_string(located->second + 1)
                       : "*";
    }
};
static std::vector<std::pair<char, int>> runs(const std::string &operations) {
    std::vector<std::pair<char, int>> out;
    for (char operation : operations) {
        if (out.empty() || out.back().first != operation)
            out.push_back({operation, 1});
        else
            ++out.back().second;
    }
    return out;
}
static Alignment describe(int reference, int position, int strand, const std::string &operations,
                          const Result &result, const std::vector<Reference> &references) {
    Alignment out;
    out.reference = reference;
    out.position = position;
    out.strand = strand;
    out.operations = operations;
    out.oriented = strand ? reverse_complement(result.core) : result.core;
    const std::string &sequence = references[reference].bases;
    int read_position = 0, reference_position = position, matches = 0;
    for (const auto &run : runs(operations)) {
        char op = run.first;
        int count = run.second;
        out.cigar += std::to_string(count) + op;
        if (op == 'I') {
            read_position += count;
            out.nm += count;
        } else if (op == 'D') {
            out.md += std::to_string(matches) + "^" + sequence.substr(reference_position, count);
            matches = 0;
            reference_position += count;
            out.nm += count;
        } else
            for (int i = 0; i < count; ++i) {
                out.pairs.push_back({read_position, reference_position});
                if (out.oriented[read_position] == sequence[reference_position])
                    ++matches;
                else {
                    out.md += std::to_string(matches) + sequence[reference_position];
                    matches = 0;
                    ++out.nm;
                }
                ++read_position;
                ++reference_position;
            }
    }
    out.md += std::to_string(matches);
    if (result.trimmed) {
        std::string clip = std::to_string(result.trimmed) + "S";
        out.cigar = strand ? clip + out.cigar : out.cigar + clip;
    }
    return out;
}
static constexpr int unreachable = -1000000;
struct BandRow {
    int first, last;
    std::array<std::vector<int>, 3> values;
    int get(int state, int column) const {
        return column < first || column > last ? unreachable : values[state][column - first];
    }
};
static int subtract(int value, int penalty) {
    return value == unreachable ? unreachable : value - penalty;
}
struct Banded {
    int score, position;
    std::string operations;
};
static std::optional<Banded> banded_alignment(const std::string &oriented,
                                              const std::string &sequence, int center,
                                              const Params &p) {
    int length = int(oriented.size()), reference_length = int(sequence.size());
    std::vector<BandRow> rows;
    rows.reserve(length + 1);
    for (int i = 0; i <= length; ++i) {
        BandRow row;
        row.first = std::max(0, i + center - p.band_width);
        row.last = std::min(reference_length, i + center + p.band_width);
        for (auto &state : row.values)
            state.assign(std::max(0, row.last - row.first + 1), unreachable);
        rows.push_back(std::move(row));
    }
    std::fill(rows[0].values[0].begin(), rows[0].values[0].end(), 0);
    for (int i = 1; i <= length; ++i) {
        BandRow &row = rows[i];
        for (int j = row.first; j <= row.last; ++j) {
            int column = j - row.first;
            row.values[2][column] =
                std::max(subtract(rows[i - 1].get(0, j), p.gap_open + p.gap_extend),
                         subtract(rows[i - 1].get(2, j), p.gap_extend));
            int diagonal = unreachable;
            if (j >= 1) {
                row.values[1][column] =
                    std::max(subtract(row.get(0, j - 1), p.gap_open + p.gap_extend),
                             subtract(row.get(1, j - 1), p.gap_extend));
                int previous = rows[i - 1].get(0, j - 1);
                if (previous != unreachable)
                    diagonal =
                        previous + (oriented[i - 1] == sequence[j - 1] ? p.match : -p.mismatch);
            }
            row.values[0][column] =
                std::max({diagonal, row.values[1][column], row.values[2][column]});
        }
    }
    int best = unreachable, column = -1;
    for (int j = rows[length].first; j <= rows[length].last; ++j) {
        int value = rows[length].get(0, j);
        if (value > best) {
            best = value;
            column = j;
        }
    }
    if (column < 0)
        return {};
    int row = length, state = 0;
    std::string backward;
    while (true) {
        if (state == 0) {
            if (row == 0)
                break;
            int previous = column >= 1 ? rows[row - 1].get(0, column - 1) : unreachable;
            if (previous != unreachable &&
                rows[row].get(0, column) ==
                    previous +
                        (oriented[row - 1] == sequence[column - 1] ? p.match : -p.mismatch)) {
                backward += 'M';
                --row;
                --column;
                continue;
            }
            state = rows[row].get(2, column) != unreachable &&
                            rows[row].get(0, column) == rows[row].get(2, column)
                        ? 1
                        : 2;
        } else if (state == 1) {
            backward += 'I';
            int previous = rows[row - 1].get(2, column);
            state = previous != unreachable && rows[row].get(2, column) == previous - p.gap_extend
                        ? 1
                        : 0;
            --row;
        } else {
            backward += 'D';
            int previous = rows[row].get(1, column - 1);
            state = previous != unreachable && rows[row].get(1, column) == previous - p.gap_extend
                        ? 2
                        : 0;
            --column;
        }
    }
    std::reverse(backward.begin(), backward.end());
    return Banded{best, column, backward};
}
struct SearchTotals {
    I calls = 0, nodes = 0, leaves = 0, positions = 0;
};
struct SeedTotals {
    I reads = 0, seeds = 0, with_n = 0, repetitive = 0, without_hit = 0, candidates = 0,
      passing = 0;
};
struct Mapper {
    const ReferenceText &reference;
    const Index &forward, &reverse;
    const Params &p;
    SearchTotals searches;
    SeedTotals seeds;
    std::pair<int, int> locate(int row) const {
        return *reference.position(forward.locate(row).first);
    }
    Result map_read(const Read &read) {
        Result out;
        out.read = read;
        for (unsigned char quality : read.quality)
            out.qualities.push_back(int(quality) - 33);
        out.length = int(read.bases.size());
        while (out.length > 0 && out.qualities[out.length - 1] < p.trim_quality)
            --out.length;
        out.trimmed = int(read.bases.size()) - out.length;
        out.core = read.bases.substr(0, out.length);
        if (out.length < p.minimum_length)
            return out;
        std::array<std::string, 2> oriented = {out.core, reverse_complement(out.core)};
        std::array<Interval, 2> exact_intervals = {forward.backward_search(oriented[0]),
                                                   forward.backward_search(oriented[1])};
        bool exact = !exact_intervals[0].empty() || !exact_intervals[1].empty();
        int maximum = exact ? 1 : p.mismatches;
        struct Hit {
            int mismatches, reference, position, strand;
        };
        std::vector<Hit> hits;
        for (int strand = 0; strand < 2; ++strand) {
            Search result = backtrack(oriented[strand], maximum, forward, reverse);
            ++searches.calls;
            searches.nodes += result.nodes;
            searches.leaves += I(result.leaves.size());
            searches.positions += result.positions;
            for (const Leaf &leaf : result.leaves)
                for (int row = leaf.lower; row < leaf.upper; ++row) {
                    auto position = locate(row);
                    hits.push_back({leaf.mismatches, position.first, position.second, strand});
                }
        }
        if (!hits.empty()) {
            std::sort(hits.begin(), hits.end(), [](const Hit &a, const Hit &b) {
                return std::tie(a.mismatches, a.reference, a.position, a.strand) <
                       std::tie(b.mismatches, b.reference, b.position, b.strand);
            });
            int best = hits.front().mismatches, eligible = 0;
            for (const Hit &hit : hits) {
                out.x0 += hit.mismatches == best;
                out.x1 += hit.mismatches == best + 1;
                eligible += hit.mismatches <= best + 1;
                if (hit.mismatches == best)
                    out.targets.insert(hit.reference);
            }
            const Hit &first = hits.front();
            out.primary = describe(first.reference, first.position, first.strand,
                                   std::string(out.length, 'M'), out, reference.references);
            out.other_count = eligible - 1;
            if (out.other_count <= p.maximum_alternatives)
                for (int i = 1; i < eligible; ++i) {
                    const Hit &hit = hits[i];
                    out.others.push_back(describe(hit.reference, hit.position, hit.strand,
                                                  std::string(out.length, 'M'), out,
                                                  reference.references));
                }
            out.mapped = true;
            out.method = best == 0 ? "EXACT" : "MISMATCH";
            out.score = (out.length - best) * p.match - best * p.mismatch;
            out.mapq = out.x0 >= 2   ? 0
                       : out.x1 == 0 ? 60 - 12 * best
                                     : std::max(30 - 12 * best - 3 * out.x1, 1);
            return out;
        }
        out.reason = "NOHIT";
        if (out.length < p.seed_length)
            return out;
        ++seeds.reads;
        std::set<std::tuple<int, int, int>> candidates;
        for (int strand = 0; strand < 2; ++strand)
            for (int start = 0; start + p.seed_length <= out.length; start += p.seed_step) {
                ++seeds.seeds;
                std::string seed = oriented[strand].substr(start, p.seed_length);
                if (seed.find('N') != std::string::npos) {
                    ++seeds.with_n;
                    continue;
                }
                Interval interval = forward.backward_search(seed);
                if (interval.upper - interval.lower > p.maximum_seed_hits) {
                    ++seeds.repetitive;
                    continue;
                }
                if (interval.empty()) {
                    ++seeds.without_hit;
                    continue;
                }
                for (int row = interval.lower; row < interval.upper; ++row) {
                    auto position = locate(row);
                    candidates.insert({strand, position.first, position.second - start});
                }
            }
        seeds.candidates += I(candidates.size());
        struct Accepted {
            int score, reference, position, strand;
            std::string operations;
        };
        std::map<std::tuple<int, int, int>, Accepted> accepted;
        for (const auto &candidate : candidates) {
            int strand = std::get<0>(candidate), r = std::get<1>(candidate),
                center = std::get<2>(candidate);
            std::optional<Banded> alignment =
                banded_alignment(oriented[strand], reference.references[r].bases, center, p);
            if (!alignment || 100 * alignment->score < p.minimum_score * p.match * out.length)
                continue;
            auto key = std::make_tuple(r, alignment->position, strand);
            auto old = accepted.find(key);
            if (old == accepted.end() || alignment->score > old->second.score)
                accepted[key] = {alignment->score, r, alignment->position, strand,
                                 alignment->operations};
        }
        seeds.passing += I(accepted.size());
        if (accepted.empty())
            return out;
        std::vector<Accepted> ordered;
        for (const auto &entry : accepted)
            ordered.push_back(entry.second);
        std::sort(ordered.begin(), ordered.end(), [](const Accepted &a, const Accepted &b) {
            return a.score != b.score ? a.score > b.score
                                      : std::tie(a.reference, a.position, a.strand) <
                                            std::tie(b.reference, b.position, b.strand);
        });
        out.score = ordered.front().score;
        int second = 0;
        for (const Accepted &alignment : ordered)
            if (alignment.score == out.score) {
                ++out.x0;
                out.targets.insert(alignment.reference);
            } else
                second = std::max(second, alignment.score);
        out.x1 = int(ordered.size()) - out.x0;
        out.other_count = int(ordered.size()) - 1;
        const Accepted &first = ordered.front();
        out.primary = describe(first.reference, first.position, first.strand, first.operations, out,
                               reference.references);
        if (out.other_count <= p.maximum_alternatives)
            for (int i = 1; i < int(ordered.size()); ++i) {
                const Accepted &alignment = ordered[i];
                out.others.push_back(describe(alignment.reference, alignment.position,
                                              alignment.strand, alignment.operations, out,
                                              reference.references));
            }
        out.mapped = true;
        out.method = "SEED";
        out.mapq = out.x0 >= 2 ? 0 : 60 * (out.score - second) / out.score;
        return out;
    }
};
static Lines index_statistics(const ReferenceText &reference, const SuffixArray &suffixes,
                              const Index &forward, const SuffixArray &reverse_suffixes,
                              const Index &reverse, const Params &p) {
    const std::string &text = reference.text;
    int size = int(text.size());
    Lines out;
    line(out, "text length ", size, " sequences ", reference.references.size());
    for (int r = 0; r < int(reference.references.size()); ++r) {
        const Reference &item = reference.references[r];
        int gc = 0;
        for (char c : item.bases)
            gc += c == 'G' || c == 'C';
        line(out, "sequence ", item.name, " length ", item.bases.size(), " offset ",
             reference.offsets[r], " gc ", ratio(gc, I(item.bases.size())), " masked ",
             item.masked);
    }
    std::array<int, 6> frequencies{};
    for (char c : text)
        ++frequencies[symbol_number(c)];
    std::ostringstream frequency;
    frequency << "symbols";
    for (int i = 0; i < 6; ++i)
        frequency << ' ' << alphabet[i] << ' ' << frequencies[i];
    out.push_back(frequency.str());
    out.push_back("");
    out.push_back("forward_index");
    line(out, "suffix_array rounds ", suffixes.classes.size() - 1);
    for (int t = 0; t < int(suffixes.classes.size()); ++t)
        line(out, "round ", t, " prefix_length ", 1 << t, " classes ", suffixes.classes[t]);
    Check checked = adjacent_check(text, suffixes.order);
    line(out, "sa_check pairs ", size - 1, " ordered ", checked.ordered, " lcp_sum ",
         checked.lcp_sum, " mean_lcp ", ratio(checked.lcp_sum, size - 1), " max_lcp ",
         checked.maximum);
    line(out, "longest_repeat ", checked.maximum, " ",
         reference.label(suffixes.order[checked.row - 1]), " ",
         reference.label(suffixes.order[checked.row]));
    std::vector<int> base_runs(size + 1);
    for (int i = size - 1; i >= 0; --i)
        if (text[i] != '#' && text[i] != '$')
            base_runs[i] = base_runs[i + 1] + 1;
    int occurrences = 0, distinct = 0, unique = 0, maximum = 0, group = 0, previous = -1;
    auto finish = [&]() {
        if (group) {
            ++distinct;
            unique += group == 1;
            maximum = std::max(maximum, group);
        }
    };
    for (int position : suffixes.order)
        if (base_runs[position] >= p.seed_length) {
            ++occurrences;
            if (previous >= 0 &&
                text.compare(previous, p.seed_length, text, position, p.seed_length) == 0)
                ++group;
            else {
                finish();
                group = 1;
            }
            previous = position;
        }
    finish();
    line(out, "kmers length ", p.seed_length, " occurrences ", occurrences, " distinct ", distinct,
         " unique ", unique, " max_occurrence ", maximum, " unique_fraction ",
         ratio(unique, occurrences));
    line(out, "bwt runs ", runs(forward.bwt).size(), " head ", forward.bwt.substr(0, 60));
    std::ostringstream cumulative;
    cumulative << "c_array";
    for (int i = 0; i < 6; ++i)
        cumulative << ' ' << alphabet[i] << ' ' << forward.C[i];
    out.push_back(cumulative.str());
    line(out, "occ interval ", forward.interval, " checkpoints ", forward.checkpoints.size());
    line(out, "sa_sample interval ", p.sample_interval, " samples ", forward.sample_count);
    I total_steps = 0;
    int correct = 0, max_steps = 0;
    for (int row = 0; row < size; ++row) {
        auto located = forward.locate(row);
        correct += located.first == suffixes.order[row];
        total_steps += located.second;
        max_steps = std::max(max_steps, located.second);
    }
    line(out, "locate rows ", size, " correct ", correct, " total_steps ", total_steps,
         " max_steps ", max_steps, " mean_steps ", ratio(total_steps, size));
    line(out, "inverse_bwt identical ", forward.inverse() == text ? "yes" : "no");
    out.push_back("");
    out.push_back("reverse_index");
    line(out, "suffix_array rounds ", reverse_suffixes.classes.size() - 1);
    Check reverse_check = adjacent_check(reference.reverse, reverse_suffixes.order);
    line(out, "sa_check pairs ", size - 1, " ordered ", reverse_check.ordered);
    line(out, "bwt runs ", runs(reverse.bwt).size(), " head ", reverse.bwt.substr(0, 60));
    line(out, "inverse_bwt identical ", reverse.inverse() == reference.reverse ? "yes" : "no");
    out.push_back("");
    out.push_back("direct_sort");
    int checks = 0;
    for (const Reference &item : reference.references)
        if (int(item.bases.size()) <= p.direct_limit) {
            std::string sequence = item.bases + "$";
            SuffixArray doubled = suffix_array(sequence);
            line(out, item.name, " length ", sequence.size(), " rounds ",
                 doubled.classes.size() - 1, " identical ",
                 doubled.order == direct_sort(sequence) ? "yes" : "no");
            ++checks;
        }
    if (!checks)
        out.push_back("none");
    I occurrence_bytes = 24 * I(forward.checkpoints.size()),
      sample_bytes = 4 * forward.sample_count, bitmap_bytes = (size + 7) / 8,
      total_bytes = size + occurrence_bytes + sample_bytes + bitmap_bytes;
    out.push_back("");
    line(out, "index_size bwt_bytes ", size, " occ_bytes ", occurrence_bytes, " sample_bytes ",
         sample_bytes, " bitmap_bytes ", bitmap_bytes, " total_bytes ", total_bytes, " full_bytes ",
         5 * size, " ratio ", ratio(total_bytes, 5 * size));
    return out;
}
static std::pair<Lines, Lines> coverage_and_variants(const std::vector<Result> &results,
                                                     const std::vector<Reference> &references,
                                                     const Params &p) {
    using Pileup = std::array<std::array<int, 2>, 4>;
    std::vector<std::vector<int>> depths, starts;
    std::vector<std::vector<Pileup>> pileups;
    for (const Reference &reference : references) {
        depths.emplace_back(reference.bases.size());
        starts.emplace_back(reference.bases.size());
        pileups.emplace_back(reference.bases.size());
    }
    for (const Result &result : results)
        if (result.mapped) {
            const Alignment &alignment = result.primary;
            int r = alignment.reference;
            if (result.mapq == 0)
                ++starts[r][alignment.position];
            if (result.mapq < p.coverage_mapq)
                continue;
            for (const auto &pair : alignment.pairs) {
                int i = pair.first, j = pair.second;
                ++depths[r][j];
                char base = alignment.oriented[i];
                int cycle = alignment.strand ? result.length - i : i + 1;
                if (base != 'N' && result.qualities[cycle - 1] >= p.variant_quality)
                    ++pileups[r][j][bases.find(base)][alignment.strand];
            }
        }
    Lines coverage, variants;
    line(coverage, "window ", p.coverage_window, " min_mapq ", p.coverage_mapq);
    line(variants, "min_depth ", p.variant_depth, " min_base_quality ", p.variant_quality,
         " min_alt_percent ", p.variant_percent, " hom_percent ", p.homozygous_percent);
    int callable = 0, variant_count = 0, heterozygous = 0, homozygous = 0;
    for (int r = 0; r < int(references.size()); ++r) {
        const Reference &reference = references[r];
        int length = int(reference.bases.size()), covered = 0, maximum = 0;
        I total = 0;
        for (int depth : depths[r]) {
            covered += depth > 0;
            total += depth;
            maximum = std::max(maximum, depth);
        }
        line(coverage, "reference ", reference.name, " length ", length, " covered ", covered,
             " breadth ", ratio(covered, length), " mean_depth ", ratio(total, length),
             " max_depth ", maximum);
        std::vector<int> histogram(maximum + 1);
        for (int depth : depths[r])
            ++histogram[depth];
        std::ostringstream row;
        row << "depth_histogram";
        for (int i = 0; i <= maximum; ++i)
            row << ' ' << i << ':' << histogram[i];
        coverage.push_back(row.str());
        for (int first = 0; first < length; first += p.coverage_window) {
            int last = std::min(first + p.coverage_window, length), size = last - first, gc = 0,
                zero = 0, mapq_zero = 0, largest = 0;
            I sum = 0;
            for (int j = first; j < last; ++j) {
                gc += reference.bases[j] == 'G' || reference.bases[j] == 'C';
                sum += depths[r][j];
                largest = std::max(largest, depths[r][j]);
                zero += depths[r][j] == 0;
                mapq_zero += starts[r][j];
            }
            line(coverage, reference.name, " ", first + 1, " ", last, " gc ", ratio(gc, size),
                 " sum ", sum, " mean ", ratio(sum, size), " max ", largest, " zero ", zero,
                 " mapq0 ", mapq_zero, " |", std::string(std::size_t(10 * sum / size), '#'));
        }
        for (int j = 0; j < length; ++j) {
            std::array<int, 4> counts{};
            int depth = 0;
            for (int base = 0; base < 4; ++base) {
                counts[base] = pileups[r][j][base][0] + pileups[r][j][base][1];
                depth += counts[base];
            }
            if (depth < p.variant_depth)
                continue;
            ++callable;
            int alternative = -1;
            for (int base = 0; base < 4; ++base)
                if (bases[base] != reference.bases[j] &&
                    (alternative < 0 || counts[base] > counts[alternative]))
                    alternative = base;
            int count = counts[alternative];
            if (count < 2 || 100 * count < p.variant_percent * depth)
                continue;
            bool homo = 100 * count >= p.homozygous_percent * depth;
            homozygous += homo;
            heterozygous += !homo;
            ++variant_count;
            line(variants, reference.name, " ", j + 1, " ", reference.bases[j], ">",
                 bases[alternative], " depth ", depth, " alt ", count, " fraction ",
                 ratio(count, depth), " genotype ", homo ? "1/1" : "0/1", " strands ",
                 pileups[r][j][alternative][0], " ", pileups[r][j][alternative][1], " counts ",
                 counts[0], " ", counts[1], " ", counts[2], " ", counts[3]);
        }
    }
    line(variants, "callable ", callable, " variants ", variant_count, " heterozygous ",
         heterozygous, " homozygous ", homozygous);
    return {coverage, variants};
}
static Lines error_statistics(const std::vector<Result> &results,
                              const std::vector<Reference> &references) {
    int maximum_cycle = 0;
    for (const Result &result : results)
        maximum_cycle = std::max(maximum_cycle, int(result.read.bases.size()));
    std::vector<std::array<int, 2>> cycles(maximum_cycle + 1);
    std::array<std::array<int, 5>, 4> substitutions{};
    std::array<I, 2> quality_counts{}, quality_sums{};
    std::array<std::array<int, 2>, 5> quality_bins{};
    std::map<char, I> operation_counts, events, indel_bases;
    for (const Result &result : results)
        if (result.mapped) {
            const Alignment &alignment = result.primary;
            for (char operation : alignment.operations)
                ++operation_counts[operation];
            operation_counts['S'] += result.trimmed;
            if (result.x0 != 1)
                continue;
            const std::string &reference = references[alignment.reference].bases;
            for (const auto &pair : alignment.pairs) {
                int i = pair.first, j = pair.second;
                char observed = alignment.oriented[i], expected = reference[j];
                int mismatch = observed != expected,
                    cycle = alignment.strand ? result.length - i : i + 1,
                    quality = result.qualities[cycle - 1];
                ++cycles[cycle][0];
                cycles[cycle][1] += mismatch;
                ++substitutions[bases.find(expected)][std::string("ACGTN").find(observed)];
                ++quality_counts[mismatch];
                quality_sums[mismatch] += quality;
                int bin = std::min(quality / 10, 4);
                ++quality_bins[bin][0];
                quality_bins[bin][1] += mismatch;
            }
            for (const auto &run : runs(alignment.operations))
                if (run.first == 'I' || run.first == 'D') {
                    ++events[run.first];
                    indel_bases[run.first] += run.second;
                }
        }
    I aligned = quality_counts[0] + quality_counts[1], mismatches = quality_counts[1];
    Lines out;
    line(out, "error_profile aligned_bases ", aligned, " mismatches ", mismatches, " rate ",
         ratio(mismatches, aligned));
    out.push_back("substitutions");
    out.push_back("ref A C G T N");
    for (int b = 0; b < 4; ++b) {
        const auto &counts = substitutions[b];
        line(out, bases[b], " ", counts[0], " ", counts[1], " ", counts[2], " ", counts[3], " ",
             counts[4]);
    }
    out.push_back("mismatch_by_cycle");
    for (int cycle = 1; cycle <= maximum_cycle; ++cycle)
        line(out, "cycle ", cycle, " aligned ", cycles[cycle][0], " mismatches ", cycles[cycle][1],
             " rate ", ratio(cycles[cycle][1], cycles[cycle][0]));
    line(out, "quality matched ", quality_counts[0], " mean ",
         ratio(quality_sums[0], quality_counts[0]), " mismatched ", quality_counts[1], " mean ",
         ratio(quality_sums[1], quality_counts[1]));
    out.push_back("quality_bins");
    const std::array<std::string, 5> ranges = {"0-9", "10-19", "20-29", "30-39", "40-"};
    for (int i = 0; i < 5; ++i)
        line(out, ranges[i], " aligned ", quality_bins[i][0], " mismatches ", quality_bins[i][1],
             " rate ", ratio(quality_bins[i][1], quality_bins[i][0]));
    line(out, "cigar M ", operation_counts['M'], " I ", operation_counts['I'], " D ",
         operation_counts['D'], " S ", operation_counts['S']);
    line(out, "indels insertions ", events['I'], " ", indel_bases['I'], " deletions ", events['D'],
         " ", indel_bases['D']);
    return out;
}
static Lines mapping_statistics(const std::vector<Result> &results,
                                const std::vector<Reference> &references,
                                const SearchTotals &search, const SeedTotals &seeds) {
    int mapped = 0, unique = 0, short_reads = 0, no_hit = 0, trimmed = 0, trimmed_bases = 0,
        forward = 0, reverse = 0, minimum_length = 101, maximum_length = 0, n_reads = 0,
        n_bases = 0, n_mapped = 0;
    std::map<std::string, int> method_counts, target_counts;
    std::map<int, int> mapq_counts, nm_counts;
    for (const Result &result : results) {
        trimmed += result.trimmed > 0;
        trimmed_bases += result.trimmed;
        minimum_length = std::min(minimum_length, result.length);
        maximum_length = std::max(maximum_length, result.length);
        int count = int(std::count(result.read.bases.begin(), result.read.bases.end(), 'N'));
        if (count) {
            ++n_reads;
            n_bases += count;
            n_mapped += result.mapped;
        }
        if (!result.mapped) {
            short_reads += result.reason == "SHORT";
            no_hit += result.reason == "NOHIT";
            continue;
        }
        ++mapped;
        unique += result.x0 == 1;
        ++method_counts[result.method];
        forward += result.primary.strand == 0;
        reverse += result.primary.strand == 1;
        ++mapq_counts[result.mapq];
        ++nm_counts[result.primary.nm];
        if (result.x0 >= 2) {
            std::string names;
            for (int r : result.targets) {
                if (!names.empty())
                    names += '+';
                names += references[r].name;
            }
            ++target_counts[names];
        }
    }
    Lines out;
    line(out, "reads total ", results.size(), " trimmed ", trimmed, " trimmed_bases ",
         trimmed_bases, " short ", short_reads);
    line(out, "mapped ", mapped, " rate ", ratio(mapped, I(results.size())), " unique ", unique,
         " multi ", mapped - unique, " unmapped ", int(results.size()) - mapped);
    line(out, "unmapped short ", short_reads, " nohit ", no_hit);
    line(out, "method exact ", method_counts["EXACT"], " mismatch ", method_counts["MISMATCH"],
         " seed ", method_counts["SEED"]);
    line(out, "strand forward ", forward, " reverse ", reverse);
    for (int r = 0; r < int(references.size()); ++r) {
        int count = 0, uniques = 0, plus = 0;
        for (const Result &result : results)
            if (result.mapped && result.primary.reference == r) {
                ++count;
                uniques += result.x0 == 1;
                plus += result.primary.strand == 0;
            }
        line(out, "reference ", references[r].name, " mapped ", count, " unique ", uniques,
             " forward ", plus, " reverse ", count - plus);
    }
    out.push_back("length_bins");
    for (int lower = minimum_length / 10 * 10; lower <= maximum_length / 10 * 10; lower += 10) {
        int count = 0, mapped_count = 0, unique_count = 0;
        for (const Result &result : results)
            if (result.length >= lower && result.length <= lower + 9) {
                ++count;
                mapped_count += result.mapped;
                unique_count += result.mapped && result.x0 == 1;
            }
        line(out, lower, "-", lower + 9, " reads ", count, " mapped ", mapped_count, " unique ",
             unique_count);
    }
    line(out, "n_reads ", n_reads, " n_bases ", n_bases, " mapped ", n_mapped);
    out.push_back("multi_targets");
    if (target_counts.empty())
        out.push_back("none");
    else
        for (const auto &entry : target_counts)
            line(out, entry.first, " ", entry.second);
    out.push_back("mapq_histogram");
    for (auto at = mapq_counts.rbegin(); at != mapq_counts.rend(); ++at)
        line(out, at->first, " ", at->second);
    out.push_back("nm_histogram");
    for (const auto &entry : nm_counts)
        line(out, entry.first, " ", entry.second);
    append(out, error_statistics(results, references));
    line(out, "search dfs_calls ", search.calls, " dfs_nodes ", search.nodes, " dfs_leaves ",
         search.leaves, " dfs_positions ", search.positions);
    line(out, "seeds reads ", seeds.reads, " seeds ", seeds.seeds, " with_n ", seeds.with_n,
         " repetitive ", seeds.repetitive, " without_hit ", seeds.without_hit, " candidates ",
         seeds.candidates, " passing ", seeds.passing);
    return out;
}
int main() {
    Input input = read_inputs();
    Params params(input);
    ReferenceText reference(input.references);
    SuffixArray suffixes = suffix_array(reference.text),
                reverse_suffixes = suffix_array(reference.reverse);
    Index forward(reference.text, suffixes.order, params.occ_interval, params.sample_interval),
        reverse(reference.reverse, reverse_suffixes.order, params.occ_interval);
    Lines index = index_statistics(reference, suffixes, forward, reverse_suffixes, reverse, params);
    Mapper mapper{reference, forward, reverse, params};
    std::vector<Result> results;
    for (const Read &read : input.reads)
        results.push_back(mapper.map_read(read));
    Lines sam = sam_header(input.references);
    for (const Result &result : results)
        sam.push_back(sam_record(result, input.references, params.maximum_alternatives));
    auto pileup = coverage_and_variants(results, input.references, params);
    Lines summary = mapping_statistics(results, input.references, mapper.searches, mapper.seeds);
    std::filesystem::create_directories("output");
    save("alignments.sam", sam);
    save("coverage.txt", pileup.first);
    save("variants.txt", pileup.second);
    save("index_stats.txt", index);
    save("summary.txt", summary);
}
