#include "survival.h"
#include <sys/stat.h>
static char *real(double value) {
    if (fabs(value) < 0.00005)
        value = 0;
    return format("%.4f", value);
}
static char *optional(int value) {
    return value >= 0 ? format("%d", value) : text("NA");
}
static void write_lines(const char *name, const Lines *lines) {
    char *path = format("output/%s", name);
    FILE *file = fopen(path, "wb");
    free(path);
    if (!file)
        return;
    for (int i = 0; i < lines->count; ++i) {
        fputs(lines->data[i], file);
        fputc('\n', file);
    }
    fclose(file);
}
static void write_owned(const char *name, Lines lines) {
    write_lines(name, &lines);
    lines_free(&lines);
}
static void paragraph(Lines *out, Lines *part) {
    if (out->count)
        line_push(out, text(""));
    lines_extend(out, part);
    lines_free(part);
}
typedef struct {
    const char *name;
    Subjects subjects;
    KMRows km;
    LifeRows life;
    int events, maximum, person_days, followup, percentiles[3][3];
    double rate, rate_lower, rate_upper, rmst, rmst_se, life_median;
    bool life_median_defined;
} Collection;
static Collection collection(const char *name, Subjects subjects, const Params *params) {
    Collection out = {.name = name, .subjects = subjects, .followup = -1};
    for (int i = 0; i < 3; ++i)
        for (int j = 0; j < 3; ++j)
            out.percentiles[i][j] = -1;
    out.km = kaplan_meier(&subjects);
    out.life = life_table(&subjects, params->life_width, params->life_intervals);
    Subjects reverse = {0};
    for (int i = 0; i < subjects.count; ++i) {
        Subject subject = subjects.data[i];
        subject.event = 1 - subject.event;
        subject_push(&reverse, subject);
    }
    KMRows reversed = kaplan_meier(&reverse);
    for (int i = 0; i < reversed.count; ++i)
        if (reversed.data[i].survival <= 0.5) {
            out.followup = reversed.data[i].time;
            break;
        }
    free(reversed.data);
    free(reverse.data);
    double previous = 1;
    for (int i = 0; i < out.life.count; ++i) {
        const LifeRow *row = &out.life.data[i];
        if (row->survival <= 0.5) {
            out.life_median = row->a + params->life_width * (previous - 0.5) / (previous - row->survival);
            out.life_median_defined = true;
            break;
        }
        previous = row->survival;
    }
    for (int i = 0; i < subjects.count; ++i) {
        const Subject *subject = &subjects.data[i];
        out.events += subject->event;
        if (subject->time > out.maximum)
            out.maximum = subject->time;
        out.person_days += subject->time;
    }
    out.rate = (double)(1000 * out.events) / out.person_days;
    double eta = NORMAL_Z / sqrt((double)out.events);
    out.rate_lower = exp(log(out.rate) - eta);
    out.rate_upper = exp(log(out.rate) + eta);
    const double quantiles[] = {0.75, 0.5, 0.25};
    for (int q = 0; q < 3; ++q)
        for (int i = 0; i < out.km.count; ++i) {
            const KMRow *row = &out.km.data[i];
            if (out.percentiles[q][0] < 0 && row->survival <= quantiles[q])
                out.percentiles[q][0] = row->time;
            if (out.percentiles[q][1] < 0 && (row->survival == 0 || row->lower <= quantiles[q]))
                out.percentiles[q][1] = row->time;
            if (out.percentiles[q][2] < 0 && (row->survival == 0 || row->upper <= quantiles[q]))
                out.percentiles[q][2] = row->time;
        }
    int count = 0;
    while (count < out.km.count && out.km.data[count].time <= params->tau)
        ++count;
    double rectangles[401], tails[401];
    for (int i = 0; i <= count; ++i) {
        int first = i == 0 ? 0 : out.km.data[i - 1].time,
            last = i == count ? params->tau : out.km.data[i].time;
        rectangles[i] = (i == 0 ? 1 : out.km.data[i - 1].survival) * (last - first);
    }
    tails[count] = rectangles[count];
    for (int i = count - 1; i >= 0; --i)
        tails[i] = rectangles[i] + tails[i + 1];
    out.rmst = tails[0];
    double variance = 0;
    for (int i = 1; i <= count; ++i) {
        const KMRow *row = &out.km.data[i - 1];
        variance += tails[i] * tails[i] * ((double)row->events / (row->risk * (row->risk - row->events)));
    }
    out.rmst_se = sqrt(variance);
    return out;
}
static Lines km_tables(const Collection *collections, int count, const Params *params) {
    Lines out = {0};
    for (int c = 0; c < count; ++c) {
        const Collection *item = &collections[c];
        Lines part = {0};
        line_push(&part, format("group %s subjects %d events %d censored %d max_time %d", item->name,
                                item->subjects.count, item->events, item->subjects.count - item->events,
                                item->maximum));
        line_push(&part, format("person_days %d rate %s lower %s upper %s", item->person_days,
                                real(item->rate), real(item->rate_lower), real(item->rate_upper)));
        line_push(&part, format("followup_median %s", optional(item->followup)));
        line_push(&part,
                  format("life_table_median %s", item->life_median_defined ? real(item->life_median) : "NA"));
        for (int q = 0; q < 3; ++q)
            line_push(&part, format("percentile %d time %s lower %s upper %s", 25 * (q + 1),
                                    optional(item->percentiles[q][0]), optional(item->percentiles[q][1]),
                                    optional(item->percentiles[q][2])));
        line_push(&part,
                  format("rmst tau %d estimate %s se %s lower %s upper %s", params->tau, real(item->rmst),
                         real(item->rmst_se), real(item->rmst - NORMAL_Z * item->rmst_se),
                         real(item->rmst + NORMAL_Z * item->rmst_se)));
        for (int i = 0; i < params->report_times.count; ++i) {
            int time = params->report_times.data[i], events = 0;
            KMRow row = row_at(&item->km, time);
            for (int j = 0; j < item->subjects.count; ++j)
                events += item->subjects.data[j].time <= time && item->subjects.data[j].event;
            line_push(
                &part,
                format(
                    "at %d at_risk %d events %d survival %s std_err %s lower %s upper %s cum_hazard %s hazard_se %s",
                    time, risk_size(&item->subjects, time), events, real(row.survival),
                    row.error_defined ? real(row.std_err) : "NA",
                    row.interval_defined ? real(row.lower) : "NA",
                    row.interval_defined ? real(row.upper) : "NA", real(row.hazard), real(row.hazard_se)));
        }
        line_push(&part, format("%9s%9s%9s%9s%9s%9s%9s%9s%9s%9s", "time", "at_risk", "events", "censored",
                                "survival", "std_err", "lower", "upper", "cum_haz", "haz_se"));
        for (int i = 0; i < item->km.count; ++i) {
            const KMRow *row = &item->km.data[i];
            line_push(&part, format("%9d%9d%9d%9d%9s%9s%9s%9s%9s%9s", row->time, row->risk, row->events,
                                    row->censored, real(row->survival),
                                    row->error_defined ? real(row->std_err) : "NA",
                                    row->interval_defined ? real(row->lower) : "NA",
                                    row->interval_defined ? real(row->upper) : "NA", real(row->hazard),
                                    real(row->hazard_se)));
        }
        paragraph(&out, &part);
    }
    return out;
}
static int level(const Subject *subject, const char *variable) {
    return !strcmp(variable, "sex") ? (subject->sex == 'M' ? 1 : 0) : subject->stage;
}
static char *level_name(int value, const char *variable) {
    return !strcmp(variable, "sex") ? text(value == 0 ? "F" : "M") : format("%d", value);
}
static IntList levels(const Subjects *subjects, const char *variable) {
    IntList out = {0};
    for (int i = 0; i < subjects->count; ++i) {
        int value = level(&subjects->data[i], variable);
        bool found = false;
        for (int j = 0; j < out.count; ++j)
            if (out.data[j] == value)
                found = true;
        if (!found)
            int_push(&out, value);
    }
    int_sort(&out);
    return out;
}
static Subjects select_level(const Subjects *subjects, const char *variable, int value) {
    Subjects out = {0};
    for (int i = 0; i < subjects->count; ++i)
        if (level(&subjects->data[i], variable) == value)
            subject_push(&out, subjects->data[i]);
    return out;
}
static Subjects select_groups(const Subjects *subjects, int a, int b) {
    Subjects out = {0};
    for (int i = 0; i < subjects->count; ++i)
        if (subjects->data[i].group == a || subjects->data[i].group == b)
            subject_push(&out, subjects->data[i]);
    return out;
}
static void group_lines(Lines *out, const GroupTest *test, const Params *params) {
    for (int g = 0; g < test->count; ++g)
        line_push(out,
                  format("  group %s events %d observed %s expected %s o_minus_e %s variance %s",
                         params->groups.data[test->groups[g]], test->events[g], real(test->observed.v[g]),
                         real(test->expected.v[g]), real(test->observed.v[g] - test->expected.v[g]),
                         real(test->covariance.v[g][g])));
}
static char *test_values(double statistic, int degrees) {
    return format("chisq %s df %d p %s", real(statistic), degrees, real(p_value(statistic, degrees)));
}
typedef struct {
    GroupTest test;
    double hr, lower, upper, phi;
} TwoGroup;
static TwoGroup two_group(const Subjects *subjects, int a, int b, int total) {
    int groups[] = {a, b};
    TwoGroup out = {0};
    out.test = weighted_test(subjects, groups, 2, 0, total);
    out.hr =
        (out.test.observed.v[1] / out.test.expected.v[1]) / (out.test.observed.v[0] / out.test.expected.v[0]);
    out.phi = 1 / out.test.expected.v[0] + 1 / out.test.expected.v[1];
    double logarithm = log(out.hr), se = sqrt(out.phi);
    out.lower = exp(logarithm - NORMAL_Z * se);
    out.upper = exp(logarithm + NORMAL_Z * se);
    return out;
}
static Lines group_report(const Dataset *data, const Collection *collections) {
    const Params *p = &data->params;
    const Subjects *subjects = &data->subjects;
    int groups = p->groups.count, total = subjects->count, group_ids[6];
    for (int g = 0; g < groups; ++g)
        group_ids[g] = g;
    Lines out = {0}, part = {0};
    line_push(&part, text("baseline"));
    for (int c = 0; c <= groups; ++c) {
        const Collection *item = &collections[c];
        int age_sum = 0, males = 0, stages[4] = {0};
        IntList ages = {0};
        for (int i = 0; i < item->subjects.count; ++i) {
            const Subject *subject = &item->subjects.data[i];
            age_sum += subject->age;
            males += subject->sex == 'M';
            ++stages[subject->stage - 1];
            int_push(&ages, subject->age);
        }
        int count = ages.count;
        double mean = (double)age_sum / count, squares = 0;
        for (int i = 0; i < item->subjects.count; ++i) {
            double age = item->subjects.data[i].age;
            squares += (age - mean) * (age - mean);
        }
        int_sort(&ages);
        double median = (double)(ages.data[(count - 1) / 2] + ages.data[count / 2]) / 2;
        line_push(
            &part,
            format("  group %s subjects %d age_mean %s age_sd %s age_median %.1f male %d stage %d %d %d %d",
                   item->name, count, real(mean), real(sqrt(squares / (count - 1))), median, males, stages[0],
                   stages[1], stages[2], stages[3]));
        free(ages.data);
    }
    int age_order[400];
    for (int i = 0; i < total; ++i) {
        int j = i;
        while (j > 0 && (subjects->data[i].age < subjects->data[age_order[j - 1]].age ||
                         (subjects->data[i].age == subjects->data[age_order[j - 1]].age &&
                          subjects->data[i].id < subjects->data[age_order[j - 1]].id))) {
            age_order[j] = age_order[j - 1];
            --j;
        }
        age_order[j] = i;
    }
    double ranks[400];
    int tied = 0, first = 0;
    while (first < total) {
        int end = first + 1;
        while (end < total && subjects->data[age_order[end]].age == subjects->data[age_order[first]].age)
            ++end;
        double rank = (double)(first + 1 + end) / 2;
        for (int i = first; i < end; ++i)
            ranks[age_order[i]] = rank;
        int count = end - first;
        tied += count * count * count - count;
        first = end;
    }
    Vector rank_sums = {0};
    for (int i = 0; i < total; ++i)
        rank_sums.v[subjects->data[i].group] += ranks[i];
    double sum = 0;
    for (int g = 0; g < groups; ++g)
        sum += rank_sums.v[g] * rank_sums.v[g] / collections[g].subjects.count;
    double initial = 12 * sum / (total * (total + 1)) - 3 * (total + 1),
           kw = initial / (1 - (double)tied / (total * total * total - total));
    line_push(&part, format("  age kruskal_wallis %s", test_values(kw, groups - 1)));
    const char *variables[] = {"sex", "stage"};
    for (int variable_index = 0; variable_index < 2; ++variable_index) {
        const char *variable = variables[variable_index];
        IntList values = levels(subjects, variable);
        int counts[6][4] = {{0}}, columns[4] = {0};
        for (int i = 0; i < total; ++i) {
            const Subject *subject = &subjects->data[i];
            int j = 0;
            while (values.data[j] != level(subject, variable))
                ++j;
            ++counts[subject->group][j];
            ++columns[j];
        }
        double statistic = 0;
        for (int g = 0; g < groups; ++g)
            for (int j = 0; j < values.count; ++j) {
                double expected = (double)(collections[g].subjects.count * columns[j]) / total;
                statistic += (counts[g][j] - expected) * (counts[g][j] - expected) / expected;
            }
        line_push(&part,
                  format("  %s %s", variable, test_values(statistic, (groups - 1) * (values.count - 1))));
        free(values.data);
    }
    paragraph(&out, &part);
    const char *weights[] = {"logrank", "gehan_wilcoxon", "tarone_ware"};
    GroupTest overall[3];
    for (int kind = 0; kind < 3; ++kind) {
        overall[kind] = weighted_test(subjects, group_ids, groups, kind, total);
        line_push(&part, format("test %s %s", weights[kind],
                                test_values(overall[kind].statistic, overall[kind].degrees)));
        group_lines(&part, &overall[kind], p);
    }
    double trend_u = 0, trend_v = 0;
    for (int g = 0; g < groups; ++g) {
        trend_u += (g + 1) * (overall[0].observed.v[g] - overall[0].expected.v[g]);
        double inner = 0;
        for (int h = 0; h < groups; ++h)
            inner += ((g + 1) * (h + 1)) * overall[0].covariance.v[g][h];
        trend_v += inner;
    }
    line_push(&part, format("test logrank_trend %s", test_values(trend_u * trend_u / trend_v, 1)));
    paragraph(&out, &part);
    IntList strata = levels(subjects, p->strata);
    for (int kind = 0; kind < 3; ++kind) {
        GroupTest tests[4];
        Subjects sets[4];
        for (int i = 0; i < strata.count; ++i) {
            sets[i] = select_level(subjects, p->strata, strata.data[i]);
            tests[i] = weighted_test(&sets[i], group_ids, groups, kind, total);
        }
        GroupTest combined = combine_tests(tests, strata.count);
        line_push(&part, format("stratified %s by %s %s", weights[kind], p->strata,
                                test_values(combined.statistic, combined.degrees)));
        for (int i = 0; i < strata.count; ++i) {
            int events = 0;
            for (int j = 0; j < sets[i].count; ++j)
                events += sets[i].data[j].event;
            line_push(&part, format("  stratum %s subjects %d events %d chisq %s p %s",
                                    level_name(strata.data[i], p->strata), sets[i].count, events,
                                    real(tests[i].statistic), real(tests[i].p)));
            free(sets[i].data);
        }
        group_lines(&part, &combined, p);
    }
    free(strata.data);
    paragraph(&out, &part);
    Subjects landmark = {0};
    for (int i = 0; i < total; ++i)
        if (subjects->data[i].time > p->landmark)
            subject_push(&landmark, subjects->data[i]);
    GroupTest landmark_test = weighted_test(&landmark, group_ids, groups, 0, total);
    line_push(&part, format("landmark %d subjects %d %s", p->landmark, landmark.count,
                            test_values(landmark_test.statistic, landmark_test.degrees)));
    group_lines(&part, &landmark_test, p);
    free(landmark.data);
    paragraph(&out, &part);
    typedef struct {
        int a, b;
        TwoGroup result;
        double adjusted;
    } Pair;
    Pair pairs[15];
    int pair_count = 0;
    for (int a = 0; a < groups; ++a)
        for (int b = a + 1; b < groups; ++b) {
            Subjects selected = select_groups(subjects, a, b);
            pairs[pair_count++] = (Pair){a, b, two_group(&selected, a, b, total), 0};
            free(selected.data);
        }
    int order[15];
    for (int i = 0; i < pair_count; ++i) {
        int j = i;
        while (j > 0 && pairs[i].result.test.p < pairs[order[j - 1]].result.test.p) {
            order[j] = order[j - 1];
            --j;
        }
        order[j] = i;
    }
    double adjusted = 0;
    for (int r = 0; r < pair_count; ++r) {
        double value = (pair_count - r) * pairs[order[r]].result.test.p;
        if (value > 1)
            value = 1;
        if (value > adjusted)
            adjusted = value;
        pairs[order[r]].adjusted = adjusted;
    }
    line_push(&part, text("pairwise logrank adjust holm"));
    for (int i = 0; i < pair_count; ++i) {
        const Pair *pair = &pairs[i];
        line_push(&part,
                  format("  %s %s chisq %s p %s p_holm %s hr %s lower %s upper %s", p->groups.data[pair->a],
                         p->groups.data[pair->b], real(pair->result.test.statistic),
                         real(pair->result.test.p), real(pair->adjusted), real(pair->result.hr),
                         real(pair->result.lower), real(pair->result.upper)));
    }
    paragraph(&out, &part);
    line_push(&part, format("subgroups reference %s", p->groups.data[0]));
    for (int variable_index = 0; variable_index < p->subgroups.count; ++variable_index) {
        const char *variable = p->subgroups.data[variable_index];
        IntList values = levels(subjects, variable);
        for (int b = 1; b < groups; ++b) {
            double weights_[4], logarithms[4], numerator = 0, denominator = 0;
            for (int i = 0; i < values.count; ++i) {
                Subjects level_subjects = select_level(subjects, variable, values.data[i]),
                         selected = select_groups(&level_subjects, 0, b);
                TwoGroup comparison = two_group(&selected, 0, b, total);
                int events = 0;
                for (int j = 0; j < selected.count; ++j)
                    events += selected.data[j].event;
                line_push(&part, format("  %s %s %s subjects %d events %d hr %s lower %s upper %s p %s",
                                        variable, level_name(values.data[i], variable), p->groups.data[b],
                                        selected.count, events, real(comparison.hr), real(comparison.lower),
                                        real(comparison.upper), real(comparison.test.p)));
                weights_[i] = 1 / comparison.phi;
                logarithms[i] = log(comparison.hr);
                numerator += weights_[i] * logarithms[i];
                denominator += weights_[i];
                free(level_subjects.data);
                free(selected.data);
            }
            double mean = numerator / denominator, heterogeneity = 0;
            for (int i = 0; i < values.count; ++i)
                heterogeneity += weights_[i] * (logarithms[i] - mean) * (logarithms[i] - mean);
            line_push(&part, format("  %s %s heterogeneity %s", variable, p->groups.data[b],
                                    test_values(heterogeneity, values.count - 1)));
        }
        free(values.data);
    }
    paragraph(&out, &part);
    line_push(&part, format("rmst_difference tau %d reference %s", p->tau, p->groups.data[0]));
    for (int g = 1; g < groups; ++g) {
        double difference = collections[g].rmst - collections[0].rmst,
               se = sqrt(collections[g].rmst_se * collections[g].rmst_se +
                         collections[0].rmst_se * collections[0].rmst_se),
               statistic = difference / se;
        line_push(&part, format("  %s difference %s se %s lower %s upper %s z %s p %s", p->groups.data[g],
                                real(difference), real(se), real(difference - NORMAL_Z * se),
                                real(difference + NORMAL_Z * se), real(statistic),
                                real(p_value(statistic * statistic, 1))));
    }
    paragraph(&out, &part);
    line_push(&part, format("rate_ratio reference %s", p->groups.data[0]));
    for (int g = 1; g < groups; ++g) {
        double ratio = collections[g].rate / collections[0].rate,
               se = sqrt(1.0 / collections[g].events + 1.0 / collections[0].events), logarithm = log(ratio),
               statistic = logarithm / se;
        line_push(&part, format("  %s ratio %s lower %s upper %s z %s p %s", p->groups.data[g], real(ratio),
                                real(exp(logarithm - NORMAL_Z * se)), real(exp(logarithm + NORMAL_Z * se)),
                                real(statistic), real(p_value(statistic * statistic, 1))));
    }
    paragraph(&out, &part);
    line_push(&part, format("survival_difference reference %s", p->groups.data[0]));
    for (int i = 0; i < p->report_times.count; ++i) {
        int time = p->report_times.data[i];
        for (int g = 1; g < groups; ++g) {
            KMRow first_ = row_at(&collections[0].km, time), second = row_at(&collections[g].km, time);
            double difference = second.survival - first_.survival,
                   se = sqrt(second.std_err * second.std_err + first_.std_err * first_.std_err),
                   statistic = difference / se;
            line_push(&part, format("  at %d %s difference %s se %s lower %s upper %s z %s p %s", time,
                                    p->groups.data[g], real(difference), real(se),
                                    real(difference - NORMAL_Z * se), real(difference + NORMAL_Z * se),
                                    real(statistic), real(p_value(statistic * statistic, 1))));
        }
    }
    paragraph(&out, &part);
    return out;
}
static char *coefficient(const char *prefix, double value, double se) {
    double statistic = value / se;
    return format("%s coef %s se %s z %s p %s hr %s lower %s upper %s", prefix, real(value), real(se),
                  real(statistic), real(p_value(statistic * statistic, 1)), real(exp(value)),
                  real(exp(value - NORMAL_Z * se)), real(exp(value + NORMAL_Z * se)));
}
static double cumulative(const CoxTime *times, const double *baseline, int count, int time) {
    double value = 0;
    for (int i = 0; i < count; ++i) {
        if (times[i].time > time)
            break;
        value = baseline[i];
    }
    return value;
}
static Lines cox_report(const Dataset *data) {
    const Subjects *subjects = &data->subjects;
    const Params *p = &data->params;
    int size = p->covariates.count, count = subjects->count;
    Vector design[400] = {{0}};
    bool group_term[6] = {0};
    for (int c = 0; c < size; ++c) {
        const char *name = p->covariates.data[c];
        group_term[c] = strcmp(name, "age") && strcmp(name, "male") && strcmp(name, "stage");
        int group = 0;
        if (group_term[c])
            while (strcmp(p->groups.data[group], name))
                ++group;
        for (int j = 0; j < count; ++j)
            design[j].v[c] = !strcmp(name, "age")               ? subjects->data[j].age
                             : !strcmp(name, "male")            ? (subjects->data[j].sex == 'M' ? 1 : 0)
                             : !strcmp(name, "stage")           ? subjects->data[j].stage
                             : subjects->data[j].group == group ? 1
                                                                : 0;
    }
    CoxFit *fit = cox_fit(subjects, design, size);
    Matrix covariance = inverse(fit->final.information, size);
    int events = 0;
    for (int j = 0; j < count; ++j)
        events += subjects->data[j].event;
    char *header = text("cox covariates");
    for (int c = 0; c < size; ++c) {
        char *next = format("%s %s", header, p->covariates.data[c]);
        free(header);
        header = next;
    }
    Lines out = {0};
    line_push(&out, format("%s subjects %d events %d event_times %d", header, count, events,
                           fit->final.time_count));
    free(header);
    for (int i = 0; i < 25; ++i) {
        char *line = format("iter %d loglik %s beta", i + 1, real(fit->iterations[i].loglik));
        for (int c = 0; c < size; ++c) {
            char *next = format("%s %s", line, real(fit->iterations[i].beta.v[c]));
            free(line);
            line = next;
        }
        line_push(&out, line);
    }
    line_push(&out,
              format("final loglik %s null_loglik %s", real(fit->final.loglik), real(fit->initial.loglik)));
    for (int c = 0; c < size; ++c)
        line_push(&out, coefficient(format("term %s", p->covariates.data[c]), fit->beta.v[c],
                                    sqrt(covariance.v[c][c])));
    for (int a = 0; a < size; ++a)
        if (group_term[a])
            for (int b = a + 1; b < size; ++b)
                if (group_term[b])
                    line_push(
                        &out,
                        coefficient(format("contrast %s vs %s", p->covariates.data[b], p->covariates.data[a]),
                                    fit->beta.v[b] - fit->beta.v[a],
                                    sqrt(covariance.v[b][b] + covariance.v[a][a] - 2 * covariance.v[a][b])));
    double likelihood = 2 * (fit->final.loglik - fit->initial.loglik), wald = 0;
    for (int c = 0; c < size; ++c) {
        double sum = 0;
        for (int d = 0; d < size; ++d)
            sum += fit->final.information.v[c][d] * fit->beta.v[d];
        wald += fit->beta.v[c] * sum;
    }
    Vector score_solution = solve(fit->initial.information, fit->initial.score, size);
    double score = 0;
    for (int c = 0; c < size; ++c)
        score += fit->initial.score.v[c] * score_solution.v[c];
    line_push(&out, format("likelihood_ratio %s", test_values(likelihood, size)));
    line_push(&out, format("wald %s", test_values(wald, size)));
    line_push(&out, format("score %s", test_values(score, size)));
    for (int c = 0; c < size; ++c) {
        double loglik = fit->initial.loglik;
        if (size >= 2) {
            Vector reduced[400] = {{0}};
            for (int j = 0; j < count; ++j) {
                int column = 0;
                for (int d = 0; d < size; ++d)
                    if (c != d)
                        reduced[j].v[column++] = design[j].v[d];
            }
            CoxFit *smaller = cox_fit(subjects, reduced, size - 1);
            loglik = smaller->final.loglik;
            free(smaller);
        }
        double statistic = 2 * (fit->final.loglik - loglik);
        line_push(&out, format("drop %s loglik %s chisq %s df 1 p %s", p->covariates.data[c], real(loglik),
                               real(statistic), real(p_value(statistic, 1))));
    }
    int comparable = 0, concordant = 0, tied = 0;
    for (int i = 0; i < count; ++i)
        if (subjects->data[i].event)
            for (int j = 0; j < count; ++j)
                if (i != j &&
                    (subjects->data[i].time < subjects->data[j].time ||
                     (subjects->data[i].time == subjects->data[j].time && !subjects->data[j].event))) {
                    ++comparable;
                    bool equal = true;
                    for (int c = 0; c < size; ++c)
                        if (design[i].v[c] != design[j].v[c])
                            equal = false;
                    if (equal)
                        ++tied;
                    else if (fit->final.theta[i] > fit->final.theta[j])
                        ++concordant;
                }
    line_push(&out,
              format("concordance %s comparable %d concordant %d tied %d",
                     real((double)(2 * concordant + tied) / (2 * comparable)), comparable, concordant, tied));
    CoxTime times[400];
    for (int i = 0; i < fit->final.time_count; ++i)
        times[i] = fit->final.times[fit->final.time_count - 1 - i];
    int event_order[400], event_count_ = 0, time_sum = 0;
    for (int i = 0; i < count; ++i)
        if (subjects->data[i].event) {
            int position = event_count_;
            while (position > 0 &&
                   (subjects->data[i].time < subjects->data[event_order[position - 1]].time ||
                    (subjects->data[i].time == subjects->data[event_order[position - 1]].time &&
                     subjects->data[i].id < subjects->data[event_order[position - 1]].id))) {
                event_order[position] = event_order[position - 1];
                --position;
            }
            event_order[position] = i;
            ++event_count_;
            time_sum += subjects->data[i].time;
        }
    double time_mean = (double)time_sum / event_count_;
    for (int c = 0; c < size; ++c) {
        double residuals[400], sum = 0;
        for (int j = 0; j < event_count_; ++j) {
            int i = event_order[j], at = 0;
            while (times[at].time != subjects->data[i].time)
                ++at;
            double value = design[i].v[c] - times[at].s1.v[c] / times[at].s0;
            residuals[j] = value;
            sum += value;
        }
        double mean = sum / event_count_, sxy = 0, sxx = 0, syy = 0;
        for (int j = 0; j < event_count_; ++j) {
            double x = residuals[j] - mean, y = subjects->data[event_order[j]].time - time_mean;
            sxy += x * y;
            sxx += x * x;
            syy += y * y;
        }
        double rho = sxy / sqrt(sxx * syy),
               statistic = 0.5 * log((1 + rho) / (1 - rho)) * sqrt((double)(event_count_ - 3));
        line_push(&out, format("ph_check %s rho %s z %s p %s", p->covariates.data[c], real(rho),
                               real(statistic), real(p_value(statistic * statistic, 1))));
    }
    double baseline[400], hazard = 0;
    for (int i = 0; i < fit->final.time_count; ++i) {
        hazard += times[i].events / times[i].s0;
        baseline[i] = hazard;
    }
    typedef struct {
        int subject;
        double martingale, deviance;
    } Residual;
    Residual residuals[400];
    int residual_count = 0;
    for (int j = 0; j < count; ++j) {
        double martingale = subjects->data[j].event -
                            cumulative(times, baseline, fit->final.time_count, subjects->data[j].time) *
                                exp(fit->final.theta[j]);
        double deviance =
            subjects->data[j].event ? sqrt(-2 * (martingale + log(1 - martingale))) : sqrt(-2 * martingale);
        if (!(martingale > 0))
            deviance = -deviance;
        int position = residual_count;
        while (position > 0 &&
               (fabs(deviance) > fabs(residuals[position - 1].deviance) ||
                (fabs(deviance) == fabs(residuals[position - 1].deviance) &&
                 subjects->data[j].id < subjects->data[residuals[position - 1].subject].id))) {
            residuals[position] = residuals[position - 1];
            --position;
        }
        residuals[position] = (Residual){j, martingale, deviance};
        ++residual_count;
    }
    line_push(&out, format("residuals top %d", p->residuals));
    for (int i = 0; i < p->residuals; ++i) {
        const Residual *residual = &residuals[i];
        const Subject *subject = &subjects->data[residual->subject];
        line_push(&out, format("  id %d group %s time %d event %d martingale %s deviance %s", subject->id,
                               p->groups.data[subject->group], subject->time, subject->event,
                               real(residual->martingale), real(residual->deviance)));
    }
    Vector means = {0};
    char *mean_line = text("adjusted_survival mean");
    bool any = false;
    for (int c = 0; c < size; ++c)
        if (!group_term[c]) {
            int sum = 0;
            for (int j = 0; j < count; ++j)
                sum += (int)design[j].v[c];
            means.v[c] = (double)sum / count;
            char *next = format("%s %s %s", mean_line, p->covariates.data[c], real(means.v[c]));
            free(mean_line);
            mean_line = next;
            any = true;
        }
    if (!any) {
        char *next = format("%s none", mean_line);
        free(mean_line);
        mean_line = next;
    }
    line_push(&out, mean_line);
    double group_risks[6];
    for (int group = 0; group < p->groups.count; ++group) {
        double predictor = 0;
        for (int c = 0; c < size; ++c) {
            double value =
                group_term[c] ? (!strcmp(p->covariates.data[c], p->groups.data[group]) ? 1 : 0) : means.v[c];
            predictor += fit->beta.v[c] * value;
        }
        group_risks[group] = exp(predictor);
    }
    for (int i = 0; i < p->report_times.count; ++i) {
        int time = p->report_times.data[i];
        char *line = format("  at %d", time);
        for (int group = 0; group < p->groups.count; ++group) {
            char *next = format(
                "%s %s %s", line, p->groups.data[group],
                real(exp(-cumulative(times, baseline, fit->final.time_count, time) * group_risks[group])));
            free(line);
            line = next;
        }
        line_push(&out, line);
    }
    char *median_line = text("  median");
    for (int group = 0; group < p->groups.count; ++group) {
        int median = -1;
        for (int i = 0; i < fit->final.time_count; ++i)
            if (exp(-baseline[i] * group_risks[group]) <= 0.5) {
                median = times[i].time;
                break;
            }
        char *next = format("%s %s %s", median_line, p->groups.data[group], optional(median));
        free(median_line);
        median_line = next;
    }
    line_push(&out, median_line);
    free(fit);
    return out;
}
int main(void) {
    mkdir("output", 0777);
    Dataset *data = read_dataset();
    int groups = data->params.groups.count;
    Collection collections[7];
    for (int group = 0; group < groups; ++group) {
        Subjects subjects = {0};
        for (int i = 0; i < data->subjects.count; ++i)
            if (data->subjects.data[i].group == group)
                subject_push(&subjects, data->subjects.data[i]);
        collections[group] = collection(data->params.groups.data[group], subjects, &data->params);
    }
    Subjects all = {0};
    for (int i = 0; i < data->subjects.count; ++i)
        subject_push(&all, data->subjects.data[i]);
    collections[groups] = collection("all", all, &data->params);
    write_owned("km_tables.txt", km_tables(collections, groups + 1, &data->params));
    Lines life = {0};
    line_push(&life, text("group,interval,at_risk,events,withdrawn,exposed,q,survival,std_err,hazard"));
    for (int c = 0; c <= groups; ++c) {
        const Collection *item = &collections[c];
        for (int i = 0; i < item->life.count; ++i) {
            const LifeRow *row = &item->life.data[i];
            line_push(&life,
                      format("%s,%d-%d,%d,%d,%d,%.1f,%s,%s,%s,%s", item->name, row->a, row->b, row->risk,
                             row->events, row->withdrawn, (double)row->exposure2 / 2, real(row->probability),
                             real(row->survival), real(row->std_err), real(row->hazard)));
        }
    }
    write_owned("life_table.csv", life);
    write_owned("tests.txt", group_report(data, collections));
    write_owned("cox.txt", cox_report(data));
    KMRows curves[6];
    int maximums[6];
    for (int group = 0; group < groups; ++group) {
        curves[group] = collections[group].km;
        maximums[group] = collections[group].maximum;
    }
    Lines plot = curve_plot(curves, maximums, &data->params);
    char *line = text("at_risk");
    for (int i = 0; i <= data->params.plot_divisions; ++i) {
        char *next = format("%s %d", line, i * (data->params.plot_time / data->params.plot_divisions));
        free(line);
        line = next;
    }
    line_push(&plot, line);
    for (int group = 0; group < groups; ++group) {
        line = text(data->params.groups.data[group]);
        for (int i = 0; i <= data->params.plot_divisions; ++i) {
            char *next = format("%s %d", line,
                                risk_size(&collections[group].subjects,
                                          i * (data->params.plot_time / data->params.plot_divisions)));
            free(line);
            line = next;
        }
        line_push(&plot, line);
    }
    write_owned("km_plot.txt", plot);
    for (int c = 0; c <= groups; ++c) {
        free(collections[c].subjects.data);
        free(collections[c].km.data);
        free(collections[c].life.data);
    }
    free(data->subjects.data);
    lines_free(&data->params.groups);
    lines_free(&data->params.subgroups);
    lines_free(&data->params.covariates);
    free(data->params.report_times.data);
    free(data->params.strata);
    free(data);
    return 0;
}
