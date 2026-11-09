#include <algorithm>
#include <array>
#include <cstdint>
#include <iomanip>
#include <iostream>
#include <map>
#include <optional>
#include <set>
#include <sstream>
#include <stdexcept>
#include <string>
#include <utility>
#include <vector>

using Address = std::uint32_t;
using Address6 = std::array<unsigned, 8>;
const std::vector<std::string> types{"A", "NS", "CNAME", "SOA", "PTR", "MX", "TXT", "AAAA"};
const std::vector<std::string> response_kinds{"ANSWER", "CNAME", "REFERRAL", "NODATA", "NXDOMAIN", "LAME", "TIMEOUT"};

std::vector<std::string> split(const std::string& text, char separator) {
    std::vector<std::string> result;
    std::size_t start = 0;
    for (std::size_t i = 0; i <= text.size(); ++i) {
        if (i == text.size() || text[i] == separator) {
            result.push_back(text.substr(start, i - start));
            start = i + 1;
        }
    }
    return result;
}

std::string join(const std::vector<std::string>& parts, const std::string& separator) {
    std::string result;
    for (std::size_t i = 0; i < parts.size(); ++i) {
        if (i) result += separator;
        result += parts[i];
    }
    return result;
}

std::string lower(std::string text) {
    for (char& c : text) if (c >= 'A' && c <= 'Z') c += 'a' - 'A';
    return text;
}

std::optional<int> decimal(const std::string& text, std::size_t maximum = 9) {
    if (text.empty() || text.size() > maximum || (text.size() > 1 && text[0] == '0')) return std::nullopt;
    int value = 0;
    for (char c : text) {
        if (c < '0' || c > '9') return std::nullopt;
        value = value * 10 + c - '0';
    }
    return value;
}

std::optional<Address> address4(const std::string& text) {
    std::vector<std::string> fields = split(text, '.');
    if (fields.size() != 4) return std::nullopt;
    Address address = 0;
    for (const std::string& field : fields) {
        std::optional<int> value = decimal(field, 3);
        if (!value || *value > 255) return std::nullopt;
        address = address * 256 + static_cast<Address>(*value);
    }
    return address;
}

std::string address_text(Address address) {
    return std::to_string(address >> 24) + "." + std::to_string((address >> 16) & 255) + "." +
           std::to_string((address >> 8) & 255) + "." + std::to_string(address & 255);
}

Address require_address(const std::string& text) {
    std::optional<Address> value = address4(text);
    if (!value) throw std::runtime_error("bad address " + text);
    return *value;
}

std::optional<std::vector<unsigned>> groups(const std::string& text) {
    std::vector<unsigned> result;
    if (text.empty()) return result;
    for (const std::string& group : split(text, ':')) {
        if (group.empty() || group.size() > 4) return std::nullopt;
        unsigned value = 0;
        for (char c : group) {
            unsigned h;
            if (c >= '0' && c <= '9') h = static_cast<unsigned>(c - '0');
            else if (c >= 'a' && c <= 'f') h = static_cast<unsigned>(c - 'a' + 10);
            else if (c >= 'A' && c <= 'F') h = static_cast<unsigned>(c - 'A' + 10);
            else return std::nullopt;
            value = value * 16 + h;
        }
        result.push_back(value);
    }
    return result;
}

std::optional<Address6> address6(const std::string& text) {
    std::size_t colon = text.find("::");
    Address6 result{};
    if (colon == std::string::npos) {
        std::optional<std::vector<unsigned>> values = groups(text);
        if (!values || values->size() != 8) return std::nullopt;
        std::copy(values->begin(), values->end(), result.begin());
    } else {
        if (text.find("::", colon + 2) != std::string::npos) return std::nullopt;
        std::optional<std::vector<unsigned>> first = groups(text.substr(0, colon));
        std::optional<std::vector<unsigned>> last = groups(text.substr(colon + 2));
        if (!first || !last || first->size() + last->size() > 7) return std::nullopt;
        std::copy(first->begin(), first->end(), result.begin());
        std::copy(last->begin(), last->end(), result.end() - static_cast<std::ptrdiff_t>(last->size()));
    }
    return result;
}

