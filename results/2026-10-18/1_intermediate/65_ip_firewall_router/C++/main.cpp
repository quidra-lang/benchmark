#include <algorithm>
#include <array>
#include <cstdint>
#include <iostream>
#include <map>
#include <optional>
#include <set>
#include <sstream>
#include <stdexcept>
#include <string>
#include <tuple>
#include <utility>
#include <vector>

using Address = std::uint32_t;

struct Prefix {
    Address address;
    int length;
};

std::vector<std::string> words(const std::string& line) {
    std::istringstream input(line);
    std::vector<std::string> result;
    std::string word;
    while (input >> word) result.push_back(word);
    return result;
}

std::optional<int> decimal(const std::string& text, std::size_t max_digits) {
    if (text.empty() || text.size() > max_digits || (text.size() > 1 && text[0] == '0'))
        return std::nullopt;
    int value = 0;
    for (char c : text) {
        if (c < '0' || c > '9') return std::nullopt;
        value = value * 10 + c - '0';
    }
    return value;
}

std::optional<Address> parse_address(const std::string& text) {
    Address value = 0;
    std::size_t position = 0;
    for (int i = 0; i < 4; ++i) {
        std::size_t end = text.find('.', position);
        if ((i < 3) == (end == std::string::npos)) return std::nullopt;
        std::optional<int> field = decimal(text.substr(position, end == std::string::npos
                                                                 ? std::string::npos : end - position), 3);
        if (!field || *field > 255) return std::nullopt;
        value = value * 256 + static_cast<Address>(*field);
        if (i < 3) position = end + 1;
    }
    return value;
}

std::optional<Prefix> parse_prefix(const std::string& text) {
    std::size_t slash = text.find('/');
    if (slash == std::string::npos || text.find('/', slash + 1) != std::string::npos)
        return std::nullopt;
    std::optional<Address> address = parse_address(text.substr(0, slash));
    std::optional<int> length = decimal(text.substr(slash + 1), 2);
    if (!address || !length || *length > 32) return std::nullopt;
    return Prefix{*address, *length};
}

Address mask(int length) {
    return length == 0 ? Address{0} : ~Address{0} << (32 - length);
}

Address network(Address address, int length) {
    return address & mask(length);
}

bool contains(Prefix prefix, Address address) {
    return network(prefix.address, prefix.length) == network(address, prefix.length);
}

std::string address_text(Address address) {
    return std::to_string(address >> 24) + "." + std::to_string((address >> 16) & 255) + "." +
           std::to_string((address >> 8) & 255) + "." + std::to_string(address & 255);
}

std::string prefix_text(Prefix prefix) {
    return address_text(prefix.address) + "/" + std::to_string(prefix.length);
}

std::string endpoint(Address address, int port) {
    return address_text(address) + ":" + std::to_string(port);
}

Address require_address(const std::string& word) {
    std::optional<Address> result = parse_address(word);
    if (!result) throw std::runtime_error("bad address " + word);
    return *result;
}

Prefix require_prefix(const std::string& word, bool acl = false) {
    if (acl && word == "ANY") return {0, 0};
    std::optional<Prefix> prefix = parse_prefix(word);
    if (!prefix) throw std::runtime_error("bad prefix " + word);
    if (network(prefix->address, prefix->length) != prefix->address)
        throw std::runtime_error("host bits set in " + word);
    return *prefix;
}

int require_number(const std::string& text, int minimum, int maximum, const std::string& label) {
    int value = std::stoi(text);
    if (value < minimum || value > maximum) throw std::runtime_error(label + " " + text);
    return value;
}

std::string lowercase(std::string text) {
    for (char& c : text) if (c >= 'A' && c <= 'Z') c += 'a' - 'A';
    return text;
}

struct Ports {
    int low = 0, high = 65535;
    bool any = true;
    bool contains(int port) const { return low <= port && port <= high; }
    std::string text() const {
        if (any) return "any";
        return std::to_string(low) + (low == high ? "" : "-" + std::to_string(high));
    }
};

