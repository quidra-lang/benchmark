#include "coherence.hpp"
Lines split(const std::string &source) {
    Lines out;
    std::size_t start = 0;
    for (;;) {
        std::size_t end = source.find(' ', start);
        out.push_back(source.substr(start, end == std::string::npos ? end : end - start));
        if (end == std::string::npos)
            return out;
        start = end + 1;
    }
}
Lines read_lines(const std::string &path) {
    std::ifstream file(path);
    Lines out;
    std::string source;
    while (std::getline(file, source))
        out.push_back(source);
    return out;
}
std::string join(const Lines &values, const std::string &separator) {
    std::string out;
    for (std::size_t i = 0; i < values.size(); ++i) {
        if (i)
            out += separator;
        out += values[i];
    }
    return out;
}
void extend(Lines &out, const Lines &other) { out.insert(out.end(), other.begin(), other.end()); }
bool decimal_integer(const std::string &s, std::size_t maximum) {
    return !s.empty() && s.size() <= maximum && (s.size() == 1 || s[0] != '0') &&
           std::all_of(s.begin(), s.end(), [](char c) { return c >= '0' && c <= '9'; });
}
bool valid_hex_address(const std::string &s) {
    return s.size() == 8 && std::all_of(s.begin(), s.end(), [](char c) {
               return (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f');
           });
}
Number hex_value(const std::string &s) { return std::stoll(s, nullptr, 16); }
std::string hex_address(Number value) {
    std::ostringstream out;
    out << std::hex << std::setw(8) << std::setfill('0') << value;
    return out.str();
}
Config read_config() {
    Config c{};
    for (const std::string &source : read_lines("input/config.txt")) {
        Lines f = split(source);
        const std::string &kind = f[0];
        if (kind == "CORES")
            c.cores = std::stoi(f[1]);
        else if (kind == "LINE")
            c.line_size = std::stoi(f[1]);
        else if (kind == "L1") {
            c.l1_size = std::stoi(f[1]);
            c.l1_ways = std::stoi(f[2]);
        } else if (kind == "L2") {
            c.l2_size = std::stoi(f[1]);
            c.l2_ways = std::stoi(f[2]);
        } else if (kind == "LATENCY") {
            c.t1 = std::stoll(f[1]);
            c.t2 = std::stoll(f[2]);
            c.tm = std::stoll(f[3]);
            c.tb = std::stoll(f[4]);
        } else if (kind == "SCENARIO")
            c.scenarios.push_back({f[1], f[2], f[3], f[4], int(c.scenarios.size())});
        else if (kind == "PRIMARY")
            c.primary = f[1];
        else if (kind == "INTERVAL")
            c.interval = std::stoll(f[1]);
        else if (kind == "TOP")
            c.top = std::stoi(f[1]);
        else if (kind == "REGION")
            c.regions.push_back({f[1], hex_value(f[2]), hex_value(f[3])});
        else if (kind == "WATCH")
            c.watch.push_back(hex_value(f[1]) / c.line_size);
    }
    c.l1_sets = c.l1_size / (c.line_size * c.l1_ways);
    c.l2_sets = c.l2_size / (c.line_size * c.l2_ways);
    c.cap = c.l1_sets * c.l1_ways;
    return c;
}
void write_lines(const std::string &filename, const Lines &lines) {
    std::filesystem::create_directories("output");
    std::ofstream file("output/" + filename);
    for (const std::string &source : lines)
        file << source << '\n';
}
