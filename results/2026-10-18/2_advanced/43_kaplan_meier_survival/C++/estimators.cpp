#include "survival.hpp"
int risk_size(const Subjects &subjects, int time) {
    int count = 0;
    for (const Subject &subject : subjects)
        count += subject.time >= time;
    return count;
}
int event_count(const Subjects &subjects, int time) {
    int count = 0;
    for (const Subject &subject : subjects)
        count += subject.time == time && subject.event == 1;
    return count;
}
std::vector<int> event_times(const Subjects &subjects) {
    std::set<int> times;
    for (const Subject &subject : subjects)
        if (subject.event)
            times.insert(subject.time);
    return {times.begin(), times.end()};
}
std::vector<KMRow> kaplan_meier(const Subjects &subjects) {
    const auto times = event_times(subjects);
    std::vector<KMRow> out;
    double survival = 1, greenwood = 0, hazard = 0, variance = 0;
    bool defined = true;
    for (std::size_t i = 0; i < times.size(); ++i) {
        KMRow row;
        row.time = times[i];
        row.risk = risk_size(subjects, row.time);
        row.events = event_count(subjects, row.time);
        for (const Subject &subject : subjects)
            if (!subject.event && subject.time >= row.time &&
                (i + 1 == times.size() || subject.time < times[i + 1]))
                ++row.censored;
        survival = survival * (double(row.risk - row.events) / row.risk);
        row.survival = survival;
        if (row.risk == row.events)
            defined = false;
        if (defined) {
            greenwood += double(row.events) / (row.risk * (row.risk - row.events));
            row.std_err = survival * std::sqrt(greenwood);
            const double logarithm = std::log(survival),
                         omega = normal_z * std::sqrt(greenwood) / (-logarithm);
            row.lower = std::exp(logarithm * std::exp(omega));
            row.upper = std::exp(logarithm * std::exp(-omega));
            row.interval_defined = true;
        } else
            row.error_defined = false;
        hazard += double(row.events) / row.risk;
        variance += double(row.events) / (row.risk * row.risk);
        row.hazard = hazard;
        row.hazard_se = std::sqrt(variance);
        out.push_back(row);
    }
    return out;
}
KMRow row_at(const std::vector<KMRow> &rows, int time) {
    KMRow out;
    for (const KMRow &row : rows) {
        if (row.time > time)
            break;
        out = row;
    }
    return out;
}
std::vector<LifeRow> life_table(const Subjects &subjects, int width, int intervals) {
    std::vector<LifeRow> out;
    double survival = 1, greenwood = 0;
    for (int i = 0; i < intervals; ++i) {
        LifeRow row{};
        row.a = i * width;
        row.b = (i + 1) * width;
        row.risk = risk_size(subjects, row.a);
        for (const Subject &subject : subjects)
            if (subject.time >= row.a && subject.time < row.b) {
                if (subject.event)
                    ++row.events;
                else
                    ++row.withdrawn;
            }
        row.exposure2 = 2 * row.risk - row.withdrawn;
        const int f = row.exposure2, d = row.events;
        row.probability = double(2 * d) / f;
        survival = survival * (double(f - 2 * d) / f);
        row.survival = survival;
        greenwood += double(4 * d) / (f * (f - 2 * d));
        row.std_err = survival * std::sqrt(greenwood);
        row.hazard = double(2000 * d) / (width * (f - d));
        out.push_back(row);
    }
    return out;
}