Ports require_ports(const std::string& word) {
    if (word == "ANY") return Ports{};
    std::size_t dash = word.find('-');
    int low = std::stoi(word.substr(0, dash));
    int high = dash == std::string::npos ? low : std::stoi(word.substr(dash + 1));
    if (low > 65535 || high > 65535 || low > high)
        throw std::runtime_error("bad port range " + word);
    return {low, high, false};
}

struct Flow {
    std::string protocol;
    Address source;
    int sport;
    Address destination;
    int dport;

    bool operator==(const Flow& other) const {
        return std::tie(protocol, source, sport, destination, dport) ==
               std::tie(other.protocol, other.source, other.sport, other.destination, other.dport);
    }
    std::string text() const { return endpoint(source, sport) + " > " + endpoint(destination, dport); }
};

struct Rule {
    int sequence;
    std::string action, protocol;
    Prefix source;
    Ports sports;
    Prefix destination;
    Ports dports;
    bool established;
    int hits = 0;

    bool matches(const Flow& flow, bool existing) const {
        if (protocol != "ANY" && protocol != flow.protocol) return false;
        if (!contains(source, flow.source) || !contains(destination, flow.destination)) return false;
        if ((protocol == "TCP" || protocol == "UDP") &&
            (!sports.contains(flow.sport) || !dports.contains(flow.dport))) return false;
        return !established || existing;
    }
};

struct AccessList {
    std::map<int, Rule> rules;
    int default_hits = 0;
};

struct Pat {
    std::string protocol;
    Address inside;
    int inside_port, outside_port;
    int last_used;
};

struct Interface {
    std::string name;
    Address address;
    int length;
    bool up = true, outside = false;
    int pool_size = 0;
    std::string rpf = "off";
    int rx = 0, tx = 0, drop = 0;
    std::array<AccessList, 2> acls;
    std::vector<Pat> mappings;
};

struct Route {
    char type;
    Prefix prefix;
    std::string interface;
    std::optional<Address> hop;
    int metric, hits = 0;

    std::string text() const {
        std::string result = std::string(1, type) + " " + prefix_text(prefix);
        if (hop) result += " via " + address_text(*hop);
        return result + " dev " + interface + " metric " + std::to_string(metric);
    }
};

struct StaticNat { Address inside, outside; };
struct Forward {
    std::string interface, protocol;
    int outside_port;
    Address inside;
    int inside_port;
};

struct Connection {
    int number;
    Flow orig, reply;
    std::string input, output, state;
    int orig_packets = 0, reply_packets = 0, last_used = 0;
    bool orig_fin = false, reply_fin = false;

    void record(const std::string& direction, const std::string& flags, int clock) {
        bool reply_side = direction == "reply";
        if (reply_side) ++reply_packets;
        else ++orig_packets;
        last_used = clock;
        if (orig.protocol != "TCP") {
            if (reply_side) state = "REPLIED";
            return;
        }
        if (flags.find('R') != std::string::npos) {
            state = "CLOSED";
            return;
        }
        if (state == "SYN_SENT" && reply_side && flags.find('S') != std::string::npos &&
            flags.find('A') != std::string::npos) state = "ESTABLISHED";
        if (flags.find('F') != std::string::npos && (state == "ESTABLISHED" || state == "FIN_WAIT")) {
            if (reply_side) reply_fin = true;
            else orig_fin = true;
            state = orig_fin && reply_fin ? "CLOSED" : "FIN_WAIT";
        }
    }
};

class Router {
    std::map<std::string, Interface> interfaces;
    std::vector<std::string> definition_order;
    std::vector<Route> routes;
    std::vector<StaticNat> statics;
    std::vector<Forward> forwards;
    std::vector<Connection> connections;
    std::map<std::string, int> timeouts{{"TCP", 300}, {"UDP", 60}, {"ICMP", 30}};
    std::map<std::string, int> counts;
    const std::vector<std::string> reasons{
        "down", "martian", "rpf", "invalid", "acl_in", "ttl", "noroute", "acl_out", "exhausted"
    };
    int clock = 0, packet_number = 0, connection_number = 0, errors = 0;

