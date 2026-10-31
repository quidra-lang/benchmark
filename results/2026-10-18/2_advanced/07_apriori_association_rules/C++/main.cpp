#include "market.hpp"
#include <algorithm>
#include <array>
#include <fstream>
#include <iomanip>
#include <iterator>
#include <numeric>
#include <sstream>
#include <tuple>
#include <utility>

template<class... Args> static std::string line(const Args&... args) {
    std::ostringstream out; bool first = true;
    ((out << (first ? "" : " ") << args,first = false),...); return out.str();
}
static void append(Items& lines, const Items& added) { lines.insert(lines.end(),added.begin(),added.end()); }
static bool sizeBefore(const Items& a, const Items& b) { return a.size() != b.size() ? a.size() < b.size() : a < b; }
static Fraction median(std::vector<Integer> values) {
    std::sort(values.begin(),values.end()); int middle = static_cast<int>(values.size()) / 2;
    return values.size() % 2 ? Fraction(values[middle]) : Fraction(values[middle - 1] + values[middle],2);
}
static std::pair<Items, Items> splitItemset(const Items& items, int mask) {
    Items chosen, rest;
    for (int j = 0; j < static_cast<int>(items.size()); ++j) ((mask >> j) & 1 ? chosen : rest).push_back(items[j]);
    return {chosen,rest};
}
struct Params {
    Integer support, categorySupport, sequenceSupport, trainSupport, testSupport, negativeExpected;
    int maximum, splitDay, top, matrix;
    Fraction confidence, lift, groupLift, negativeLift, trend;
    Params() {
        std::ifstream file("input/params.txt"); std::map<std::string, std::string> fields; std::string name, value;
        while (file >> name >> value) fields[name] = value;
        auto integer = [&](const std::string& key) { return std::stoll(fields.at(key)); };
        auto fraction = [&](const std::string& key) { const std::string& text = fields.at(key); int slash = static_cast<int>(text.find('/')); return Fraction(std::stoll(text.substr(0,slash)),std::stoll(text.substr(slash + 1))); };
        support = integer("min_support"); categorySupport = integer("category_min_support"); sequenceSupport = integer("sequence_min_support");
        trainSupport = integer("train_min_support"); testSupport = integer("test_min_support"); negativeExpected = integer("negative_min_expected");
        maximum = static_cast<int>(integer("max_size")); splitDay = static_cast<int>(integer("split_day")); top = static_cast<int>(integer("recommend_top")); matrix = static_cast<int>(integer("matrix_size"));
        confidence = fraction("min_confidence"); lift = fraction("min_lift"); groupLift = fraction("group_min_lift"); negativeLift = fraction("negative_max_lift"); trend = fraction("trend_threshold");
    }
};
struct Dataset {
    Items errors;
    std::map<std::string, Product> products;
    std::vector<Transaction> transactions;
    int itemRows = 0, transactionLines = 0, adopted = 0, rejected = 0, duplicates = 0;
    void error(const std::string& file, int number, const std::string& message) { errors.push_back(line(file,"line",std::to_string(number) + ":",message)); }
    Dataset() {
        std::vector<Items> records = readRecords("items.csv"); itemRows = static_cast<int>(records.size());
        for (int j = 0; j < itemRows; ++j) {
            const Items& p = records[j]; Integer price = std::stoll(p[2]);
            if (products.count(p[0])) error("items.csv",j + 2,line("duplicate item",p[0]));
            else if (price == 0) error("items.csv",j + 2,"bad price 0");
            else products[p[0]] = {p[0],p[1],price};
        }
        records = readRecords("transactions.csv"); transactionLines = static_cast<int>(records.size());
        std::set<std::string> known;
        for (int j = 0; j < transactionLines; ++j) {
            const Items& p = records[j]; int day = std::stoi(p[2]); std::string problem;
            if (known.count(p[0]) && p[0] != transactions.back().tid) problem = line("tid",p[0],"not contiguous");
            else {
                if (!known.count(p[0])) { known.insert(p[0]); transactions.push_back({p[0],p[1],day,{}}); }
                const Transaction& current = transactions.back();
                if (p[1] != current.customer) problem = line("tid",p[0],"customer",p[1],"differs from",current.customer);
                else if (day != current.day) problem = line("tid",p[0],"day",day,"differs from",current.day);
                else if (!products.count(p[3])) problem = line("unknown item",p[3]);
            }
            if (!problem.empty()) { error("transactions.csv",j + 2,problem); ++rejected; }
            else { ++adopted; duplicates += transactions.back().add(p[3]); }
        }
    }
};
struct Level { int number, candidates, excluded, pruned, counted; Itemsets frequent; };
struct AprioriResult { std::vector<Level> levels; Supports supports; Counts singles; };
static AprioriResult runApriori(const Baskets& baskets, Items universe, Integer minimum, int maximum, const Taxonomy* taxonomy = nullptr) {
    AprioriResult result; std::sort(universe.begin(),universe.end()); Itemsets candidates, previous;
    for (const std::string& item : universe) candidates.push_back({item});
    for (int size = 1; size <= maximum; ++size) {
        CandidateLevel generated = size == 1 ? CandidateLevel{static_cast<int>(candidates.size()),0,0,candidates} : generateCandidates(previous,size,taxonomy);
        Supports counts = countSupports(baskets,generated.itemsets); Itemsets frequent;
        for (const auto& entry : counts) {
            if (size == 1) result.singles[entry.first[0]] = entry.second;
            if (entry.second >= minimum) { frequent.push_back(entry.first); result.supports[entry.first] = entry.second; }
        }
        result.levels.push_back({size,generated.joined,generated.excluded,generated.pruned,static_cast<int>(generated.itemsets.size()),frequent});
        if (frequent.empty()) break;
        previous = frequent;
    }
    return result;
}
static RuleSet makeRules(const Supports& supports, Integer total, const Params& p, const std::set<std::string>* required = nullptr) {
    RuleSet result;
    auto support = [&](const Items& items) { return items.empty() ? total : supports.at(items); };
    for (const auto& entry : supports) {
        const Items& z = entry.first;
        if (z.size() < 2 || (required && std::none_of(z.begin(),z.end(),[&](const std::string& item) { return required->count(item) != 0; }))) continue;
        for (int mask = 1; mask < (1 << z.size()) - 1; ++mask) {
            auto parts = splitItemset(z,mask); ++result.generated;
            Rule rule(z,parts.first,parts.second,entry.second,total,support(parts.first),support(parts.second));
            if (!meetsThresholds(rule.confidence,rule.lift,p.confidence,p.lift)) continue;
            Fraction reference;
            for (int subset = 0; subset < (1 << parts.first.size()) - 1; ++subset) {
                Items w = splitItemset(parts.first,subset).first;
                Fraction confidence(support(united(w,parts.second)),support(w));
                if (confidence > reference) reference = confidence;
            }
            rule.improvement = rule.confidence - reference; result.productive += rule.improvement > Fraction(); result.rules.push_back(rule);
        }
    }
    std::sort(result.rules.begin(),result.rules.end(),ruleBefore);
    for (int j = 0; j < static_cast<int>(result.rules.size()); ++j) result.rules[j].rank = j + 1;
    return result;
}
static Items recommend(const Items& held, const Items& candidates, int limit) {
    Items selected;
    for (const std::string& item : candidates) {
        if (static_cast<int>(selected.size()) == limit) break;
        if (!std::binary_search(held.begin(),held.end(),item) && std::find(selected.begin(),selected.end(),item) == selected.end()) selected.push_back(item);
    }
    return selected;
}
static Items ruleCandidates(const std::vector<Rule>& rules, const Items& held) {
    Items candidates; for (const Rule& rule : rules) if (rule.consequent.size() == 1 && contains(held,rule.antecedent)) candidates.push_back(rule.consequent[0]); return candidates;
}
struct Tally {
    Integer cases = 0, covered = 0, top = 0, hits = 0, baseline = 0;
    void add(const std::string& held, const Items& suggestion, const Items& popular) {
        ++cases; covered += !suggestion.empty(); top += !suggestion.empty() && suggestion.front() == held;
        hits += std::find(suggestion.begin(),suggestion.end(),held) != suggestion.end(); baseline += std::find(popular.begin(),popular.end(),held) != popular.end();
    }
    std::string text() const { return line("cases",cases,"covered",covered,"hit1",top,"hit",hits,"rate",fractionText({hits,cases}),"baseline",baseline,"rate",fractionText({baseline,cases})); }
};
struct Sequence { std::string first, second; Integer customers, base; Fraction confidence, lift, gap; };
struct Repeat { std::string item; int customers, count; Integer minimum, maximum; Fraction mean, median; };
struct RuleCheck { Rule rule; Integer together, antecedent; std::optional<Fraction> confidence, lift; std::string verdict; };
struct Category { std::string name; int products; Integer units, revenue, baskets; };
struct Group { Items members; int edges; std::string core; Integer revenue; };
struct Substitute { std::string first, second; Integer together; Fraction expected, lift; };
struct Trend { std::string name; Integer units; Fraction slope; std::optional<Fraction> relative; std::string verdict; };
struct Customer { std::string id; int baskets, days, first, last, products; Integer units, revenue; std::string favorite, segment; Items offer; };

