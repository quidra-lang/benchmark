#include "synthesizer.hpp"
std::string decimal(Integer value) {
    return std::to_string(value);
}
std::string hexadecimal(Integer value, int width) {
    std::ostringstream out;
    out << std::uppercase << std::hex << std::setw(width) << std::setfill('0') << value;
    return out.str();
}
std::string join(const Lines &values, const std::string &delimiter) {
    std::string out;
    for (std::size_t i = 0; i < values.size(); ++i) {
        if (i)
            out += delimiter;
        out += values[i];
    }
    return out;
}
std::string aligned(Integer value, int width) {
    std::ostringstream out;
    out << std::setw(width) << value;
    return out.str();
}
Lines read_lines(const std::string &path) {
    std::ifstream in(path);
    Lines out;
    std::string line;
    while (std::getline(in, line))
        out.push_back(line);
    return out;
}
void write_lines(const std::string &name, const Lines &lines) {
    std::ofstream out("output/" + name, std::ios::binary);
    for (const std::string &line : lines)
        out << line << '\n';
}
Integer adler32(const std::vector<int> &samples) {
    Integer a = 1, b = 0;
    for (int value : samples) {
        a = (a + value) % 65521;
        b = (b + a) % 65521;
    }
    return b * 65536 + a;
}
Integer integer_sqrt(Integer value) {
    Integer lo = 0, hi = value + 1;
    while (lo + 1 < hi) {
        const Integer middle = (lo + hi) / 2;
        if (middle <= value / middle)
            lo = middle;
        else
            hi = middle;
    }
    return lo;
}
SampleStats sample_stats(const std::vector<int> &samples) {
    SampleStats out;
    out.minimum = out.maximum = samples[0];
    Integer squares = 0;
    for (std::size_t i = 0; i < samples.size(); ++i) {
        const Integer centered = samples[i] - 128;
        out.peak = std::max(out.peak, centered < 0 ? -centered : centered);
        out.minimum = std::min(out.minimum, samples[i]);
        out.maximum = std::max(out.maximum, samples[i]);
        squares += centered * centered;
        if (i && ((samples[i - 1] < 128) != (samples[i] < 128)))
            ++out.crossings;
    }
    out.rms = integer_sqrt(squares / Integer(samples.size()));
    return out;
}
Lines sample_dump(const std::vector<int> &samples) {
    Lines out;
    for (std::size_t start = 0; start < samples.size(); start += 32) {
        std::string line;
        for (std::size_t i = start; i < std::min(start + 32, samples.size()); ++i)
            line += hexadecimal(samples[i]);
        out.push_back(line);
    }
    return out;
}