    Interface& require_interface(const std::string& name) {
        auto found = interfaces.find(name);
        if (found == interfaces.end()) throw std::runtime_error("no interface " + name);
        return found->second;
    }

    Interface* local(Address address) {
        for (auto& item : interfaces) if (item.second.address == address) return &item.second;
        return nullptr;
    }

    Route* select(Address address) {
        Route* best = nullptr;
        for (Route& route : routes) {
            if (!interfaces.at(route.interface).up || !contains(route.prefix, address)) continue;
            if (!best || route.prefix.length > best->prefix.length ||
                (route.prefix.length == best->prefix.length && route.metric < best->metric)) best = &route;
        }
        return best;
    }

    std::string evaluate(Interface& interface, int direction, const Flow& flow, bool existing) {
        AccessList& acl = interface.acls[direction];
        if (acl.rules.empty()) return "";
        std::string label = "acl " + interface.name + (direction == 0 ? " in " : " out ");
        for (auto& entry : acl.rules) {
            Rule& rule = entry.second;
            if (!rule.matches(flow, existing)) continue;
            ++rule.hits;
            if (rule.action == "PERMIT") return "";
            if (rule.action == "DENY") return "DROP " + label + std::to_string(rule.sequence);
            return "REJECT " + label + std::to_string(rule.sequence) +
                   (flow.protocol == "TCP" ? " tcp-reset" : " icmp-prohibited");
        }
        ++acl.default_hits;
        return "DROP " + label + "default";
    }

    std::pair<Connection*, std::string> find_connection(const Flow& flow, bool pure_syn) {
        for (auto it = connections.begin(); it != connections.end(); ++it) {
            std::string direction;
            if (it->orig == flow) direction = "orig";
            else if (it->reply == flow) direction = "reply";
            else continue;
            if (it->state == "CLOSED" && pure_syn) {
                connections.erase(it);
                return {nullptr, ""};
            }
            return {&*it, direction};
        }
        return {nullptr, ""};
    }

