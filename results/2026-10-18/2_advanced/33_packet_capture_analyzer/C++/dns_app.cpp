#include "capture.hpp"
std::string type_name(Integer type) {
    const std::map<Integer, std::string> names = {{1, "A"},    {2, "NS"},  {5, "CNAME"}, {6, "SOA"},
                                                  {12, "PTR"}, {15, "MX"}, {16, "TXT"},  {28, "AAAA"}};
    const auto found = names.find(type);
    return found == names.end() ? "TYPE" + decimal(type) : found->second;
}
std::string rcode_name(Integer code) {
    const std::array<std::string, 6> names = {"NoError",  "FormErr", "ServFail",
                                              "NXDomain", "NotImp",  "Refused"};
    return code < 6 ? names[code] : "RCODE" + decimal(code);
}
struct DnsReader {
    const Bytes &bytes;
    void need(std::size_t position, std::size_t count) const {
        if (position > bytes.size() || count > bytes.size() - position)
            throw std::string("dns: truncated");
    }
    Integer integer(std::size_t &position, std::size_t count) const {
        need(position, count);
        const Integer value = read_integer(bytes, position, count);
        position += count;
        return value;
    }
    std::string name(std::size_t &position) const {
        std::size_t cursor = position;
        std::optional<std::size_t> end;
        int pointers = 0;
        std::vector<std::string> labels;
        while (true) {
            need(cursor, 1);
            const int count = bytes[cursor];
            if (count == 0) {
                if (!end)
                    end = cursor + 1;
                break;
            }
            if (count >= 192) {
                need(cursor + 1, 1);
                if (!end)
                    end = cursor + 2;
                if (++pointers > 16)
                    throw std::string("dns: compression loop");
                const std::size_t target = (count - 192) * 256 + bytes[cursor + 1];
                if (target >= bytes.size())
                    throw std::string("dns: pointer out of range");
                cursor = target;
                continue;
            }
            if (count >= 64)
                throw std::string("dns: bad label type");
            need(cursor + 1, count);
            std::string label;
            for (int j = 0; j < count; ++j) {
                const int c = bytes[cursor + 1 + j];
                if (c >= 33 && c <= 126 && c != 46 && c != 92)
                    label += char(c);
                else {
                    std::ostringstream out;
                    out << '\\' << std::setw(3) << std::setfill('0') << c;
                    label += out.str();
                }
            }
            labels.push_back(label);
            cursor += count + 1;
        }
        position = *end;
        return labels.empty() ? "<root>" : join(labels, ".");
    }
    std::string ipv6(std::size_t &position) const {
        std::vector<std::string> groups;
        std::array<Integer, 8> values{};
        for (Integer &value : values) {
            value = integer(position, 2);
            groups.push_back(hex(value));
        }
        int start = -1, length = 1;
        for (int i = 0; i < 8;) {
            if (values[i]) {
                ++i;
                continue;
            }
            int end = i;
            while (end < 8 && values[end] == 0)
                ++end;
            if (end - i > length) {
                start = i;
                length = end - i;
            }
            i = end;
        }
        if (start < 0)
            return join(groups, ":");
        return join(std::vector<std::string>(groups.begin(), groups.begin() + start), ":") +
               "::" + join(std::vector<std::string>(groups.begin() + start + length, groups.end()), ":");
    }
};
void dns(Packet &p, const Bytes &data) {
    const DnsReader reader{data};
    reader.need(0, 12);
    std::size_t position = 0;
    p.n("dns.id", reader.integer(position, 2));
    const Integer flags = reader.integer(position, 2);
    p.n("dns.flags", flags);
    p.n("dns.flags.response", (flags >> 15) & 1);
    p.n("dns.flags.opcode", (flags >> 11) & 15);
    p.n("dns.flags.rcode", flags & 15);
    const std::array<std::string, 4> count_names = {"queries", "answers", "auth_rr", "add_rr"};
    std::array<Integer, 4> counts{};
    for (int i = 0; i < 4; ++i) {
        counts[i] = reader.integer(position, 2);
        p.n("dns.count." + count_names[i], counts[i]);
    }
    for (Integer q = 0; q < counts[0]; ++q) {
        const std::string name = reader.name(position);
        reader.need(position, 4);
        const Integer type = reader.integer(position, 2);
        position += 2;
        p.s("dns.qry.name", name, true);
        p.n("dns.qry.type", type, true);
    }
    const std::array<std::string, 3> sections = {"dns.answer", "dns.authority", "dns.additional"};
    for (int section = 0; section < 3; ++section)
        for (Integer record = 0; record < counts[section + 1]; ++record) {
            const std::string name = reader.name(position);
            reader.need(position, 10);
            const Integer type = reader.integer(position, 2), klass = reader.integer(position, 2),
                          ttl = reader.integer(position, 4), length = reader.integer(position, 2);
            reader.need(position, length);
            const std::size_t end = position + length;
            std::string body;
            std::optional<Integer> address;
            if (type == 1) {
                address = reader.integer(position, 4);
                body = ipv4(*address);
            } else if (type == 28)
                body = reader.ipv6(position);
            else if (type == 2 || type == 5 || type == 12)
                body = reader.name(position);
            else if (type == 15) {
                const Integer preference = reader.integer(position, 2);
                body = decimal(preference) + " " + reader.name(position);
            } else if (type == 6) {
                body = reader.name(position);
                body += " " + reader.name(position);
                for (int i = 0; i < 5; ++i)
                    body += " " + decimal(reader.integer(position, 4));
            } else {
                body = decimal(length) + " bytes";
                position = end;
            }
            if (position != end)
                throw std::string("dns: bad rdata length");
            p.s(sections[section],
                name + " " + type_name(type) + " " + (klass == 1 ? "IN" : "CLASS" + decimal(klass)) + " " +
                    decimal(ttl) + " " + body,
                true);
            if (section == 0) {
                p.dns_answers.emplace_back(type, body);
                if (address)
                    p.n("dns.a", *address, true);
            }
        }
}
