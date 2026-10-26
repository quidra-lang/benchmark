#include "segments.hpp"
#include <filesystem>
#include <optional>

class Minstd {
    Integer state;
public:
    explicit Minstd(Integer seed) : state(seed) {}
    Integer draw() { state = 48271 * state % 2147483647; return state; }
};
static Point nearestGaps(const Points& points, const Indices& chosen) {
    Point gaps;
    for (const Point& point : points) {
        double gap = squaredDistance(point, points[chosen.front()]);
        for (std::size_t index : chosen) gap = std::min(gap, squaredDistance(point, points[index]));
        gaps.push_back(gap);
    }
    return gaps;
}
static Indices maximin(const Points& points, int k, int number) {
    Point center = meanPoint(points), spreads;
    for (const Point& point : points) spreads.push_back(squaredDistance(point, center));
    Indices order(points.size());
    std::iota(order.begin(), order.end(), std::size_t{0});
    std::sort(order.begin(), order.end(), [&](std::size_t first, std::size_t second) {
        return spreads[first] != spreads[second] ? spreads[first] < spreads[second] : first < second;
    });
    Indices chosen{order[number - 1]};
    while (chosen.size() < static_cast<std::size_t>(k)) {
        Point gaps = nearestGaps(points, chosen);
        chosen.push_back(static_cast<std::size_t>(std::max_element(gaps.begin(), gaps.end()) - gaps.begin()));
    }
    return chosen;
}
static Indices initialSeeds(const std::string& method, const Points& points, int k, int number, Minstd& generator) {
    if (method == "maximin") return maximin(points, k, number);
    Indices chosen;
    if (method == "forgy") {
        while (chosen.size() < static_cast<std::size_t>(k)) {
            std::size_t index = static_cast<std::size_t>(generator.draw() % static_cast<Integer>(points.size()));
            if (std::find(chosen.begin(), chosen.end(), index) == chosen.end()) chosen.push_back(index);
        }
        return chosen;
    }
    chosen.push_back(static_cast<std::size_t>(generator.draw() % static_cast<Integer>(points.size())));
    while (chosen.size() < static_cast<std::size_t>(k)) {
        Point gaps = nearestGaps(points, chosen);
        double threshold = (static_cast<double>(generator.draw()) / 2147483647) * orderedSum(gaps), total = 0;
        std::size_t selected = points.size(), fallback = 0;
        for (std::size_t index = 0; index < points.size(); ++index) {
            if (gaps[index] > 0) fallback = index;
            total += gaps[index];
            if (total > threshold) { selected = index; break; }
        }
        chosen.push_back(selected == points.size() ? fallback : selected);
    }
    return chosen;
}
struct Improvement { Labels labels; int passes, transfers; double sse; };
static Improvement improve(const Points& points, const Labels& initial, int k, int limit) {
    Labels labels = initial, sizes = clusterSizes(labels, k);
    Points centers = clusterCenters(points, labels, k);
    int passes = 0, transfers = 0;
    bool moved = true;
    while (moved && passes < limit) {
        moved = false;
        ++passes;
        for (std::size_t index = 0; index < points.size(); ++index) {
            int own = labels[index];
            if (sizes[own] == 1) continue;
            double removal = (static_cast<double>(sizes[own]) / (sizes[own] - 1)) * squaredDistance(points[index], centers[own]);
            int target = -1;
            double targetCost = 0;
            for (int q = 0; q < k; ++q) if (q != own) {
                double cost = (static_cast<double>(sizes[q]) / (sizes[q] + 1)) * squaredDistance(points[index], centers[q]);
                if (target < 0 || cost < targetCost) { target = q; targetCost = cost; }
            }
            if (targetCost < removal) {
                labels[index] = target;
                --sizes[own];
                ++sizes[target];
                centers[own] = clusterCenter(points, labels, own);
                centers[target] = clusterCenter(points, labels, target);
                ++transfers;
                moved = true;
            }
        }
    }
    return {labels, passes, transfers, sse(points, labels, clusterCenters(points, labels, k))};
}
struct Run {
    std::string method;
    int number;
    Indices seeds;
    LloydResult result;
    double lloydSse;
    Improvement improved;
    Run(std::string method, int number, Indices seeds, const Points& points, int limit) : method(std::move(method)), number(number), seeds(std::move(seeds)) {
        Points initial;
        for (std::size_t index : this->seeds) initial.push_back(points[index]);
        result = lloyd(points, initial, limit);
        lloydSse = sse(points, result.labels, result.centers);
        improved = improve(points, result.labels, static_cast<int>(initial.size()), limit);
    }
};
static std::size_t bestRun(const std::vector<Run>& runs, const Indices& indices) {
    std::size_t best = indices.front();
    for (std::size_t index : indices) if (fourDecimal(runs[index].improved.sse) < fourDecimal(runs[best].improved.sse)) best = index;
    return best;
}
struct Solution {
    int k;
    std::vector<Indices> members;
    Labels sizes, labels;
    Points centers;
    double within;
    Solution(const Points& points, const Labels& initial, int k) : k(k), members(k), labels(initial.size()) {
        for (std::size_t i = 0; i < initial.size(); ++i) members[initial[i]].push_back(i);
        std::sort(members.begin(), members.end(), [](const Indices& first, const Indices& second) {
            return first.size() != second.size() ? first.size() > second.size() : first.front() < second.front();
        });
        for (int j = 0; j < k; ++j) {
            sizes.push_back(static_cast<int>(members[j].size()));
            for (std::size_t index : members[j]) labels[index] = j;
        }
        centers = clusterCenters(points, labels, k);
        within = sse(points, labels, centers);
    }
};
struct Candidate {
    int k;
    std::vector<Run> runs;
    Indices methodBests;
    std::size_t best;
    Solution solution;
    Point silhouettes;
    double silhouette = 0, ch = 0, db = 0, elbow = 0;
    std::optional<double> hartigan;
    Labels ruleNumbers;
    Lines names;
    Candidate(int k, std::vector<Run> runs, Indices methodBests, const Points& points) : k(k), runs(std::move(runs)), methodBests(std::move(methodBests)), best(bestRun(this->runs, this->methodBests)), solution(points, this->runs[best].improved.labels, k) {}
};
using Categories = std::map<std::string, Integer>;
static Categories categoryTotals(const std::vector<const Customer*>& customers) {
    Categories result;
    for (const Customer* customer : customers) for (const std::pair<const std::string, Integer>& entry : customer->categorySpend) result[entry.first] += entry.second;
    return result;
}
static Lines categoryRanking(const Categories& totals) {
    Lines result;
    for (const std::pair<const std::string, Integer>& entry : totals) if (entry.second > 0) result.push_back(entry.first);
    std::sort(result.begin(), result.end(), [&](const std::string& first, const std::string& second) { return totals.at(first) != totals.at(second) ? totals.at(first) > totals.at(second) : first < second; });
    return result;
}
static Integer categorySpend(const Categories& categories, const std::string& category) {
    Categories::const_iterator found = categories.find(category);
    return found == categories.end() ? 0 : found->second;
}
static std::string yesNo(bool value) { return value ? "yes" : "no"; }
static Lines joinBlocks(const std::vector<Lines>& blocks) {
    Lines lines;
    for (const Lines& block : blocks) {
        if (!lines.empty()) lines.push_back("");
        lines.insert(lines.end(), block.begin(), block.end());
    }
    return lines;
}
static double gini(std::vector<Integer> spends) {
    std::sort(spends.begin(), spends.end());
    Integer total = 0, weighted = 0, n = static_cast<Integer>(spends.size());
    for (std::size_t i = 0; i < spends.size(); ++i) { total += spends[i]; weighted += static_cast<Integer>(i + 1) * spends[i]; }
    return static_cast<double>(2 * weighted - (n + 1) * total) / (n * total);
}
template<class T> static T lowerMedian(std::vector<T> values) { std::sort(values.begin(), values.end()); return values[(values.size() - 1) / 2]; }
static Points selectedPoints(const Points& points, const Indices& indices) { Points result; for (std::size_t index : indices) result.push_back(points[index]); return result; }
class Analysis {
    Params params;
    TransactionData data;
    std::vector<NamingRule> rules;
    Minstd generator;
    std::vector<Order> referenceOrders;
    CustomerOrders customerOrders;
    std::vector<Customer> customers;
    std::map<std::string, std::size_t> numbers;
    int n, k = 0, finalVotes = 0;
    std::size_t selected = 0;
    Point means, deviations;
    Points points;
    std::vector<Candidate> candidates;
    std::vector<std::pair<std::string, int>> votes;
    Point distances, otherDistances;
    Labels others, codes;
    std::vector<std::array<int, 3>> scores;
    Integer totalSpend = 0;
    Categories overallCategories;
    Lines categoryNames;
    std::vector<std::vector<const Customer*>> segmentCustomers;
    std::vector<Integer> segmentSpends;
    std::vector<Categories> segmentCategories;
    std::vector<Lines> rankings;
    Point segmentSse;
    Points jaccards;
    const Candidate& final() const { return candidates[selected]; }
    const Candidate& candidate(int candidateK) const { return candidates[candidateK - params.kMin]; }
    std::string ids(const Indices& indices) const { Lines result; for (std::size_t index : indices) result.push_back(customers[index].id); return join(result); }
    static std::string runSummary(const Run& run) { return text(run.method, " restart ", run.number, " sse ", realText(run.improved.sse)); }
    void analyze() {
        Points transformed;
        for (std::size_t i = 0; i < customers.size(); ++i) { numbers[customers[i].id] = i; transformed.push_back(customers[i].transformed()); }
        std::pair<Point, Point> scales = standardization(transformed);
        means = scales.first;
        deviations = scales.second;
        for (const Point& values : transformed) points.push_back(standardize(values, means, deviations));
        for (int candidateK = params.kMin; candidateK <= params.kMax; ++candidateK) {
            std::vector<Run> runs;
            Indices bests;
            for (const std::string& method : params.methods) {
                Indices methodRuns;
                for (int number = 1; number <= params.restarts; ++number) {
                    methodRuns.push_back(runs.size());
                    runs.emplace_back(method, number, initialSeeds(method, points, candidateK, number, generator), points, params.maxIterations);
                }
                bests.push_back(bestRun(runs, methodRuns));
            }
            candidates.emplace_back(candidateK, std::move(runs), std::move(bests), points);
        }
        Points table = distanceTable(points);
        for (std::size_t i = 0; i < candidates.size(); ++i) {
            Candidate& current = candidates[i];
            const Solution& solution = current.solution;
            current.silhouettes = silhouettes(table, solution.labels, solution.sizes);
            current.silhouette = mean(current.silhouettes);
            current.ch = calinskiHarabasz(points, solution.centers, solution.sizes, solution.within);
            current.db = daviesBouldin(points, solution.labels, solution.centers, solution.sizes);
            current.elbow = elbow(current.k, params.kMin, params.kMax, solution.within, candidates.front().solution.within, candidates.back().solution.within);
            if (i + 1 < candidates.size()) current.hartigan = hartigan(solution.within, candidates[i + 1].solution.within, n, current.k);
            for (const Point& center : solution.centers) {
                int number = ruleNumber(rules, center);
                int repeats = static_cast<int>(std::count(current.ruleNumbers.begin(), current.ruleNumbers.end(), number));
                current.ruleNumbers.push_back(number);
                current.names.push_back(rules[number].name + (repeats == 0 ? "" : text('_', repeats + 1)));
            }
        }
        std::size_t elbowBest = 1, silhouetteBest = 0, chBest = 0, dbBest = 0;
        int hartiganVote = params.kMax;
        bool hartiganFound = false;
        for (std::size_t i = 0; i < candidates.size(); ++i) {
            const Candidate& current = candidates[i];
            if (i > 0 && i + 1 < candidates.size() && fourDecimal(current.elbow) > fourDecimal(candidates[elbowBest].elbow)) elbowBest = i;
            if (fourDecimal(current.silhouette) > fourDecimal(candidates[silhouetteBest].silhouette)) silhouetteBest = i;
            if (fourDecimal(current.ch) > fourDecimal(candidates[chBest].ch)) chBest = i;
            if (fourDecimal(current.db) < fourDecimal(candidates[dbBest].db)) dbBest = i;
            if (!hartiganFound && current.hartigan && *current.hartigan <= 10) { hartiganVote = current.k; hartiganFound = true; }
        }
        votes = {{"elbow", candidates[elbowBest].k}, {"silhouette", candidates[silhouetteBest].k}, {"calinski_harabasz", candidates[chBest].k}, {"davies_bouldin", candidates[dbBest].k}, {"hartigan", hartiganVote}};
        for (std::size_t i = 0; i < candidates.size(); ++i) {
            int count = 0;
            for (const std::pair<std::string, int>& vote : votes) if (vote.second == candidates[i].k) ++count;
            if (count > finalVotes || (count == finalVotes && fourDecimal(candidates[i].silhouette) > fourDecimal(candidates[selected].silhouette))) { selected = i; finalVotes = count; }
        }
        k = final().k;
        const Solution& solution = final().solution;
        std::vector<const Customer*> all;
        segmentCustomers.resize(k);
        segmentSpends.resize(k);
        segmentSse.resize(k);
        for (std::size_t i = 0; i < customers.size(); ++i) {
            int label = solution.labels[i], other = -1;
            double otherSquared = 0;
            for (int j = 0; j < k; ++j) if (j != label) {
                double squared = squaredDistance(points[i], solution.centers[j]);
                if (other < 0 || squared < otherSquared) { other = j; otherSquared = squared; }
            }
            distances.push_back(std::sqrt(squaredDistance(points[i], solution.centers[label])));
            others.push_back(other);
            otherDistances.push_back(std::sqrt(otherSquared));
            std::array<int, 3> score{{1, 1, 1}};
            std::array<int, 3> lower{{0, 0, 0}};
            for (const Customer& customer : customers) { lower[0] += customer.recency > customers[i].recency; lower[1] += customer.frequency < customers[i].frequency; lower[2] += customer.spend < customers[i].spend; }
            for (std::size_t part = 0; part < 3; ++part) score[part] += 5 * lower[part] / n;
            scores.push_back(score);
            codes.push_back(100 * score[0] + 10 * score[1] + score[2]);
            totalSpend += customers[i].spend;
            all.push_back(&customers[i]);
            segmentCustomers[label].push_back(&customers[i]);
            segmentSpends[label] += customers[i].spend;
            segmentSse[label] += squaredDistance(points[i], solution.centers[label]);
        }
        overallCategories = categoryTotals(all);
        for (const std::pair<const std::string, Integer>& entry : overallCategories) categoryNames.push_back(entry.first);
        for (const std::vector<const Customer*>& group : segmentCustomers) { segmentCategories.push_back(categoryTotals(group)); rankings.push_back(categoryRanking(segmentCategories.back())); }
        int sampleSize = n * params.subsamplePercent / 100;
        jaccards.resize(k);
        for (int repeat = 0; repeat < params.subsamples; ++repeat) {
            Indices order(customers.size());
            std::iota(order.begin(), order.end(), std::size_t{0});
            for (int t = 0; t < sampleSize; ++t) {
                std::size_t index = static_cast<std::size_t>(t + generator.draw() % (n - t));
                std::swap(order[t], order[index]);
            }
            order.resize(sampleSize);
            std::sort(order.begin(), order.end());
            LloydResult result = lloyd(selectedPoints(points, order), solution.centers, params.maxIterations);
            for (int segment = 0; segment < k; ++segment) {
                double best = 0;
                for (int j = 0; j < k; ++j) {
                    int both = 0, either = 0;
                    for (std::size_t index = 0; index < order.size(); ++index) {
                        bool member = solution.labels[order[index]] == segment, assigned = result.labels[index] == j;
                        both += member && assigned;
                        either += member || assigned;
                    }
                    if (either > 0) best = std::max(best, static_cast<double>(both) / either);
                }
                jaccards[segment].push_back(best);
            }
        }
    }
    Lines featuresLines() const {
        Lines lines{"customer,recency,frequency,monetary,basket,categories,tenure,z_recency,z_frequency,z_monetary,z_basket,z_categories,z_tenure"};
        for (std::size_t i = 0; i < customers.size(); ++i) {
            const Customer& customer = customers[i];
            Lines fields{customer.id, text(customer.recency), text(customer.frequency), amount(customer.spend), realText(customer.basket), text(customer.categories), text(customer.tenure)};
            for (double value : points[i]) fields.push_back(realText(value));
            lines.push_back(join(fields, ","));
        }
        return lines;
    }
    Lines runsLines() const {
        std::vector<Lines> blocks;
        for (const Candidate& current : candidates) {
            Lines lines{text("k ", current.k)};
            for (const Run& run : current.runs) add(lines, "run ", run.method, ' ', run.number, " seeds ", ids(run.seeds), " iterations ", run.result.iterations, " converged ", yesNo(run.result.converged), " reseeds ", run.result.reseeds, " sse ", realText(run.lloydSse), " passes ", run.improved.passes, " transfers ", run.improved.transfers, " refined ", realText(run.improved.sse));
            for (std::size_t index : current.methodBests) add(lines, "best ", runSummary(current.runs[index]));
            add(lines, "chosen ", runSummary(current.runs[current.best]));
            add(lines, "sizes ", join(current.solution.sizes));
            blocks.push_back(std::move(lines));
        }
        return joinBlocks(blocks);
    }
    Lines selectionLines() const {
        Lines indices{"indices"}, voteLines{"votes"}, names{"segments"}, stability{"stability"};
        for (std::size_t i = 0; i < candidates.size(); ++i) {
            const Candidate& current = candidates[i];
            add(indices, "k=", current.k, " sse ", realText(current.solution.within), " elbow ", realText(current.elbow), " silhouette ", realText(current.silhouette), " calinski_harabasz ", realText(current.ch), " davies_bouldin ", realText(current.db), " hartigan ", current.hartigan ? realText(*current.hartigan) : "-");
            Lines parts{text("k=", current.k)};
            for (int j = 0; j < current.k; ++j) parts.push_back(text(current.names[j], ':', current.solution.sizes[j]));
            names.push_back(join(parts));
            parts = {text("k=", current.k)};
            for (std::size_t first = 0; first < current.methodBests.size(); ++first) for (std::size_t second = first + 1; second < current.methodBests.size(); ++second) {
                const Run& a = current.runs[current.methodBests[first]];
                const Run& b = current.runs[current.methodBests[second]];
                parts.push_back(text(a.method, ':', b.method, ' ', realText(adjustedRandIndex(a.improved.labels, b.improved.labels))));
            }
            parts.push_back("final");
            for (std::size_t index : current.methodBests) { const Run& run = current.runs[index]; parts.push_back(text(run.method, ' ', realText(adjustedRandIndex(run.improved.labels, current.solution.labels)))); }
            parts.push_back(text("next ", i + 1 < candidates.size() ? realText(adjustedRandIndex(current.solution.labels, candidates[i + 1].solution.labels)) : "-"));
            stability.push_back(join(parts));
        }
        for (const std::pair<std::string, int>& vote : votes) add(voteLines, vote.first, " k=", vote.second);
        add(voteLines, "chosen k=", k, " votes ", finalVotes);
        return joinBlocks({indices, voteLines, names, stability});
    }
    std::string recommendation(std::size_t index) const {
        for (const std::string& category : rankings[final().solution.labels[index]]) if (categorySpend(customers[index].categorySpend, category) <= 0) return category;
        return "-";
    }
    Lines segmentsLines() const {
        Lines lines{"customer,segment,name,distance,other,other_distance,silhouette,recommend"};
        for (std::size_t i = 0; i < customers.size(); ++i) {
            int label = final().solution.labels[i];
            add(lines, customers[i].id, ',', label + 1, ',', final().names[label], ',', realText(distances[i]), ',', others[i] + 1, ',', realText(otherDistances[i]), ',', realText(final().silhouettes[i]), ',', recommendation(i));
        }
        return lines;
    }
    std::string related(const Indices& members, int otherK) const {
        if (otherK < params.kMin || otherK > params.kMax) return text("k=", otherK, " -");
        Labels counts(otherK);
        for (std::size_t index : members) ++counts[candidate(otherK).solution.labels[index]];
        int best = static_cast<int>(std::max_element(counts.begin(), counts.end()) - counts.begin());
        return text("k=", otherK, " segment ", best + 1, " shared ", counts[best]);
    }
    std::vector<Integer> spends(const std::vector<const Customer*>& group) const { std::vector<Integer> result; for (const Customer* customer : group) result.push_back(customer->spend); return result; }
    Lines segmentProfile(int segment) const {
        const Indices& members = final().solution.members[segment];
        const std::vector<const Customer*>& group = segmentCustomers[segment];
        int size = static_cast<int>(members.size());
        const Point& center = final().solution.centers[segment];
        Integer spend = segmentSpends[segment];
        Lines lines;
        add(lines, "segment ", segment + 1, ' ', final().names[segment], " rule ", final().ruleNumbers[segment] + 1, " size ", size, " share ", realText(static_cast<double>(size) / n), " revenue ", amount(spend), " revenue_share ", realText(static_cast<double>(spend) / totalSpend));
        add(lines, "  center ", reals(center));
        Point original = originalScale(center, means, deviations);
        Lines parts{"  value"};
        for (std::size_t feature = 0; feature < featureNames.size(); ++feature) parts.push_back(text(featureNames[feature], ' ', realText(original[feature])));
        lines.push_back(join(parts));
        Indices order(center.size());
        std::iota(order.begin(), order.end(), std::size_t{0});
        std::sort(order.begin(), order.end(), [&](std::size_t a, std::size_t b) { return std::abs(center[a]) != std::abs(center[b]) ? std::abs(center[a]) > std::abs(center[b]) : a < b; });
        add(lines, "  traits ", center[order[0]] > 0 ? "high_" : "low_", featureNames[order[0]], ' ', center[order[1]] > 0 ? "high_" : "low_", featureNames[order[1]]);
        Point medians;
        for (std::size_t feature = 0; feature < featureNames.size(); ++feature) { Point values; for (const Customer* customer : group) values.push_back(customer->values()[feature]); medians.push_back(lowerMedian(values)); }
        add(lines, "  median recency ", static_cast<int>(medians[0]), " frequency ", static_cast<int>(medians[1]), " monetary ", amount(lowerMedian(spends(group))), " basket ", realText(medians[3]), " categories ", static_cast<int>(medians[4]), " tenure ", static_cast<int>(medians[5]));
        add(lines, "  related ", related(members, k - 1), ' ', related(members, k + 1));
        Indices top = members;
        std::sort(top.begin(), top.end(), [&](std::size_t a, std::size_t b) { return customers[a].spend != customers[b].spend ? customers[a].spend > customers[b].spend : a < b; });
        parts = {"  top_customers"};
        for (std::size_t position = 0; position < top.size() && position < static_cast<std::size_t>(params.topCustomers); ++position) parts.push_back(text(customers[top[position]].id, ' ', amount(customers[top[position]].spend)));
        lines.push_back(join(parts));
        Point gaps;
        int overdue = 0, cancelled = 0;
        Labels bins(params.orderBins.size() + 1);
        Integer gross = 0, returned = 0;
        for (const Customer* customer : group) {
            if (customer->frequency >= 2) {
                Integer active = customer->tenure - customer->recency, intervals = customer->frequency - 1;
                gaps.push_back(static_cast<double>(active) / intervals);
                overdue += customer->recency * intervals > params.overdueFactor * active;
            }
            for (const Order* orderValue : customer->orders) {
                std::size_t bin = 0;
                for (Integer bound : params.orderBins) bin += orderValue->net >= 100 * bound;
                ++bins[bin];
            }
            for (const Order* orderValue : customerOrders.at(customer->id)) {
                cancelled += orderValue->net <= 0;
                for (const Transaction* row : orderValue->rows) { gross += std::max(row->amount, Integer{0}); returned -= std::min(row->amount, Integer{0}); }
            }
        }
        add(lines, "  cadence customers ", gaps.size(), " mean_gap ", gaps.empty() ? "-" : realText(mean(gaps)), " overdue ", overdue);
        add(lines, "  order_sizes ", join(bins));
        add(lines, "  sse ", realText(segmentSse[segment]), " share ", realText(segmentSse[segment] / final().solution.within));
        add(lines, "  gini ", realText(gini(spends(group))));
        add(lines, "  returns rate ", realText(static_cast<double>(returned) / gross), " returned ", amount(returned), " cancelled ", cancelled);
        Point values;
        int negative = 0;
        std::array<Integer, 3> scoreTotals{{0, 0, 0}};
        std::map<int, int> codeCounts;
        for (std::size_t index : members) {
            values.push_back(final().silhouettes[index]);
            negative += final().silhouettes[index] < 0;
            for (std::size_t part = 0; part < 3; ++part) scoreTotals[part] += scores[index][part];
            ++codeCounts[codes[index]];
        }
        add(lines, "  silhouette ", realText(mean(values)), " negative ", negative);
        int mode = codeCounts.begin()->first;
        for (const std::pair<const int, int>& entry : codeCounts) if (entry.second > codeCounts.at(mode)) mode = entry.first;
        add(lines, "  rfm r ", realText(static_cast<double>(scoreTotals[0]) / size), " f ", realText(static_cast<double>(scoreTotals[1]) / size), " m ", realText(static_cast<double>(scoreTotals[2]) / size), " mode ", mode, ' ', codeCounts.at(mode));
        parts = {"  categories"};
        for (std::size_t position = 0; position < rankings[segment].size() && position < static_cast<std::size_t>(params.topCategories); ++position) {
            const std::string& category = rankings[segment][position];
            double share = static_cast<double>(segmentCategories[segment].at(category)) / spend;
            double lift = share / (static_cast<double>(overallCategories.at(category)) / totalSpend);
            parts.push_back(text(category, ' ', realText(share), ' ', realText(lift)));
        }
        lines.push_back(join(parts));
        Indices outliers;
        if (size >= 2) {
            Point values;
            for (std::size_t index : members) values.push_back(distances[index]);
            double limit = mean(values) + params.outlierSd * sampleSd(values);
            for (std::size_t index : members) if (distances[index] > limit) outliers.push_back(index);
        }
        add(lines, "  outliers ", outliers.size(), outliers.empty() ? "" : " " + ids(outliers));
        return lines;
    }
    Lines profilesLines() const {
        std::vector<const Customer*> all;
        for (const Customer& customer : customers) all.push_back(&customer);
        std::vector<Lines> blocks{{text("segments k=", k, " customers ", n, " revenue ", amount(totalSpend), " gini ", realText(gini(spends(all))))}};
        for (int segment = 0; segment < k; ++segment) blocks.push_back(segmentProfile(segment));
        Labels clusterNumbers(k);
        std::iota(clusterNumbers.begin(), clusterNumbers.end(), 1);
        Lines mix{text("category_mix ", join(clusterNumbers))};
        for (const std::string& category : categoryNames) {
            Point shares;
            for (int segment = 0; segment < k; ++segment) shares.push_back(static_cast<double>(categorySpend(segmentCategories[segment], category)) / segmentSpends[segment]);
            add(mix, category, ' ', reals(shares));
        }
        Lines recency{text("rfm_recency ", join(clusterNumbers))};
        for (int score = 5; score >= 1; --score) {
            Labels counts(k);
            for (std::size_t i = 0; i < customers.size(); ++i) if (scores[i][0] == score) ++counts[final().solution.labels[i]];
            add(recency, "r=", score, ' ', join(counts));
        }
        add(recency, "ari rfm_codes ", realText(adjustedRandIndex(codes, final().solution.labels)));
        Lines centerDistances{"center_distances"};
        for (int segment = 0; segment < k; ++segment) {
            Point row;
            for (const Point& other : final().solution.centers) row.push_back(std::sqrt(squaredDistance(final().solution.centers[segment], other)));
            add(centerDistances, segment + 1, ' ', reals(row));
        }
        blocks.push_back(mix);
        blocks.push_back(recency);
        blocks.push_back(centerDistances);
        return joinBlocks(blocks);
    }
    Lines robustnessLines() const {
        Lines samples{text("subsamples ", params.subsamples, " size ", n * params.subsamplePercent / 100)}, ablation{"ablation"};
        for (int segment = 0; segment < k; ++segment) add(samples, "segment ", segment + 1, ' ', final().names[segment], " mean_jaccard ", realText(mean(jaccards[segment])), " min_jaccard ", realText(*std::min_element(jaccards[segment].begin(), jaccards[segment].end())));
        for (std::size_t feature = 0; feature < featureNames.size(); ++feature) {
            Points reduced = points;
            for (Point& point : reduced) point.erase(point.begin() + static_cast<std::ptrdiff_t>(feature));
            Indices seeds = maximin(reduced, k, 1);
            Run run("maximin", 1, seeds, reduced, params.maxIterations);
            add(ablation, "without ", featureNames[feature], " seeds ", ids(seeds), " iterations ", run.result.iterations, " converged ", yesNo(run.result.converged), " transfers ", run.improved.transfers, " sse ", realText(run.improved.sse), " ari ", realText(adjustedRandIndex(run.improved.labels, final().solution.labels)));
        }
        const Indices& members = final().solution.members[0];
        Points subset = selectedPoints(points, members);
        Indices seeds = maximin(subset, 2, 1), originalSeeds;
        for (std::size_t index : seeds) originalSeeds.push_back(members[index]);
        Run run("maximin", 1, seeds, subset, params.maxIterations);
        Solution parts(subset, run.improved.labels, 2);
        Lines drilldown{text("drilldown segment 1 ", final().names[0], " size ", members.size(), " seeds ", ids(originalSeeds), " iterations ", run.result.iterations, " converged ", yesNo(run.result.converged), " transfers ", run.improved.transfers), text("sse before ", realText(segmentSse[0]), " after ", realText(run.improved.sse), " gain ", realText(segmentSse[0] - run.improved.sse))};
        for (int part = 0; part < 2; ++part) add(drilldown, "part ", part + 1, " size ", parts.sizes[part], " center ", reals(parts.centers[part]));
        return joinBlocks({samples, ablation, drilldown});
    }
    Lines trackingLines() const {
        Lines periods{text("periods ", params.periods, " days ", params.periodDays)};
        for (int q = 1; q <= params.periods; ++q) {
            int first = params.referenceDay - q * params.periodDays + 1, last = params.referenceDay - (q - 1) * params.periodDays;
            std::vector<Integer> revenue(k);
            Labels active(k), acquired(k);
            for (std::size_t i = 0; i < customers.size(); ++i) {
                int label = final().solution.labels[i];
                bool seen = false;
                for (const Order* order : customers[i].orders) if (first <= order->day && order->day <= last) { revenue[label] += order->net; seen = true; }
                active[label] += seen;
                acquired[label] += first <= params.referenceDay - customers[i].tenure && params.referenceDay - customers[i].tenure <= last;
            }
            Lines amounts;
            for (Integer value : revenue) amounts.push_back(amount(value));
            add(periods, "period ", q, " days ", first, ' ', last, " revenue ", join(amounts), " active ", join(active), " acquired ", join(acquired));
        }
        std::vector<Order> snapshotOrders = groupOrders(data.validRows, 1, params.snapshotDay);
        std::vector<Customer> snapshot = eligibleCustomers(snapshotOrders, params.snapshotDay);
        std::map<std::string, int> origins;
        for (const Customer& customer : snapshot) {
            Point point = standardize(customer.transformed(), means, deviations);
            origins[customer.id] = assign(Points{point}, final().solution.centers).first[0];
        }
        std::vector<Labels> table(k + 1, Labels(k));
        Lines moved;
        int stayed = 0, fresh = 0, lost = 0;
        for (std::size_t i = 0; i < customers.size(); ++i) {
            std::map<std::string, int>::const_iterator found = origins.find(customers[i].id);
            int origin = found == origins.end() ? k : found->second, label = final().solution.labels[i];
            ++table[origin][label];
            if (origin == k) ++fresh;
            else if (origin == label) ++stayed;
            else add(moved, customers[i].id, ' ', origin + 1, ' ', label + 1);
        }
        for (const std::pair<const std::string, int>& entry : origins) lost += !numbers.count(entry.first);
        Labels clusterNumbers(k);
        std::iota(clusterNumbers.begin(), clusterNumbers.end(), 1);
        Lines migration{text("migration day ", params.snapshotDay, " customers ", origins.size()), text("from\\to ", join(clusterNumbers))};
        for (int origin = 0; origin <= k; ++origin) add(migration, origin == k ? "none" : text(origin + 1), ' ', join(table[origin]));
        migration.push_back("moved_customers");
        migration.insert(migration.end(), moved.begin(), moved.end());
        add(migration, "stayed ", stayed, " moved ", moved.size(), " new ", fresh, " lost ", lost);
        int first = params.referenceDay + 1, last = params.referenceDay + params.outcomeDays;
        std::vector<Order> outcomeOrders = groupOrders(data.validRows, first, last);
        CustomerOrders purchases = ordersByCustomer(outcomeOrders, true);
        Lines outcome{text("outcome days ", first, ' ', last)};
        for (int segment = 0; segment < k; ++segment) {
            int buyers = 0;
            Integer spend = 0;
            for (const Customer* customer : segmentCustomers[segment]) {
                CustomerOrders::const_iterator found = purchases.find(customer->id);
                if (found != purchases.end()) { ++buyers; for (const Order* order : found->second) spend += order->net; }
            }
            int size = final().solution.sizes[segment];
            add(outcome, "segment ", segment + 1, ' ', final().names[segment], " size ", size, " buyers ", buyers, " rate ", realText(static_cast<double>(buyers) / size), " revenue ", amount(spend), " per_customer ", realText((static_cast<double>(spend) / 100) / size));
        }
        int outsiders = 0;
        Integer outsiderSpend = 0;
        for (const std::pair<const std::string, std::vector<const Order*>>& entry : purchases) if (!numbers.count(entry.first)) { ++outsiders; for (const Order* order : entry.second) outsiderSpend += order->net; }
        add(outcome, "unsegmented buyers ", outsiders, " revenue ", amount(outsiderSpend));
        return joinBlocks({periods, migration, outcome});
    }
    Lines summaryLines() const {
        int used = 0, returned = 0, later = 0, valid = 0;
        for (const Transaction& row : data.validRows) {
            if (row.day <= params.referenceDay) { ++used; returned += row.amount < 0; }
            else ++later;
        }
        for (const Order& order : referenceOrders) valid += order.net > 0;
        Lines excluded;
        for (const std::string& id : data.customers) if (!numbers.count(id)) excluded.push_back(id);
        Lines counts{text("rows ", data.rowCount, " duplicates ", data.duplicates, " zero ", data.free, " used ", used, " returns ", returned, " later ", later), text("orders ", referenceOrders.size(), " valid ", valid, " cancelled ", referenceOrders.size() - valid), text("customers ", data.customers.size(), " clustered ", n, " excluded ", excluded.size()), text("excluded_ids ", excluded.empty() ? "-" : join(excluded))};
        Lines categories, features, correlations{text("correlation ", join(featureNames))};
        for (const std::string& category : categoryNames) {
            int buyers = 0;
            for (const Customer& customer : customers) buyers += categorySpend(customer.categorySpend, category) > 0;
            Integer total = overallCategories.at(category);
            add(categories, "category ", category, " revenue ", amount(total), " share ", realText(static_cast<double>(total) / totalSpend), " customers ", buyers);
        }
        for (std::size_t feature = 0; feature < featureNames.size(); ++feature) {
            Point column, row;
            for (const Customer& customer : customers) column.push_back(customer.values()[feature]);
            add(features, "feature ", featureNames[feature], " transform ", sqrtFeatures[feature] ? "sqrt" : "none", " raw_mean ", realText(mean(column)), " raw_sd ", realText(sampleSd(column)), " mean ", realText(means[feature]), " sd ", realText(deviations[feature]));
            for (std::size_t second = 0; second < featureNames.size(); ++second) row.push_back(correlation(points, feature, second));
            add(correlations, featureNames[feature], ' ', reals(row));
        }
        return joinBlocks({counts, categories, features, correlations});
    }
public:
    Analysis(Params params, TransactionData data, std::vector<NamingRule> rules) : params(std::move(params)), data(std::move(data)), rules(std::move(rules)), generator(this->params.seed), referenceOrders(groupOrders(this->data.validRows, 1, this->params.referenceDay)), customerOrders(ordersByCustomer(referenceOrders)), customers(eligibleCustomers(referenceOrders, this->params.referenceDay)), n(static_cast<int>(customers.size())) { analyze(); }
    void run() const {
        std::filesystem::create_directories("output");
        writeLines("output/features.csv", featuresLines());
        writeLines("output/runs.txt", runsLines());
        writeLines("output/selection.txt", selectionLines());
        writeLines("output/segments.csv", segmentsLines());
        writeLines("output/profiles.txt", profilesLines());
        writeLines("output/robustness.txt", robustnessLines());
        writeLines("output/tracking.txt", trackingLines());
        writeLines("output/summary.txt", summaryLines());
    }
};
int main() {
    Analysis analysis(readParams("input/params.txt"), readTransactions("input/transactions.csv"), readRules("input/segment_rules.txt"));
    analysis.run();
}
