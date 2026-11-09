#include "coherence.hpp"
std::string fraction(Number p, Number q) {
    Number factor = std::gcd(p, q);
    return text(p / factor, "/", q / factor);
}
std::string decimal(Number p, Number q) {
    Number value = (2 * p * 100 + q) / (2 * q);
    std::ostringstream out;
    out << value / 100 << '.' << std::setw(2) << std::setfill('0') << value % 100;
    return out.str();
}
std::string core_string(unsigned cores) {
    std::string out;
    for (int core = 0; core < 8; ++core)
        if (cores & (1u << core))
            out += char('0' + core);
    return out.empty() ? "-" : out;
}
std::string range_counts(const Lines &names, const std::vector<Number> &counts) {
    Lines values;
    for (std::size_t i = 0; i < names.size(); ++i)
        values.push_back(text(names[i], ":", counts[i]));
    return join(values);
}
CoreStats total_counters(const std::vector<CoreStats> &cores) {
    CoreStats total;
    for (const CoreStats &s : cores) {
        total.accesses += s.accesses;
        total.reads += s.reads;
        total.writes += s.writes;
        total.hits += s.hits;
        total.misses += s.misses;
        total.fences += s.fences;
        total.latency += s.latency;
        total.fence_stall += s.fence_stall;
        total.read_latency += s.read_latency;
        total.write_latency += s.write_latency;
        total.finish = std::max(total.finish, s.finish);
        for (int i = 0; i < 6; ++i) {
            total.miss_counts[i] += s.miss_counts[i];
            total.service[i] += s.service[i];
        }
        for (int i = 0; i < 5; ++i)
            total.bus[i] += s.bus[i];
        for (int i = 0; i < 4; ++i)
            total.snoop[i] += s.snoop[i];
    }
    return total;
}
Lines six_lines(const std::string &label, const CoreStats &s) {
    Lines out;
    line(out, label, " accesses ", s.accesses, " reads ", s.reads, " writes ", s.writes, " hits ",
         s.hits, " misses ", s.misses, " fences ", s.fences);
    line(out, label, " misses compulsory ", s.miss_counts[0], " capacity ", s.miss_counts[1],
         " conflict ", s.miss_counts[2], " coherence ", s.miss_counts[3], " true_sharing ",
         s.miss_counts[4], " false_sharing ", s.miss_counts[5]);
    Lines values;
    for (int i = 0; i < 6; ++i)
        values.push_back(text(service_names[i], " ", s.service[i]));
    line(out, label, " service ", join(values));
    values.clear();
    for (int i = 0; i < 5; ++i)
        values.push_back(text(transaction_names[i], " ", s.bus[i]));
    line(out, label, " bus ", join(values));
    const Lines snoop_names{"invalidations_sent", "invalidations_received", "supplied",
                            "back_invalidations"};
    values.clear();
    for (int i = 0; i < 4; ++i)
        values.push_back(text(snoop_names[i], " ", s.snoop[i]));
    line(out, label, " snoop ", join(values));
    line(out, label, " time latency ", s.latency, " amat ", fraction(s.latency, s.accesses), " ",
         decimal(s.latency, s.accesses), " fence_stall ", s.fence_stall, " finish ", s.finish);
    return out;
}