std::string address_text(const Address6& address) {
    std::vector<std::string> fields;
    for (unsigned group : address) {
        std::ostringstream text;
        text << std::hex << group;
        fields.push_back(text.str());
    }
    std::size_t best_start = 0, best_length = 0;
    for (std::size_t i = 0; i < 8;) {
        if (address[i] != 0) {
            ++i;
            continue;
        }
        std::size_t end = i;
        while (end < 8 && address[end] == 0) ++end;
        if (end - i > best_length && end - i >= 2) {
            best_start = i;
            best_length = end - i;
        }
        i = end;
    }
    if (!best_length) return join(fields, ":");
    return join(std::vector<std::string>(fields.begin(), fields.begin() + best_start), ":") + "::" +
           join(std::vector<std::string>(fields.begin() + best_start + best_length, fields.end()), ":");
}

struct Name {
    std::vector<std::string> labels;
    std::string text() const { return labels.empty() ? "." : join(labels, ".") + "."; }
    bool operator==(const Name& other) const { return labels == other.labels; }
    bool operator!=(const Name& other) const { return !(*this == other); }
    bool operator<(const Name& other) const {
        return std::lexicographical_compare(labels.rbegin(), labels.rend(), other.labels.rbegin(), other.labels.rend());
    }
    Name suffix(std::size_t length) const {
        return Name{std::vector<std::string>(labels.end() - static_cast<std::ptrdiff_t>(length), labels.end())};
    }
};

bool below(const Name& name, const Name& ancestor) {
    return name.labels.size() >= ancestor.labels.size() && name.suffix(ancestor.labels.size()) == ancestor;
}