    std::pair<std::string, std::string> process(Interface& input, const Flow& original,
                                             const std::string& flags, int ttl) {
        auto drop = [](const std::string& reason) {
            return std::make_pair(reason, "DROP " + reason);
        };
        if (!input.up) return drop("down");
        for (Prefix prefix : std::array<Prefix, 3>{{{0, 8}, {0x7f000000U, 8}, {0xe0000000U, 3}}})
            if (contains(prefix, original.source) || contains(prefix, original.destination)) return drop("martian");
        if (local(original.source)) return drop("martian");
        if (input.rpf != "off") {
            Route* route = select(original.source);
            if (!route || (input.rpf == "strict" && route->interface != input.name)) return drop("rpf");
        }
        bool pure_syn = original.protocol == "TCP" && flags == "S";
        std::pair<Connection*, std::string> found = find_connection(original, pure_syn);
        Connection* connection = found.first;
        std::string direction = found.second;
        if (original.protocol == "TCP" && !connection && !pure_syn) return drop("invalid");
        std::string verdict = evaluate(input, 0, original, connection != nullptr);
        if (!verdict.empty()) return {"acl_in", verdict};
        Flow translated = original;
        Pat* used = nullptr;
        if (input.outside) {
            bool done = false;
            for (const StaticNat& mapping : statics) {
                if (mapping.outside != original.destination) continue;
                translated.destination = mapping.inside;
                done = true;
                break;
            }
            if (!done && original.destination == input.address) {
                for (const Forward& forward : forwards) {
                    if (forward.interface == input.name && forward.protocol == original.protocol &&
                        forward.outside_port == original.dport) {
                        translated.destination = forward.inside;
                        translated.dport = forward.inside_port;
                        done = true;
                        break;
                    }
                }
                if (!done) {
                    for (Pat& mapping : input.mappings) {
                        if (mapping.protocol == original.protocol && mapping.outside_port == original.dport) {
                            translated.destination = mapping.inside;
                            translated.dport = mapping.inside_port;
                            used = &mapping;
                            break;
                        }
                    }
                }
            }
        }
        if (Interface* destination = local(translated.destination))
            return {"local", "LOCAL " + destination->name};
        if (ttl == 1) return drop("ttl");
        Route* route = select(translated.destination);
        if (!route) return drop("noroute");
        Interface& output = interfaces.at(route->interface);
        verdict = evaluate(output, 1, translated, connection != nullptr);
        if (!verdict.empty()) return {"acl_out", verdict};
        if (!input.outside && output.outside) {
            bool done = false;
            for (const StaticNat& mapping : statics) {
                if (mapping.inside != original.source) continue;
                translated.source = mapping.outside;
                done = true;
                break;
            }
            if (!done) {
                for (const Forward& forward : forwards) {
                    if (forward.interface == output.name && forward.protocol == original.protocol &&
                        forward.inside == original.source && forward.inside_port == original.sport) {
                        translated.source = output.address;
                        translated.sport = forward.outside_port;
                        done = true;
                        break;
                    }
                }
            }
            if (!done && output.pool_size) {
                for (Pat& mapping : output.mappings) {
                    if (mapping.protocol == original.protocol && mapping.inside == original.source &&
                        mapping.inside_port == original.sport) {
                        used = &mapping;
                        break;
                    }
                }
                if (!used) {
                    std::set<int> occupied;
                    for (const Pat& mapping : output.mappings) occupied.insert(mapping.outside_port);
                    for (const Forward& forward : forwards)
                        if (forward.interface == output.name) occupied.insert(forward.outside_port);
                    int port = 20000;
                    while (port < 20000 + output.pool_size && occupied.count(port)) ++port;
                    if (port == 20000 + output.pool_size) return drop("exhausted");
                    output.mappings.push_back({original.protocol, original.source, original.sport, port, clock});
                    used = &output.mappings.back();
                }
                translated.source = output.address;
                translated.sport = used->outside_port;
            }
        }
        if (used) used->last_used = clock;
        if (!connection) {
            Flow reply{original.protocol, translated.destination, translated.dport,
                       translated.source, translated.sport};
            connections.push_back({++connection_number, original, reply, input.name, output.name,
                                   original.protocol == "TCP" ? "SYN_SENT" : "UNREPLIED"});
            connection = &connections.back();
            direction = "new";
        }
        connection->record(direction, flags, clock);
        ++output.tx;
        ++route->hits;
        verdict = "FORWARD " + output.name + (route->hop ? " via " + address_text(*route->hop) : " direct") +
                  " ttl=" + std::to_string(ttl - 1);
        if (translated.destination != original.destination || translated.dport != original.dport)
            verdict += " dnat=" + endpoint(translated.destination, translated.dport);
        if (translated.source != original.source || translated.sport != original.sport)
            verdict += " snat=" + endpoint(translated.source, translated.sport);
        verdict += " conn=" + std::to_string(connection->number) + " " + direction;
        return {"forwarded", verdict};
    }