class Analysis {
    Params p;
    Dataset data;
    std::map<std::string, Product>& products;
    Items names, categories, customers;
    Taxonomy taxonomy;
    std::vector<Transaction> baskets;
    Baskets sets, extended, train, test;
    std::map<std::string, std::vector<int>> customerBaskets;
    std::map<std::string, std::map<std::string, std::set<int>>> histories;
    Integer total, totalRevenue = 0;
    int firstDay = 113, lastDay = 0, sequencePairs = 0, weeks = 0;
    AprioriResult main, categoryRun, trainRun;
    GrowthResult growth;
    RuleSet mainRules, categoryRules;
    std::vector<Rule> trainRules, emerging;
    Itemsets closed, maximal, generators, pairs;
    Counts buyers, units, revenue, heldOut, heldHits;
    std::vector<Sequence> sequences;
    std::vector<Repeat> repeats;
    std::vector<RuleCheck> checks;
    std::map<int, Tally> tallies;
    Tally overall;
    std::vector<Category> categorySummaries;
    std::vector<Group> groups;
    std::vector<Substitute> substitutes;
    std::vector<Trend> trends;
    std::vector<Customer> customerSummaries;
    std::vector<Integer> weekBaskets, weekUnits, weekCustomers;
    std::map<std::string, std::vector<Integer>> series;
    void frequent() {
        main = runApriori(sets,names,p.support,p.maximum); growth = fpGrowth(sets,p.support,p.maximum);
        std::set<Items> closedSet, maximalSet;
        for (const auto& entry : main.supports) { closedSet.insert(entry.first); maximalSet.insert(entry.first); if (entry.first.size() == 2) pairs.push_back(entry.first); }
        for (const auto& entry : main.supports) {
            bool generator = true;
            for (const Items& subset : smallerSubsets(entry.first)) {
                Integer count = subset.empty() ? total : main.supports.at(subset);
                if (count <= entry.second) generator = false;
                if (!subset.empty()) { maximalSet.erase(subset); if (count == entry.second) closedSet.erase(subset); }
            }
            if (generator) generators.push_back(entry.first);
        }
        closed = Itemsets(closedSet.begin(),closedSet.end()); maximal = Itemsets(maximalSet.begin(),maximalSet.end());
        for (Itemsets* itemsets : {&closed,&maximal,&generators}) std::sort(itemsets->begin(),itemsets->end(),sizeBefore);
        mainRules = makeRules(main.supports,total,p);
        Items universe = names; universe.insert(universe.end(),categories.begin(),categories.end());
        categoryRun = runApriori(extended,universe,p.categorySupport,p.maximum,&taxonomy);
        std::set<std::string> required(categories.begin(),categories.end()); categoryRules = makeRules(categoryRun.supports,total,p,&required);
    }
    void sequential() {
        std::map<Items, std::vector<Integer>> gaps;
        std::map<std::string, std::vector<Integer>> intervals;
        Counts repeaters;
        for (const std::string& name : names) buyers[name] = 0;
        for (const auto& customer : histories) for (const auto& first : customer.second) {
            ++buyers[first.first];
            if (first.second.size() >= 2) {
                ++repeaters[first.first]; int previous = *first.second.begin();
                for (auto day = std::next(first.second.begin()); day != first.second.end(); ++day) { intervals[first.first].push_back(*day - previous); previous = *day; }
            }
            for (const auto& second : customer.second) if (*first.second.begin() < *second.second.rbegin()) {
                int shortest = 113;
                for (int a : first.second) for (int b : second.second) if (a < b) shortest = std::min(shortest,b - a);
                gaps[{first.first,second.first}].push_back(shortest);
            }
        }
        sequencePairs = static_cast<int>(gaps.size());
        for (const auto& entry : gaps) if (static_cast<Integer>(entry.second.size()) >= p.sequenceSupport) {
            const std::string& a = entry.first[0]; const std::string& b = entry.first[1]; Integer count = entry.second.size();
            sequences.push_back({a,b,count,buyers[a],{count,buyers[a]},liftOf(customers.size(),count,buyers[a],buyers[b]),median(entry.second)});
        }
        std::sort(sequences.begin(),sequences.end(),[](const Sequence& a, const Sequence& b) {
            if (a.customers != b.customers) return a.customers > b.customers;
            if (!(a.confidence == b.confidence)) return a.confidence > b.confidence;
            return std::tie(a.first,a.second) < std::tie(b.first,b.second);
        });
        for (const auto& entry : intervals) {
            const auto& values = entry.second; Integer sum = std::accumulate(values.begin(),values.end(),Integer{});
            repeats.push_back({entry.first,static_cast<int>(repeaters[entry.first]),static_cast<int>(values.size()),*std::min_element(values.begin(),values.end()),*std::max_element(values.begin(),values.end()),{sum,static_cast<Integer>(values.size())},median(values)});
        }
        std::sort(repeats.begin(),repeats.end(),[](const Repeat& a, const Repeat& b) { return !(a.mean == b.mean) ? a.mean < b.mean : a.item < b.item; });
    }
    void validate() {
        trainRun = runApriori(train,names,p.trainSupport,p.maximum); trainRules = makeRules(trainRun.supports,train.size(),p).rules;
        std::set<std::pair<Items, Items>> known;
        for (const Rule& rule : trainRules) {
            known.insert({rule.antecedent,rule.consequent});
            Integer a = countSupport(test,rule.antecedent), b = countSupport(test,rule.consequent), c = countSupport(test,rule.itemset);
            RuleCheck check{rule,c,a,std::nullopt,std::nullopt,"UNSEEN"};
            if (a && b) { check.confidence = Fraction(c,a); check.lift = liftOf(test.size(),c,a,b); check.verdict = meetsThresholds(*check.confidence,*check.lift,p.confidence,p.lift) ? "HOLD" : "FAIL"; }
            checks.push_back(check);
        }
        AprioriResult testRun = runApriori(test,names,p.testSupport,p.maximum);
        for (const Rule& rule : makeRules(testRun.supports,test.size(),p).rules) if (!known.count({rule.antecedent,rule.consequent})) emerging.push_back(rule);
        Items popularity = names;
        std::sort(popularity.begin(),popularity.end(),[&](const std::string& a, const std::string& b) { return trainRun.singles[a] != trainRun.singles[b] ? trainRun.singles[a] > trainRun.singles[b] : a < b; });
        for (const std::string& name : names) { heldOut[name] = 0; heldHits[name] = 0; }
        for (const Items& basket : test) if (basket.size() >= 2) for (const std::string& item : basket) {
            Items held; for (const std::string& name : basket) if (name != item) held.push_back(name);
            Items suggestion = recommend(held,ruleCandidates(trainRules,held),p.top), baseline = recommend(held,popularity,p.top);
            tallies[static_cast<int>(basket.size())].add(item,suggestion,baseline); overall.add(item,suggestion,baseline); ++heldOut[item];
            heldHits[item] += std::find(suggestion.begin(),suggestion.end(),item) != suggestion.end();
        }
    }
    Fraction pairLift(const Items& pair) const { return liftOf(total,main.supports.at(pair),main.singles.at(pair[0]),main.singles.at(pair[1])); }
    void summarizeProducts() {
        for (const std::string& name : names) units[name] = 0;
        for (const Transaction& basket : baskets) for (const auto& entry : basket.counts) units[entry.first] += entry.second;
        for (const std::string& name : names) { revenue[name] = units[name] * products.at(name).price; totalRevenue += revenue[name]; }
        for (const std::string& category : categories) {
            Category summary{category,0,0,0,categoryRun.singles.at(category)};
            for (const std::string& name : names) if (taxonomy.at(name) == category) { ++summary.products; summary.units += units[name]; summary.revenue += revenue[name]; }
            categorySummaries.push_back(summary);
        }
        std::sort(categorySummaries.begin(),categorySummaries.end(),[](const Category& a, const Category& b) { return a.revenue != b.revenue ? a.revenue > b.revenue : a.name < b.name; });
        std::map<std::string, Items> neighbors;
        for (const Items& pair : pairs) if (pairLift(pair) >= p.groupLift) { neighbors[pair[0]].push_back(pair[1]); neighbors[pair[1]].push_back(pair[0]); }
        std::set<std::string> visited;
        for (const std::string& name : names) if (!visited.count(name) && !neighbors[name].empty()) {
            Items members, stack{name}; visited.insert(name); Integer sum = 0; int degree = 0;
            while (!stack.empty()) {
                std::string item = stack.back(); stack.pop_back(); members.push_back(item); sum += revenue[item]; degree += static_cast<int>(neighbors[item].size());
                for (const std::string& next : neighbors[item]) if (visited.insert(next).second) stack.push_back(next);
            }
            std::sort(members.begin(),members.end()); std::string core = members.front();
            for (const std::string& item : members) if (neighbors[item].size() > neighbors[core].size() || (neighbors[item].size() == neighbors[core].size() && main.singles[item] > main.singles[core])) core = item;
            groups.push_back({members,degree / 2,core,sum});
        }
        std::sort(groups.begin(),groups.end(),[](const Group& a, const Group& b) { return a.members.size() != b.members.size() ? a.members.size() > b.members.size() : a.members.front() < b.members.front(); });
        const Itemsets& singles = main.levels.front().frequent;
        for (int i = 0; i < static_cast<int>(singles.size()); ++i) for (int j = i + 1; j < static_cast<int>(singles.size()); ++j) {
            const std::string& a = singles[i][0]; const std::string& b = singles[j][0]; Integer expected = main.singles[a] * main.singles[b];
            if (expected < p.negativeExpected * total) continue;
            Integer together = countSupport(sets,{a,b}); Fraction lift = liftOf(total,together,main.singles[a],main.singles[b]);
            if (lift <= p.negativeLift) substitutes.push_back({a,b,together,{expected,total},lift});
        }
        std::sort(substitutes.begin(),substitutes.end(),[](const Substitute& a, const Substitute& b) {
            if (!(a.lift == b.lift)) return a.lift < b.lift;
            if (!(a.expected == b.expected)) return a.expected > b.expected;
            return std::tie(a.first,a.second) < std::tie(b.first,b.second);
        });
    }
    void summarizeTrends() {
        weeks = (lastDay - 1) / 7 + 1; weekBaskets.resize(weeks); weekUnits.resize(weeks); weekCustomers.resize(weeks);
        std::vector<std::set<std::string>> buyersByWeek(weeks);
        for (const std::string& name : categories) series[name] = std::vector<Integer>(weeks);
        for (const std::string& name : names) series[name] = std::vector<Integer>(weeks);
        for (const Transaction& basket : baskets) {
            int week = (basket.day - 1) / 7; ++weekBaskets[week]; weekUnits[week] += basket.units(); buyersByWeek[week].insert(basket.customer);
            for (const auto& entry : basket.counts) { series[entry.first][week] += entry.second; series[taxonomy.at(entry.first)][week] += entry.second; }
        }
        for (int j = 0; j < weeks; ++j) weekCustomers[j] = buyersByWeek[j].size();
        Integer sumWeeks = 0, sumSquares = 0;
        for (int week = 1; week <= weeks; ++week) { sumWeeks += week; sumSquares += week * week; }
        for (const auto& entry : series) {
            Integer weighted = 0, sum = 0;
            for (int j = 0; j < weeks; ++j) { sum += entry.second[j]; weighted += (j + 1) * entry.second[j]; }
            Fraction slope(weeks * weighted - sumWeeks * sum,weeks * sumSquares - sumWeeks * sumWeeks);
            Trend trend{entry.first,sum,slope,std::nullopt,"NONE"};
            if (sum) {
                trend.relative = slope * Fraction(weeks,sum);
                trend.verdict = *trend.relative >= p.trend ? "RISING" : *trend.relative <= Fraction(-p.trend.numerator,p.trend.denominator) ? "FALLING" : "FLAT";
            }
            trends.push_back(trend);
        }
        std::sort(trends.begin(),trends.end(),[](const Trend& a, const Trend& b) {
            if (a.relative.has_value() != b.relative.has_value()) return a.relative.has_value();
            if (a.relative && !(*a.relative == *b.relative)) return *a.relative > *b.relative;
            return a.name < b.name;
        });
    }
    void summarizeCustomers() {
        for (const std::string& id : customers) {
            const auto& indices = customerBaskets.at(id); const auto& history = histories.at(id);
            Customer c{id,static_cast<int>(indices.size()),0,113,0,static_cast<int>(history.size()),0,0,"","",{}};
            std::set<int> days; Counts categoryUnits;
            for (int index : indices) {
                const Transaction& basket = baskets[index]; days.insert(basket.day); c.first = std::min(c.first,basket.day); c.last = std::max(c.last,basket.day);
                for (const auto& entry : basket.counts) { c.units += entry.second; c.revenue += entry.second * products.at(entry.first).price; categoryUnits[taxonomy.at(entry.first)] += entry.second; }
            }
            c.days = static_cast<int>(days.size()); Integer maximum = -1;
            for (const auto& entry : categoryUnits) if (entry.second > maximum) { c.favorite = entry.first; maximum = entry.second; }
            c.segment = c.first > lastDay - 28 ? "NEW" : c.baskets >= 4 && lastDay - c.last <= 14 ? "LOYAL" : lastDay - c.last > 28 ? "AT_RISK" : "REGULAR";
            Items held; for (const auto& entry : history) held.push_back(entry.first);
            c.offer = recommend(held,ruleCandidates(mainRules.rules,held),p.top); customerSummaries.push_back(c);
        }
    }
    Items summaryLines() const {
        Items lines; for (const std::string& error : data.errors) lines.push_back("ERROR " + error);
        lines.push_back(line("ITEMS rows",data.itemRows,"adopted",products.size(),"categories",categories.size()));
        lines.push_back(line("TRANSACTIONS lines",data.transactionLines,"adopted",data.adopted,"rejected",data.rejected,"duplicates",data.duplicates,"transactions",data.transactions.size(),"empty",data.transactions.size() - baskets.size()));
        Integer sum = 0; int largest = 0; std::map<int, int> sizes;
        for (const Items& basket : sets) { int size = static_cast<int>(basket.size()); sum += size; largest = std::max(largest,size); ++sizes[size]; }
        lines.push_back(line("BASKETS count",total,"customers",customers.size(),"first_day",firstDay,"last_day",lastDay,"average_size",fractionText({sum,total}),"largest",largest));
        for (int size = 1; size <= largest; ++size) lines.push_back(line("SIZE",size,"baskets",sizes[size],"share",percentText(sizes[size],total)));
        lines.push_back(line("FREQUENT itemsets",main.supports.size(),"closed",closed.size(),"maximal",maximal.size(),"generators",generators.size(),"levels",main.levels.size()));
        bool match = main.supports == growth.itemsets;
        lines.push_back(line("FPGROWTH header",growth.headers,"nodes",growth.nodes,"conditional_trees",growth.conditionalTrees,"conditional_nodes",growth.conditionalNodes,"itemsets",growth.itemsets.size(),match ? "MATCH" : "MISMATCH"));
        if (!match) for (int source = 0; source < 2; ++source) {
            const Supports& from = source == 0 ? main.supports : growth.itemsets; const Supports& to = source == 0 ? growth.itemsets : main.supports;
            Itemsets missing;
            for (const auto& entry : from) { auto found = to.find(entry.first); if (found == to.end() || found->second != entry.second) missing.push_back(entry.first); }
            std::sort(missing.begin(),missing.end(),sizeBefore);
            for (const Items& itemset : missing) lines.push_back(line(source == 0 ? "ONLY_APRIORI" : "ONLY_FPGROWTH",itemsetText(itemset),from.at(itemset)));
        }
        lines.push_back(line("RULES generated",mainRules.generated,"passed",mainRules.rules.size(),"productive",mainRules.productive));
        for (const Level& level : categoryRun.levels) lines.push_back(line("CATEGORY_LEVEL",level.number,"candidates",level.candidates,"taxonomy",level.excluded,"pruned",level.pruned,"counted",level.counted,"frequent",level.frequent.size()));
        lines.push_back(line("CATEGORY_RULES itemsets",categoryRun.supports.size(),"generated",categoryRules.generated,"passed",categoryRules.rules.size(),"productive",categoryRules.productive));
        int multiDay = 0; for (const Customer& c : customerSummaries) multiDay += c.days >= 2;
        lines.push_back(line("SEQUENCES customers",customers.size(),"multi_day",multiDay,"pairs",sequencePairs,"frequent",sequences.size()));
        return lines;
    }
    Items itemsetLines() const {
        Items lines;
        for (const Level& level : main.levels) {
            lines.push_back(line("LEVEL",level.number,"candidates",level.candidates,"pruned",level.pruned,"counted",level.counted,"frequent",level.frequent.size()));
            for (const Items& itemset : level.frequent) lines.push_back(line(itemsetText(itemset),main.supports.at(itemset)));
        }
        return lines;
    }
    Items classificationLines() const {
        Items lines; const Items labels{"CLOSED","MAXIMAL","GENERATOR"}; const std::array<const Itemsets*, 3> sections{&closed,&maximal,&generators};
        for (int j = 0; j < 3; ++j) for (const Items& itemset : *sections[j]) lines.push_back(line(labels[j],itemsetText(itemset),main.supports.at(itemset)));
        return lines;
    }
    Items sequenceLines() const {
        Items lines;
        for (int j = 0; j < static_cast<int>(sequences.size()); ++j) {
            const Sequence& s = sequences[j];
            lines.push_back(line("SEQ",j + 1,s.first,"->",s.second,"customers",s.customers,"base",s.base,"confidence",fractionText(s.confidence),"lift",fractionText(s.lift),"gap",fractionText(s.gap)));
        }
        for (const Repeat& r : repeats) lines.push_back(line("REPEAT",r.item,"customers",r.customers,"intervals",r.count,"min",r.minimum,"max",r.maximum,"mean",fractionText(r.mean),"median",fractionText(r.median)));
        return lines;
    }
    Items validationLines() const {
        Items lines; std::map<std::string, int> counts;
        for (const RuleCheck& check : checks) {
            const Rule& r = check.rule; ++counts[check.verdict];
            lines.push_back(line("RULE",r.rank,ruleArrow(r),"train",r.count,"confidence",fractionText(r.confidence),"lift",fractionText(r.lift),"test",check.together,"of",check.antecedent,"confidence",check.confidence ? fractionText(*check.confidence) : "-","lift",check.lift ? fractionText(*check.lift) : "-",check.verdict));
        }
        for (const Rule& r : emerging) lines.push_back(line("EMERGING",r.rank,ruleArrow(r),"test",r.count,"confidence",fractionText(r.confidence),"lift",fractionText(r.lift)));
        lines.push_back(line("VALIDATION train",train.size(),"test",test.size(),"itemsets",trainRun.supports.size(),"rules",trainRules.size(),"hold",counts["HOLD"],"fail",counts["FAIL"],"unseen",counts["UNSEEN"],"emerging",emerging.size()));
        for (const auto& entry : tallies) lines.push_back(line("RECOMMEND size",entry.first,entry.second.text()));
        lines.push_back(line("RECOMMEND total",overall.text())); return lines;
    }
    std::string partner(const std::string& name) const {
        const Items* best = nullptr;
        auto other = [&](const Items& pair) { return pair[0] == name ? pair[1] : pair[0]; };
        for (const Items& pair : pairs) if (pair[0] == name || pair[1] == name) {
            bool better = !best;
            if (best) {
                Fraction a = pairLift(pair), b = pairLift(*best);
                better = !(a == b) ? a > b : main.supports.at(pair) != main.supports.at(*best) ? main.supports.at(pair) > main.supports.at(*best) : other(pair) < other(*best);
            }
            if (better) best = &pair;
        }
        return best ? line(other(*best),fractionText(pairLift(*best))) : "none";
    }
    std::string strongest(const std::string& name) const {
        for (const Rule& rule : mainRules.rules) if (std::binary_search(rule.itemset.begin(),rule.itemset.end(),name)) return line(rule.rank,ruleArrow(rule));
        return "none";
    }
    Items matrixLines(const std::string& label, const Items& items, const Counts& counts, const Baskets& baskets) const {
        Items lines;
        for (int j = 0; j < static_cast<int>(items.size()); ++j) lines.push_back(line(label,j + 1,items[j],"baskets",counts.at(items[j])));
        std::ostringstream heading; heading << "    "; for (int j = 1; j <= static_cast<int>(items.size()); ++j) heading << std::setw(7) << j; lines.push_back(heading.str());
        for (int i = 0; i < static_cast<int>(items.size()); ++i) {
            std::ostringstream row; row << std::setw(4) << i + 1;
            for (int j = 0; j < static_cast<int>(items.size()); ++j) {
                std::string cell = "-";
                if (i != j) { Items pair{items[i],items[j]}; std::sort(pair.begin(),pair.end()); Integer together = countSupport(baskets,pair); cell = std::to_string(100 * static_cast<Integer>(baskets.size()) * together / (counts.at(items[i]) * counts.at(items[j]))); }
                row << std::setw(7) << cell;
            }
            lines.push_back(row.str());
        }
        return lines;
    }
    Items itemLines() const {
        Items ranked = names, lines;
        std::sort(ranked.begin(),ranked.end(),[&](const std::string& a, const std::string& b) { return revenue.at(a) != revenue.at(b) ? revenue.at(a) > revenue.at(b) : a < b; });
        for (int j = 0; j < static_cast<int>(ranked.size()); ++j) {
            const std::string& name = ranked[j]; const Product& product = products.at(name); Integer count = main.singles.at(name); int containing = 0;
            for (const auto& entry : main.supports) containing += std::binary_search(entry.first.begin(),entry.first.end(),name);
            lines.push_back(line("ITEM",j + 1,name,product.category,"price",moneyText(product.price),"units",units.at(name),"revenue",moneyText(revenue.at(name)),"share",percentText(revenue.at(name),totalRevenue),"baskets",count,"support",fractionText({count,total}),"customers",buyers.at(name),"itemsets",containing,"heldout",heldOut.at(name),"hits",heldHits.at(name),"partner",partner(name),"best",strongest(name)));
        }
        for (const Category& c : categorySummaries) lines.push_back(line("CATEGORY",c.name,"items",c.products,"units",c.units,"revenue",moneyText(c.revenue),"share",percentText(c.revenue,totalRevenue),"baskets",c.baskets,"support",fractionText({c.baskets,total})));
        Integer totalUnits = 0; for (const auto& entry : units) totalUnits += entry.second;
        lines.push_back(line("TOTAL items",products.size(),"units",totalUnits,"revenue",moneyText(totalRevenue),"baskets",total,"customers",customers.size()));
        for (int j = 0; j < static_cast<int>(groups.size()); ++j) {
            const Group& g = groups[j]; lines.push_back(line("GROUP",j + 1,"items",g.members.size(),"edges",g.edges,"core",g.core,"revenue",moneyText(g.revenue),"share",percentText(g.revenue,totalRevenue),"members",itemsetText(g.members)));
        }
        for (const Substitute& s : substitutes) lines.push_back(line("SUBSTITUTE",s.first,s.second,"count",s.together,"expected",fractionText(s.expected),"lift",fractionText(s.lift)));
        auto popularity = [](Items items, const Counts& counts) { std::sort(items.begin(),items.end(),[&](const std::string& a, const std::string& b) { return counts.at(a) != counts.at(b) ? counts.at(a) > counts.at(b) : a < b; }); return items; };
        Items top = popularity(names,main.singles); top.resize(p.matrix); append(lines,matrixLines("MATRIX",top,main.singles,sets));
        append(lines,matrixLines("CATEGORY_MATRIX",popularity(categories,categoryRun.singles),categoryRun.singles,extended)); return lines;
    }
    static std::string tableRow(const std::string& label, const std::vector<Integer>& values) {
        std::ostringstream out; out << std::left << std::setw(17) << label << std::right;
        for (Integer value : values) out << std::setw(6) << value; return out.str();
    }
    Items trendLines() const {
        std::vector<Integer> weekNumbers; for (int j = 1; j <= weeks; ++j) weekNumbers.push_back(j);
        Items lines{tableRow("WEEK",weekNumbers),tableRow("BASKETS",weekBaskets),tableRow("UNITS",weekUnits),tableRow("CUSTOMERS",weekCustomers)};
        for (const std::string& name : categories) lines.push_back(tableRow(name,series.at(name)));
        for (const std::string& name : names) lines.push_back(tableRow(name,series.at(name)));
        for (const Trend& t : trends) lines.push_back(line("TREND",t.name,"units",t.units,"slope",fractionText(t.slope),"relative",t.relative ? fractionText(*t.relative) : "-",t.verdict));
        return lines;
    }
    Items customerLines() const {
        Items lines;
        for (const Customer& c : customerSummaries) lines.push_back(line("CUSTOMER",c.id,"baskets",c.baskets,"days",c.days,"first",c.first,"last",c.last,"items",c.products,"units",c.units,"revenue",moneyText(c.revenue),"average",moneyText(c.revenue / c.baskets),"favorite",c.favorite,"segment",c.segment,"offer",c.offer.empty() ? "none" : itemsetText(c.offer)));
        for (const std::string& segment : Items{"NEW","LOYAL","AT_RISK","REGULAR"}) {
            int count = 0; Integer sum = 0; for (const Customer& c : customerSummaries) if (c.segment == segment) { ++count; sum += c.revenue; }
            lines.push_back(line("SEGMENT",segment,"customers",count,"revenue",moneyText(sum),"share",percentText(sum,totalRevenue)));
        }
        return lines;
    }
public:
    Analysis() : products(data.products) {
        std::set<std::string> categorySet;
        for (const auto& entry : products) { names.push_back(entry.first); taxonomy[entry.first] = entry.second.category; categorySet.insert(entry.second.category); }
        categories = Items(categorySet.begin(),categorySet.end());
        for (const Transaction& transaction : data.transactions) if (!transaction.counts.empty()) baskets.push_back(transaction);
        total = baskets.size();
        for (int j = 0; j < static_cast<int>(baskets.size()); ++j) {
            const Transaction& basket = baskets[j]; Items items = basket.products(); sets.push_back(items); extended.push_back(extendedBasket(items,taxonomy));
            (basket.day <= p.splitDay ? train : test).push_back(items); customerBaskets[basket.customer].push_back(j);
            firstDay = std::min(firstDay,basket.day); lastDay = std::max(lastDay,basket.day);
            for (const std::string& name : items) histories[basket.customer][name].insert(basket.day);
        }
        for (const auto& entry : customerBaskets) customers.push_back(entry.first);
    }
    void run() {
        frequent(); sequential(); validate(); summarizeProducts(); summarizeTrends(); summarizeCustomers();
        writeReport("summary.txt",summaryLines()); writeReport("itemsets.txt",itemsetLines()); writeReport("closed_maximal.txt",classificationLines());
        writeReport("rules.csv",rulesCsv(mainRules.rules)); writeReport("category_rules.csv",rulesCsv(categoryRules.rules));
        writeReport("sequences.txt",sequenceLines()); writeReport("validation.txt",validationLines()); writeReport("items_report.txt",itemLines());
        writeReport("trends.txt",trendLines()); writeReport("customers.txt",customerLines());
    }
};

int main() { Analysis analysis; analysis.run(); }
