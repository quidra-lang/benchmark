#include "survival.hpp"
#include <filesystem>
static std::string number(int value) {
    return std::to_string(value);
}
static std::string real(double value) {
    if (std::abs(value) < 0.00005)
        value = 0;
    std::ostringstream out;
    out << std::fixed << std::setprecision(4) << value;
    return out.str();
}
static std::string one_decimal(double value) {
    std::ostringstream out;
    out << std::fixed << std::setprecision(1) << value;
    return out.str();
}
static std::string optional(std::optional<int> value) {
    return value ? number(*value) : "NA";
}
static void write_lines(const std::string &name, const Lines &lines) {
    std::ofstream file("output/" + name, std::ios::binary);
    for (const std::string &line : lines)
        file << line << '\n';
}
static void paragraph(Lines &out, const Lines &lines) {
    if (!out.empty())
        out.push_back("");
    out.insert(out.end(), lines.begin(), lines.end());
}
struct Collection {
    std::string name;
    Subjects subjects;
    std::vector<KMRow> km;
    std::vector<LifeRow> life;
    int events = 0, maximum = 0, person_days = 0;
    double rate = 0, rate_lower = 0, rate_upper = 0, rmst = 0, rmst_se = 0;
    std::optional<int> followup;
    std::optional<double> life_median;
    std::array<std::array<std::optional<int>, 3>, 3> percentiles;
};
static Collection collection(const std::string &name, const Subjects &subjects, const Params &params) {
    Collection out;
    out.name = name;
    out.subjects = subjects;
    out.km = kaplan_meier(subjects);
    out.life = life_table(subjects, params.life_width, params.life_intervals);
    Subjects reverse = subjects;
    for (Subject &subject : reverse)
        subject.event = 1 - subject.event;
    for (const KMRow &row : kaplan_meier(reverse))
        if (row.survival <= 0.5) {
            out.followup = row.time;
            break;
        }
    double previous = 1;
    for (const LifeRow &row : out.life) {
        if (row.survival <= 0.5) {
            out.life_median = row.a + params.life_width * (previous - 0.5) / (previous - row.survival);
            break;
        }
        previous = row.survival;
    }
    for (const Subject &subject : subjects) {
        out.events += subject.event;
        out.maximum = std::max(out.maximum, subject.time);
        out.person_days += subject.time;
    }
    out.rate = double(1000 * out.events) / out.person_days;
    const double eta = normal_z / std::sqrt(double(out.events));
    out.rate_lower = std::exp(std::log(out.rate) - eta);
    out.rate_upper = std::exp(std::log(out.rate) + eta);
    const std::array<double, 3> quantiles = {0.75, 0.5, 0.25};
    for (int q = 0; q < 3; ++q)
        for (const KMRow &row : out.km) {
            if (!out.percentiles[q][0] && row.survival <= quantiles[q])
                out.percentiles[q][0] = row.time;
            if (!out.percentiles[q][1] && (row.survival == 0 || row.lower <= quantiles[q]))
                out.percentiles[q][1] = row.time;
            if (!out.percentiles[q][2] && (row.survival == 0 || row.upper <= quantiles[q]))
                out.percentiles[q][2] = row.time;
        }
    int count = 0;
    while (count < int(out.km.size()) && out.km[count].time <= params.tau)
        ++count;
    std::vector<double> rectangles(count + 1), tails(count + 1);
    for (int i = 0; i <= count; ++i) {
        const int first = i == 0 ? 0 : out.km[i - 1].time, last = i == count ? params.tau : out.km[i].time;
        rectangles[i] = (i == 0 ? 1 : out.km[i - 1].survival) * (last - first);
    }
    tails[count] = rectangles[count];
    for (int i = count - 1; i >= 0; --i)
        tails[i] = rectangles[i] + tails[i + 1];
    out.rmst = tails[0];
    double variance = 0;
    for (int i = 1; i <= count; ++i) {
        const KMRow &row = out.km[i - 1];
        variance += tails[i] * tails[i] * (double(row.events) / (row.risk * (row.risk - row.events)));
    }
    out.rmst_se = std::sqrt(variance);
    return out;
}
static Lines km_tables(const std::vector<Collection> &collections, const Params &params) {
    Lines out;
    for (const Collection &item : collections) {
        Lines part = {"group " + item.name + " subjects " + number(item.subjects.size()) + " events " +
                          number(item.events) + " censored " + number(item.subjects.size() - item.events) +
                          " max_time " + number(item.maximum),
                      "person_days " + number(item.person_days) + " rate " + real(item.rate) + " lower " +
                          real(item.rate_lower) + " upper " + real(item.rate_upper),
                      "followup_median " + optional(item.followup),
                      "life_table_median " + (item.life_median ? real(*item.life_median) : "NA")};
        for (int q = 0; q < 3; ++q)
            part.push_back("percentile " + number(25 * (q + 1)) + " time " +
                           optional(item.percentiles[q][0]) + " lower " + optional(item.percentiles[q][1]) +
                           " upper " + optional(item.percentiles[q][2]));
        part.push_back("rmst tau " + number(params.tau) + " estimate " + real(item.rmst) + " se " +
                       real(item.rmst_se) + " lower " + real(item.rmst - normal_z * item.rmst_se) +
                       " upper " + real(item.rmst + normal_z * item.rmst_se));
        for (int time : params.report_times) {
            const KMRow row = row_at(item.km, time);
            int events = 0;
            for (const Subject &subject : item.subjects)
                events += subject.time <= time && subject.event;
            part.push_back("at " + number(time) + " at_risk " + number(risk_size(item.subjects, time)) +
                           " events " + number(events) + " survival " + real(row.survival) + " std_err " +
                           (row.error_defined ? real(row.std_err) : "NA") + " lower " +
                           (row.interval_defined ? real(row.lower) : "NA") + " upper " +
                           (row.interval_defined ? real(row.upper) : "NA") + " cum_hazard " +
                           real(row.hazard) + " hazard_se " + real(row.hazard_se));
        }
        std::ostringstream header;
        for (const std::string name : {"time", "at_risk", "events", "censored", "survival", "std_err",
                                       "lower", "upper", "cum_haz", "haz_se"})
            header << std::setw(9) << name;
        part.push_back(header.str());
        for (const KMRow &row : item.km) {
            const Lines fields = {number(row.time),
                                  number(row.risk),
                                  number(row.events),
                                  number(row.censored),
                                  real(row.survival),
                                  row.error_defined ? real(row.std_err) : "NA",
                                  row.interval_defined ? real(row.lower) : "NA",
                                  row.interval_defined ? real(row.upper) : "NA",
                                  real(row.hazard),
                                  real(row.hazard_se)};
            std::ostringstream line;
            for (const std::string &field : fields)
                line << std::setw(9) << field;
            part.push_back(line.str());
        }
        paragraph(out, part);
    }
    return out;
}
static int level(const Subject &subject, const std::string &variable) {
    return variable == "sex" ? (subject.sex == 'M' ? 1 : 0) : subject.stage;
}
static std::string level_name(int value, const std::string &variable) {
    return variable == "sex" ? (value == 0 ? "F" : "M") : number(value);
}
static std::vector<int> levels(const Subjects &subjects, const std::string &variable) {
    std::set<int> values;
    for (const Subject &subject : subjects)
        values.insert(level(subject, variable));
    return {values.begin(), values.end()};
}
static Subjects select_level(const Subjects &subjects, const std::string &variable, int value) {
    Subjects out;
    for (const Subject &subject : subjects)
        if (level(subject, variable) == value)
            out.push_back(subject);
    return out;
}
static Subjects select_groups(const Subjects &subjects, int a, int b) {
    Subjects out;
    for (const Subject &subject : subjects)
        if (subject.group == a || subject.group == b)
            out.push_back(subject);
    return out;
}
static void group_lines(Lines &out, const GroupTest &test, const Params &params) {
    for (std::size_t g = 0; g < test.groups.size(); ++g)
        out.push_back("  group " + params.groups[test.groups[g]] + " events " + number(test.events[g]) +
                      " observed " + real(test.observed[g]) + " expected " + real(test.expected[g]) +
                      " o_minus_e " + real(test.observed[g] - test.expected[g]) + " variance " +
                      real(test.covariance[g][g]));
}
static std::string test_values(double statistic, int degrees) {
    return "chisq " + real(statistic) + " df " + number(degrees) + " p " + real(p_value(statistic, degrees));
}
struct TwoGroup {
    GroupTest test;
    double hr, lower, upper, phi;
};
static TwoGroup two_group(const Subjects &subjects, int a, int b, int total) {
    TwoGroup out;
    out.test = weighted_test(subjects, {a, b}, 0, total);
    out.hr = (out.test.observed[1] / out.test.expected[1]) / (out.test.observed[0] / out.test.expected[0]);
    out.phi = 1 / out.test.expected[0] + 1 / out.test.expected[1];
    const double logarithm = std::log(out.hr), se = std::sqrt(out.phi);
    out.lower = std::exp(logarithm - normal_z * se);
    out.upper = std::exp(logarithm + normal_z * se);
    return out;
}
static Lines group_report(const Dataset &data, const std::vector<Collection> &collections) {
    const Params &p = data.params;
    const Subjects &subjects = data.subjects;
    const int groups = p.groups.size(), total = subjects.size();
    std::vector<int> group_ids(groups);
    std::iota(group_ids.begin(), group_ids.end(), 0);
    Lines out, part = {"baseline"};
    for (const Collection &item : collections) {
        int age_sum = 0, males = 0;
        std::array<int, 4> stages{};
        std::vector<int> ages;
        for (const Subject &subject : item.subjects) {
            age_sum += subject.age;
            males += subject.sex == 'M';
            ++stages[subject.stage - 1];
            ages.push_back(subject.age);
        }
        const int count = ages.size();
        const double mean = double(age_sum) / count;
        double squares = 0;
        for (const Subject &subject : item.subjects)
            squares += (subject.age - mean) * (subject.age - mean);
        std::sort(ages.begin(), ages.end());
        const double median = double(ages[(count - 1) / 2] + ages[count / 2]) / 2;
        part.push_back("  group " + item.name + " subjects " + number(count) + " age_mean " + real(mean) +
                       " age_sd " + real(std::sqrt(squares / (count - 1))) + " age_median " +
                       one_decimal(median) + " male " + number(males) + " stage " + number(stages[0]) + " " +
                       number(stages[1]) + " " + number(stages[2]) + " " + number(stages[3]));
    }
    std::vector<int> age_order(total);
    std::iota(age_order.begin(), age_order.end(), 0);
    std::sort(age_order.begin(), age_order.end(), [&](int a, int b) {
        return subjects[a].age != subjects[b].age ? subjects[a].age < subjects[b].age
                                                  : subjects[a].id < subjects[b].id;
    });
    std::vector<double> ranks(total);
    int tied = 0, first = 0;
    while (first < total) {
        int end = first + 1;
        while (end < total && subjects[age_order[end]].age == subjects[age_order[first]].age)
            ++end;
        const double rank = double(first + 1 + end) / 2;
        for (int i = first; i < end; ++i)
            ranks[age_order[i]] = rank;
        const int count = end - first;
        tied += count * count * count - count;
        first = end;
    }
    Vector rank_sums{};
    for (int i = 0; i < total; ++i)
        rank_sums[subjects[i].group] += ranks[i];
    double sum = 0;
    for (int g = 0; g < groups; ++g)
        sum += rank_sums[g] * rank_sums[g] / collections[g].subjects.size();
    const double initial = 12 * sum / (total * (total + 1)) - 3 * (total + 1),
                 kw = initial / (1 - double(tied) / (total * total * total - total));
    part.push_back("  age kruskal_wallis " + test_values(kw, groups - 1));
    for (const std::string variable : {"sex", "stage"}) {
        const auto values = levels(subjects, variable);
        std::vector<std::vector<int>> counts(groups, std::vector<int>(values.size()));
        std::vector<int> columns(values.size());
        for (const Subject &subject : subjects) {
            const int j =
                std::lower_bound(values.begin(), values.end(), level(subject, variable)) - values.begin();
            ++counts[subject.group][j];
            ++columns[j];
        }
        double statistic = 0;
        for (int g = 0; g < groups; ++g)
            for (std::size_t j = 0; j < values.size(); ++j) {
                const double expected = double(int(collections[g].subjects.size()) * columns[j]) / total;
                statistic += (counts[g][j] - expected) * (counts[g][j] - expected) / expected;
            }
        part.push_back("  " + variable + " " + test_values(statistic, (groups - 1) * (values.size() - 1)));
    }
    paragraph(out, part);
    part.clear();
    const std::array<std::string, 3> weights = {"logrank", "gehan_wilcoxon", "tarone_ware"};
    std::array<GroupTest, 3> overall;
    for (int kind = 0; kind < 3; ++kind) {
        overall[kind] = weighted_test(subjects, group_ids, kind, total);
        part.push_back("test " + weights[kind] + " " +
                       test_values(overall[kind].statistic, overall[kind].degrees));
        group_lines(part, overall[kind], p);
    }
    double trend_u = 0, trend_v = 0;
    for (int g = 0; g < groups; ++g) {
        trend_u += (g + 1) * (overall[0].observed[g] - overall[0].expected[g]);
        double inner = 0;
        for (int h = 0; h < groups; ++h)
            inner += ((g + 1) * (h + 1)) * overall[0].covariance[g][h];
        trend_v += inner;
    }
    part.push_back("test logrank_trend " + test_values(trend_u * trend_u / trend_v, 1));
    paragraph(out, part);
    part.clear();
    const auto strata = levels(subjects, p.strata);
    for (int kind = 0; kind < 3; ++kind) {
        std::vector<GroupTest> tests;
        std::vector<Subjects> sets;
        for (int value : strata) {
            sets.push_back(select_level(subjects, p.strata, value));
            tests.push_back(weighted_test(sets.back(), group_ids, kind, total));
        }
        const GroupTest combined = combine_tests(tests);
        part.push_back("stratified " + weights[kind] + " by " + p.strata + " " +
                       test_values(combined.statistic, combined.degrees));
        for (std::size_t i = 0; i < strata.size(); ++i) {
            int events = 0;
            for (const Subject &subject : sets[i])
                events += subject.event;
            part.push_back("  stratum " + level_name(strata[i], p.strata) + " subjects " +
                           number(sets[i].size()) + " events " + number(events) + " chisq " +
                           real(tests[i].statistic) + " p " + real(tests[i].p));
        }
        group_lines(part, combined, p);
    }
    paragraph(out, part);
    Subjects landmark;
    for (const Subject &subject : subjects)
        if (subject.time > p.landmark)
            landmark.push_back(subject);
    const GroupTest landmark_test = weighted_test(landmark, group_ids, 0, total);
    part = {"landmark " + number(p.landmark) + " subjects " + number(landmark.size()) + " " +
            test_values(landmark_test.statistic, landmark_test.degrees)};
    group_lines(part, landmark_test, p);
    paragraph(out, part);
    struct Pair {
        int a, b;
        TwoGroup result;
        double adjusted = 0;
    };
    std::vector<Pair> pairs;
    for (int a = 0; a < groups; ++a)
        for (int b = a + 1; b < groups; ++b)
            pairs.push_back({a, b, two_group(select_groups(subjects, a, b), a, b, total), 0});
    std::vector<int> order(pairs.size());
    std::iota(order.begin(), order.end(), 0);
    std::sort(order.begin(), order.end(), [&](int a, int b) {
        return pairs[a].result.test.p != pairs[b].result.test.p
                   ? pairs[a].result.test.p < pairs[b].result.test.p
                   : a < b;
    });
    double adjusted = 0;
    for (std::size_t r = 0; r < order.size(); ++r) {
        Pair &pair = pairs[order[r]];
        adjusted = std::max(adjusted, std::min(1.0, (order.size() - r) * pair.result.test.p));
        pair.adjusted = adjusted;
    }
    part = {"pairwise logrank adjust holm"};
    for (const Pair &pair : pairs)
        part.push_back("  " + p.groups[pair.a] + " " + p.groups[pair.b] + " chisq " +
                       real(pair.result.test.statistic) + " p " + real(pair.result.test.p) + " p_holm " +
                       real(pair.adjusted) + " hr " + real(pair.result.hr) + " lower " +
                       real(pair.result.lower) + " upper " + real(pair.result.upper));
    paragraph(out, part);
    part = {"subgroups reference " + p.groups[0]};
    for (const std::string &variable : p.subgroups) {
        const auto values = levels(subjects, variable);
        for (int b = 1; b < groups; ++b) {
            std::vector<double> weights_, logarithms;
            double numerator = 0, denominator = 0;
            for (int value : values) {
                const Subjects selected = select_groups(select_level(subjects, variable, value), 0, b);
                const TwoGroup comparison = two_group(selected, 0, b, total);
                int events = 0;
                for (const Subject &subject : selected)
                    events += subject.event;
                part.push_back("  " + variable + " " + level_name(value, variable) + " " + p.groups[b] +
                               " subjects " + number(selected.size()) + " events " + number(events) + " hr " +
                               real(comparison.hr) + " lower " + real(comparison.lower) + " upper " +
                               real(comparison.upper) + " p " + real(comparison.test.p));
                const double weight = 1 / comparison.phi, logarithm = std::log(comparison.hr);
                weights_.push_back(weight);
                logarithms.push_back(logarithm);
                numerator += weight * logarithm;
                denominator += weight;
            }
            const double mean = numerator / denominator;
            double heterogeneity = 0;
            for (std::size_t i = 0; i < weights_.size(); ++i)
                heterogeneity += weights_[i] * (logarithms[i] - mean) * (logarithms[i] - mean);
            part.push_back("  " + variable + " " + p.groups[b] + " heterogeneity " +
                           test_values(heterogeneity, values.size() - 1));
        }
    }
    paragraph(out, part);
    part = {"rmst_difference tau " + number(p.tau) + " reference " + p.groups[0]};
    for (int g = 1; g < groups; ++g) {
        const double difference = collections[g].rmst - collections[0].rmst,
                     se = std::sqrt(collections[g].rmst_se * collections[g].rmst_se +
                                    collections[0].rmst_se * collections[0].rmst_se),
                     statistic = difference / se;
        part.push_back("  " + p.groups[g] + " difference " + real(difference) + " se " + real(se) +
                       " lower " + real(difference - normal_z * se) + " upper " +
                       real(difference + normal_z * se) + " z " + real(statistic) + " p " +
                       real(p_value(statistic * statistic, 1)));
    }
    paragraph(out, part);
    part = {"rate_ratio reference " + p.groups[0]};
    for (int g = 1; g < groups; ++g) {
        const double ratio = collections[g].rate / collections[0].rate,
                     se = std::sqrt(1.0 / collections[g].events + 1.0 / collections[0].events),
                     logarithm = std::log(ratio), statistic = logarithm / se;
        part.push_back("  " + p.groups[g] + " ratio " + real(ratio) + " lower " +
                       real(std::exp(logarithm - normal_z * se)) + " upper " +
                       real(std::exp(logarithm + normal_z * se)) + " z " + real(statistic) + " p " +
                       real(p_value(statistic * statistic, 1)));
    }
    paragraph(out, part);
    part = {"survival_difference reference " + p.groups[0]};
    for (int time : p.report_times)
        for (int g = 1; g < groups; ++g) {
            const KMRow first_ = row_at(collections[0].km, time), second = row_at(collections[g].km, time);
            const double difference = second.survival - first_.survival,
                         se = std::sqrt(second.std_err * second.std_err + first_.std_err * first_.std_err),
                         statistic = difference / se;
            part.push_back("  at " + number(time) + " " + p.groups[g] + " difference " + real(difference) +
                           " se " + real(se) + " lower " + real(difference - normal_z * se) + " upper " +
                           real(difference + normal_z * se) + " z " + real(statistic) + " p " +
                           real(p_value(statistic * statistic, 1)));
        }
    paragraph(out, part);
    return out;
}
static Lines cox_report(const Dataset &data) {
    const Subjects &subjects = data.subjects;
    const Params &p = data.params;
    const int size = p.covariates.size(), count = subjects.size();
    std::vector<Vector> design(count);
    std::vector<bool> group_term(size);
    for (int c = 0; c < size; ++c) {
        const std::string &name = p.covariates[c];
        group_term[c] = name != "age" && name != "male" && name != "stage";
        const int group = std::find(p.groups.begin(), p.groups.end(), name) - p.groups.begin();
        for (int j = 0; j < count; ++j)
            design[j][c] = name == "age"                ? subjects[j].age
                           : name == "male"             ? (subjects[j].sex == 'M' ? 1 : 0)
                           : name == "stage"            ? subjects[j].stage
                           : subjects[j].group == group ? 1
                                                        : 0;
    }
    const CoxFit fit = cox_fit(subjects, design, size);
    const Matrix covariance = inverse(fit.final.information, size);
    int events = 0;
    for (const Subject &subject : subjects)
        events += subject.event;
    std::string header = "cox covariates";
    for (const std::string &name : p.covariates)
        header += " " + name;
    header += " subjects " + number(count) + " events " + number(events) + " event_times " +
              number(fit.final.times.size());
    Lines out = {header};
    for (std::size_t i = 0; i < fit.iterations.size(); ++i) {
        std::string line = "iter " + number(i + 1) + " loglik " + real(fit.iterations[i].first) + " beta";
        for (int c = 0; c < size; ++c)
            line += " " + real(fit.iterations[i].second[c]);
        out.push_back(line);
    }
    out.push_back("final loglik " + real(fit.final.loglik) + " null_loglik " + real(fit.initial.loglik));
    auto coefficient = [&](const std::string &prefix, double value, double se) {
        const double statistic = value / se;
        return prefix + " coef " + real(value) + " se " + real(se) + " z " + real(statistic) + " p " +
               real(p_value(statistic * statistic, 1)) + " hr " + real(std::exp(value)) + " lower " +
               real(std::exp(value - normal_z * se)) + " upper " + real(std::exp(value + normal_z * se));
    };
    for (int c = 0; c < size; ++c)
        out.push_back(coefficient("term " + p.covariates[c], fit.beta[c], std::sqrt(covariance[c][c])));
    for (int a = 0; a < size; ++a)
        if (group_term[a])
            for (int b = a + 1; b < size; ++b)
                if (group_term[b])
                    out.push_back(coefficient(
                        "contrast " + p.covariates[b] + " vs " + p.covariates[a], fit.beta[b] - fit.beta[a],
                        std::sqrt(covariance[b][b] + covariance[a][a] - 2 * covariance[a][b])));
    const double likelihood = 2 * (fit.final.loglik - fit.initial.loglik);
    double wald = 0;
    for (int c = 0; c < size; ++c) {
        double sum = 0;
        for (int d = 0; d < size; ++d)
            sum += fit.final.information[c][d] * fit.beta[d];
        wald += fit.beta[c] * sum;
    }
    const Vector score_solution = solve(fit.initial.information, fit.initial.score, size);
    double score = 0;
    for (int c = 0; c < size; ++c)
        score += fit.initial.score[c] * score_solution[c];
    out.push_back("likelihood_ratio " + test_values(likelihood, size));
    out.push_back("wald " + test_values(wald, size));
    out.push_back("score " + test_values(score, size));
    for (int c = 0; c < size; ++c) {
        double loglik = fit.initial.loglik;
        if (size >= 2) {
            std::vector<Vector> reduced(count);
            for (int j = 0; j < count; ++j) {
                int column = 0;
                for (int d = 0; d < size; ++d)
                    if (c != d)
                        reduced[j][column++] = design[j][d];
            }
            loglik = cox_fit(subjects, reduced, size - 1).final.loglik;
        }
        out.push_back("drop " + p.covariates[c] + " loglik " + real(loglik) + " chisq " +
                      real(2 * (fit.final.loglik - loglik)) + " df 1 p " +
                      real(p_value(2 * (fit.final.loglik - loglik), 1)));
    }
    int comparable = 0, concordant = 0, tied = 0;
    for (int i = 0; i < count; ++i)
        if (subjects[i].event)
            for (int j = 0; j < count; ++j)
                if (i != j && (subjects[i].time < subjects[j].time ||
                               (subjects[i].time == subjects[j].time && !subjects[j].event))) {
                    ++comparable;
                    bool equal = true;
                    for (int c = 0; c < size; ++c)
                        if (design[i][c] != design[j][c])
                            equal = false;
                    if (equal)
                        ++tied;
                    else if (fit.final.theta[i] > fit.final.theta[j])
                        ++concordant;
                }
    out.push_back("concordance " + real(double(2 * concordant + tied) / (2 * comparable)) + " comparable " +
                  number(comparable) + " concordant " + number(concordant) + " tied " + number(tied));
    std::map<int, CoxTime> time_values;
    for (const CoxTime &time : fit.final.times)
        time_values[time.time] = time;
    std::vector<int> event_order;
    for (int i = 0; i < count; ++i)
        if (subjects[i].event)
            event_order.push_back(i);
    std::sort(event_order.begin(), event_order.end(), [&](int a, int b) {
        return subjects[a].time != subjects[b].time ? subjects[a].time < subjects[b].time
                                                    : subjects[a].id < subjects[b].id;
    });
    int time_sum = 0;
    for (int i : event_order)
        time_sum += subjects[i].time;
    const double time_mean = double(time_sum) / event_order.size();
    for (int c = 0; c < size; ++c) {
        std::vector<double> residuals;
        double sum = 0;
        for (int i : event_order) {
            const CoxTime &time = time_values.at(subjects[i].time);
            const double value = design[i][c] - time.s1[c] / time.s0;
            residuals.push_back(value);
            sum += value;
        }
        const double mean = sum / event_order.size();
        double sxy = 0, sxx = 0, syy = 0;
        for (std::size_t i = 0; i < event_order.size(); ++i) {
            const double x = residuals[i] - mean, y = subjects[event_order[i]].time - time_mean;
            sxy += x * y;
            sxx += x * x;
            syy += y * y;
        }
        const double rho = sxy / std::sqrt(sxx * syy), statistic = 0.5 * std::log((1 + rho) / (1 - rho)) *
                                                                   std::sqrt(double(event_order.size() - 3));
        out.push_back("ph_check " + p.covariates[c] + " rho " + real(rho) + " z " + real(statistic) + " p " +
                      real(p_value(statistic * statistic, 1)));
    }
    std::map<int, double> baseline;
    double hazard = 0;
    for (const auto &entry : time_values) {
        hazard += entry.second.events / entry.second.s0;
        baseline[entry.first] = hazard;
    }
    auto cumulative = [&](int time) {
        const auto found = baseline.upper_bound(time);
        return found == baseline.begin() ? 0 : std::prev(found)->second;
    };
    struct Residual {
        int subject;
        double martingale, deviance;
    };
    std::vector<Residual> residuals;
    for (int j = 0; j < count; ++j) {
        const double martingale =
            subjects[j].event - cumulative(subjects[j].time) * std::exp(fit.final.theta[j]);
        double deviance = subjects[j].event ? std::sqrt(-2 * (martingale + std::log(1 - martingale)))
                                            : std::sqrt(-2 * martingale);
        if (!(martingale > 0))
            deviance = -deviance;
        residuals.push_back({j, martingale, deviance});
    }
    std::sort(residuals.begin(), residuals.end(), [&](const Residual &a, const Residual &b) {
        return std::abs(a.deviance) != std::abs(b.deviance) ? std::abs(a.deviance) > std::abs(b.deviance)
                                                            : subjects[a.subject].id < subjects[b.subject].id;
    });
    out.push_back("residuals top " + number(p.residuals));
    for (int i = 0; i < p.residuals; ++i) {
        const Residual &residual = residuals[i];
        const Subject &subject = subjects[residual.subject];
        out.push_back("  id " + number(subject.id) + " group " + p.groups[subject.group] + " time " +
                      number(subject.time) + " event " + number(subject.event) + " martingale " +
                      real(residual.martingale) + " deviance " + real(residual.deviance));
    }
    Vector means{};
    std::string mean_line = "adjusted_survival mean";
    bool any = false;
    for (int c = 0; c < size; ++c)
        if (!group_term[c]) {
            int sum = 0;
            for (int j = 0; j < count; ++j)
                sum += int(design[j][c]);
            means[c] = double(sum) / count;
            mean_line += " " + p.covariates[c] + " " + real(means[c]);
            any = true;
        }
    if (!any)
        mean_line += " none";
    out.push_back(mean_line);
    std::vector<double> group_risks;
    for (std::size_t group = 0; group < p.groups.size(); ++group) {
        double predictor = 0;
        for (int c = 0; c < size; ++c) {
            const double value = group_term[c] ? (p.covariates[c] == p.groups[group] ? 1 : 0) : means[c];
            predictor += fit.beta[c] * value;
        }
        group_risks.push_back(std::exp(predictor));
    }
    for (int time : p.report_times) {
        std::string line = "  at " + number(time);
        for (std::size_t group = 0; group < p.groups.size(); ++group)
            line += " " + p.groups[group] + " " + real(std::exp(-cumulative(time) * group_risks[group]));
        out.push_back(line);
    }
    std::string median_line = "  median";
    for (std::size_t group = 0; group < p.groups.size(); ++group) {
        std::optional<int> median;
        for (const auto &entry : baseline)
            if (std::exp(-entry.second * group_risks[group]) <= 0.5) {
                median = entry.first;
                break;
            }
        median_line += " " + p.groups[group] + " " + optional(median);
    }
    out.push_back(median_line);
    return out;
}
int main() {
    std::filesystem::create_directories("output");
    const Dataset data = read_dataset();
    std::vector<Collection> collections;
    for (std::size_t group = 0; group < data.params.groups.size(); ++group) {
        Subjects subjects;
        for (const Subject &subject : data.subjects)
            if (subject.group == int(group))
                subjects.push_back(subject);
        collections.push_back(collection(data.params.groups[group], subjects, data.params));
    }
    collections.push_back(collection("all", data.subjects, data.params));
    write_lines("km_tables.txt", km_tables(collections, data.params));
    Lines life = {"group,interval,at_risk,events,withdrawn,exposed,q,survival,std_err,hazard"};
    for (const Collection &item : collections)
        for (const LifeRow &row : item.life)
            life.push_back(item.name + "," + number(row.a) + "-" + number(row.b) + "," + number(row.risk) +
                           "," + number(row.events) + "," + number(row.withdrawn) + "," +
                           one_decimal(double(row.exposure2) / 2) + "," + real(row.probability) + "," +
                           real(row.survival) + "," + real(row.std_err) + "," + real(row.hazard));
    write_lines("life_table.csv", life);
    write_lines("tests.txt", group_report(data, collections));
    write_lines("cox.txt", cox_report(data));
    std::vector<std::vector<KMRow>> curves;
    std::vector<int> maximums;
    for (std::size_t group = 0; group < data.params.groups.size(); ++group) {
        curves.push_back(collections[group].km);
        maximums.push_back(collections[group].maximum);
    }
    Lines plot = curve_plot(curves, maximums, data.params);
    std::string line = "at_risk";
    for (int i = 0; i <= data.params.plot_divisions; ++i)
        line += " " + number(i * (data.params.plot_time / data.params.plot_divisions));
    plot.push_back(line);
    for (std::size_t group = 0; group < data.params.groups.size(); ++group) {
        line = data.params.groups[group];
        for (int i = 0; i <= data.params.plot_divisions; ++i)
            line += " " + number(risk_size(collections[group].subjects,
                                           i * (data.params.plot_time / data.params.plot_divisions)));
        plot.push_back(line);
    }
    write_lines("km_plot.txt", plot);
}