Name require_name(const std::string& word, bool wildcard = false, const Name* origin = nullptr) {
    if (origin && word == "@") return *origin;
    Name name;
    if (word == ".") return name;
    bool absolute = !word.empty() && word.back() == '.';
    std::string base = absolute ? word.substr(0, word.size() - 1) : word;
    std::vector<std::string> labels = split(base, '.');
    for (std::size_t i = 0; i < labels.size(); ++i) {
        std::string label = lower(labels[i]);
        if (i == 0 && wildcard && label == "*") {
            name.labels.push_back(label);
            continue;
        }
        if (label.empty() || label.size() > 63 || label.front() == '-' || label.back() == '-')
            throw std::runtime_error("bad name " + word);
        for (char c : label)
            if (!((c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '-'))
                throw std::runtime_error("bad name " + word);
        name.labels.push_back(label);
    }
    if (origin && !absolute) name.labels.insert(name.labels.end(), origin->labels.begin(), origin->labels.end());
    return name;
}

int require_type(const std::string& word) {
    auto found = std::find(types.begin(), types.end(), word);
    if (found == types.end()) throw std::runtime_error("bad type " + word);
    return static_cast<int>(found - types.begin());
}

int ttl_value(const std::string& word) {
    std::optional<int> integer = decimal(word);
    long long total = 0;
    bool valid = true;
    if (integer) total = *integer;
    else {
        static const std::string units = "wdhms";
        static const std::array<int, 5> seconds{604800, 86400, 3600, 60, 1};
        std::size_t position = 0;
        int previous = -1;
        while (position < word.size()) {
            std::size_t start = position;
            while (position < word.size() && word[position] >= '0' && word[position] <= '9') ++position;
            std::optional<int> number = decimal(word.substr(start, position - start), 3);
            if (!number || position == word.size()) {
                valid = false;
                break;
            }
            char unit = lower(word.substr(position++, 1))[0];
            std::size_t index = units.find(unit);
            if (index == std::string::npos || static_cast<int>(index) <= previous) {
                valid = false;
                break;
            }
            previous = static_cast<int>(index);
            total += static_cast<long long>(*number) * seconds[index];
        }
    }
    if (!valid || total < 1 || total > 604800) throw std::runtime_error("bad ttl " + word);
    return static_cast<int>(total);
}

struct Record {
    Name owner;
    int ttl = 0, type = 0;
    Address ipv4 = 0;
    Address6 ipv6{};
    Name target, rname;
    int preference = 0;
    std::vector<int> numbers;
    std::string text_data;

    std::string data() const {
        if (type == 0) return address_text(ipv4);
        if (type == 7) return address_text(ipv6);
        if (type == 5) return std::to_string(preference) + " " + target.text();
        if (type == 6) return text_data;
        if (type != 3) return target.text();
        std::string result = target.text() + " " + rname.text();
        for (int number : numbers) result += " " + std::to_string(number);
        return result;
    }
    std::string line() const { return owner.text() + " " + std::to_string(ttl) + " " + types[type] + " " + data(); }
};

bool data_less(const Record& a, const Record& b) {
    if (a.type == 0) return a.ipv4 < b.ipv4;
    if (a.type == 7) return a.ipv6 < b.ipv6;
    if (a.type == 6) return a.text_data < b.text_data;
    if (a.type == 5 && a.preference != b.preference) return a.preference < b.preference;
    if (a.target != b.target) return a.target < b.target;
    if (a.type == 3) {
        if (a.rname != b.rname) return a.rname < b.rname;
        return a.numbers < b.numbers;
    }
    return false;
}

bool record_less(const Record& a, const Record& b) {
    if (a.owner != b.owner) return a.owner < b.owner;
    if (a.type != b.type) return a.type < b.type;
    return data_less(a, b);
}

struct Zone {
    Name origin;
    Address server;
    int line;
    std::vector<Record> records;
};
struct Response {
    std::string kind;
    std::vector<Record> answer, authority, additional;
    Name referral;
    explicit Response(std::string kind) : kind(std::move(kind)) {}
    std::string description() const {
        if (kind == "REFERRAL") return kind + " " + referral.text();
        if (kind == "CNAME") return kind + " " + answer.front().target.text();
        return kind;
    }
};
struct Entry {
    std::string kind;
    std::vector<Record> records;
    int expiry;
};
struct Resolution {
    std::string status;
    std::vector<Record> answer;
};
using Key = std::pair<Name, int>;

class Resolver {
    std::vector<Address> roots;
    std::vector<Zone> zones;
    std::optional<std::size_t> current;
    std::set<Address> down;
    std::map<Key, Entry> cache;
    int clock = 0, minttl = 1, maxttl = 86400, negttl = 3600, hits = 0;
    std::map<Address, std::array<int, 7>> queries;
    std::map<std::string, int> resolutions;

    bool known(Address server) const {
        return std::any_of(zones.begin(), zones.end(), [server](const Zone& zone) { return zone.server == server; });
    }
    std::vector<Record> records(const Zone& zone, const Name& owner, std::optional<int> type = std::nullopt) const {
        std::vector<Record> result;
        for (const Record& record : zone.records) if (record.owner == owner && (!type || record.type == *type)) result.push_back(record);
        std::sort(result.begin(), result.end(), record_less);
        return result;
    }
    bool exists(const Zone& zone, const Name& name) const {
        return std::any_of(zone.records.begin(), zone.records.end(), [&](const Record& record) { return below(record.owner, name); });
    }
    Response negative(const Zone& zone, const std::string& kind) const {
        Response result(kind);
        for (const Record& record : zone.records) if (record.type == 3) {
            result.authority.push_back(record);
            break;
        }
        return result;
    }
    Response authoritative(Address server, const Name& name, int type, const Name& cut) const {
        if (down.count(server) || !known(server)) return Response("TIMEOUT");
        const Zone* chosen = nullptr;
        for (const Zone& zone : zones)
            if (zone.server == server && below(name, zone.origin) && (!chosen || zone.origin.labels.size() > chosen->origin.labels.size())) chosen = &zone;
        if (!chosen || chosen->origin.labels.size() < cut.labels.size()) return Response("LAME");
        const Zone& zone = *chosen;
        for (std::size_t length = zone.origin.labels.size() + 1; length <= name.labels.size(); ++length) {
            Name ancestor = name.suffix(length);
            std::vector<Record> nameservers = records(zone, ancestor, 1);
            if (nameservers.empty()) continue;
            Response result("REFERRAL");
            result.referral = ancestor;
            result.authority = nameservers;
            for (const Record& ns : nameservers) {
                std::vector<Record> glue = records(zone, ns.target, 0);
                result.additional.insert(result.additional.end(), glue.begin(), glue.end());
            }
            return result;
        }
        std::vector<Record> candidates = records(zone, name);
        if (candidates.empty()) {
            if (exists(zone, name)) return negative(zone, "NODATA");
            Name ancestor;
            for (std::size_t removed = 1; removed <= name.labels.size(); ++removed) {
                ancestor = name.suffix(name.labels.size() - removed);
                if (exists(zone, ancestor)) break;
            }
            Name wildcard = ancestor;
            wildcard.labels.insert(wildcard.labels.begin(), "*");
            candidates = records(zone, wildcard);
            if (candidates.empty()) return negative(zone, "NXDOMAIN");
        }
        Response result("ANSWER");
        for (Record record : candidates) if (record.type == type) {
            record.owner = name;
            result.answer.push_back(std::move(record));
        }
        if (!result.answer.empty()) return result;
        if (type != 2) for (Record record : candidates) if (record.type == 2) {
            result.kind = "CNAME";
            record.owner = name;
            result.answer.push_back(std::move(record));
            return result;
        }
        return negative(zone, "NODATA");
    }
    Response ask(Address server, const Name& name, int type, const Name& cut) {
        Response result = authoritative(server, name, type, cut);
        auto found = std::find(response_kinds.begin(), response_kinds.end(), result.kind);
        ++queries[server][static_cast<std::size_t>(found - response_kinds.begin())];
        return result;
    }
    void trace(int depth, const std::string& text) const { std::cout << std::string(2 * (depth + 1), ' ') << text << '\n'; }
    std::vector<Record> cached_records(const Entry& entry) const {
        std::vector<Record> result = entry.records;
        for (Record& record : result) record.ttl = entry.expiry - clock;
        return result;
    }
    int store(std::vector<Record> records) {
        int ttl = records.front().ttl;
        for (const Record& record : records) ttl = std::min(ttl, record.ttl);
        ttl = std::min(std::max(ttl, minttl), maxttl);
        std::sort(records.begin(), records.end(), data_less);
        Key key{records.front().owner, records.front().type};
        cache[key] = {"POS", std::move(records), clock + ttl};
        return ttl;
    }
    std::optional<Response> query_servers(const Name& name, int type, const Name& cut,
                                        const std::optional<std::vector<Name>>& nameservers,
                                        int depth, std::vector<Key>& resolving) {
        auto query = [&](Address address) -> std::optional<Response> {
            Response result = ask(address, name, type, cut);
            trace(depth, "ASK " + address_text(address) + " " + name.text() + " " + types[type] + " -> " + result.description());
            if (result.kind == "LAME" || result.kind == "TIMEOUT") return std::nullopt;
            return result;
        };
        if (!nameservers) {
            for (Address address : roots) {
                std::optional<Response> result = query(address);
                if (result) return result;
            }
        } else {
            std::vector<Name> ordered = *nameservers;
            std::sort(ordered.begin(), ordered.end());
            for (const Name& host : ordered) {
                std::set<Address> addresses;
                auto cached = cache.find({host, 0});
                if (cached != cache.end() && cached->second.kind == "POS") {
                    for (const Record& record : cached->second.records) addresses.insert(record.ipv4);
                } else if (std::find(resolving.begin(), resolving.end(), Key{host, 0}) != resolving.end()) {
                    trace(depth, "GLUELESS " + host.text() + " -> LOOP");
                } else {
                    trace(depth, "GLUELESS " + host.text());
                    Resolution result = resolve(host, 0, depth + 1, resolving);
                    if (result.status == "NOERROR") for (const Record& record : result.answer) if (record.type == 0) addresses.insert(record.ipv4);
                }
                for (Address address : addresses) {
                    std::optional<Response> result = query(address);
                    if (result) return result;
                }
            }
        }
        return std::nullopt;
    }
    Response lookup(const Name& name, int type, int depth, std::vector<Key>& resolving) {
        auto cache_hit = [&](Response result) {
            ++hits;
            trace(depth, "CACHE HIT " + name.text() + " " + types[type] + " -> " + result.description());
            return result;
        };
        auto exact = cache.find({name, type});
        if (exact != cache.end()) {
            Response result(exact->second.kind == "POS" ? "ANSWER" : exact->second.kind);
            if (exact->second.kind == "POS") result.answer = cached_records(exact->second);
            return cache_hit(std::move(result));
        }
        for (const auto& entry : cache)
            if (entry.second.kind == "NXDOMAIN" && below(name, entry.first.first)) return cache_hit(Response("NXDOMAIN"));
        if (type != 2) {
            auto cname = cache.find({name, 2});
            if (cname != cache.end() && cname->second.kind == "POS") {
                Response result("CNAME");
                result.answer = cached_records(cname->second);
                return cache_hit(std::move(result));
            }
        }
        Name cut;
        std::optional<std::vector<Name>> nameservers;
        for (const auto& entry : cache) {
            if (entry.first.second == 1 && entry.second.kind == "POS" && below(name, entry.first.first) &&
                (!nameservers || entry.first.first.labels.size() > cut.labels.size())) {
                cut = entry.first.first;
                nameservers.emplace();
                for (const Record& record : entry.second.records) nameservers->push_back(record.target);
            }
        }
        if (nameservers) {
            ++hits;
            trace(depth, "CACHE HIT " + name.text() + " " + types[type] + " -> REFERRAL " + cut.text());
        }
        while (true) {
            std::optional<Response> obtained = query_servers(name, type, cut, nameservers, depth, resolving);
            if (!obtained) return Response("SERVFAIL no server for " + cut.text());
            Response result = std::move(*obtained);
            if (result.kind == "REFERRAL") {
                store(result.authority);
                std::map<Name, std::vector<Record>> glue;
                for (const Record& record : result.additional) glue[record.owner].push_back(record);
                for (const auto& entry : glue) store(entry.second);
                cut = result.referral;
                nameservers.emplace();
                for (const Record& record : result.authority) nameservers->push_back(record.target);
            } else if (result.kind == "ANSWER" || result.kind == "CNAME") {
                int ttl = store(result.answer);
                for (Record& record : result.answer) record.ttl = ttl;
                return result;
            } else {
                const Record& soa = result.authority.front();
                int ttl = std::min({soa.ttl, soa.numbers.back(), negttl});
                cache[{name, type}] = {result.kind, {}, clock + ttl};
                return result;
            }
        }
    }
    Resolution resolve(const Name& name, int type, int depth, std::vector<Key>& resolving) {
        resolving.emplace_back(name, type);
        std::vector<Record> chain;
        std::set<Name> seen{name};
        Name current_name = name;
        Resolution resolution;
        while (true) {
            Response result = lookup(current_name, type, depth, resolving);
            if (result.kind == "CNAME") {
                const Record& cname = result.answer.front();
                chain.push_back(cname);
                if (seen.count(cname.target)) {
                    resolution.status = "SERVFAIL cname loop";
                    break;
                }
                if (chain.size() == 9) {
                    resolution.status = "SERVFAIL cname chain too long";
                    break;
                }
                seen.insert(cname.target);
                current_name = cname.target;
            } else {
                resolution.status = result.kind == "ANSWER" ? "NOERROR" : result.kind;
                if (resolution.status.compare(0, 8, "SERVFAIL") != 0) {
                    resolution.answer = std::move(chain);
                    if (result.kind == "ANSWER") resolution.answer.insert(resolution.answer.end(), result.answer.begin(), result.answer.end());
                }
                break;
            }
        }
        resolving.pop_back();
        ++resolutions[resolution.status.compare(0, 8, "SERVFAIL") == 0 ? "SERVFAIL" : resolution.status];
        return resolution;
    }
    Resolution resolve(const Name& name, int type) {
        std::vector<Key> resolving;
        return resolve(name, type, 0, resolving);
    }
    void write_result(const Resolution& result) const {
        for (const Record& record : result.answer) std::cout << "answer " << record.line() << '\n';
        std::cout << "status " << result.status << '\n';
    }
    void addresses(const Name& host, const std::string& prefix) {
        Resolution a = resolve(host, 0), aaaa = resolve(host, 7);
        std::vector<std::string> result;
        if (a.status == "NOERROR") for (const Record& record : a.answer) if (record.type == 0) result.push_back(address_text(record.ipv4));
        if (aaaa.status == "NOERROR") for (const Record& record : aaaa.answer) if (record.type == 7) result.push_back(address_text(record.ipv6));
        std::cout << prefix << host.text() << " -> " << (result.empty() ? "no address" : join(result, " ")) << '\n';
    }

    void add_zone_line(const std::vector<std::string>& w, int line) {
        if (w[0] == "ROOT") {
            std::vector<Address> added;
            for (std::size_t i = 1; i < w.size(); ++i) {
                Address address = require_address(w[i]);
                if (std::find(roots.begin(), roots.end(), address) != roots.end() ||
                    std::find(added.begin(), added.end(), address) != added.end()) throw std::runtime_error("duplicate root " + w[i]);
                added.push_back(address);
            }
            roots.insert(roots.end(), added.begin(), added.end());
            return;
        }
        if (w[0] == "ZONE") {
            current.reset();
            Name origin = require_name(w[1]);
            Address server = require_address(w[2]);
            for (const Zone& zone : zones)
                if (zone.origin == origin && zone.server == server)
                    throw std::runtime_error("duplicate zone " + origin.text() + " at " + w[2]);
            zones.push_back({origin, server, line, {}});
            current = zones.size() - 1;
            return;
        }
        if (!current) throw std::runtime_error("no current zone");
        Zone& zone = zones[*current];
        Record record;
        record.owner = require_name(w[0], true, &zone.origin);
        if (!below(record.owner, zone.origin)) throw std::runtime_error("out of zone " + record.owner.text());
        record.ttl = ttl_value(w[1]);
        record.type = require_type(w[2]);
        std::size_t count = w.size() - 3;
        std::size_t expected = record.type == 5 ? 2 : record.type == 3 ? 7 : 1;
        if (record.type != 6 && count != expected) throw std::runtime_error("wrong field count");
        if (record.type == 0) record.ipv4 = require_address(w[3]);
        else if (record.type == 7) {
            std::optional<Address6> address = address6(w[3]);
            if (!address) throw std::runtime_error("bad address " + w[3]);
            record.ipv6 = *address;
        } else if (record.type == 1 || record.type == 2 || record.type == 4) record.target = require_name(w[3], false, &zone.origin);
        else if (record.type == 5) {
            std::optional<int> preference = decimal(w[3]);
            if (!preference || *preference > 65535) throw std::runtime_error("bad preference " + w[3]);
            record.preference = *preference;
            record.target = require_name(w[4], false, &zone.origin);
        } else if (record.type == 6) {
            record.text_data = join(std::vector<std::string>(w.begin() + 3, w.end()), " ");
            const std::string& text = record.text_data;
            if (text.size() < 2 || text.front() != '"' || text.back() != '"' || text.find('"', 1) != text.size() - 1)
                throw std::runtime_error("bad text " + text);
        } else {
            record.target = require_name(w[3], false, &zone.origin);
            record.rname = require_name(w[4], false, &zone.origin);
            for (std::size_t i = 5; i <= 8; ++i) {
                std::optional<int> number = decimal(w[i]);
                if (!number) throw std::runtime_error("bad number " + w[i]);
                record.numbers.push_back(*number);
            }
            std::optional<int> minimum = decimal(w[9]);
            if (!minimum || *minimum < 1 || *minimum > 86400) throw std::runtime_error("bad minimum " + w[9]);
            record.numbers.push_back(*minimum);
        }
        if (record.type == 1 && !record.owner.labels.empty() && record.owner.labels[0] == "*") throw std::runtime_error("ns at wildcard");
        if (record.type == 3 && record.owner != zone.origin) throw std::runtime_error("soa not at origin");
        if (record.type == 3 && std::any_of(zone.records.begin(), zone.records.end(), [](const Record& r) { return r.type == 3; }))
            throw std::runtime_error("duplicate soa");
        for (const Record& existing : zone.records)
            if (existing.owner == record.owner && existing.type == record.type && !data_less(existing, record) && !data_less(record, existing))
                throw std::runtime_error("duplicate record");
        for (const Record& existing : zone.records)
            if (existing.owner == record.owner && (record.type == 2 || existing.type == 2))
                throw std::runtime_error("cname conflict " + record.owner.text());
        zone.records.push_back(std::move(record));
    }

    void execute(const std::vector<std::string>& w) {
        const std::string& command = w[0];
        if (command == "RESOLVE" || command == "MX") {
            Name name = require_name(w[1], true);
            int type = command == "MX" ? 5 : require_type(w[2]);
            std::cout << (command == "MX" ? "mx " : "resolve ") << name.text();
            if (command != "MX") std::cout << ' ' << types[type];
            std::cout << '\n';
            Resolution result = resolve(name, type);
            write_result(result);
            if (command == "MX") {
                if (result.status == "NOERROR") for (const Record& record : result.answer) if (record.type == 5) {
                    if (record.target.labels.empty()) std::cout << "exchange " << record.preference << " . -> null\n";
                    else addresses(record.target, "exchange " + std::to_string(record.preference) + " ");
                }
                if (result.status == "NODATA") {
                    Name host = name;
                    for (const Record& record : result.answer) if (record.type == 2) host = record.target;
                    addresses(host, "implicit ");
                }
            }
        } else if (command == "REVERSE") {
            Name name;
            std::string address;
            if (w[1].find(':') == std::string::npos) {
                Address value = require_address(w[1]);
                address = address_text(value);
                std::vector<std::string> parts = split(address, '.');
                std::reverse(parts.begin(), parts.end());
                name = require_name(join(parts, ".") + ".in-addr.arpa.");
            } else {
                std::optional<Address6> value = address6(w[1]);
                if (!value) throw std::runtime_error("bad address " + w[1]);
                address = address_text(*value);
                std::ostringstream digits;
                digits << std::hex << std::setfill('0');
                for (unsigned group : *value) digits << std::setw(4) << group;
                std::string reversed;
                std::string raw = digits.str();
                for (auto i = raw.rbegin(); i != raw.rend(); ++i) {
                    reversed += *i;
                    reversed += '.';
                }
                name = require_name(reversed + "ip6.arpa.");
            }
            std::cout << "reverse " << address << ' ' << name.text() << '\n';
            write_result(resolve(name, 4));
        } else if (command == "QUERY" || command == "DUMP") {
            Address server = require_address(w[1]);
            Name name = require_name(w[2], command == "QUERY");
            if (command == "QUERY") {
                int type = require_type(w[3]);
                Response result = ask(server, name, type, Name{});
                std::cout << "query " << address_text(server) << ' ' << name.text() << ' ' << types[type] << " -> " << result.description() << '\n';
                for (const Record& record : result.answer) std::cout << "answer " << record.line() << '\n';
                for (const Record& record : result.authority) std::cout << "authority " << record.line() << '\n';
                for (const Record& record : result.additional) std::cout << "additional " << record.line() << '\n';
            } else {
                std::string prefix = "dump " + address_text(server) + " " + name.text();
                if (down.count(server) || !known(server)) {
                    std::cout << prefix << " -> TIMEOUT\n";
                    return;
                }
                for (const Zone& zone : zones) if (zone.server == server && zone.origin == name) {
                    std::vector<Record> ordered = zone.records;
                    std::sort(ordered.begin(), ordered.end(), record_less);
                    std::cout << prefix << " records=" << ordered.size() << '\n';
                    for (const Record& record : ordered) std::cout << "  " << record.line() << '\n';
                    return;
                }
                std::cout << prefix << " -> REFUSED\n";
            }
        } else if (command == "DOWN" || command == "UP") {
            Address server = require_address(w[1]);
            if (command == "DOWN" && down.count(server)) throw std::runtime_error("server " + w[1] + " already down");
            if (command == "UP" && !down.count(server)) throw std::runtime_error("server " + w[1] + " not down");
            if (command == "DOWN") down.insert(server);
            else down.erase(server);
            std::cout << lower(command) << ' ' << address_text(server) << '\n';
        } else if (command == "SET") {
            if (w[1] != "MINTTL" && w[1] != "MAXTTL" && w[1] != "NEGTTL") throw std::runtime_error("bad setting " + w[1]);
            std::optional<int> value = decimal(w[2]);
            if (!value || *value < 1 || *value > 604800) throw std::runtime_error("bad value " + w[2]);
            if ((w[1] == "MINTTL" && *value > maxttl) || (w[1] == "MAXTTL" && *value < minttl))
                throw std::runtime_error("minttl above maxttl");
            if (w[1] == "MINTTL") minttl = *value;
            else if (w[1] == "MAXTTL") maxttl = *value;
            else negttl = *value;
            std::cout << "set " << w[1] << '=' << *value << '\n';
        } else if (command == "TIME") {
            std::optional<int> seconds = decimal(w[1]);
            if (!seconds || *seconds < 1 || *seconds > 1000000) throw std::runtime_error("bad time " + w[1]);
            clock += *seconds;
            std::size_t removed = 0;
            for (auto it = cache.begin(); it != cache.end();) {
                if (it->second.expiry <= clock) {
                    it = cache.erase(it);
                    ++removed;
                }
                else ++it;
            }
            std::cout << "time now=" << clock << " expired=" << removed << '\n';
        } else if (command == "CACHE" || command == "FLUSH") {
            std::optional<Name> name;
            if (w.size() > 1) name = require_name(w[1]);
            std::vector<Key> selected;
            for (const auto& entry : cache) if (!name || below(entry.first.first, *name)) selected.push_back(entry.first);
            if (command == "FLUSH") {
                for (const Key& key : selected) cache.erase(key);
                std::cout << "flush removed=" << selected.size() << '\n';
            } else {
                std::cout << "cache entries=" << selected.size() << '\n';
                for (const Key& key : selected) {
                    const Entry& entry = cache.at(key);
                    if (entry.kind == "POS") for (const Record& record : cached_records(entry)) std::cout << "  " << record.line() << '\n';
                    else std::cout << "  " << key.first.text() << ' ' << entry.expiry - clock << ' ' << types[key.second] << ' ' << entry.kind << '\n';
                }
            }
        } else if (command == "STATS") {
            int total = 0;
            for (const auto& entry : queries) for (int count : entry.second) total += count;
            std::cout << "stats queries=" << total << " hits=" << hits << '\n';
            for (const auto& entry : queries) {
                int sent = 0;
                for (int count : entry.second) sent += count;
                std::cout << "  " << address_text(entry.first) << " sent=" << sent;
                for (std::size_t i = 0; i < response_kinds.size(); ++i)
                    std::cout << ' ' << lower(response_kinds[i]) << '=' << entry.second[i];
                std::cout << '\n';
            }
            std::cout << "resolutions noerror=" << resolutions["NOERROR"] << " nodata=" << resolutions["NODATA"]
                      << " nxdomain=" << resolutions["NXDOMAIN"] << " servfail=" << resolutions["SERVFAIL"] << '\n';
        }
    }
public:
    void zone_line(const std::string& line, int number) {
        try { add_zone_line(split(line, ' '), number); }
        catch (const std::runtime_error& error) { std::cout << "error line " << number << ": " << error.what() << '\n'; }
    }
    void finish_zones() {
        std::vector<Zone> valid;
        std::size_t total = 0;
        for (Zone& zone : zones) {
            bool soa = std::any_of(zone.records.begin(), zone.records.end(), [](const Record& record) { return record.type == 3; });
            if (!soa) std::cout << "error line " << zone.line << ": zone " << zone.origin.text() << " at " << address_text(zone.server) << " has no soa\n";
            else {
                std::cout << "zone " << zone.origin.text() << " at " << address_text(zone.server) << " records=" << zone.records.size() << '\n';
                total += zone.records.size();
                valid.push_back(std::move(zone));
            }
        }
        zones = std::move(valid);
        current.reset();
        std::cout << "loaded roots=" << roots.size() << " zones=" << zones.size() << " records=" << total << '\n';
    }
    void command(const std::string& line, int number) {
        try { execute(split(line, ' ')); }
        catch (const std::runtime_error& error) { std::cout << "error line " << number << ": " << error.what() << '\n'; }
    }
};

int main() {
    Resolver resolver;
    std::string line;
    int number = 0;
    while (std::getline(std::cin, line)) {
        ++number;
        if (line == "END ZONES") break;
        resolver.zone_line(line, number);
    }
    resolver.finish_zones();
    while (std::getline(std::cin, line)) {
        ++number;
        if (line == "END") break;
        resolver.command(line, number);
    }
}