    void show(const std::string& what) {
        if (what == "IFACES") {
            std::cout << "show ifaces count=" << interfaces.size() << '\n';
            for (const auto& entry : interfaces) {
                const Interface& interface = entry.second;
                std::cout << interface.name << ' ' << prefix_text({interface.address, interface.length})
                          << (interface.up ? " up " : " down ") << (interface.outside ? "outside" : "inside")
                          << " rpf=" << interface.rpf;
                if (interface.pool_size) std::cout << " pat=" << interface.mappings.size() << '/' << interface.pool_size;
                std::cout << '\n';
            }
        } else if (what == "ROUTES") {
            std::vector<const Route*> ordered;
            for (const Route& route : routes) ordered.push_back(&route);
            std::stable_sort(ordered.begin(), ordered.end(), [](const Route* a, const Route* b) {
                return std::tie(a->prefix.address, a->prefix.length, a->metric) <
                       std::tie(b->prefix.address, b->prefix.length, b->metric);
            });
            std::cout << "show routes count=" << routes.size() << '\n';
            for (const Route* route : ordered)
                std::cout << route->text() << " hits=" << route->hits
                          << (interfaces.at(route->interface).up ? "" : " inactive") << '\n';
        } else if (what == "ACL") {
            std::size_t total = 0;
            for (const auto& entry : interfaces) for (const AccessList& acl : entry.second.acls) total += acl.rules.size();
            std::cout << "show acl count=" << total << '\n';
            for (const auto& entry : interfaces) {
                for (int d = 0; d < 2; ++d) {
                    const AccessList& acl = entry.second.acls[d];
                    if (acl.rules.empty()) continue;
                    std::string label = "acl " + entry.first + (d == 0 ? " in " : " out ");
                    for (const auto& rule_entry : acl.rules) {
                        const Rule& rule = rule_entry.second;
                        std::cout << label << rule.sequence << ' ' << rule.action << ' ' << rule.protocol << ' '
                                  << (rule.source.length ? prefix_text(rule.source) : "any") << ' ' << rule.sports.text() << ' '
                                  << (rule.destination.length ? prefix_text(rule.destination) : "any") << ' ' << rule.dports.text()
                                  << (rule.established ? " established" : "") << " hits=" << rule.hits << '\n';
                    }
                    std::cout << label << "default DENY hits=" << acl.default_hits << '\n';
                }
            }
        } else if (what == "NAT") {
            std::size_t total = 0;
            for (const auto& entry : interfaces) total += entry.second.mappings.size();
            std::cout << "show nat static=" << statics.size() << " forward=" << forwards.size() << " pat=" << total << '\n';
            std::vector<StaticNat> ordered_statics = statics;
            std::sort(ordered_statics.begin(), ordered_statics.end(), [](StaticNat a, StaticNat b) { return a.inside < b.inside; });
            for (StaticNat mapping : ordered_statics)
                std::cout << "static " << address_text(mapping.inside) << ' ' << address_text(mapping.outside) << '\n';
            std::vector<Forward> ordered_forwards = forwards;
            std::sort(ordered_forwards.begin(), ordered_forwards.end(), [](const Forward& a, const Forward& b) {
                return std::tie(a.interface, a.outside_port, a.protocol) < std::tie(b.interface, b.outside_port, b.protocol);
            });
            for (const Forward& forward : ordered_forwards)
                std::cout << "forward " << forward.interface << ' ' << forward.protocol << ' ' << forward.outside_port
                          << ' ' << endpoint(forward.inside, forward.inside_port) << '\n';
            for (const auto& entry : interfaces) {
                std::vector<Pat> ordered = entry.second.mappings;
                std::sort(ordered.begin(), ordered.end(), [](const Pat& a, const Pat& b) { return a.outside_port < b.outside_port; });
                for (const Pat& mapping : ordered)
                    std::cout << "pat " << entry.first << ' ' << mapping.outside_port << ' ' << mapping.protocol
                              << ' ' << endpoint(mapping.inside, mapping.inside_port) << " idle=" << clock - mapping.last_used << '\n';
            }
        } else if (what == "CONNS") {
            std::cout << "show conns count=" << connections.size() << '\n';
            for (const Connection& connection : connections)
                std::cout << "conn " << connection.number << ' ' << connection.orig.protocol << ' ' << connection.orig.text()
                          << " reply " << connection.reply.text() << " in=" << connection.input << " out=" << connection.output
                          << " state=" << connection.state << " pkts=" << connection.orig_packets << '/' << connection.reply_packets
                          << " idle=" << clock - connection.last_used << '\n';
        } else {
            int dropped = 0;
            for (const std::string& reason : reasons) dropped += counts[reason];
            std::cout << "show counters packets=" << counts["forwarded"] + counts["local"] + dropped
                      << " forwarded=" << counts["forwarded"] << " local=" << counts["local"]
                      << " dropped=" << dropped << " errors=" << errors << '\n';
            std::cout << "drops";
            for (const std::string& reason : reasons) std::cout << ' ' << reason << '=' << counts[reason];
            std::cout << '\n';
            for (const auto& entry : interfaces)
                std::cout << "iface " << entry.first << " rx=" << entry.second.rx << " tx=" << entry.second.tx
                          << " drop=" << entry.second.drop << '\n';
        }
    }

