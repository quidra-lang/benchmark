#include "statistics.hpp"
#include <cstdlib>

static const Lines groupNames{"mean", "median", "trimmed_mean", "sd"};
static const Lines pairNames{"mean_diff", "median_ratio", "hodges_lehmann", "cohen_d"};
static const Lines testNames{"mean", "median", "ranksum", "absdev"};
static void extend(Lines& target, const Lines& source) { target.insert(target.end(), source.begin(), source.end()); }
struct Summary {
    double estimate = 0, average = 0, se = 0, bias = 0, low = 0, high = 0, basicLow = 0, basicHigh = 0;
    Values values, ordered;
    Summary() = default;
    Summary(double estimate, Values values, int lowRank, int highRank) : estimate(estimate), values(std::move(values)), ordered(this->values) {
        std::sort(ordered.begin(), ordered.end());
        std::pair<double, double> spread = meanAndSe(this->values);
        average = spread.first;
        se = spread.second;
        bias = average - estimate;
        low = ordered[lowRank - 1];
        high = ordered[highRank - 1];
        basicLow = 2 * estimate - high;
        basicHigh = 2 * estimate - low;
    }
    std::string csv(const std::string& name, const std::string& statistic) const {
        return text(name, ',', statistic, ',', realText(estimate), ',', realText(se), ',', realText(bias), ',', realText(low), ',', realText(high), ',', realText(basicLow), ',', realText(basicHigh));
    }
    std::string interval() const { return text("se ", realText(se), " bias ", realText(bias), " percentile ", realText(low), ' ', realText(high), " basic ", realText(basicLow), ' ', realText(basicHigh)); }
};
struct GroupResult { std::vector<Indices> indices; std::vector<Sample> samples; std::array<Summary, 4> ordinary, balanced; };
struct PairResult { int first, second; std::string name; std::array<Summary, 4> summaries; std::array<Integer, 4> extremes{}; };
struct Jackknife {
    Values values;
    double average, variance, bias, se;
    Jackknife(double estimate, Values input) : values(std::move(input)) {
        average = sequentialSum(values) / values.size();
        double squares = 0;
        for (double value : values) { double difference = value - average; squares += difference * difference; }
        variance = (values.size() - 1) * squares / values.size();
        bias = (values.size() - 1) * (average - estimate);
        se = std::sqrt(variance);
    }
};
struct Tally {
    Integer observed, extreme = 0, greater = 0;
    void count(Integer value) { if (std::abs(value) >= std::abs(observed)) ++extreme; if (value >= observed) ++greater; }
    std::string str(Integer offset, Integer denominator) const { return text("extreme ", extreme, " greater ", greater, " p_two ", pValue(extreme + offset, denominator), " p_greater ", pValue(greater + offset, denominator)); }
};
class Study {
    Dataset data;
    Minstd generator;
    int lowRank, highRank;
    double zLow;
    std::vector<GroupResult> groups;
    std::vector<PairResult> pairs;
    Summary pairedMean, pairedCorrelation;
public:
    explicit Study(Dataset input) : data(std::move(input)), generator(data.settings.seed), groups(data.groups.size()) {
        lowRank = (data.settings.bootstrap + 1) * (100 - data.settings.confidence) / 200;
        highRank = data.settings.bootstrap + 1 - lowRank;
        zLow = phiInverse(static_cast<double>(100 - data.settings.confidence) / 200);
    }
    Summary summarize(double estimate, Values values) const { return Summary(estimate, std::move(values), lowRank, highRank); }
    static Sample chosen(const Sample& values, const Indices& indices) {
        Sample sample;
        for (std::size_t index : indices) sample.push_back(values[index]);
        return sample;
    }
    void bootstraps() {
        int count = data.settings.bootstrap;
        for (std::size_t g = 0; g < groups.size(); ++g) {
            const Sample& original = data.groups[g].values;
            GroupResult& result = groups[g];
            result.indices = ordinaryIndices(generator, original.size(), count);
            std::array<Values, 4> columns;
            for (const Indices& indices : result.indices) {
                result.samples.push_back(chosen(original, indices));
                std::array<double, 4> values = groupStatistics(result.samples.back());
                for (int s = 0; s < 4; ++s) columns[s].push_back(values[s]);
            }
            std::array<double, 4> estimates = groupStatistics(original);
            for (int s = 0; s < 4; ++s) result.ordinary[s] = summarize(estimates[s], std::move(columns[s]));
        }
        for (std::size_t g = 0; g < groups.size(); ++g) {
            const Sample& original = data.groups[g].values;
            std::array<Values, 4> columns;
            for (const Indices& indices : balancedIndices(generator, original.size(), count)) {
                std::array<double, 4> values = groupStatistics(chosen(original, indices));
                for (int s = 0; s < 4; ++s) columns[s].push_back(values[s]);
            }
            for (int s = 0; s < 4; ++s) groups[g].balanced[s] = summarize(groups[g].ordinary[s].estimate, std::move(columns[s]));
        }
        Values means, correlations;
        for (const Indices& indices : ordinaryIndices(generator, data.before.size(), count)) {
            means.push_back(mean(chosen(data.differences, indices)));
            correlations.push_back(correlation(chosen(data.before, indices), chosen(data.after, indices)));
        }
        pairedMean = summarize(mean(data.differences), std::move(means));
        pairedCorrelation = summarize(correlation(data.before, data.after), std::move(correlations));
        for (const std::pair<int, int>& pair : data.pairs) {
            int first = pair.first, second = pair.second;
            PairResult result{first, second, data.groups[first].name + "-" + data.groups[second].name, {}, {}};
            std::array<Values, 4> columns;
            for (int r = 0; r < count; ++r) {
                std::array<double, 4> values = pairStatistics(groups[first].samples[r], groups[second].samples[r]);
                for (int s = 0; s < 4; ++s) columns[s].push_back(values[s]);
            }
            std::array<double, 4> estimates = pairStatistics(data.groups[first].values, data.groups[second].values);
            for (int s = 0; s < 4; ++s) result.summaries[s] = summarize(estimates[s], std::move(columns[s]));
            pairs.push_back(std::move(result));
        }
    }
    static Lines describe(const std::string& kind, const std::string& name, const Sample& sample, Integer low, Integer high, bool stems) {
        Sample ordered = sample;
        std::sort(ordered.begin(), ordered.end());
        double center = mean(sample);
        Moments moment = moments(sample);
        Sample wins = winsorized(sample);
        Integer q1 = quantileNumerator(sample, 25), q3 = quantileNumerator(sample, 75);
        Indices outliers;
        Sample inside;
        for (std::size_t i = 0; i < sample.size(); ++i) {
            Integer value = sample[i];
            if (200 * value < 5 * q1 - 3 * q3 || 200 * value > 5 * q3 - 3 * q1) outliers.push_back(i + 1);
            else inside.push_back(value);
        }
        Integer w1 = *std::min_element(inside.begin(), inside.end()), w2 = *std::max_element(inside.begin(), inside.end());
        Integer delta = 100 * (high - low);
        const std::function<std::size_t(Integer)> position = [&](Integer value) { return static_cast<std::size_t>((120 * (value - 100 * low) + delta) / (2 * delta)); };
        std::string band(61, '.');
        for (std::size_t i = position(100 * w1); i <= position(100 * w2); ++i) band[i] = '-';
        for (std::size_t i = position(q1); i <= position(q3); ++i) band[i] = '=';
        band[position(quantileNumerator(sample, 50))] = '|';
        for (std::size_t number : outliers) band[position(100 * sample[number - 1])] = 'o';
        Lines lines;
        add(lines, kind, ' ', name);
        add(lines, "n ", sample.size());
        add(lines, "mean ", realText(center));
        add(lines, "median ", realText(median(sample)));
        add(lines, "trimmed_mean ", realText(trimmedMean(sample)), " trim ", sample.size() / 10);
        add(lines, "winsorized_mean ", realText(mean(wins)), " winsorized_sd ", realText(sd(wins)));
        add(lines, "sd ", realText(moment.sd));
        add(lines, "se_mean ", realText(moment.sd / std::sqrt(sample.size())));
        add(lines, "cv ", realText(moment.sd / center));
        add(lines, "skewness ", realText(moment.third / (moment.second * std::sqrt(moment.second))));
        add(lines, "kurtosis ", realText(moment.fourth / (moment.second * moment.second) - 3));
        add(lines, "mad ", realText(mad(sample)));
        add(lines, "min ", realText(static_cast<double>(ordered.front()) / 100));
        add(lines, "q1 ", realText(static_cast<double>(q1) / 10000));
        add(lines, "q3 ", realText(static_cast<double>(q3) / 10000));
        add(lines, "iqr ", realText(static_cast<double>(q3 - q1) / 10000));
        add(lines, "max ", realText(static_cast<double>(ordered.back()) / 100));
        add(lines, "percentiles p05 ", realText(static_cast<double>(quantileNumerator(sample, 5)) / 10000), " p10 ", realText(static_cast<double>(quantileNumerator(sample, 10)) / 10000), " p90 ", realText(static_cast<double>(quantileNumerator(sample, 90)) / 10000), " p95 ", realText(static_cast<double>(quantileNumerator(sample, 95)) / 10000));
        add(lines, "whiskers ", realText(static_cast<double>(w1) / 100), ' ', realText(static_cast<double>(w2) / 100));
        add(lines, "outliers ", numberList(outliers));
        add(lines, "box ", band);
        if (stems) for (Integer stem = ordered.front() / 100; stem <= ordered.back() / 100; ++stem) {
            std::string leaves;
            for (Integer value : ordered) if (value / 100 == stem) leaves += static_cast<char>('0' + value % 100 / 10);
            add(lines, "stem ", stem, leaves.empty() ? "" : " " + leaves);
        }
        return lines;
    }
    Lines descriptiveLines() const {
        Sample combined;
        for (const Group& group : data.groups) combined.insert(combined.end(), group.values.begin(), group.values.end());
        Integer low = *std::min_element(combined.begin(), combined.end()), high = *std::max_element(combined.begin(), combined.end());
        Lines lines;
        add(lines, "groups ", data.groups.size(), " observations ", combined.size());
        for (const Group& group : data.groups) extend(lines, describe("group", group.name, group.values, low, high, true));
        combined = data.before;
        combined.insert(combined.end(), data.after.begin(), data.after.end());
        low = *std::min_element(combined.begin(), combined.end());
        high = *std::max_element(combined.begin(), combined.end());
        add(lines, "paired subjects ", data.before.size());
        extend(lines, describe("series", "before", data.before, low, high, false));
        extend(lines, describe("series", "after", data.after, low, high, false));
        extend(lines, describe("series", "diff", data.differences, *std::min_element(data.differences.begin(), data.differences.end()), *std::max_element(data.differences.begin(), data.differences.end()), false));
        return lines;
    }
    Lines bootstrapLines() const {
        Lines lines{"group,statistic,estimate,se,bias,percentile_lo,percentile_hi,basic_lo,basic_hi"};
        for (std::size_t g = 0; g < groups.size(); ++g) {
            for (int s = 0; s < 4; ++s) lines.push_back(groups[g].ordinary[s].csv(data.groups[g].name, groupNames[s]));
            for (int s = 0; s < 4; ++s) lines.push_back(groups[g].balanced[s].csv(data.groups[g].name, "balanced_" + groupNames[s]));
        }
        for (const PairResult& pair : pairs) for (int s = 0; s < 4; ++s) lines.push_back(pair.summaries[s].csv(pair.name, pairNames[s]));
        return lines;
    }
    Lines groupJackknife(std::size_t group) const {
        const Sample& sample = data.groups[group].values;
        const GroupResult& bootstrap = groups[group];
        std::array<Values, 4> deleted;
        for (std::size_t i = 0; i < sample.size(); ++i) {
            std::array<double, 4> values = groupStatistics(without(sample, i));
            for (int s = 0; s < 4; ++s) deleted[s].push_back(values[s]);
        }
        std::vector<Jackknife> jackknives;
        Lines lines;
        add(lines, "group ", data.groups[group].name, " n ", sample.size());
        for (int s = 0; s < 4; ++s) {
            jackknives.emplace_back(bootstrap.ordinary[s].estimate, deleted[s]);
            const Jackknife& jack = jackknives.back();
            add(lines, "jackknife ", groupNames[s], " estimate ", realText(bootstrap.ordinary[s].estimate), " average ", realText(jack.average), " bias ", realText(jack.bias), " se ", realText(jack.se));
        }
        for (int s = 0; s < 4; ++s) {
            const Summary& summary = bootstrap.ordinary[s];
            Integer below = 0;
            for (double value : summary.values) if (value < summary.estimate) ++below;
            double z0 = phiInverse(static_cast<double>(below) / data.settings.bootstrap), squares = 0, cubes = 0;
            for (double value : deleted[s]) {
                double difference = jackknives[s].average - value;
                squares += difference * difference;
                cubes += difference * difference * difference;
            }
            double acceleration = cubes / (6 * squares * std::sqrt(squares));
            const std::function<double(double)> alpha = [&](double z) { return phi(z0 + (z0 + z) / (1 - acceleration * (z0 + z))); };
            int first = std::clamp(static_cast<int>(std::floor((data.settings.bootstrap + 1) * alpha(zLow))), 1, data.settings.bootstrap);
            int second = std::clamp(data.settings.bootstrap + 1 - static_cast<int>(std::floor((data.settings.bootstrap + 1) * (1 - alpha(-zLow)))), 1, data.settings.bootstrap);
            add(lines, "bca ", groupNames[s], " below ", below, " z0 ", realText(z0), " acceleration ", realText(acceleration), " ranks ", first, ' ', second, " interval ", realText(summary.ordered[first - 1]), ' ', realText(summary.ordered[second - 1]));
        }
        std::vector<Indices> omitted(sample.size());
        for (std::size_t r = 0; r < bootstrap.indices.size(); ++r) {
            std::vector<bool> seen(sample.size());
            for (std::size_t index : bootstrap.indices[r]) seen[index] = true;
            for (std::size_t i = 0; i < seen.size(); ++i) if (!seen[i]) omitted[i].push_back(r);
        }
        std::array<Values, 4> errors;
        for (int s = 0; s < 4; ++s) {
            for (const Indices& indices : omitted) {
                Values values;
                for (std::size_t r : indices) values.push_back(bootstrap.ordinary[s].values[r]);
                errors[s].push_back(meanAndSe(values).second);
            }
            Jackknife spread(0, errors[s]);
            add(lines, "after_bootstrap ", groupNames[s], " se ", realText(bootstrap.ordinary[s].se), " average ", realText(spread.average), " se_of_se ", realText(spread.se));
        }
        std::size_t minimum = omitted.front().size(), maximum = 0;
        for (const Indices& indices : omitted) { minimum = std::min(minimum, indices.size()); maximum = std::max(maximum, indices.size()); }
        add(lines, "without min ", minimum, " max ", maximum);
        Indices order(sample.size());
        std::iota(order.begin(), order.end(), std::size_t{0});
        Integer total = sum(sample), size = static_cast<Integer>(sample.size());
        std::sort(order.begin(), order.end(), [&](std::size_t a, std::size_t b) {
            Integer first = std::abs(size * sample[a] - total), second = std::abs(size * sample[b] - total);
            return first != second ? first > second : a < b;
        });
        for (std::size_t rank = 0; rank < 5; ++rank) {
            std::size_t index = order[rank];
            Values shifted;
            for (std::size_t r : omitted[index]) shifted.push_back(bootstrap.ordinary[0].values[r] - bootstrap.ordinary[0].estimate);
            std::sort(shifted.begin(), shifted.end());
            const std::function<double(int)> quantile = [&](int percent) { return shifted[(percent * shifted.size() + 99) / 100 - 1]; };
            double influence = (size - 1) * (jackknives[0].average - deleted[0][index]);
            add(lines, "influence ", rank + 1, " obs ", index + 1, " value ", realText(static_cast<double>(sample[index]) / 100), " l ", realText(influence), " without ", omitted[index].size(), " se ", realText(errors[0][index]), " q05 ", realText(quantile(5)), " q50 ", realText(quantile(50)), " q95 ", realText(quantile(95)));
        }
        return lines;
    }
    Lines pairJackknife(const PairResult& pair) const {
        const Sample& x = data.groups[pair.first].values;
        const Sample& y = data.groups[pair.second].values;
        std::array<std::array<Values, 4>, 2> deleted;
        for (std::size_t i = 0; i < x.size(); ++i) {
            std::array<double, 4> values = pairStatistics(without(x, i), y);
            for (int s = 0; s < 4; ++s) deleted[0][s].push_back(values[s]);
        }
        for (std::size_t i = 0; i < y.size(); ++i) {
            std::array<double, 4> values = pairStatistics(x, without(y, i));
            for (int s = 0; s < 4; ++s) deleted[1][s].push_back(values[s]);
        }
        Lines lines;
        for (int s = 0; s < 4; ++s) {
            double bias = 0, variance = 0;
            for (int part = 0; part < 2; ++part) {
                Jackknife jack(pair.summaries[s].estimate, deleted[part][s]);
                bias += jack.bias;
                variance += jack.variance;
            }
            add(lines, "pair ", pair.name, ' ', pairNames[s], " estimate ", realText(pair.summaries[s].estimate), " bias ", realText(bias), " se ", realText(std::sqrt(variance)));
        }
        return lines;
    }
    Lines jackknifeLines() const {
        Lines lines;
        for (std::size_t g = 0; g < groups.size(); ++g) extend(lines, groupJackknife(g));
        for (const PairResult& pair : pairs) extend(lines, pairJackknife(pair));
        return lines;
    }
    Lines histogram(const std::string& name, const std::string& statistic, const Summary& summary) const {
        int bins = data.settings.bins;
        double low = summary.ordered.front(), high = summary.ordered.back();
        std::vector<int> counts(bins);
        for (double value : summary.values) ++counts[binNumber(value, low, high, bins) - 1];
        int top = *std::max_element(counts.begin(), counts.end());
        int estimate = summary.estimate >= low && summary.estimate <= high ? binNumber(summary.estimate, low, high, bins) : 0;
        int first = binNumber(summary.low, low, high, bins), last = binNumber(summary.high, low, high, bins);
        Lines lines;
        add(lines, "histogram ", name, ' ', statistic, " min ", realText(low), " max ", realText(high), " width ", realText((high - low) / bins), " top ", top, " estimate_bin ", estimate ? text(estimate) : "none");
        Lines convergence;
        for (int quarter = 1; quarter <= 4; ++quarter) {
            std::size_t size = quarter * summary.values.size() / 4;
            Values values(summary.values.begin(), summary.values.begin() + static_cast<std::ptrdiff_t>(size));
            convergence.push_back(text(size, ':', realText(meanAndSe(values).second)));
        }
        add(lines, "convergence ", join(convergence));
        for (int i = 0; i < bins; ++i) {
            std::string line = text("bin ", i + 1, ' ', realText(low + (high - low) * i / bins), ' ', counts[i]);
            if (counts[i]) line += " " + bar(counts[i], top);
            if (i + 1 == first) line += " L";
            if (i + 1 == estimate) line += " E";
            if (i + 1 == last) line += " H";
            lines.push_back(line);
        }
        return lines;
    }
    Lines histogramLines() const {
        Lines lines;
        for (std::size_t g = 0; g < groups.size(); ++g) for (int s = 0; s < 4; ++s) extend(lines, histogram(data.groups[g].name, groupNames[s], groups[g].ordinary[s]));
        for (const PairResult& pair : pairs) for (int s = 0; s < 4; ++s) extend(lines, histogram(pair.name, pairNames[s], pair.summaries[s]));
        return lines;
    }
    static std::array<Integer, 4> splitStatistics(const Sample& values, const Sample& ranks, const Indices& order, std::size_t size) {
        Sample first, second;
        Integer rankTotal = 0;
        for (std::size_t i = 0; i < order.size(); ++i) {
            (i < size ? first : second).push_back(values[order[i]]);
            if (i < size) rankTotal += ranks[order[i]];
        }
        Integer firstMedian = doubledMedian(first), secondMedian = doubledMedian(second), firstDeviation = 0, secondDeviation = 0;
        for (Integer value : first) firstDeviation += std::abs(2 * value - firstMedian);
        for (Integer value : second) secondDeviation += std::abs(2 * value - secondMedian);
        Integer k = static_cast<Integer>(first.size()), m = static_cast<Integer>(second.size());
        return {contrast(first, second), firstMedian - secondMedian, rankTotal - k * (k + m + 1), m * firstDeviation - k * secondDeviation};
    }
    Lines permutationLines(PairResult& pair) {
        const Sample& x = data.groups[pair.first].values;
        const Sample& y = data.groups[pair.second].values;
        Sample values = x;
        values.insert(values.end(), y.begin(), y.end());
        Sample ranks = doubledRanks(values);
        Indices positions(values.size());
        std::iota(positions.begin(), positions.end(), std::size_t{0});
        std::array<Integer, 4> observed = splitStatistics(values, ranks, positions, x.size());
        std::array<Tally, 4> tallies{{{observed[0]}, {observed[1]}, {observed[2]}, {observed[3]}}};
        for (int r = 0; r < data.settings.permutations; ++r) {
            Indices shuffled = positions;
            generator.shuffle(shuffled);
            std::array<Integer, 4> trial = splitStatistics(values, ranks, shuffled, x.size());
            for (int s = 0; s < 4; ++s) tallies[s].count(trial[s]);
        }
        for (int s = 0; s < 4; ++s) pair.extremes[s] = tallies[s].extreme;
        Integer k = static_cast<Integer>(x.size()), m = static_cast<Integer>(y.size());
        Integer rankTotal = std::accumulate(ranks.begin(), ranks.begin() + static_cast<std::ptrdiff_t>(x.size()), Integer{0});
        Integer denominator = data.settings.permutations + 1;
        Lines lines;
        add(lines, "permutation n ", k, ' ', m, " perms ", data.settings.permutations);
        add(lines, "mean diff ", realText(meanDifference(x, y)), ' ', tallies[0].str(1, denominator));
        add(lines, "median diff ", realText(static_cast<double>(observed[1]) / 200), ' ', tallies[1].str(1, denominator));
        add(lines, "ranksum w ", realText(static_cast<double>(rankTotal) / 2), " u ", realText(static_cast<double>(rankTotal - k * (k + 1)) / 2), ' ', tallies[2].str(1, denominator));
        add(lines, "absdev diff ", realText(static_cast<double>(observed[3]) / (200 * k * m)), ' ', tallies[3].str(1, denominator));
        return lines;
    }
    std::string powerLine(const PairResult& pair) {
        const Sample& x = data.groups[pair.first].values;
        const Sample& y = data.groups[pair.second].values;
        int rejections = 0;
        for (int simulation = 0; simulation < data.settings.simulations; ++simulation) {
            Sample first = chosen(x, resampleIndices(generator, x.size()));
            Sample second = chosen(y, resampleIndices(generator, y.size()));
            Sample combined = first;
            combined.insert(combined.end(), second.begin(), second.end());
            Integer observed = std::abs(contrast(first, second));
            Integer extreme = 0;
            Indices order(combined.size());
            std::iota(order.begin(), order.end(), std::size_t{0});
            for (int r = 0; r < data.settings.innerPermutations; ++r) {
                Indices permutation = order;
                generator.shuffle(permutation);
                Sample shuffled = chosen(combined, permutation);
                Sample head(shuffled.begin(), shuffled.begin() + static_cast<std::ptrdiff_t>(x.size()));
                Sample tail(shuffled.begin() + static_cast<std::ptrdiff_t>(x.size()), shuffled.end());
                if (std::abs(contrast(head, tail)) >= observed) ++extreme;
            }
            if (100 * (extreme + 1) <= (100 - data.settings.confidence) * (data.settings.innerPermutations + 1)) ++rejections;
        }
        double power = static_cast<double>(rejections) / data.settings.simulations;
        return text("power sims ", data.settings.simulations, " perms ", data.settings.innerPermutations, " rejections ", rejections, " power ", realText(power), " se ", realText(std::sqrt(power * (1 - power) / data.settings.simulations)));
    }
    Lines exactLines(const PairResult& pair) const {
        std::size_t q = static_cast<std::size_t>(data.settings.pilot);
        const Sample& x = data.groups[pair.first].values;
        const Sample& y = data.groups[pair.second].values;
        Sample first(x.begin(), x.begin() + static_cast<std::ptrdiff_t>(q)), second(y.begin(), y.begin() + static_cast<std::ptrdiff_t>(q));
        Sample combined = first;
        combined.insert(combined.end(), second.begin(), second.end());
        Sample ranks = doubledRanks(combined);
        Integer size = static_cast<Integer>(q), total = sum(combined);
        Integer rankTotal = std::accumulate(ranks.begin(), ranks.begin() + static_cast<std::ptrdiff_t>(q), Integer{0});
        Tally means{contrast(first, second)}, rankSums{rankTotal - size * (2 * size + 1)};
        std::map<Integer, Integer, std::greater<Integer>> frequencies;
        Indices choice(q);
        std::iota(choice.begin(), choice.end(), std::size_t{0});
        Integer splits = 0;
        do {
            Integer chosenTotal = 0, chosenRanks = 0;
            for (std::size_t position : choice) { chosenTotal += combined[position]; chosenRanks += ranks[position]; }
            Integer value = size * chosenTotal - size * (total - chosenTotal);
            means.count(value);
            rankSums.count(chosenRanks - size * (2 * size + 1));
            ++frequencies[std::abs(value)];
            ++splits;
        } while (nextChoice(choice, 2 * q));
        Integer cumulative = 0, critical = 0, attained = 0;
        for (const std::pair<const Integer, Integer>& entry : frequencies) {
            cumulative += entry.second;
            if (100 * cumulative > (100 - data.settings.confidence) * splits) break;
            critical = entry.first;
            attained = cumulative;
        }
        Lines lines;
        add(lines, "exact size ", q, " splits ", splits);
        add(lines, "mean diff ", realText(meanDifference(first, second)), ' ', means.str(0, splits));
        add(lines, "ranksum w ", realText(static_cast<double>(rankTotal) / 2), " u ", realText(static_cast<double>(rankTotal - size * (size + 1)) / 2), ' ', rankSums.str(0, splits));
        if (attained) add(lines, "critical diff ", realText(static_cast<double>(critical) / (100 * size * size)), " attained ", pValue(attained, splits));
        else lines.push_back("critical diff none attained none");
        return lines;
    }
    Lines studentizedLines(const PairResult& pair) const {
        const Sample& x = data.groups[pair.first].values;
        const Sample& y = data.groups[pair.second].values;
        double sx = sd(x), sy = sd(y), vx = sx * sx / x.size(), vy = sy * sy / y.size();
        double se0 = std::sqrt(vx + vy), estimate = pair.summaries[0].estimate, statistic = estimate / se0;
        Values values;
        Integer extreme = 0;
        for (int r = 0; r < data.settings.bootstrap; ++r) {
            double first = groups[pair.first].ordinary[3].values[r], second = groups[pair.second].ordinary[3].values[r];
            double value = (pair.summaries[0].values[r] - estimate) / std::sqrt(first * first / x.size() + second * second / y.size());
            values.push_back(value);
            if (std::abs(value) >= std::abs(statistic)) ++extreme;
        }
        std::sort(values.begin(), values.end());
        double low = estimate - values[highRank - 1] * se0, high = estimate - values[lowRank - 1] * se0;
        double degrees = (vx + vy) * (vx + vy) / (vx * vx / (x.size() - 1) + vy * vy / (y.size() - 1));
        Integer greater = 0, equal = 0;
        for (Integer first : x) for (Integer second : y) { if (first > second) ++greater; if (first == second) ++equal; }
        double d = cohenD(x, y), hedges = d * (1 - 3.0 / (4 * (x.size() + y.size() - 2) - 1));
        double cles = static_cast<double>(2 * greater + equal) / (2 * static_cast<Integer>(x.size()) * static_cast<Integer>(y.size()));
        Lines lines;
        add(lines, "bootstrap_t t ", realText(statistic), " df ", realText(degrees), " extreme ", extreme, " p ", pValue(extreme + 1, data.settings.bootstrap + 1), " interval ", realText(low), ' ', realText(high));
        add(lines, "effect pooled_sd ", realText(pooledSd(x, y)), " cohen_d ", realText(d), " hedges_g ", realText(hedges), " cles ", realText(cles));
        return lines;
    }
    Lines holmLines() const {
        Lines lines;
        Integer denominator = data.settings.permutations + 1;
        for (int s = 0; s < 4; ++s) {
            Indices order(pairs.size());
            std::iota(order.begin(), order.end(), std::size_t{0});
            std::sort(order.begin(), order.end(), [&](std::size_t a, std::size_t b) { return pairs[a].extremes[s] != pairs[b].extremes[s] ? pairs[a].extremes[s] < pairs[b].extremes[s] : a < b; });
            Integer adjusted = 0;
            for (std::size_t rank = 0; rank < order.size(); ++rank) {
                const PairResult& pair = pairs[order[rank]];
                Integer numerator = pair.extremes[s] + 1;
                adjusted = std::max(adjusted, std::min(denominator, static_cast<Integer>(pairs.size() - rank) * numerator));
                bool reject = 100 * adjusted <= (100 - data.settings.confidence) * denominator;
                add(lines, "holm ", testNames[s], " rank ", rank + 1, ' ', data.groups[pair.first].name, ' ', data.groups[pair.second].name, " p ", pValue(numerator, denominator), " adjusted ", pValue(adjusted, denominator), reject ? " reject" : " retain");
            }
        }
        return lines;
    }
    Lines pairedLines() const {
        std::size_t count = data.differences.size();
        int positive = 0, negative = 0;
        for (Integer value : data.differences) {
            if (value > 0) ++positive;
            if (value < 0) ++negative;
        }
        double average = mean(data.differences), deviation = sd(data.differences);
        double r = pairedCorrelation.estimate;
        double z = 0.5 * std::log((1 + r) / (1 - r));
        double half = -zLow / std::sqrt(count - 3);
        const auto tangent = [](double value) { double e = std::exp(2 * value); return (e - 1) / (e + 1); };
        Lines lines;
        add(lines, "paired subjects ", count, " positive ", positive, " negative ", negative, " zero ", count - positive - negative);
        add(lines, "paired before ", realText(mean(data.before)), " after ", realText(mean(data.after)), " diff ", realText(average), " sd_diff ", realText(deviation), " t ", realText(average / (deviation / std::sqrt(count))), " dz ", realText(average / deviation));
        add(lines, "paired_bootstrap ", pairedMean.interval());
        add(lines, "correlation r ", realText(r), ' ', pairedCorrelation.interval(), " fisher ", realText(tangent(z - half)), ' ', realText(tangent(z + half)));
        return lines;
    }
    Lines signFlipLines() {
        Sample absolute;
        for (Integer value : data.differences) if (value) absolute.push_back(std::abs(value));
        Sample ranks = doubledRanks(absolute), signedRanks;
        std::size_t position = 0;
        Integer plus = 0;
        for (Integer value : data.differences) {
            Integer rank = value ? (value > 0 ? ranks[position] : -ranks[position]) : 0;
            if (value) ++position;
            signedRanks.push_back(rank);
            if (rank > 0) plus += rank;
        }
        Tally means{sum(data.differences)}, rankSums{sum(signedRanks)};
        for (int r = 0; r < data.settings.permutations; ++r) {
            Integer total = 0, rankTotal = 0;
            for (std::size_t i = 0; i < data.differences.size(); ++i) {
                Integer sign = generator.draw() % 2 ? -1 : 1;
                total += sign * data.differences[i];
                rankTotal += sign * signedRanks[i];
            }
            means.count(total);
            rankSums.count(rankTotal);
        }
        Lines lines;
        add(lines, "signflip flips ", data.settings.permutations);
        add(lines, "mean diff ", realText(mean(data.differences)), ' ', means.str(1, data.settings.permutations + 1));
        add(lines, "signedrank w_plus ", realText(static_cast<double>(plus) / 2), ' ', rankSums.str(1, data.settings.permutations + 1));
        return lines;
    }
    Lines anovaLines() {
        std::vector<Sample> samples;
        std::vector<std::size_t> sizes;
        Sample combined;
        for (const Group& group : data.groups) {
            samples.push_back(group.values);
            sizes.push_back(group.values.size());
            combined.insert(combined.end(), group.values.begin(), group.values.end());
        }
        Anova original = anova(samples);
        std::size_t count = combined.size(), groupCount = samples.size();
        double eta = original.between / (original.between + original.within);
        double msw = original.within / (count - groupCount);
        double omega = (original.between - (groupCount - 1) * msw) / (original.between + original.within + msw);
        Values etaValues;
        for (int r = 0; r < data.settings.bootstrap; ++r) {
            std::vector<Sample> replicate;
            for (const GroupResult& group : groups) replicate.push_back(group.samples[r]);
            Anova trial = anova(replicate);
            etaValues.push_back(trial.between / (trial.between + trial.within));
        }
        Summary etaSummary = summarize(eta, std::move(etaValues));
        Values weights;
        double weightTotal = 0, weightedTotal = 0;
        for (std::size_t g = 0; g < groupCount; ++g) {
            double deviation = sd(samples[g]);
            double weight = samples[g].size() / (deviation * deviation);
            weights.push_back(weight);
            weightTotal += weight;
            weightedTotal += weight * original.means[g];
        }
        double center = weightedTotal / weightTotal, aw = 0, lambda = 0;
        for (std::size_t g = 0; g < groupCount; ++g) {
            double difference = original.means[g] - center, remaining = 1 - weights[g] / weightTotal;
            aw += weights[g] * (difference * difference);
            lambda += remaining * remaining / (sizes[g] - 1);
        }
        aw /= groupCount - 1;
        double welch = aw / (1 + 2 * (groupCount - 2) * lambda / (groupCount * groupCount - 1));
        double degrees = (groupCount * groupCount - 1) / (3 * lambda);
        Sample ranks = doubledRanks(combined);
        Integer ties = 0, tieGroups = 0, n = static_cast<Integer>(count);
        for (const std::pair<const Integer, Integer>& entry : valueCounts(combined)) if (entry.second >= 2) {
            Integer t = entry.second;
            ties += t * t * t - t;
            ++tieGroups;
        }
        double correction = 1 - static_cast<double>(ties) / (n * n * n - n);
        double h = kruskal(divide(ranks, sizes), correction);
        Lines lines;
        add(lines, "anova groups ", groupCount, " observations ", count, " ssb ", realText(original.between), " ssw ", realText(original.within), " df ", groupCount - 1, ' ', count - groupCount, " f ", realText(original.f), " eta_squared ", realText(eta), " omega_squared ", realText(omega));
        add(lines, "eta_bootstrap ", etaSummary.interval());
        add(lines, "welch f ", realText(welch), " df ", groupCount - 1, ' ', realText(degrees));
        add(lines, "kruskal h ", realText(h), " tie_groups ", tieGroups);
        struct Comparison { std::size_t first, second; Integer numerator, denominator, extreme = 0, maximum = 0; };
        std::vector<Comparison> comparisons;
        for (std::size_t i = 0; i < groupCount; ++i) for (std::size_t j = i + 1; j < groupCount; ++j) comparisons.push_back({i, j, std::abs(contrast(samples[i], samples[j])), static_cast<Integer>(sizes[i] * sizes[j])});
        Indices positions(count);
        std::iota(positions.begin(), positions.end(), std::size_t{0});
        Integer fExtreme = 0, hExtreme = 0;
        for (int r = 0; r < data.settings.permutations; ++r) {
            Indices order = positions;
            generator.shuffle(order);
            std::vector<Sample> trialSamples = divide(chosen(combined, order), sizes);
            Anova trial = anova(trialSamples);
            if (trial.f >= original.f - 0.000000001 * original.f) ++fExtreme;
            if (kruskal(divide(chosen(ranks, order), sizes), correction) >= h - 0.000000001 * h) ++hExtreme;
            Sample numerators;
            std::size_t largest = 0;
            for (std::size_t i = 0; i < comparisons.size(); ++i) {
                const Comparison& pair = comparisons[i];
                numerators.push_back(std::abs(contrast(trialSamples[pair.first], trialSamples[pair.second])));
                if (numerators[i] * comparisons[largest].denominator > numerators[largest] * pair.denominator) largest = i;
            }
            for (std::size_t i = 0; i < comparisons.size(); ++i) {
                Comparison& pair = comparisons[i];
                if (numerators[i] >= pair.numerator) ++pair.extreme;
                if (numerators[largest] * pair.denominator >= pair.numerator * comparisons[largest].denominator) ++pair.maximum;
            }
        }
        Integer denominator = data.settings.permutations + 1;
        add(lines, "anova_permutation perms ", data.settings.permutations, " f_extreme ", fExtreme, " f_p ", pValue(fExtreme + 1, denominator), " h_extreme ", hExtreme, " h_p ", pValue(hExtreme + 1, denominator));
        for (const Comparison& pair : comparisons) add(lines, "pairwise ", data.groups[pair.first].name, ' ', data.groups[pair.second].name, " diff ", realText(meanDifference(samples[pair.first], samples[pair.second])), " extreme ", pair.extreme, " p ", pValue(pair.extreme + 1, denominator), " maxt ", pair.maximum, " adjusted ", pValue(pair.maximum + 1, denominator));
        return lines;
    }
    void run() {
        bootstraps();
        Lines tests;
        for (PairResult& pair : pairs) {
            add(tests, "compare ", data.groups[pair.first].name, ' ', data.groups[pair.second].name);
            extend(tests, permutationLines(pair));
            tests.push_back(powerLine(pair));
            extend(tests, exactLines(pair));
            extend(tests, studentizedLines(pair));
        }
        extend(tests, holmLines());
        extend(tests, pairedLines());
        extend(tests, signFlipLines());
        extend(tests, anovaLines());
        writeLines("descriptives.txt", descriptiveLines());
        writeLines("bootstrap.csv", bootstrapLines());
        writeLines("jackknife.txt", jackknifeLines());
        writeLines("tests.txt", tests);
        writeLines("histograms.txt", histogramLines());
    }
};
int main() {
    Study(loadDataset()).run();
}
