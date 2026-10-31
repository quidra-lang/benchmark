#include "capture.hpp"
void Packet::n(const std::string &name, Integer value, bool append) {
    if (!append)
        fields[name].clear();
    fields[name].push_back({value, {}});
}
void Packet::s(const std::string &name, const std::string &value, bool append) {
    if (!append)
        fields[name].clear();
    fields[name].push_back({0, value});
}
void Packet::flag(const std::string &name) {
    n(name, 0);
}
bool Packet::has(const std::string &name) const {
    const auto found = fields.find(name);
    return found != fields.end() && !found->second.empty();
}
Integer Packet::num(const std::string &name) const {
    return has(name) ? fields.at(name)[0].number : 0;
}
std::string Packet::str(const std::string &name) const {
    return has(name) ? fields.at(name)[0].text : "";
}
std::string decimal(Integer value) {
    return std::to_string(value);
}
std::string hex(Integer value, int width) {
    std::ostringstream out;
    out << std::hex << std::setfill('0') << std::setw(width) << value;
    return out.str();
}
std::string seconds(Integer value) {
    std::ostringstream out;
    out << value / 1000000 << '.' << std::setw(6) << std::setfill('0') << value % 1000000;
    return out.str();
}
std::string join(const std::vector<std::string> &values, const std::string &delimiter) {
    std::string out;
    for (std::size_t i = 0; i < values.size(); ++i) {
        if (i)
            out += delimiter;
        out += values[i];
    }
    return out;
}
std::vector<std::string> read_lines(const std::string &path) {
    std::ifstream in(path);
    std::vector<std::string> lines;
    std::string line;
    while (std::getline(in, line))
        lines.push_back(line);
    return lines;
}
enum class Type { integer, hex2, hex4, ipv4, mac, string, presence };
struct FieldSpec {
    std::string name;
    Type type;
};
const std::vector<FieldSpec> field_specs = {
    {"frame.number", Type::integer},
    {"frame.time", Type::integer},
    {"frame.len", Type::integer},
    {"frame.protocols", Type::string},
    {"frame.malformed", Type::string},
    {"frame.bad_checksum", Type::presence},
    {"eth.dst", Type::mac},
    {"eth.src", Type::mac},
    {"eth.type", Type::hex4},
    {"arp.opcode", Type::integer},
    {"arp.src.hw", Type::mac},
    {"arp.src.ip", Type::ipv4},
    {"arp.dst.hw", Type::mac},
    {"arp.dst.ip", Type::ipv4},
    {"ip.hdr_len", Type::integer},
    {"ip.tos", Type::hex2},
    {"ip.len", Type::integer},
    {"ip.id", Type::hex4},
    {"ip.flags.df", Type::integer},
    {"ip.flags.mf", Type::integer},
    {"ip.frag_offset", Type::integer},
    {"ip.ttl", Type::integer},
    {"ip.proto", Type::integer},
    {"ip.checksum", Type::hex4},
    {"ip.checksum.status", Type::string},
    {"ip.src", Type::ipv4},
    {"ip.dst", Type::ipv4},
    {"ip.fragment", Type::presence},
    {"icmp.type", Type::integer},
    {"icmp.code", Type::integer},
    {"icmp.checksum", Type::hex4},
    {"icmp.checksum.status", Type::string},
    {"icmp.id", Type::integer},
    {"icmp.seq", Type::integer},
    {"udp.srcport", Type::integer},
    {"udp.dstport", Type::integer},
    {"udp.length", Type::integer},
    {"udp.checksum", Type::hex4},
    {"udp.checksum.status", Type::string},
    {"tcp.srcport", Type::integer},
    {"tcp.dstport", Type::integer},
    {"tcp.stream", Type::integer},
    {"tcp.seq", Type::integer},
    {"tcp.seq_raw", Type::integer},
    {"tcp.ack", Type::integer},
    {"tcp.ack_raw", Type::integer},
    {"tcp.hdr_len", Type::integer},
    {"tcp.flags", Type::hex2},
    {"tcp.flags.fin", Type::integer},
    {"tcp.flags.syn", Type::integer},
    {"tcp.flags.rst", Type::integer},
    {"tcp.flags.psh", Type::integer},
    {"tcp.flags.ack", Type::integer},
    {"tcp.flags.urg", Type::integer},
    {"tcp.window", Type::integer},
    {"tcp.window.calc", Type::integer},
    {"tcp.checksum", Type::hex4},
    {"tcp.checksum.status", Type::string},
    {"tcp.urgent", Type::integer},
    {"tcp.option", Type::string},
    {"tcp.options.mss", Type::integer},
    {"tcp.options.wscale", Type::integer},
    {"tcp.options.malformed", Type::presence},
    {"tcp.len", Type::integer},
    {"tcp.analysis.retransmission", Type::presence},
    {"tcp.analysis.out_of_order", Type::presence},
    {"tcp.analysis.lost_segment", Type::presence},
    {"tcp.analysis.duplicate_ack", Type::presence},
    {"dns.id", Type::hex4},
    {"dns.flags", Type::hex4},
    {"dns.flags.response", Type::integer},
    {"dns.flags.opcode", Type::integer},
    {"dns.flags.rcode", Type::integer},
    {"dns.count.queries", Type::integer},
    {"dns.count.answers", Type::integer},
    {"dns.count.auth_rr", Type::integer},
    {"dns.count.add_rr", Type::integer},
    {"dns.qry.name", Type::string},
    {"dns.qry.type", Type::integer},
    {"dns.answer", Type::string},
    {"dns.authority", Type::string},
    {"dns.additional", Type::string},
    {"dns.a", Type::ipv4},
    {"data.len", Type::integer},
};
const std::map<std::string, std::pair<std::string, std::string>> aliases = {
    {"eth.addr", {"eth.dst", "eth.src"}},
    {"ip.addr", {"ip.src", "ip.dst"}},
    {"udp.port", {"udp.srcport", "udp.dstport"}},
    {"tcp.port", {"tcp.srcport", "tcp.dstport"}}};