    void configure(const std::vector<std::string>& w) {
        const std::string& command = w[0];
        if (command == "IFACE") {
            if (interfaces.count(w[1])) throw std::runtime_error("duplicate interface " + w[1]);
            std::optional<Prefix> prefix = parse_prefix(w[2]);
            if (!prefix || prefix->length < 8 || prefix->length > 30) throw std::runtime_error("bad prefix " + w[2]);
            Address host = prefix->address & ~mask(prefix->length);
            if (host == 0 || host == ~mask(prefix->length)) throw std::runtime_error("bad host address " + w[2]);
            for (const std::string& name : definition_order) {
                const Interface& existing = interfaces.at(name);
                int length = std::min(prefix->length, existing.length);
                if (network(prefix->address, length) == network(existing.address, length))
                    throw std::runtime_error("subnet overlaps " + name);
            }
            Interface interface;
            interface.name = w[1];
            interface.address = prefix->address;
            interface.length = prefix->length;
            interfaces.emplace(w[1], std::move(interface));
            definition_order.push_back(w[1]);
            Prefix connected{network(prefix->address, prefix->length), prefix->length};
            routes.push_back({'C', connected, w[1], std::nullopt, 0});
            std::cout << "ok iface " << w[1] << ' ' << w[2] << " network " << prefix_text(connected) << '\n';
        } else if (command == "UP" || command == "DOWN") {
            Interface& interface = require_interface(w[1]);
            bool up = command == "UP";
            if (interface.up == up) throw std::runtime_error("interface " + w[1] + " already " + lowercase(command));
            interface.up = up;
            std::cout << "ok " << lowercase(command) << ' ' << w[1] << '\n';
        } else if (command == "ROUTE") {
            Prefix prefix = require_prefix(w[1]);
            std::optional<Address> hop;
            std::string output;
            if (w[2] == "VIA") hop = require_address(w[3]);
            else output = require_interface(w[3]).name;
            int metric = require_number(w[4], 1, 255, "bad metric");
            if (hop) {
                if (local(*hop)) throw std::runtime_error("nexthop " + w[3] + " is local");
                for (const auto& entry : interfaces)
                    if (contains({entry.second.address, entry.second.length}, *hop)) output = entry.first;
                if (output.empty()) throw std::runtime_error("nexthop " + w[3] + " unreachable");
            }
            for (const Route& route : routes)
                if (route.type == 'S' && route.prefix.address == prefix.address && route.prefix.length == prefix.length &&
                    route.interface == output && route.hop == hop) throw std::runtime_error("duplicate route " + w[1]);
            routes.push_back({'S', prefix, output, hop, metric});
            std::cout << "ok route " << routes.back().text() << '\n';
        } else if (command == "NOROUTE") {
            Prefix prefix = require_prefix(w[1]);
            auto matches = [&](const Route& route) {
                return route.type == 'S' && route.prefix.address == prefix.address && route.prefix.length == prefix.length;
            };
            std::size_t removed = static_cast<std::size_t>(std::count_if(routes.begin(), routes.end(), matches));
            if (!removed) throw std::runtime_error("no static route " + w[1]);
            routes.erase(std::remove_if(routes.begin(), routes.end(), matches), routes.end());
            std::cout << "ok noroute " << w[1] << " removed=" << removed << '\n';
        } else if (command == "LOOKUP") {
            Address address = require_address(w[1]);
            Route* route = select(address);
            std::cout << "lookup " << w[1] << ' ' << (route ? route->text() : "none") << '\n';
        } else if (command == "ACL") {
            Interface& interface = require_interface(w[1]);
            int sequence = require_number(w[3], 1, 9999, "bad sequence");
            Prefix source = require_prefix(w[6], true);
            Ports sports = require_ports(w[7]);
            Prefix destination = require_prefix(w[8], true);
            Ports dports = require_ports(w[9]);
            if ((w[5] == "ICMP" || w[5] == "ANY") && (w[7] != "ANY" || w[9] != "ANY"))
                throw std::runtime_error("ports not allowed for " + w[5]);
            AccessList& acl = interface.acls[w[2] == "IN" ? 0 : 1];
            if (acl.rules.count(sequence)) throw std::runtime_error("duplicate sequence " + w[3]);
            acl.rules.emplace(sequence, Rule{sequence, w[4], w[5], source, sports, destination, dports, w.size() == 11});
            std::cout << "ok acl " << w[1] << ' ' << lowercase(w[2]) << ' ' << w[3] << '\n';
        } else if (command == "NOACL") {
            Interface& interface = require_interface(w[1]);
            AccessList& acl = interface.acls[w[2] == "IN" ? 0 : 1];
            auto rule = acl.rules.find(std::stoi(w[3]));
            if (rule == acl.rules.end()) throw std::runtime_error("no rule " + w[3] + " on " + w[1] + " " + lowercase(w[2]));
            int hits = rule->second.hits;
            acl.rules.erase(rule);
            std::cout << "ok noacl " << w[1] << ' ' << lowercase(w[2]) << ' ' << w[3] << " hits=" << hits << '\n';
        } else if (command == "NAT") {
            if (w[1] == "STATIC") {
                Address inside = require_address(w[2]), outside = require_address(w[3]);
                if (local(inside)) throw std::runtime_error("address " + w[2] + " is local");
                if (local(outside)) throw std::runtime_error("address " + w[3] + " is local");
                for (StaticNat mapping : statics)
                    if (mapping.inside == inside) throw std::runtime_error("duplicate static " + w[2]);
                for (StaticNat mapping : statics)
                    if (mapping.outside == outside) throw std::runtime_error("duplicate static " + w[3]);
                statics.push_back({inside, outside});
                std::cout << "ok nat static " << w[2] << ' ' << w[3] << '\n';
            } else {
                Interface& interface = require_interface(w[2]);
                if (w[1] == "OUTSIDE") {
                    if (interface.outside) throw std::runtime_error("interface " + w[2] + " already outside");
                    interface.outside = true;
                    std::cout << "ok nat outside " << w[2] << '\n';
                } else if (w[1] == "PAT") {
                    int count = require_number(w[3], 1, 1000, "bad pool size");
                    if (interface.pool_size) throw std::runtime_error("pat already on " + w[2]);
                    interface.pool_size = count;
                    interface.outside = true;
                    std::cout << "ok nat pat " << w[2] << ' ' << address_text(interface.address) << " 20000-" << 20000 + count - 1 << '\n';
                } else {
                    int port = require_number(w[4], 1, 65535, "bad port");
                    Address inside = require_address(w[5]);
                    int inport = require_number(w[6], 1, 65535, "bad port");
                    if (!interface.outside) throw std::runtime_error("interface " + w[2] + " not outside");
                    if (local(inside)) throw std::runtime_error("address " + w[5] + " is local");
                    for (const Forward& forward : forwards)
                        if (forward.interface == w[2] && forward.protocol == w[3] && forward.outside_port == port)
                            throw std::runtime_error("duplicate forward " + w[2] + " " + w[3] + " " + w[4]);
                    forwards.push_back({w[2], w[3], port, inside, inport});
                    std::cout << "ok nat forward " << w[2] << ' ' << w[3] << ' ' << w[4] << ' ' << w[5] << ':' << w[6] << '\n';
                }
            }
        } else if (command == "RPF") {
            Interface& interface = require_interface(w[1]);
            interface.rpf = lowercase(w[2]);
            std::cout << "ok rpf " << w[1] << ' ' << interface.rpf << '\n';
        } else if (command == "TIMEOUT") {
            int seconds = require_number(w[2], 1, 86400, "bad timeout");
            timeouts[w[1]] = seconds;
            std::cout << "ok timeout " << w[1] << ' ' << w[2] << '\n';
        } else if (command == "TICK") {
            int seconds = require_number(w[1], 1, 86400, "bad tick");
            clock += seconds;
            std::size_t before = connections.size();
            connections.erase(std::remove_if(connections.begin(), connections.end(), [&](const Connection& connection) {
                int timeout = timeouts.at(connection.orig.protocol);
                if (connection.orig.protocol == "TCP") {
                    if (connection.state == "SYN_SENT" || connection.state == "FIN_WAIT") timeout = 60;
                    if (connection.state == "CLOSED") timeout = 10;
                }
                return clock - connection.last_used >= timeout;
            }), connections.end());
            std::size_t removed = 0;
            for (auto& entry : interfaces) {
                std::vector<Pat>& mappings = entry.second.mappings;
                std::size_t old_size = mappings.size();
                mappings.erase(std::remove_if(mappings.begin(), mappings.end(), [&](const Pat& mapping) {
                    return clock - mapping.last_used >= timeouts.at(mapping.protocol);
                }), mappings.end());
                removed += old_size - mappings.size();
            }
            std::cout << "ok tick time=" << clock << " expired conns=" << before - connections.size() << " nat=" << removed << '\n';
        } else if (command == "PACKET") {
            Interface& interface = require_interface(w[1]);
            if (w[2] != "TCP" && w[3] != "-") throw std::runtime_error("flags not allowed for " + w[2]);
            if (w[2] == "TCP" && w[3] != "-") {
                std::set<char> seen;
                for (char c : w[3])
                    if (std::string("SAFR").find(c) == std::string::npos || !seen.insert(c).second)
                        throw std::runtime_error("bad flags " + w[3]);
            }
            Address source = require_address(w[4]);
            int sport = require_number(w[5], 0, 65535, "bad port");
            Address destination = require_address(w[6]);
            int dport = require_number(w[7], 0, 65535, "bad port");
            int ttl = require_number(w[8], 1, 255, "bad ttl");
            ++packet_number;
            ++interface.rx;
            std::pair<std::string, std::string> result = process(interface, {w[2], source, sport, destination, dport},
                                                              w[3] == "-" ? "" : w[3], ttl);
            ++counts[result.first];
            if (result.first != "forwarded" && result.first != "local") ++interface.drop;
            std::cout << '#' << packet_number << ' ' << w[2] << ' ' << w[3] << ' ' << w[4] << ':' << w[5]
                      << " > " << w[6] << ':' << w[7] << ' ' << result.second << '\n';
        } else if (command == "SHOW") {
            show(w[1]);
        } else if (command == "CLEAR" && w[1] == "COUNTERS") {
            for (auto& count : counts) count.second = 0;
            errors = 0;
            for (auto& entry : interfaces) {
                Interface& interface = entry.second;
                interface.rx = interface.tx = interface.drop = 0;
                for (AccessList& acl : interface.acls) {
                    acl.default_hits = 0;
                    for (auto& rule : acl.rules) rule.second.hits = 0;
                }
            }
            for (Route& route : routes) route.hits = 0;
            std::cout << "ok clear counters\n";
        } else if (command == "CLEAR") {
            std::size_t removed = 0;
            for (auto& entry : interfaces) {
                removed += entry.second.mappings.size();
                entry.second.mappings.clear();
            }
            std::cout << "ok clear conns=" << connections.size() << " nat=" << removed << '\n';
            connections.clear();
        }
    }

public:
    void execute(const std::string& line) {
        try {
            configure(words(line));
        } catch (const std::runtime_error& error) {
            ++errors;
            std::cout << "error: " << error.what() << '\n';
        }
    }
};

int main() {
    int count;
    std::cin >> count;
    std::string line;
    std::getline(std::cin, line);
    Router router;
    for (int i = 0; i < count; ++i) {
        std::getline(std::cin, line);
        router.execute(line);
    }
}
