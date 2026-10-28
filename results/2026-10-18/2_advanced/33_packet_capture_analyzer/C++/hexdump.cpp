#include "capture.hpp"
std::vector<Packet> read_capture() {
    std::vector<Packet> packets;
    const auto lines = read_lines("input/capture.txt");
    const std::regex pattern("[0-9a-f]{4}  [0-9a-f]{2}( [0-9a-f]{2}){0,15}");
    auto finish = [&]() {
        if (packets.empty())
            return;
        Packet &p = packets.back();
        if (p.reason.empty() && Integer(p.raw.size()) != p.length)
            p.reason = "dump: length mismatch (header " + decimal(p.length) + ", data " +
                       decimal(p.raw.size()) + ")";
    };
    for (std::size_t line = 0; line < lines.size(); ++line) {
        const std::string &text = lines[line];
        if (text.rfind("PACKET ", 0) == 0) {
            finish();
            Packet p;
            std::string word;
            std::istringstream in(text);
            in >> word >> p.number >> p.time >> p.length;
            packets.push_back(std::move(p));
            continue;
        }
        if (text.empty() || !packets.back().reason.empty())
            continue;
        Packet &p = packets.back();
        if (!std::regex_match(text, pattern)) {
            p.reason = "dump: bad line " + decimal(line + 1);
            continue;
        }
        if (std::stoll(text.substr(0, 4), nullptr, 16) != Integer(p.raw.size())) {
            p.reason = "dump: offset mismatch at line " + decimal(line + 1);
            continue;
        }
        for (std::size_t i = 6; i < text.size(); i += 3)
            p.raw.push_back(static_cast<unsigned char>(std::stoll(text.substr(i, 2), nullptr, 16)));
    }
    finish();
    return packets;
}
std::vector<std::string> dump_lines(const Bytes &data) {
    std::vector<std::string> lines;
    for (std::size_t start = 0; start < data.size(); start += 16) {
        std::string bytes, chars;
        for (std::size_t i = start; i < std::min(start + 16, data.size()); ++i) {
            if (i != start)
                bytes += " ";
            bytes += hex(data[i], 2);
            chars += data[i] >= 32 && data[i] <= 126 ? char(data[i]) : '.';
        }
        bytes.resize(47, ' ');
        lines.push_back(hex(start, 4) + "  " + bytes + "  |" + chars + "|");
    }
    return lines;
}