const std::vector<std::string> protocols = {"eth", "arp", "ip", "icmp", "udp", "tcp", "dns", "data"};
static Type field_type(const std::string &name) {
    for (const FieldSpec &spec : field_specs)
        if (spec.name == name)
            return spec.type;
    const auto alias = aliases.find(name);
    if (alias != aliases.end())
        return field_type(alias->second.first);
    if (std::find(protocols.begin(), protocols.end(), name) != protocols.end())
        return Type::presence;
    throw "unknown field " + name;
}
static std::vector<Value> field_values(const Packet &p, const std::string &name) {
    if (std::find(protocols.begin(), protocols.end(), name) != protocols.end())
        return std::find(p.layers.begin(), p.layers.end(), name) != p.layers.end() ? std::vector<Value>{{}}
                                                                                   : std::vector<Value>{};
    const auto alias = aliases.find(name);
    if (alias != aliases.end()) {
        auto result = field_values(p, alias->second.first);
        const auto second = field_values(p, alias->second.second);
        result.insert(result.end(), second.begin(), second.end());
        return result;
    }
    const auto found = p.fields.find(name);
    return found == p.fields.end() ? std::vector<Value>{} : found->second;
}
static std::string notation(Type type, const Value &value) {
    switch (type) {
    case Type::hex2:
        return "0x" + hex(value.number, 2);
    case Type::hex4:
        return "0x" + hex(value.number, 4);
    case Type::ipv4:
        return ipv4(value.number);
    case Type::mac:
        return mac(value.number);
    case Type::string:
        return value.text;
    case Type::presence:
        return "";
    default:
        return decimal(value.number);
    }
}
static std::string notation(const Packet &p, const std::string &name) {
    return notation(field_type(name), p.fields.at(name)[0]);
}
struct Token {
    std::string kind, text;
    std::size_t column;
};
static bool word_character(char c) {
    return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '.' ||
           c == '_' || c == ':';
}
static std::vector<Token> tokenize(const std::string &text) {
    std::vector<Token> tokens;
    for (std::size_t i = 0; i < text.size();) {
        if (text[i] == ' ') {
            ++i;
            continue;
        }
        const std::size_t start = i;
        const std::string pair = text.substr(i, 2);
        if (pair == "==" || pair == "!=" || pair == "<=" || pair == ">=" || pair == "&&" || pair == "||") {
            tokens.push_back({pair, pair, i + 1});
            i += 2;
            continue;
        }
        if (std::string("()!<>").find(text[i]) != std::string::npos) {
            const std::string value(1, text[i++]);
            tokens.push_back({value, value, start + 1});
            continue;
        }
        if (text[i] == '"') {
            const auto end = text.find('"', i + 1);
            if (end == std::string::npos)
                throw "unterminated string at column " + decimal(i + 1);
            i = end + 1;
            tokens.push_back({"string", text.substr(start, i - start), start + 1});
            continue;
        }
        if (word_character(text[i])) {
            while (i < text.size() && word_character(text[i]))
                ++i;
            const std::string value = text.substr(start, i - start);
            tokens.push_back({value == "and"   ? "&&"
                              : value == "or"  ? "||"
                              : value == "not" ? "!"
                                               : "word",
                              value, start + 1});
            continue;
        }
        throw "invalid character '" + std::string(1, text[i]) + "' at column " + decimal(i + 1);
    }
    return tokens;
}
static bool digits(const std::string &text, int base) {
    if (text.empty())
        return false;
    for (char c : text)
        if (!((c >= '0' && c <= '9') || (base == 16 && ((c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F')))))
            return false;
    return true;
}
static std::vector<std::string> split(const std::string &text, char delimiter) {
    std::vector<std::string> parts;
    std::size_t first = 0;
    for (std::size_t i = 0; i <= text.size(); ++i)
        if (i == text.size() || text[i] == delimiter) {
            parts.push_back(text.substr(first, i - first));
            first = i + 1;
        }
    return parts;
}
static Value convert(Type type, const Token &token, const std::string &field) {
    if (type == Type::string && token.kind == "string")
        return {0, token.text.substr(1, token.text.size() - 2)};
    if (token.kind == "word") {
        const std::string &s = token.text;
        if (type == Type::integer || type == Type::hex2 || type == Type::hex4) {
            if (s.size() <= 15 && digits(s, 10))
                return {std::stoll(s), {}};
            if (s.size() >= 3 && s.size() <= 14 && s.substr(0, 2) == "0x" && digits(s.substr(2), 16))
                return {std::stoll(s.substr(2), nullptr, 16), {}};
        }
        if (type == Type::ipv4 || type == Type::mac) {
            const bool ip = type == Type::ipv4;
            const auto parts = split(s, ip ? '.' : ':');
            if (parts.size() == std::size_t(ip ? 4 : 6)) {
                Integer value = 0;
                bool valid = true;
                for (const std::string &part : parts) {
                    if (!(ip ? part.size() >= 1 && part.size() <= 3 && digits(part, 10)
                             : part.size() == 2 && digits(part, 16))) {
                        valid = false;
                        break;
                    }
                    const Integer byte = std::stoll(part, nullptr, ip ? 10 : 16);
                    if (byte > 255) {
                        valid = false;
                        break;
                    }
                    value = value * 256 + byte;
                }
                if (valid)
                    return {value, {}};
            }
        }
    }
    throw "invalid value " + token.text + " for " + field;
}
struct Expression {
    std::string kind, field, op;
    Type type = Type::integer;
    Value value;
    std::unique_ptr<Expression> left, right;
    bool evaluate(const Packet &p) const {
        if (kind == "or")
            return left->evaluate(p) || right->evaluate(p);
        if (kind == "and")
            return left->evaluate(p) && right->evaluate(p);
        if (kind == "not")
            return !left->evaluate(p);
        const auto values = field_values(p, field);
        if (op.empty())
            return !values.empty();
        if (values.empty())
            return false;
        for (const Value &v : values) {
            const int comparison = type == Type::string      ? v.text.compare(value.text)
                                   : v.number < value.number ? -1
                                   : v.number > value.number ? 1
                                                             : 0;
            if (op == "!=") {
                if (comparison == 0)
                    return false;
            } else if ((op == "==" && comparison == 0) || (op == "<" && comparison < 0) ||
                       (op == ">" && comparison > 0) || (op == "<=" && comparison <= 0) ||
                       (op == ">=" && comparison >= 0))
                return true;
        }
        return op == "!=";
    }
};
struct Parser {
    std::vector<Token> tokens;
    std::size_t position = 0;
    bool next(const std::string &kind) const {
        return position < tokens.size() && tokens[position].kind == kind;
    }
    Token take() {
        if (position == tokens.size())
            throw std::string("unexpected end of filter");
        return tokens[position++];
    }
    [[noreturn]] void unexpected(const Token &token) const {
        throw "unexpected '" + token.text + "' at column " + decimal(token.column);
    }
    std::unique_ptr<Expression> expression() {
        auto node = product();
        while (next("||")) {
            take();
            auto parent = std::make_unique<Expression>();
            parent->kind = "or";
            parent->left = std::move(node);
            parent->right = product();
            node = std::move(parent);
        }
        return node;
    }
    std::unique_ptr<Expression> product() {
        auto node = negation();
        while (next("&&")) {
            take();
            auto parent = std::make_unique<Expression>();
            parent->kind = "and";
            parent->left = std::move(node);
            parent->right = negation();
            node = std::move(parent);
        }
        return node;
    }
    std::unique_ptr<Expression> negation() {
        if (next("!")) {
            take();
            auto node = std::make_unique<Expression>();
            node->kind = "not";
            node->left = negation();
            return node;
        }
        const Token token = take();
        if (token.kind == "(") {
            auto node = expression();
            const Token close = take();
            if (close.kind != ")")
                unexpected(close);
            return node;
        }
        if (token.kind != "word")
            unexpected(token);
        auto node = std::make_unique<Expression>();
        node->kind = "test";
        node->field = token.text;
        node->type = field_type(token.text);
        if (!(next("==") || next("!=") || next("<") || next(">") || next("<=") || next(">=")))
            return node;
        node->op = take().text;
        if (node->type == Type::presence ||
            (node->type == Type::string && node->op != "==" && node->op != "!="))
            throw "operator " + node->op + " not allowed for " + node->field;
        const Token value = take();
        if (value.kind != "word" && value.kind != "string")
            unexpected(value);
        node->value = convert(node->type, value, node->field);
        return node;
    }
    std::unique_ptr<Expression> parse() {
        auto node = expression();
        if (position != tokens.size())
            unexpected(tokens[position]);
        return node;
    }
};
static void dissect(Packet &p) {
    if (!p.reason.empty())
        return;
    auto layer = [&](const std::string &name, auto function) -> std::optional<Bytes> {
        p.layers.push_back(name);
        Packet trial = p;
        try {
            Bytes data = function(trial);
            p = std::move(trial);
            return data;
        } catch (const std::string &error) {
            p.reason = error;
            return std::nullopt;
        }
    };
    auto payload = layer("eth", [&](Packet &trial) { return ethernet(trial, p.raw); });
    if (!payload)
        return;
    Bytes remaining;
    if (p.num("eth.type") == 2054) {
        layer("arp", [&](Packet &trial) {
            arp(trial, *payload);
            return Bytes{};
        });
    } else if (p.num("eth.type") == 2048) {
        payload = layer("ip", [&](Packet &trial) { return internet(trial, *payload); });
        if (!payload)
            return;
        if (p.has("ip.fragment"))
            remaining = *payload;
        else if (p.num("ip.proto") == 1) {
            const auto data = layer("icmp", [&](Packet &trial) { return icmp(trial, *payload); });
            if (data)
                remaining = *data;
        } else if (p.num("ip.proto") == 17) {
            payload = layer("udp", [&](Packet &trial) { return udp(trial, *payload); });
            if (payload) {
                if (p.num("udp.srcport") == 53 || p.num("udp.dstport") == 53)
                    layer("dns", [&](Packet &trial) {
                        dns(trial, *payload);
                        return Bytes{};
                    });
                else
                    remaining = *payload;
            }
        } else if (p.num("ip.proto") == 6) {
            const auto data = layer("tcp", [&](Packet &trial) { return tcp(trial, *payload); });
            if (data)
                remaining = *data;
        } else
            remaining = *payload;
    } else
        remaining = *payload;
    if (p.reason.empty() && !remaining.empty()) {
        p.layers.push_back("data");
        p.n("data.len", remaining.size());
        p.remaining = std::move(remaining);
    }
}
static std::string summary(const Packet &p, Integer origin) {
    const std::string source = p.has("ip.src")    ? ipv4(p.num("ip.src"))
                               : p.has("eth.src") ? mac(p.num("eth.src"))
                                                  : "-",
                      destination = p.has("ip.dst")    ? ipv4(p.num("ip.dst"))
                                    : p.has("eth.dst") ? mac(p.num("eth.dst"))
                                                       : "-";
    std::string last;
    for (const std::string &layer : p.layers)
        if (layer != "data")
            last = layer;
    const std::map<std::string, std::string> names = {{"eth", "ETH"},   {"arp", "ARP"}, {"ip", "IPv4"},
                                                      {"icmp", "ICMP"}, {"udp", "UDP"}, {"tcp", "TCP"},
                                                      {"dns", "DNS"}};
    const std::string protocol = last.empty() ? "DUMP" : names.at(last);
    std::string info;
    auto value = [&](const std::string &name) { return notation(p, name); };
    if (!p.reason.empty())
        info = p.reason;
    else if (last == "eth")
        info = "EtherType " + value("eth.type");
    else if (last == "arp") {
        const Integer op = p.num("arp.opcode");
        info = op == 1   ? "Who has " + value("arp.dst.ip") + "? Tell " + value("arp.src.ip")
               : op == 2 ? value("arp.src.ip") + " is at " + value("arp.src.hw")
                         : "Opcode " + decimal(op);
    } else if (last == "ip")
        info = p.has("ip.fragment") ? "Fragment id=" + value("ip.id") + " off=" + value("ip.frag_offset") +
                                          (p.num("ip.flags.mf") ? " MF" : "")
                                    : "Protocol " + value("ip.proto");
    else if (last == "icmp") {
        const Integer type = p.num("icmp.type");
        info = type == 8 || type == 0 ? std::string(type == 8 ? "Echo request" : "Echo reply") +
                                            " id=" + value("icmp.id") + " seq=" + value("icmp.seq")
                                      : "Type " + decimal(type) + " code " + value("icmp.code");
    } else if (last == "udp")
        info =
            value("udp.srcport") + " -> " + value("udp.dstport") + " Len=" + decimal(p.num("udp.length") - 8);
    else if (last == "tcp") {
        if (p.has("tcp.analysis.retransmission"))
            info = "[TCP Retransmission] ";
        else if (p.has("tcp.analysis.out_of_order"))
            info = "[TCP Out-Of-Order] ";
        else if (p.has("tcp.analysis.lost_segment"))
            info = "[TCP Previous segment not captured] ";
        else if (p.has("tcp.analysis.duplicate_ack"))
            info = "[TCP Dup ACK " + decimal(p.duplicate_origin) + "#" + decimal(p.duplicate_count) + "] ";
        const std::array<std::string, 8> flags = {"FIN", "SYN", "RST", "PSH", "ACK", "URG", "ECE", "CWR"};
        std::vector<std::string> enabled;
        for (int i = 0; i < 8; ++i)
            if (p.num("tcp.flags") & (Integer(1) << i))
                enabled.push_back(flags[i]);
        info += value("tcp.srcport") + " -> " + value("tcp.dstport") + " [" +
                (enabled.empty() ? "<None>" : join(enabled, ", ")) + "] Seq=" + value("tcp.seq");
        if (p.num("tcp.flags.ack"))
            info += " Ack=" + value("tcp.ack");
        info += " Win=" + value("tcp.window.calc") + " Len=" + value("tcp.len");
        if (p.has("tcp.option"))
            for (const Value &option : p.fields.at("tcp.option")) {
                std::istringstream in(option.text);
                std::string kind;
                Integer a, b;
                in >> kind;
                if (kind == "MSS") {
                    in >> a;
                    info += " MSS=" + decimal(a);
                } else if (kind == "WS") {
                    in >> a;
                    info += " WS=" + decimal(Integer(1) << a);
                } else if (kind == "SACK_PERM")
                    info += " SACK_PERM";
                else if (kind == "TS") {
                    in >> a >> b;
                    info += " TSval=" + decimal(a) + " TSecr=" + decimal(b);
                }
            }
    } else if (last == "dns") {
        info = std::string(p.num("dns.flags.response") ? "Response" : "Query") + " " + value("dns.id");
        if (p.num("dns.flags.rcode"))
            info += " " + rcode_name(p.num("dns.flags.rcode"));
        if (p.has("dns.qry.name"))
            for (std::size_t q = 0; q < p.fields.at("dns.qry.name").size(); ++q)
                info += " " + type_name(p.fields.at("dns.qry.type")[q].number) + " " +
                        p.fields.at("dns.qry.name")[q].text;
        for (const auto &answer : p.dns_answers)
            info += " " + type_name(answer.first) + " " + answer.second;
    }
    if (p.has("tcp.options.malformed"))
        info += " [bad TCP options]";
    const std::array<std::string, 4> checksum_names = {"ip", "icmp", "udp", "tcp"},
                                     display_names = {"IPv4", "ICMP", "UDP", "TCP"};
    for (int i = 0; i < 4; ++i)
        if (p.str(checksum_names[i] + ".checksum.status") == "bad")
            info += " [bad " + display_names[i] + " checksum]";
    return decimal(p.number) + " " + seconds(p.time - origin) + " " + source + " -> " + destination + " " +
           protocol + " " + decimal(p.length) + " " + info;
}
static std::string optional(std::optional<Integer> value) {
    return value ? decimal(*value) : "-";
}
static void write_file(const std::string &name, const std::vector<std::string> &lines) {
    std::ofstream out("output/" + name, std::ios::binary);
    for (const std::string &line : lines)
        out << line << '\n';
}
int main() {
    std::vector<Packet> packets = read_capture();
    std::vector<Stream> streams;
    const Integer origin = packets[0].time;
    for (Packet &p : packets) {
        dissect(p);
        track(p, streams);
        p.n("frame.number", p.number);
        p.n("frame.time", p.time - origin);
        p.n("frame.len", p.length);
        if (!p.layers.empty())
            p.s("frame.protocols", join(p.layers, ":"));
        if (!p.reason.empty())
            p.s("frame.malformed", p.reason);
        for (const auto &protocol : {"ip", "icmp", "udp", "tcp"})
            if (p.str(std::string(protocol) + ".checksum.status") == "bad")
                p.flag("frame.bad_checksum");
    }
    std::vector<std::string> summaries;
    for (const Packet &p : packets)
        summaries.push_back(summary(p, origin));
    std::vector<std::string> summary_lines = summaries, details;
    bool first_detail = true;
    for (const std::string &request : read_lines("input/filters.txt")) {
        if (request.empty() || request[0] == '#')
            continue;
        if (request.rfind("FILTER ", 0) == 0) {
            const std::string text = request.substr(7);
            summary_lines.push_back("");
            summary_lines.push_back("filter " + text);
            try {
                Parser parser{tokenize(text)};
                const auto expression = parser.parse();
                Integer count = 0;
                for (std::size_t i = 0; i < packets.size(); ++i)
                    if (expression->evaluate(packets[i])) {
                        summary_lines.push_back(summaries[i]);
                        ++count;
                    }
                summary_lines.push_back("matched " + decimal(count) + " of " + decimal(packets.size()));
            } catch (const std::string &error) {
                summary_lines.push_back("error: " + error);
            }
        } else {
            if (!first_detail)
                details.push_back("");
            first_detail = false;
            const Integer number = std::stoll(request.substr(7));
            if (number < 1 || number > Integer(packets.size())) {
                details.push_back("packet " + decimal(number) + " not found");
                continue;
            }
            const Packet &p = packets[number - 1];
            details.push_back("packet " + decimal(number));
            std::vector<std::string> layers = {"frame"};
            layers.insert(layers.end(), p.layers.begin(), p.layers.end());
            for (const std::string &layer : layers) {
                details.push_back(layer);
                for (const FieldSpec &spec : field_specs)
                    if (spec.name.rfind(layer + ".", 0) == 0 && p.has(spec.name))
                        for (const Value &v : p.fields.at(spec.name))
                            details.push_back(
                                "  " + spec.name +
                                (spec.type == Type::presence ? "" : " = " + notation(spec.type, v)));
                if (layer == "data")
                    for (const std::string &line : dump_lines(p.remaining))
                        details.push_back("  " + line);
            }
        }
    }
    const std::array<std::string, 3> kinds = {"ipv4", "tcp", "udp"};
    std::vector<std::string> conversation_lines = {
        "type,endpoint_a,endpoint_b,packets,bytes,packets_a_to_b,bytes_a_to_b,packets_b_to_a,bytes_b_to_a,start,duration"};
    for (const Conversation &c : conversations(packets))
        conversation_lines.push_back(
            kinds[c.kind] + "," + endpoint(c.a, c.kind != 0) + "," + endpoint(c.b, c.kind != 0) + "," +
            decimal(c.packets[0] + c.packets[1]) + "," + decimal(c.bytes[0] + c.bytes[1]) + "," +
            decimal(c.packets[0]) + "," + decimal(c.bytes[0]) + "," + decimal(c.packets[1]) + "," +
            decimal(c.bytes[1]) + "," + seconds(c.start - origin) + "," + seconds(c.end - c.start));
    std::vector<std::string> endpoint_lines = {
        "address,packets,bytes,tx_packets,tx_bytes,rx_packets,rx_bytes"};
    for (const EndpointTotals &e : endpoints(packets))
        endpoint_lines.push_back(ipv4(e.address) + "," + decimal(e.packets[0] + e.packets[1]) + "," +
                                 decimal(e.bytes[0] + e.bytes[1]) + "," + decimal(e.packets[0]) + "," +
                                 decimal(e.bytes[0]) + "," + decimal(e.packets[1]) + "," +
                                 decimal(e.bytes[1]));
    std::map<std::string, std::array<Integer, 2>> hierarchy;
    std::map<std::string, Integer> checksum_counts, malformed, marks, names;
    std::array<Integer, 16> rcodes{};
    std::vector<std::size_t> pending;
    std::vector<Integer> response_times;
    Integer total_bytes = 0, queries = 0, responses = 0;
    for (std::size_t index = 0; index < packets.size(); ++index) {
        const Packet &p = packets[index];
        total_bytes += p.length;
        for (const std::string &layer : p.layers) {
            ++hierarchy[layer][0];
            hierarchy[layer][1] += p.length;
        }
        for (const std::string &protocol : {"ip", "icmp", "udp", "tcp"})
            if (p.has(protocol + ".checksum.status"))
                ++checksum_counts[protocol + " " + p.str(protocol + ".checksum.status")];
        if (!p.reason.empty())
            ++malformed[p.layers.empty() ? "dump" : p.layers.back()];
        for (const std::string &mark : mark_names)
            if (p.has("tcp.analysis." + mark))
                ++marks[mark];
        if (!p.has("dns.id"))
            continue;
        if (p.num("dns.flags.response") == 0) {
            ++queries;
            pending.push_back(index);
            if (p.has("dns.qry.name"))
                for (const Value &value : p.fields.at("dns.qry.name"))
                    ++names[value.text];
        } else {
            ++responses;
            ++rcodes[p.num("dns.flags.rcode")];
            for (auto query = pending.begin(); query != pending.end(); ++query) {
                const Packet &q = packets[*query];
                if (q.num("dns.id") == p.num("dns.id") && q.num("ip.src") == p.num("ip.dst") &&
                    q.num("ip.dst") == p.num("ip.src") && q.num("udp.srcport") == p.num("udp.dstport") &&
                    q.num("udp.dstport") == p.num("udp.srcport")) {
                    response_times.push_back(p.time - q.time);
                    pending.erase(query);
                    break;
                }
            }
        }
    }
    std::vector<std::string> stats = {"packets " + decimal(packets.size()), "bytes " + decimal(total_bytes),
                                      "duration " + seconds(packets.back().time - origin), "hierarchy"};
    const std::array<std::string, 7> hnames = {"eth", "arp", "ip", "icmp", "udp", "dns", "tcp"};
    const std::array<int, 7> indents = {0, 2, 2, 4, 4, 6, 4};
    for (int i = 0; i < 7; ++i)
        stats.push_back(std::string(indents[i], ' ') + hnames[i] + " " + decimal(hierarchy[hnames[i]][0]) +
                        " " + decimal(hierarchy[hnames[i]][1]));
    stats.push_back("checksums");
    for (const std::string &protocol : {"ip", "icmp", "udp", "tcp"})
        stats.push_back(protocol + " good " + decimal(checksum_counts[protocol + " good"]) + " bad " +
                        decimal(checksum_counts[protocol + " bad"]) +
                        (protocol == "udp" ? " none " + decimal(checksum_counts["udp none"]) : ""));
    stats.push_back("malformed");
    for (const std::string &name : {"dump", "eth", "arp", "ip", "icmp", "udp", "tcp", "dns"})
        stats.push_back(name + " " + decimal(malformed[name]));
    stats.push_back("tcp analysis");
    for (const std::string &mark : mark_names)
        stats.push_back(mark + " " + decimal(marks[mark]));
    stats.push_back("dns");
    stats.push_back("queries " + decimal(queries));
    stats.push_back("responses " + decimal(responses));
    stats.push_back("transactions " + decimal(response_times.size()));
    stats.push_back("unanswered " + decimal(pending.size()));
    if (response_times.empty())
        stats.push_back("response_time -");
    else
        stats.push_back("response_time min " +
                        seconds(*std::min_element(response_times.begin(), response_times.end())) + " max " +
                        seconds(*std::max_element(response_times.begin(), response_times.end())));
    for (int code = 0; code < 16; ++code)
        if (rcodes[code])
            stats.push_back("rcode " + rcode_name(code) + " " + decimal(rcodes[code]));
    stats.push_back("names");
    std::vector<std::pair<std::string, Integer>> name_counts(names.begin(), names.end());
    std::sort(name_counts.begin(), name_counts.end(), [](const auto &a, const auto &b) {
        return a.second != b.second ? a.second > b.second : a.first < b.first;
    });
    for (const auto &entry : name_counts)
        stats.push_back(entry.first + " " + decimal(entry.second));
    std::vector<std::string> stream_lines;
    for (std::size_t index = 0; index < streams.size(); ++index) {
        const Stream &s = streams[index];
        if (index)
            stream_lines.push_back("");
        stream_lines.push_back("stream " + decimal(index) + " " + endpoint(s.client) + " -> " +
                               endpoint(s.server));
        stream_lines.push_back("packets " + decimal(s.packets) + " bytes " + decimal(s.bytes) + " start " +
                               seconds(s.start - origin) + " duration " + seconds(s.end - s.start));
        std::vector<std::string> states;
        for (const auto &state : s.history)
            states.push_back(state.first + " " + decimal(state.second));
        stream_lines.push_back("states " + join(states, ", "));
        stream_lines.push_back("handshake syn " + optional(s.handshake[0]) + " syn_ack " +
                               optional(s.handshake[1]) + " ack " + optional(s.handshake[2]) + " rtt " +
                               (s.handshake[0] && s.handshake[2] ? seconds(packets[*s.handshake[2] - 1].time -
                                                                           packets[*s.handshake[0] - 1].time)
                                                                 : "-"));
        stream_lines.push_back("options client mss " + optional(s.sides[0].mss) + " wscale " +
                               optional(s.sides[0].ws) + " server mss " + optional(s.sides[1].mss) +
                               " wscale " + optional(s.sides[1].ws));
        for (int side = 0; side < 2; ++side) {
            const Side &x = s.sides[side];
            std::string line = std::string(side == 0 ? "client" : "server") + " packets " +
                               decimal(x.packets) + " payload " + decimal(x.payload);
            for (int mark = 0; mark < 4; ++mark)
                line += " " + mark_names[mark] + " " + decimal(x.marks[mark]);
            stream_lines.push_back(line);
        }
        for (const Event &event : s.events)
            stream_lines.push_back("event " + decimal(event.packet) + " " +
                                   (event.side == 0 ? "client" : "server") + " " + mark_names[event.mark] +
                                   " seq " + decimal(event.seq) + " len " + decimal(event.length));
    }
    write_file("summary.txt", summary_lines);
    write_file("details.txt", details);
    write_file("conversations.csv", conversation_lines);
    write_file("endpoints.csv", endpoint_lines);
    write_file("protocol_stats.txt", stats);
    write_file("tcp_streams.txt", stream_lines);
}
