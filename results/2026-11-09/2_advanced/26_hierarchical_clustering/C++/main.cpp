#include "clustering.hpp"

static std::string real(double value) {
    std::ostringstream stream;
    stream << std::fixed << std::setprecision(4) << value;
    return stream.str() == "-0.0000" ? "0.0000" : stream.str();
}
static std::string real(const std::optional<double>& value) { return value ? real(*value) : "-"; }
static std::string exactReal(Fraction value) {
    Integer magnitude = value.numerator < 0 ? -value.numerator : value.numerator;
    Integer rounded = (2 * magnitude * 10000 + value.denominator) / (2 * value.denominator);
    std::ostringstream stream;
    if (value.numerator < 0 && rounded) stream << '-';
    stream << rounded / 10000 << '.' << std::setfill('0') << std::setw(4) << rounded % 10000;
    return stream.str();
}
static std::string ariText(Fraction value) { return text(value.numerator, '/', value.denominator, ' ', exactReal(value)); }
static double fourDigit(double value) { return std::abs(value) >= 1e12 ? value : std::round(value * 10000) / 10000; }
static std::string joined(const Lines& lines, const std::string& separator = " ") {
    std::string result;
    for (std::size_t index = 0; index < lines.size(); ++index) { if (index) result += separator; result += lines[index]; }
    return result;
}
static std::string reals(const Values& values) { Lines parts; for (double value : values) parts.push_back(real(value)); return joined(parts); }
static std::string integers(const Indices& values) { Lines parts; for (int value : values) parts.push_back(std::to_string(value)); return joined(parts); }
static Values pairValues(const Matrix& matrix) {
    Values pairs;
    for (std::size_t i = 0; i < matrix.size(); ++i) for (std::size_t j = i + 1; j < matrix.size(); ++j) pairs.push_back(matrix[i][j]);
    return pairs;
}
static int histogramBin(double value, double maximum) { return std::min(9, static_cast<int>(std::floor(10 * value / maximum))); }
static Values centroid(const Matrix& vectors, const Indices& members) {
    Values center(vectors[0].size(), 0);
    for (std::size_t feature = 0; feature < center.size(); ++feature) {
        for (int index : members) center[feature] += vectors[index][feature];
        center[feature] /= members.size();
    }
    return center;
}
static Indices sequence(int count) { Indices result(count); std::iota(result.begin(), result.end(), 0); return result; }
static std::vector<Indices> clusterMembers(const Indices& partition, int groups) {
    std::vector<Indices> members(groups);
    for (std::size_t i = 0; i < partition.size(); ++i) members[partition[i] - 1].push_back(static_cast<int>(i));
    return members;
}
static int maximum(const Indices& values) { return *std::max_element(values.begin(), values.end()); }
static int majorityClass(const std::vector<Integer>& row) { return static_cast<int>(std::max_element(row.begin(), row.end()) - row.begin()); }
static void append(Lines& first, const Lines& second) { first.insert(first.end(), second.begin(), second.end()); }
static void paragraph(Lines& first, const Lines& second) { if (!first.empty()) first.emplace_back(); append(first, second); }
struct Tree {
    std::vector<Merge> merges;
    int count;
    Values heights, subtreeHeights;
    std::vector<std::pair<int, int>> children;
    Indices order, depths;
    std::vector<Indices> members;
    Tree(std::vector<Merge> items, int size) : merges(std::move(items)), count(size), children(orderedChildren(merges, count)), order(leafOrder(children, count)), depths(count, 0) {
        for (int leaf = 0; leaf < count; ++leaf) members.push_back({leaf});
        for (const Merge& merge : merges) {
            heights.push_back(merge.height);
            Indices leaves = members[merge.a]; leaves.insert(leaves.end(), members[merge.b].begin(), members[merge.b].end());
            members.push_back(std::move(leaves));
            depths.push_back(1 + std::max(depths[merge.a], depths[merge.b]));
            subtreeHeights.push_back(std::max({merge.height, subtreeHeight(merge.a), subtreeHeight(merge.b)}));
        }
    }
    int root() const { return 2 * count - 2; }
    double heightOf(int node) const { return node < count ? 0 : heights[node - count]; }
    double subtreeHeight(int node) const { return node < count ? 0 : subtreeHeights[node - count]; }
    Indices partition(const std::vector<bool>& chosen) const {
        Indices owner = sequence(count), numbers(2 * count - 1, 0);
        for (std::size_t step = 0; step < chosen.size(); ++step) if (chosen[step]) for (int leaf : members[count + step]) owner[leaf] = count + static_cast<int>(step);
        int groups = 0;
        for (int leaf : order) if (!numbers[owner[leaf]]) numbers[owner[leaf]] = ++groups;
        Indices result;
        for (int node : owner) result.push_back(numbers[node]);
        return result;
    }
    Indices cutInto(int groups) const {
        std::vector<bool> chosen(merges.size(), false);
        for (int step = 0; step < count - groups; ++step) chosen[step] = true;
        return partition(chosen);
    }
    Indices cutAt(double height) const { std::vector<bool> chosen; for (double value : subtreeHeights) chosen.push_back(value <= height); return partition(chosen); }
    Values cophenetic() const {
        Matrix matrix(count, Values(count, 0));
        for (const Merge& merge : merges) for (int i : members[merge.a]) for (int j : members[merge.b]) matrix[i][j] = matrix[j][i] = merge.height;
        return pairValues(matrix);
    }
    Values joiningHeights() const {
        Values result(count, 0);
        for (const Merge& merge : merges) for (int child : {merge.a, merge.b}) if (child < count) result[child] = merge.height;
        return result;
    }
    Values heightSequence(int step, Integer depth) const {
        if (depth == 0) return {};
        const Merge& merge = merges[step];
        Values result{merge.height};
        for (int child : {merge.a, merge.b}) if (child >= count) {
            Values following = heightSequence(child - count, depth - 1);
            result.insert(result.end(), following.begin(), following.end());
        }
        return result;
    }
    std::string newick(int node, const Lines& ids) const {
        if (node < count) return ids[node];
        int upper = children[node - count].first, lower = children[node - count].second;
        double height = heightOf(node);
        return "(" + newick(upper, ids) + ":" + real(height - heightOf(upper)) + "," + newick(lower, ids) + ":" + real(height - heightOf(lower)) + ")";
    }
};
struct Evaluation {
    Indices partition, sizes;
    std::optional<double> silhouette, dunn, ch;
    double wss;
    Fraction ari;
    std::string description() const { return "sizes " + integers(sizes) + " silhouette " + real(silhouette) + " dunn " + real(dunn) + " wss " + real(wss) + " ch " + real(ch) + " ari " + ariText(ari); }
};
struct LinkageResult {
    std::string method;
    Tree tree;
    Values cophenetic;
    double correlation;
    std::vector<Evaluation> heightCuts, countCuts;
    Indices labelPartition;
    LinkageResult(std::string name, Tree result) : method(std::move(name)), tree(std::move(result)), cophenetic(tree.cophenetic()), correlation(0) {}
};
class Study {
    Dataset data;
    int n, p, labelCount;
    Lines classes;
    Indices targets;
    Matrix vectors, delta;
    Values means, deviations, distancePairs;
    double distanceMax;
    Indices neighbors;
    std::vector<LinkageResult> results;
    std::size_t chosen = 0, position = 0;
    int kappa;
    Indices selected, majority;
    std::vector<Indices> members;
    Values silhouettes;
    Table table;
    Table classTable(const Indices& partition) const {
        Indices zero = partition;
        for (int& value : zero) --value;
        return contingencyTable(zero, targets, maximum(partition), labelCount);
    }
    Fraction labelAri(const Indices& partition) const { return adjustedRandIndex(classTable(partition)); }
    Fraction partitionAri(const Indices& first, const Indices& second) const {
        Indices a = first, b = second;
        for (int& value : a) --value;
        for (int& value : b) --value;
        return adjustedRandIndex(contingencyTable(a, b, maximum(first), maximum(second)));
    }
    Integer matchCount(const Indices& partition) const { Integer total = 0; for (const std::vector<Integer>& row : classTable(partition)) total += *std::max_element(row.begin(), row.end()); return total; }
    Matrix centroids(const Indices& partition) const {
        Matrix centers;
        for (const Indices& group : clusterMembers(partition, maximum(partition))) centers.push_back(centroid(vectors, group));
        return centers;
    }
    double withinSum(const Indices& partition) const {
        Matrix centers = centroids(partition);
        double total = 0;
        for (int i = 0; i < n; ++i) total += squaredDistance(vectors[i], centers[partition[i] - 1]);
        return total;
    }
    std::optional<double> meanSilhouette(const Indices& partition, const Matrix& distances) const {
        if (maximum(partition) < 2) return std::nullopt;
        Values values = silhouetteValues(partition, maximum(partition), distances);
        return sequentialSum(values) / partition.size();
    }
    Evaluation evaluate(const Indices& partition) const {
        int groups = maximum(partition);
        Evaluation result;
        result.partition = partition;
        for (const Indices& group : clusterMembers(partition, groups)) result.sizes.push_back(static_cast<int>(group.size()));
        result.wss = withinSum(partition);
        result.silhouette = meanSilhouette(partition, delta);
        double diameter = 0, separation = 0;
        bool found = false;
        for (int i = 0; i < n; ++i) for (int j = i + 1; j < n; ++j) {
            if (partition[i] == partition[j]) diameter = std::max(diameter, delta[i][j]);
            else if (!found || delta[i][j] < separation) { separation = delta[i][j]; found = true; }
        }
        if (groups >= 2 && diameter > 0) result.dunn = separation / diameter;
        if (groups >= 2 && groups < n) {
            Values overall = centroid(vectors, sequence(n));
            Matrix centers = centroids(partition);
            double bss = 0;
            for (int group = 0; group < groups; ++group) bss += result.sizes[group] * squaredDistance(centers[group], overall);
            result.ch = (bss / (groups - 1)) / (result.wss / (n - groups));
        }
        result.ari = labelAri(partition);
        return result;
    }
    std::string pairText(int i, int j) const { return text(real(delta[i][j]), ' ', data.ids[i], ' ', data.ids[j]); }
    Lines dataPart() const {
        Lines lines{text("data n ", n, " features ", p, " classes ", labelCount, " distance ", data.settings.distance, " standardize ", data.settings.standardize)};
        for (int feature = 0; feature < p; ++feature) add(lines, "feature ", data.features[feature], " mean ", real(means[feature]), " sd ", real(deviations[feature]));
        std::pair<int, int> smallest{0, 1}, largest{0, 1};
        for (int i = 0; i < n; ++i) for (int j = i + 1; j < n; ++j) {
            if (delta[i][j] < delta[smallest.first][smallest.second]) smallest = {i, j};
            if (delta[i][j] > delta[largest.first][largest.second]) largest = {i, j};
        }
        add(lines, "distances pairs ", distancePairs.size(), " min ", pairText(smallest.first, smallest.second), " max ", pairText(largest.first, largest.second), " mean ", real(sequentialSum(distancePairs) / distancePairs.size()));
        double total = 0; int reciprocal = 0;
        for (int i = 0; i < n; ++i) { total += delta[i][neighbors[i]]; if (i < neighbors[i] && neighbors[neighbors[i]] == i) ++reciprocal; }
        add(lines, "nearest_neighbors mean ", real(total / n), " reciprocal_pairs ", reciprocal);
        Indices labels = targets; for (int& label : labels) ++label;
        lines.push_back("labels " + evaluate(labels).description());
        return lines;
    }
    Lines correlationPart() const {
        Matrix columns(p, Values(n));
        for (int feature = 0; feature < p; ++feature) for (int i = 0; i < n; ++i) columns[feature][i] = data.raw[i][feature];
        Lines lines{"correlation " + joined(data.features)};
        for (int feature = 0; feature < p; ++feature) {
            Values values; for (const Values& other : columns) values.push_back(correlation(columns[feature], other));
            lines.push_back(data.features[feature] + " " + reals(values));
        }
        return lines;
    }
    Lines histogramPart() const {
        Indices counts(10, 0);
        for (double value : distancePairs) ++counts[histogramBin(value, distanceMax)];
        int highest = maximum(counts);
        Lines lines{"histogram"};
        for (int bin = 0; bin < 10; ++bin) {
            std::string line = text(real(bin * distanceMax / 10), ' ', real((bin + 1) * distanceMax / 10), ' ', counts[bin]);
            int length = counts[bin] * 50 / highest;
            if (length) line += " " + std::string(length, '#');
            lines.push_back(line);
        }
        return lines;
    }
    Lines linkagePart(const LinkageResult& result) const {
        const Tree& tree = result.tree;
        double path = 0;
        for (int row = 0; row < n - 1; ++row) path += delta[tree.order[row]][tree.order[row + 1]];
        Indices inversions;
        for (int step = 1; step < n - 1; ++step) if (tree.heights[step] < tree.heights[step - 1]) inversions.push_back(step);
        Lines lines{"linkage " + result.method, text("cophenetic ", real(result.correlation), " leaf_path ", real(path)), text("heights min ", real(*std::min_element(tree.heights.begin(), tree.heights.end())), " max ", real(*std::max_element(tree.heights.begin(), tree.heights.end())), " inversions ", inversions.size())};
        for (int step : inversions) add(lines, "inversion step ", step + 1, " height ", real(tree.heights[step]), " previous ", real(tree.heights[step - 1]));
        Values ordered = tree.subtreeHeights, gaps;
        std::sort(ordered.begin(), ordered.end());
        for (int k = 2; k <= data.settings.gapMaxK; ++k) gaps.push_back(ordered[n - k] - ordered[n - k - 1]);
        int suggested = 2;
        for (int k = 3; k <= data.settings.gapMaxK; ++k) if (fourDigit(gaps[k - 2]) > fourDigit(gaps[suggested - 2])) suggested = k;
        lines.push_back("gaps " + reals(gaps)); add(lines, "suggested_k ", suggested);
        Values joining = tree.joiningHeights(); Indices late = sequence(n);
        std::stable_sort(late.begin(), late.end(), [&joining](int a, int b) { return joining[a] > joining[b]; });
        Lines pairs; for (int i = 0; i < data.settings.listSize; ++i) pairs.push_back(data.ids[late[i]] + ":" + real(joining[late[i]]));
        lines.push_back("late_joiners " + joined(pairs));
        std::array<int, 3> kinds{};
        for (const Merge& merge : tree.merges) ++kinds[2 - (merge.a < n) - (merge.b < n)];
        add(lines, "merges leaf_leaf ", kinds[0], " leaf_cluster ", kinds[1], " cluster_cluster ", kinds[2], " depth ", tree.depths[tree.root()]);
        Integer matches = matchCount(result.labelPartition);
        add(lines, "label_cut k ", labelCount, " purity ", matches, '/', n, ' ', real(static_cast<double>(matches) / n));
        add(lines, "inconsistency depth ", data.settings.inconsistencyDepthText);
        for (int step = n - data.settings.inconsistencyCount - 1; step < n - 1; ++step) {
            Values heights = tree.heightSequence(step, data.settings.inconsistencyDepth);
            double mean = sequentialSum(heights) / heights.size(), deviation = 0, coefficient = 0;
            if (heights.size() >= 2) { double squares = 0; for (double height : heights) { double difference = height - mean; squares += difference * difference; } deviation = std::sqrt(squares / (heights.size() - 1)); coefficient = (tree.heights[step] - mean) / deviation; }
            add(lines, "step ", step + 1, " height ", real(tree.heights[step]), " mean ", real(mean), " sd ", real(deviation), " count ", heights.size(), " coefficient ", real(coefficient));
        }
        for (std::size_t i = 0; i < result.heightCuts.size(); ++i) add(lines, "cut height ", real(data.settings.cutHeights[i]), " clusters ", result.heightCuts[i].sizes.size(), ' ', result.heightCuts[i].description());
        for (std::size_t i = 0; i < result.countCuts.size(); ++i) add(lines, "cut k ", data.settings.cutCounts[i], ' ', result.countCuts[i].description());
        return lines;
    }
    Lines mstPart() const {
        const LinkageResult* single = nullptr;
        for (const LinkageResult& result : results) if (result.method == "single") single = &result;
        std::vector<Edge> edges = minimumSpanningTree(delta);
        Values weights; double total = 0; std::vector<std::vector<bool>> linked(n, std::vector<bool>(n, false));
        for (const Edge& edge : edges) { total += edge.weight; weights.push_back(edge.weight); linked[edge.parent][edge.child] = linked[edge.child][edge.parent] = true; }
        std::sort(weights.begin(), weights.end());
        bool heightsMatch = true; int nearestEdges = 0;
        for (int step = 0; step < n - 1; ++step) if (std::abs(weights[step] - single->tree.heights[step]) > 0.000000001) heightsMatch = false;
        for (int i = 0; i < n; ++i) nearestEdges += linked[i][neighbors[i]];
        Lines lines{text("mst total ", real(total), " heights ", heightsMatch ? "match" : "mismatch", " nn_edges ", nearestEdges, '/', n)};
        Indices order = sequence(n - 1);
        std::stable_sort(order.begin(), order.end(), [&edges](int a, int b) { return edges[a].weight < edges[b].weight; });
        for (std::size_t position = 0; position < data.settings.cutCounts.size(); ++position) {
            int k = data.settings.cutCounts[position]; Indices components = sequence(n);
            for (int i = 0; i < n - k; ++i) {
                const Edge& edge = edges[order[i]]; int old = components[edge.child], current = components[edge.parent];
                for (int& value : components) if (value == old) value = current;
            }
            bool agrees = true;
            for (int i = 0; i < n; ++i) for (int j = i + 1; j < n; ++j) if ((components[i] == components[j]) != (single->countCuts[position].partition[i] == single->countCuts[position].partition[j])) agrees = false;
            add(lines, "mst partition k ", k, ' ', agrees ? "match" : "mismatch");
        }
        return lines;
    }
    Lines comparePart() const {
        Lines lines{text("compare linkage ", data.settings.compareLinkage, " k ", labelCount)};
        for (const std::string& kind : Lines{"euclidean", "manhattan", "correlation"}) {
            Matrix distances = distanceMatrix(vectors, kind); Tree tree(agglomerate(distances, data.settings.compareLinkage), n);
            Indices partition = tree.cutInto(labelCount);
            add(lines, "metric ", kind, " cophenetic ", real(correlation(pairValues(distances), tree.cophenetic())), " silhouette ", real(meanSilhouette(partition, distances)), " ari ", ariText(labelAri(partition)));
        }
        return lines;
    }
    Lines summaryPart() const {
        Indices ranking = sequence(static_cast<int>(results.size()));
        std::stable_sort(ranking.begin(), ranking.end(), [this](int a, int b) { return fourDigit(results[a].correlation) > fourDigit(results[b].correlation); });
        Lines names; for (int index : ranking) names.push_back(results[index].method);
        Lines lines{"summary", "cophenetic_ranking " + joined(names)};
        for (std::size_t i = 0; i < data.settings.cutCounts.size(); ++i) {
            std::size_t best = 0;
            for (std::size_t method = 1; method < results.size(); ++method) if (results[method].countCuts[i].ari > results[best].countCuts[i].ari) best = method;
            add(lines, "best_ari k ", data.settings.cutCounts[i], ' ', results[best].method, ' ', ariText(results[best].countCuts[i].ari));
        }
        for (const LinkageResult& result : results) {
            std::size_t best = 0;
            for (std::size_t i = 1; i < result.countCuts.size(); ++i) if (fourDigit(*result.countCuts[i].silhouette) > fourDigit(*result.countCuts[best].silhouette)) best = i;
            add(lines, "best_silhouette ", result.method, " k ", data.settings.cutCounts[best], ' ', real(result.countCuts[best].silhouette));
        }
        add(lines, "selected ", results[chosen].method, " k ", kappa);
        return lines;
    }
    std::string classCounts(const Tree& tree, int node) const {
        Indices counts(labelCount, 0);
        for (int leaf : tree.members[node]) ++counts[targets[leaf]];
        Lines values; for (int count : counts) values.push_back(std::to_string(count));
        return joined(values, "/");
    }
    Lines selectionPart() const {
        const Evaluation& cut = results[chosen].countCuts[position];
        Lines lines{text("selected linkage ", results[chosen].method, " k ", kappa, " ari ", ariText(cut.ari), " silhouette ", real(cut.silhouette))};
        for (int group = 0; group < kappa; ++group) {
            const Indices& items = members[group]; int size = static_cast<int>(items.size());
            double silhouette = 0; Values rawMeans(p, 0);
            for (int i : items) silhouette += silhouettes[i];
            silhouette /= size;
            for (int feature = 0; feature < p; ++feature) { for (int i : items) rawMeans[feature] += data.raw[i][feature]; rawMeans[feature] /= size; }
            int medoid = -1; double medoidSum = 0;
            for (int i : items) { double total = 0; for (int j : items) total += delta[i][j]; if (medoid < 0 || total < medoidSum) { medoid = i; medoidSum = total; } }
            std::string diameter = "0.0000 - -"; int first = -1, second = -1;
            for (std::size_t i = 0; i < items.size(); ++i) for (std::size_t j = i + 1; j < items.size(); ++j) if (first < 0 || delta[items[i]][items[j]] > delta[first][second]) { first = items[i]; second = items[j]; }
            if (first >= 0) diameter = pairText(first, second);
            int nearest = -1; double separation = 0;
            for (int other = 0; other < kappa; ++other) if (other != group) {
                double closest = delta[items[0]][members[other][0]];
                for (int i : items) for (int j : members[other]) closest = std::min(closest, delta[i][j]);
                if (nearest < 0 || closest < separation) { nearest = other; separation = closest; }
            }
            Integer count = table[group][majority[group]];
            add(lines, "cluster ", group + 1, " size ", size, " silhouette ", real(silhouette), " majority ", classes[majority[group]], " purity ", count, '/', size, ' ', real(static_cast<double>(count) / size));
            lines.push_back("  mean " + reals(rawMeans));
            add(lines, "  medoid ", data.ids[medoid], " diameter ", diameter, " nearest ", nearest + 1, " separation ", real(separation));
        }
        return lines;
    }
    Lines centroidPart() const {
        Matrix centers = centroids(selected); Lines lines{"centroid_distances"};
        for (int group = 0; group < kappa; ++group) { Values values; for (const Values& center : centers) values.push_back(std::sqrt(squaredDistance(centers[group], center))); add(lines, group + 1, ' ', reals(values)); }
        return lines;
    }
    Lines profilePart() const {
        Lines lines{"profile_bars"}; std::size_t width = 0;
        for (const std::string& name : data.features) width = std::max(width, name.size());
        for (int group = 0; group < kappa; ++group) {
            add(lines, "cluster ", group + 1);
            for (int feature = 0; feature < p; ++feature) {
                double zeta = 0;
                for (int i : members[group]) zeta += (data.raw[i][feature] - means[feature]) / deviations[feature];
                zeta /= members[group].size();
                int length = std::min(10, static_cast<int>(std::floor(std::abs(zeta) * 4)));
                std::string left(10, ' '), right(10, ' ');
                if (zeta < 0) left.replace(10 - length, length, std::string(length, '#'));
                else right.replace(0, length, std::string(length, '#'));
                add(lines, data.features[feature], std::string(width - data.features[feature].size(), ' '), ' ', left, '|', right, ' ', real(zeta));
            }
        }
        return lines;
    }
    Lines contingencyPart() const {
        Lines lines{"contingency", "cluster " + joined(classes) + " total"};
        std::vector<Integer> totals(labelCount, 0);
        for (int group = 0; group < kappa; ++group) {
            Lines values; Integer sum = 0;
            for (int label = 0; label < labelCount; ++label) { values.push_back(std::to_string(table[group][label])); sum += table[group][label]; totals[label] += table[group][label]; }
            add(lines, group + 1, ' ', joined(values), ' ', sum);
        }
        Lines values; for (Integer total : totals) values.push_back(std::to_string(total));
        add(lines, "total ", joined(values), ' ', n);
        Integer matches = matchCount(selected); add(lines, "purity ", matches, '/', n, ' ', real(static_cast<double>(matches) / n));
        return lines;
    }
    Lines misplacedPart() const {
        Lines lines{"misplaced"}; int count = 0;
        for (int i = 0; i < n; ++i) if (targets[i] != majority[selected[i] - 1]) { ++count; add(lines, data.ids[i], " label ", data.labels[i], " cluster ", selected[i], " majority ", classes[majority[selected[i] - 1]]); }
        add(lines, "count ", count); return lines;
    }
    Lines weakestPart() const {
        Indices order = sequence(n); std::stable_sort(order.begin(), order.end(), [this](int a, int b) { return silhouettes[a] < silhouettes[b]; });
        Lines lines{"weakest"};
        for (int index = 0; index < data.settings.listSize; ++index) { int i = order[index]; add(lines, data.ids[i], " label ", data.labels[i], " cluster ", selected[i], " silhouette ", real(silhouettes[i])); }
        return lines;
    }
    Lines featurePart() const {
        Values ratios;
        for (int feature = 0; feature < p; ++feature) {
            double overall = 0; for (const Values& vector : vectors) overall += vector[feature]; overall /= n;
            Values centers;
            for (const Indices& group : members) { double mean = 0; for (int i : group) mean += vectors[i][feature]; centers.push_back(mean / group.size()); }
            double between = 0, within = 0;
            for (int group = 0; group < kappa; ++group) { double difference = centers[group] - overall; between += members[group].size() * difference * difference; }
            for (int i = 0; i < n; ++i) { double difference = vectors[i][feature] - centers[selected[i] - 1]; within += difference * difference; }
            ratios.push_back((between / (kappa - 1)) / (within / (n - kappa)));
        }
        Indices order = sequence(p); std::stable_sort(order.begin(), order.end(), [&ratios](int a, int b) { return fourDigit(ratios[a]) > fourDigit(ratios[b]); });
        Lines lines{"features"}; for (int index = 0; index < p; ++index) add(lines, index + 1, ' ', data.features[order[index]], " f_ratio ", real(ratios[order[index]]));
        return lines;
    }
    Lines topMergesPart() const {
        const Tree& tree = results[chosen].tree; Lines lines{"top_merges"};
        for (int step = n - data.settings.inconsistencyCount - 1; step < n - 1; ++step) {
            const Merge& merge = tree.merges[step];
            add(lines, "step ", step + 1, " height ", real(merge.height), " a ", merge.a, ' ', tree.members[merge.a].size(), ' ', classCounts(tree, merge.a), " b ", merge.b, ' ', tree.members[merge.b].size(), ' ', classCounts(tree, merge.b));
        }
        return lines;
    }
    Lines dropFeaturePart() const {
        Lines lines{"drop_feature"};
        for (int feature = 0; feature < p; ++feature) {
            Matrix reduced = vectors;
            for (Values& vector : reduced) vector.erase(vector.begin() + feature);
            Tree tree(agglomerate(distanceMatrix(reduced, data.settings.distance), results[chosen].method), n);
            Indices partition = tree.cutInto(kappa);
            add(lines, data.features[feature], " ari_selected ", ariText(partitionAri(partition, selected)), " ari_labels ", ariText(labelAri(partition)));
        }
        return lines;
    }
    Lines refinementPart() const {
        Matrix centers = centroids(selected); Indices previous = selected;
        int iterations = data.settings.refineIterations;
        for (int iteration = 1; iteration <= data.settings.refineIterations; ++iteration) {
            Indices assignment;
            for (const Values& vector : vectors) {
                int best = 0; double bestValue = squaredDistance(vector, centers[0]);
                for (int group = 1; group < kappa; ++group) { double value = squaredDistance(vector, centers[group]); if (value < bestValue) { best = group; bestValue = value; } }
                assignment.push_back(best + 1);
            }
            if (assignment == previous) { iterations = iteration; break; }
            std::vector<Indices> groups = clusterMembers(assignment, kappa);
            for (int group = 0; group < kappa; ++group) if (!groups[group].empty()) centers[group] = centroid(vectors, groups[group]);
            previous = std::move(assignment);
        }
        int changed = 0; for (int i = 0; i < n; ++i) changed += previous[i] != selected[i];
        Indices sizes; for (const Indices& group : clusterMembers(previous, kappa)) sizes.push_back(static_cast<int>(group.size()));
        return {text("refinement max_iterations ", data.settings.refineIterations), text("iterations ", iterations, " changed ", changed, " wss ", real(withinSum(selected)), " -> ", real(withinSum(previous))), text("sizes ", integers(sizes), " silhouette ", real(meanSilhouette(previous, delta))), text("ari_selected ", ariText(partitionAri(previous, selected)), " ari_labels ", ariText(labelAri(previous)))};
    }
    Values jaccard(const Indices& partition, const Indices& restricted) const {
        Indices first = restricted, second = partition;
        for (int& value : first) --value;
        for (int& value : second) --value;
        Table table = contingencyTable(first, second, kappa, maximum(partition));
        std::vector<Integer> columns(maximum(partition), 0);
        for (const std::vector<Integer>& row : table) for (std::size_t index = 0; index < row.size(); ++index) columns[index] += row[index];
        Values values;
        for (const std::vector<Integer>& row : table) {
            Integer size = std::accumulate(row.begin(), row.end(), Integer{0}); Fraction best(0, 1);
            if (size) for (std::size_t index = 0; index < row.size(); ++index) { Fraction candidate(row[index], size + columns[index] - row[index]); if (candidate > best) best = candidate; }
            values.push_back(best.value());
        }
        return values;
    }
    Lines stabilityPart() const {
        const Settings& settings = data.settings; Integer state = settings.seed;
        int size = n * settings.percent / 100; Values aris; Matrix jaccards;
        Lines lines{text("stability replicates ", settings.replicates, " percent ", settings.percent, " seed ", settings.seed)};
        for (int replicate = 1; replicate <= settings.replicates; ++replicate) {
            Indices sample = sequence(n);
            for (int index = 0; index < size; ++index) { state = 48271 * state % 2147483647; int other = index + static_cast<int>(state % (n - index)); std::swap(sample[index], sample[other]); }
            sample.resize(size); std::sort(sample.begin(), sample.end());
            Matrix distances(size, Values(size)); Indices restricted;
            for (int i = 0; i < size; ++i) { restricted.push_back(selected[sample[i]]); for (int j = 0; j < size; ++j) distances[i][j] = delta[sample[i]][sample[j]]; }
            Tree tree(agglomerate(distances, results[chosen].method), size); Indices partition = tree.cutInto(kappa);
            Fraction ari = partitionAri(partition, restricted); Values values = jaccard(partition, restricted);
            aris.push_back(ari.value()); jaccards.push_back(values);
            add(lines, "replicate ", replicate, " size ", size, " ari ", ariText(ari), " jaccard ", reals(values));
        }
        Values means(kappa, 0);
        for (int group = 0; group < kappa; ++group) { for (const Values& row : jaccards) means[group] += row[group]; means[group] /= settings.replicates; }
        add(lines, "mean_ari ", real(sequentialSum(aris) / settings.replicates)); lines.push_back("mean_jaccard " + reals(means));
        return lines;
    }
    Lines distanceMapPart() const {
        Lines lines{"distance_map " + results[chosen].method, "+" + std::string(n, '-') + "+"};
        const std::string shades = "@%#*+=-:. ";
        for (int i : results[chosen].tree.order) { std::string row = "|"; for (int j : results[chosen].tree.order) row += shades[histogramBin(delta[i][j], distanceMax)]; lines.push_back(row + "|"); }
        lines.push_back("+" + std::string(n, '-') + "+"); return lines;
    }
public:
    explicit Study(Dataset source) : data(std::move(source)), n(static_cast<int>(data.raw.size())), p(static_cast<int>(data.features.size())) {
        std::set<std::string> unique(data.labels.begin(), data.labels.end()); classes.assign(unique.begin(), unique.end()); labelCount = static_cast<int>(classes.size());
        for (const std::string& label : data.labels) targets.push_back(static_cast<int>(std::find(classes.begin(), classes.end(), label) - classes.begin()));
        std::pair<Values, Values> statistics = featureStatistics(data.raw); means = statistics.first; deviations = statistics.second;
        vectors = data.settings.standardize == "yes" ? standardize(data.raw, means, deviations) : data.raw;
        delta = distanceMatrix(vectors, data.settings.distance); distancePairs = pairValues(delta); distanceMax = *std::max_element(distancePairs.begin(), distancePairs.end());
        for (int i = 0; i < n; ++i) { int best = -1; for (int j = 0; j < n; ++j) if (j != i && (best < 0 || delta[i][j] < delta[i][best])) best = j; neighbors.push_back(best); }
        for (const std::string& method : data.settings.linkages) {
            LinkageResult result(method, Tree(agglomerate(delta, method), n)); result.correlation = correlation(distancePairs, result.cophenetic);
            for (double height : data.settings.cutHeights) result.heightCuts.push_back(evaluate(result.tree.cutAt(height)));
            for (int k : data.settings.cutCounts) result.countCuts.push_back(evaluate(result.tree.cutInto(k)));
            result.labelPartition = result.tree.cutInto(labelCount); results.push_back(std::move(result));
        }
        for (std::size_t method = 0; method < results.size(); ++method) for (std::size_t cut = 0; cut < data.settings.cutCounts.size(); ++cut) if (results[method].countCuts[cut].ari > results[chosen].countCuts[position].ari) { chosen = method; position = cut; }
        kappa = data.settings.cutCounts[position]; selected = results[chosen].countCuts[position].partition;
        members = clusterMembers(selected, kappa); silhouettes = silhouetteValues(selected, kappa, delta); table = classTable(selected);
        for (const std::vector<Integer>& row : table) majority.push_back(majorityClass(row));
    }
    Lines linkageTable() const {
        Lines lines{"method,step,a,b,height,size"};
        for (const LinkageResult& result : results) for (std::size_t step = 0; step < result.tree.merges.size(); ++step) { const Merge& merge = result.tree.merges[step]; add(lines, result.method, ',', step + 1, ',', merge.a, ',', merge.b, ',', real(merge.height), ',', merge.size); }
        return lines;
    }
    Lines clustersTable() const {
        Lines header{"id", "label"};
        for (const LinkageResult& result : results) { for (std::size_t index = 0; index < data.settings.cutHeights.size(); ++index) header.push_back(text(result.method, "_h", index + 1)); for (int k : data.settings.cutCounts) header.push_back(text(result.method, "_k", k)); }
        Lines lines{joined(header, ",")};
        for (int i = 0; i < n; ++i) { Lines row{data.ids[i], data.labels[i]}; for (const LinkageResult& result : results) { for (const Evaluation& cut : result.heightCuts) row.push_back(std::to_string(cut.partition[i])); for (const Evaluation& cut : result.countCuts) row.push_back(std::to_string(cut.partition[i])); } lines.push_back(joined(row, ",")); }
        return lines;
    }
    Lines dendrogramReport() const {
        Lines lines;
        for (const LinkageResult& result : results) {
            double maximum = *std::max_element(result.tree.heights.begin(), result.tree.heights.end()); Indices columns;
            for (double height : data.settings.cutHeights) columns.push_back(columnPosition(height, maximum, data.settings.width));
            Lines part{text("dendrogram ", result.method, " height_max ", real(maximum), " width ", data.settings.width)};
            append(part, dendrogramRows(result.tree.merges, result.tree.children, result.tree.order, data.ids, data.labels, maximum, columns, data.settings.width));
            for (std::size_t index = 0; index < columns.size(); ++index) add(part, "cut ", real(data.settings.cutHeights[index]), " column ", columns[index] <= data.settings.width ? std::to_string(columns[index]) : "-");
            paragraph(lines, part);
        }
        return lines;
    }
    Lines treesReport() const { Lines lines; for (const LinkageResult& result : results) lines.push_back(result.method + " " + result.tree.newick(result.tree.root(), data.ids) + ";"); return lines; }
    Lines validationReport() const {
        Lines lines; paragraph(lines, dataPart()); paragraph(lines, correlationPart()); paragraph(lines, histogramPart());
        bool single = false;
        for (const LinkageResult& result : results) { paragraph(lines, linkagePart(result)); single = single || result.method == "single"; }
        if (single) paragraph(lines, mstPart());
        paragraph(lines, comparePart());
        Lines part{"cophenetic_matrix", "linkage " + joined(data.settings.linkages)};
        for (const LinkageResult& first : results) { Values values; for (const LinkageResult& second : results) values.push_back(correlation(first.cophenetic, second.cophenetic)); part.push_back(first.method + " " + reals(values)); }
        paragraph(lines, part); part = {text("agreement k ", labelCount), "linkage " + joined(data.settings.linkages)};
        for (const LinkageResult& first : results) { Values values; for (const LinkageResult& second : results) values.push_back(partitionAri(first.labelPartition, second.labelPartition).value()); part.push_back(first.method + " " + reals(values)); }
        paragraph(lines, part); paragraph(lines, summaryPart()); return lines;
    }
    Lines profilesReport() const {
        Lines lines; paragraph(lines, selectionPart()); paragraph(lines, centroidPart()); paragraph(lines, profilePart()); paragraph(lines, contingencyPart()); paragraph(lines, misplacedPart()); paragraph(lines, weakestPart()); paragraph(lines, featurePart()); paragraph(lines, topMergesPart()); paragraph(lines, dropFeaturePart()); paragraph(lines, refinementPart()); paragraph(lines, stabilityPart()); paragraph(lines, distanceMapPart()); return lines;
    }
};
int main() {
    Study study(readDataset());
    std::filesystem::create_directories("output");
    writeLines("linkage.csv", study.linkageTable()); writeLines("clusters.csv", study.clustersTable()); writeLines("dendrogram.txt", study.dendrogramReport());
    writeLines("trees.txt", study.treesReport()); writeLines("validation.txt", study.validationReport()); writeLines("profiles.txt", study.profilesReport());
}
