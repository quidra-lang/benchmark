#include <algorithm>
#include <cstdint>
#include <iomanip>
#include <iostream>
#include <map>
#include <optional>
#include <regex>
#include <set>
#include <sstream>
#include <stdexcept>
#include <string>
#include <tuple>
#include <utility>
#include <vector>

using Pairs = std::vector<std::pair<std::string, std::string>>;
using Headers = std::map<std::string, std::string>;

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

std::string trim(const std::string& text) {
    std::size_t first = text.find_first_not_of(' ');
    if (first == std::string::npos) return "";
    return text.substr(first, text.find_last_not_of(' ') - first + 1);
}

std::string lower(std::string text) {
    for (char& c : text) if (c >= 'A' && c <= 'Z') c += 'a' - 'A';
    return text;
}

template <class Collection>
std::string join(const Collection& parts, const std::string& separator) {
    std::string result;
    bool first = true;
    for (const std::string& part : parts) {
        if (!first) result += separator;
        first = false;
        result += part;
    }
    return result;
}

bool matches(const std::string& text, const std::string& pattern) {
    return std::regex_match(text, std::regex(pattern));
}

bool valid_name(const std::string& name) { return matches(name, "[a-z][a-z0-9_]{0,19}"); }
bool media_type(const std::string& text) { return matches(text, "[a-z0-9.+-]+/[a-z0-9.+-]+"); }
bool unreserved(char c) {
    return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') ||
           std::string("-._~").find(c) != std::string::npos;
}

bool segment(const std::string& text) {
    return !text.empty() && text != "." && text != ".." &&
           std::all_of(text.begin(), text.end(), unreserved);
}

bool canonical_path(const std::string& path) {
    if (path == "/") return true;
    if (path.empty() || path[0] != '/') return false;
    for (const std::string& part : split(path.substr(1), '/')) if (!segment(part)) return false;
    return true;
}

bool decimal_between(const std::string& text, int low, int high) {
    if (!matches(text, "0|[1-9][0-9]*")) return false;
    int value = 0;
    for (char c : text) {
        if (value > high / 10 || (value == high / 10 && c - '0' > high % 10)) return false;
        value = value * 10 + c - '0';
    }
    return value >= low;
}

int hex_digit(char c) {
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    return -1;
}

bool valid_escapes(const std::string& text) {
    for (std::size_t i = 0; i < text.size(); ++i) {
        if (text[i] != '%') continue;
        if (i + 2 >= text.size() || hex_digit(text[i + 1]) < 0 || hex_digit(text[i + 2]) < 0) return false;
        int code = hex_digit(text[i + 1]) * 16 + hex_digit(text[i + 2]);
        if (code < 32 || code > 126) return false;
        i += 2;
    }
    return true;
}

std::string decode(const std::string& text) {
    std::string result;
    for (std::size_t i = 0; i < text.size(); ++i) {
        if (text[i] == '%') {
            result += static_cast<char>(hex_digit(text[i + 1]) * 16 + hex_digit(text[i + 2]));
            i += 2;
        } else result += text[i];
    }
    return result;
}

std::string decode_form(std::string text) {
    std::replace(text.begin(), text.end(), '+', ' ');
    return decode(text);
}

std::string encode(const std::string& text) {
    static const char* digits = "0123456789ABCDEF";
    std::string result;
    for (unsigned char c : text) {
        if (unreserved(static_cast<char>(c))) result += static_cast<char>(c);
        else {
            result += '%';
            result += digits[c >> 4];
            result += digits[c & 15];
        }
    }
    return result;
}

std::string encoded_pairs(const Pairs& pairs) {
    std::vector<std::string> values;
    for (const auto& pair : pairs) values.push_back(encode(pair.first) + "=" + encode(pair.second));
    return join(values, "&");
}

std::string normalize(const std::string& path) {
    std::string changed;
    static const char* digits = "0123456789ABCDEF";
    for (std::size_t i = 0; i < path.size(); ++i) {
        if (path[i] != '%') {
            changed += path[i];
            continue;
        }
        int code = hex_digit(path[i + 1]) * 16 + hex_digit(path[i + 2]);
        if (unreserved(static_cast<char>(code))) changed += static_cast<char>(code);
        else {
            changed += '%';
            changed += digits[code >> 4];
            changed += digits[code & 15];
        }
        i += 2;
    }
    std::vector<std::string> stack;
    for (const std::string& part : split(changed.substr(1), '/')) {
        if (part.empty() || part == ".") continue;
        if (part == "..") { if (!stack.empty()) stack.pop_back(); }
        else stack.push_back(part);
    }
    return "/" + join(stack, "/");
}

enum class PieceKind { Literal, Untyped, Int, Slug, Wildcard };
struct Piece {
    PieceKind kind;
    std::string text;
    bool fits(const std::string& value) const {
        if (kind == PieceKind::Literal) return text == value;
        if (kind == PieceKind::Int) return matches(value, "[0-9]{1,9}");
        if (kind == PieceKind::Slug) return matches(value, "[a-z0-9-]+");
        return true;
    }
    bool accepts(const std::string& value) const {
        if (kind == PieceKind::Untyped) return !value.empty() && value != "." && value != "..";
        if (kind == PieceKind::Wildcard) {
            if (value.empty()) return true;
            for (const std::string& part : split(value, '/'))
                if (part.empty() || part == "." || part == "..") return false;
            return true;
        }
        return fits(value);
    }
};

std::optional<std::vector<Piece>> parse_pattern(const std::string& pattern) {
    if (pattern.empty() || pattern[0] != '/') return std::nullopt;
    std::vector<Piece> pieces;
    if (pattern == "/") return pieces;
    std::set<std::string> parameters;
    std::vector<std::string> parts = split(pattern.substr(1), '/');
    for (std::size_t i = 0; i < parts.size(); ++i) {
        const std::string& text = parts[i];
        if (segment(text)) {
            pieces.push_back({PieceKind::Literal, text});
            continue;
        }
        if (text.size() < 3 || text.front() != '{' || text.back() != '}') return std::nullopt;
        std::string inner = text.substr(1, text.size() - 2), name = inner;
        PieceKind kind = PieceKind::Untyped;
        if (!inner.empty() && inner[0] == '*') {
            if (i + 1 != parts.size()) return std::nullopt;
            name = inner.substr(1);
            kind = PieceKind::Wildcard;
        } else {
            std::size_t colon = inner.find(':');
            if (colon != std::string::npos) {
                name = inner.substr(0, colon);
                std::string type = inner.substr(colon + 1);
                if (type == "int") kind = PieceKind::Int;
                else if (type == "slug") kind = PieceKind::Slug;
                else return std::nullopt;
            }
        }
        if (!valid_name(name) || !parameters.insert(name).second) return std::nullopt;
        pieces.push_back({kind, name});
    }
    return pieces;
}

struct Route {
    std::string name, pattern, role;
    std::set<std::string> methods;
    std::vector<Piece> pieces;
    std::vector<std::string> types;
    int selections = 0;

    bool wildcard() const { return !pieces.empty() && pieces.back().kind == PieceKind::Wildcard; }
    int literal_count() const {
        return static_cast<int>(std::count_if(pieces.begin(), pieces.end(), [](const Piece& p) { return p.kind == PieceKind::Literal; }));
    }
    int typed_count() const {
        return static_cast<int>(std::count_if(pieces.begin(), pieces.end(), [](const Piece& p) {
            return p.kind == PieceKind::Int || p.kind == PieceKind::Slug;
        }));
    }
    bool matches_path(const std::vector<std::string>& segments) const {
        std::size_t count = pieces.size() - (wildcard() ? 1 : 0);
        if (segments.size() < count || (!wildcard() && segments.size() != count)) return false;
        for (std::size_t i = 0; i < count; ++i) if (!pieces[i].fits(segments[i])) return false;
        return true;
    }
    Pairs parameters(const std::vector<std::string>& segments) const {
        Pairs result;
        for (std::size_t i = 0; i < pieces.size(); ++i) {
            const Piece& piece = pieces[i];
            if (piece.kind == PieceKind::Literal) continue;
            std::string value;
            if (piece.kind == PieceKind::Wildcard) {
                std::vector<std::string> rest;
                for (std::size_t j = i; j < segments.size(); ++j) rest.push_back(decode(segments[j]));
                value = join(rest, "/");
            } else if (piece.kind == PieceKind::Int) value = std::to_string(std::stoi(segments[i]));
            else value = piece.kind == PieceKind::Untyped ? decode(segments[i]) : segments[i];
            result.emplace_back(piece.text, value);
        }
        std::sort(result.begin(), result.end());
        return result;
    }
};

struct RulePath {
    std::string base;
    bool prefix;
};
std::optional<RulePath> rule_path(const std::string& text) {
    if (canonical_path(text)) return RulePath{text, false};
    if (text.size() > 2 && text.compare(text.size() - 2, 2, "/*") == 0) {
        std::string base = text.substr(0, text.size() - 2);
        if (base != "/" && canonical_path(base)) return RulePath{base, true};
    }
    return std::nullopt;
}
struct Redirect {
    std::string from, source, target;
    bool prefix;
    int code;
};
struct Client {
    int level = 0, last_time = 0, allowed = 0, limited = 0;
    bool initialized = false;
};

struct Response {
    int status;
    std::string body;
    Headers headers;
    std::string type = "text/plain";
    Response(int status, std::string body = "", Headers headers = {}, std::string type = "text/plain")
        : status(status), body(std::move(body)), headers(std::move(headers)), type(std::move(type)) {}
};

std::string quoted(const std::string& text) {
    std::string result = "\"";
    for (char c : text) {
        if (c == '\\' || c == '"') result += '\\';
        result += c;
    }
    return result + '"';
}

std::string html(const std::string& text) {
    std::string result;
    for (char c : text) {
        if (c == '&') result += "&amp;";
        else if (c == '<') result += "&lt;";
        else if (c == '>') result += "&gt;";
        else if (c == '"') result += "&quot;";
        else result += c;
    }
    return result;
}

Pairs query_pairs(const std::optional<std::string>& query) {
    Pairs pairs;
    if (!query) return pairs;
    for (const std::string& part : split(*query, '&')) {
        if (part.empty()) continue;
        std::size_t equals = part.find('=');
        pairs.emplace_back(decode_form(part.substr(0, equals)),
                           equals == std::string::npos ? "" : decode_form(part.substr(equals + 1)));
    }
    return pairs;
}

Pairs cookie_pairs(const Headers& headers) {
    auto found = headers.find("cookie");
    if (found == headers.end()) return {};
    std::map<std::string, std::string> values;
    for (const std::string& raw : split(found->second, ';')) {
        std::string part = trim(raw);
        std::size_t equals = part.find('=');
        if (equals == std::string::npos || equals == 0) continue;
        values.emplace(part.substr(0, equals), part.substr(equals + 1));
    }
    return Pairs(values.begin(), values.end());
}

std::string json_pairs(const Pairs& pairs, bool array) {
    std::vector<std::string> items;
    for (const auto& pair : pairs) {
        std::string item = quoted(pair.first) + (array ? "," : ":") + quoted(pair.second);
        items.push_back(array ? "[" + item + "]" : item);
    }
    return std::string(array ? "[" : "{") + join(items, ",") + (array ? "]" : "}");
}

std::string body_for(const std::string& type, const std::string& route, const Pairs& parameters,
                     const Pairs& query, const Pairs& cookies) {
    if (type == "application/json")
        return "{\"route\":" + quoted(route) + ",\"params\":" + json_pairs(parameters, false) +
               ",\"query\":" + json_pairs(query, true) + ",\"cookies\":" + json_pairs(cookies, false) + "}";
    if (type == "text/html") {
        std::string body = "<dl><dt>route</dt><dd>" + html(route) + "</dd>";
        auto append = [&](const Pairs& pairs, const std::string& kind) {
            for (const auto& pair : pairs)
                body += "<dt>" + kind + " " + html(pair.first) + "</dt><dd>" + html(pair.second) + "</dd>";
        };
        append(parameters, "param");
        append(query, "query");
        append(cookies, "cookie");
        return body + "</dl>";
    }
    auto list = [](const Pairs& pairs) { return pairs.empty() ? "-" : encoded_pairs(pairs); };
    return "route=" + route + " params=" + list(parameters) + " query=" + list(query) + " cookies=" + list(cookies);
}

std::string etag_for(const std::string& body) {
    std::uint32_t a = 1, b = 0;
    for (unsigned char c : body) {
        a = (a + c) % 65521;
        b = (b + a) % 65521;
    }
    std::ostringstream result;
    result << '"' << std::hex << std::setfill('0') << std::setw(4) << b << std::setw(4) << a << '"';
    return result.str();
}

std::optional<std::string> negotiate(const std::vector<std::string>& types, const Headers& headers) {
    auto accept = headers.find("accept");
    if (accept == headers.end()) return types.front();
    struct Range {
        std::string text;
        int specificity, weight;
    };
    std::vector<Range> ranges;
    for (const std::string& element : split(accept->second, ',')) {
        std::vector<std::string> parts = split(element, ';');
        std::string range = lower(trim(parts[0]));
        int specificity = range == "*/*" ? 1 : matches(range, "[a-z0-9.+-]+/\\*") ? 2 : media_type(range) ? 3 : 0;
        if (!specificity) continue;
        int weight = 1000;
        bool valid = true;
        for (std::size_t i = 1; i < parts.size(); ++i) {
            std::size_t equals = parts[i].find('=');
            if (equals == std::string::npos || lower(trim(parts[i].substr(0, equals))) != "q") continue;
            std::string q = trim(parts[i].substr(equals + 1));
            if (!matches(q, "0(\\.[0-9]{0,3})?|1(\\.0{0,3})?")) valid = false;
            else {
                weight = (q[0] - '0') * 1000;
                int place = 100;
                for (std::size_t j = 2; j < q.size(); ++j) {
                    weight += (q[j] - '0') * place;
                    place /= 10;
                }
            }
            break;
        }
        if (valid) ranges.push_back({range, specificity, weight});
    }
    int best_weight = 0;
    std::optional<std::string> selected;
    for (const std::string& type : types) {
        int specificity = 0, weight = 0;
        for (const Range& range : ranges) {
            bool fits = range.specificity == 1 || range.text == type ||
                        (range.specificity == 2 && range.text.substr(0, range.text.size() - 1) ==
                                                     type.substr(0, type.find('/') + 1));
            if (fits && range.specificity > specificity) {
                specificity = range.specificity;
                weight = range.weight;
            }
        }
        if (weight > best_weight) {
            best_weight = weight;
            selected = type;
        }
    }
    return selected;
}

class Router {
    std::vector<Route> routes;
    std::map<std::string, std::size_t> route_names;
    std::vector<std::size_t> ranked;
    std::map<std::string, std::string> tokens;
    std::vector<Redirect> redirects;
    std::set<std::string> origins;
    std::optional<std::pair<int, int>> limit;
    std::map<std::string, Client> clients;
    std::map<int, int> statuses;
    int config_errors = 0, requests = 0, url_ok = 0, url_error = 0;

    void configure(const std::vector<std::string>& w) {
        const std::string& command = w[0];
        if (command != "ROUTE" && command != "TOKEN" && command != "REDIRECT" && command != "ORIGIN" &&
            command != "LIMIT" && command != "TYPES") throw std::runtime_error("unknown command " + command);
        std::size_t count = w.size() - 1;
        bool correct = command == "ROUTE" ? count == 3 || count == 5
                     : command == "TOKEN" || command == "LIMIT" ? count == 2
                     : command == "REDIRECT" ? count == 3 : command == "ORIGIN" ? count == 1 : count >= 2;
        if (!correct) throw std::runtime_error("wrong number of arguments");
        if (command == "ROUTE") {
            if (!valid_name(w[1])) throw std::runtime_error("bad route name " + w[1]);
            if (route_names.count(w[1])) throw std::runtime_error("duplicate route " + w[1]);
            std::set<std::string> methods;
            for (const std::string& method : split(w[2], ',')) {
                if ((method != "GET" && method != "POST" && method != "PUT" && method != "PATCH" && method != "DELETE") ||
                    !methods.insert(method).second) throw std::runtime_error("bad methods " + w[2]);
            }
            std::optional<std::vector<Piece>> pieces = parse_pattern(w[3]);
            if (!pieces) throw std::runtime_error("bad pattern " + w[3]);
            if (count == 5 && w[4] != "ROLE") throw std::runtime_error("unknown option " + w[4]);
            if (count == 5 && !matches(w[5], "[a-z]{1,16}")) throw std::runtime_error("bad role " + w[5]);
            route_names.emplace(w[1], routes.size());
            routes.push_back({w[1], w[3], count == 5 ? w[5] : "none", methods, *pieces, {}});
        } else if (command == "TOKEN") {
            if (!matches(w[1], "[A-Za-z0-9._-]{1,32}")) throw std::runtime_error("bad token " + w[1]);
            if (tokens.count(w[1])) throw std::runtime_error("duplicate token " + w[1]);
            if (!matches(w[2], "[a-z]{1,16}")) throw std::runtime_error("bad role " + w[2]);
            tokens[w[1]] = w[2];
        } else if (command == "REDIRECT") {
            std::optional<RulePath> from = rule_path(w[1]);
            if (!from) throw std::runtime_error("bad path " + w[1]);
            std::optional<RulePath> to = rule_path(w[2]);
            if (!to) throw std::runtime_error("bad path " + w[2]);
            if (from->prefix != to->prefix) throw std::runtime_error("wildcard mismatch");
            if (w[3] != "301" && w[3] != "302" && w[3] != "307" && w[3] != "308")
                throw std::runtime_error("bad redirect code " + w[3]);
            for (const Redirect& redirect : redirects)
                if (redirect.from == w[1]) throw std::runtime_error("duplicate redirect " + w[1]);
            redirects.push_back({w[1], from->base, to->base, from->prefix, std::stoi(w[3])});
        } else if (command == "ORIGIN") {
            if (!matches(w[1], "https?://[a-z0-9.:-]+")) throw std::runtime_error("bad origin " + w[1]);
            if (origins.count(w[1])) throw std::runtime_error("duplicate origin " + w[1]);
            origins.insert(w[1]);
        } else if (command == "LIMIT") {
            if (!decimal_between(w[1], 1, 100) || !decimal_between(w[2], 1, 3600)) throw std::runtime_error("bad limit");
            if (limit) throw std::runtime_error("duplicate limit");
            limit = std::make_pair(std::stoi(w[1]), std::stoi(w[2]));
        } else {
            auto found = route_names.find(w[1]);
            if (found == route_names.end()) throw std::runtime_error("unknown route " + w[1]);
            Route& route = routes[found->second];
            if (!route.types.empty()) throw std::runtime_error("duplicate types " + w[1]);
            std::set<std::string> seen;
            for (std::size_t i = 2; i < w.size(); ++i) {
                if (!media_type(w[i])) throw std::runtime_error("bad media type " + w[i]);
                if (!seen.insert(w[i]).second) throw std::runtime_error("duplicate media type " + w[i]);
            }
            route.types.assign(w.begin() + 2, w.end());
        }
    }

    Response route_request(const std::string& method, const std::string& path,
                           const std::optional<std::string>& query, const Headers& headers) {
        std::vector<std::string> segments = path == "/" ? std::vector<std::string>{} : split(path.substr(1), '/');
        std::vector<std::size_t> matching;
        std::set<std::string> allowed{"OPTIONS"};
        for (std::size_t index : ranked) {
            if (!routes[index].matches_path(segments)) continue;
            matching.push_back(index);
            allowed.insert(routes[index].methods.begin(), routes[index].methods.end());
        }
        if (matching.empty()) return {404, "not found: " + path};
        if (allowed.count("GET")) allowed.insert("HEAD");
        std::string allow = join(allowed, ", ");
        if (method == "OPTIONS") return {204, "", {{"Allow", allow}}};
        std::string lookup = method == "HEAD" ? "GET" : method;
        Route* selected = nullptr;
        for (std::size_t index : matching) {
            if (routes[index].methods.count(lookup)) {
                selected = &routes[index];
                break;
            }
        }
        if (!selected) return {405, "method not allowed: " + method, {{"Allow", allow}}};
        ++selected->selections;
        if (selected->role != "none") {
            auto auth = headers.find("authorization");
            if (auth == headers.end())
                return {401, "unauthorized: missing token", {{"WWW-Authenticate", "Bearer realm=\"api\""}}};
            std::size_t space = auth->second.find(' ');
            std::string scheme = lower(auth->second.substr(0, space));
            std::string token = space == std::string::npos ? "" : auth->second.substr(space + 1);
            auto found = tokens.find(token);
            if (scheme != "bearer" || found == tokens.end())
                return {401, "unauthorized: invalid token", {{"WWW-Authenticate", "Bearer realm=\"api\", error=\"invalid_token\""}}};
            if (found->second != selected->role && found->second != "admin")
                return {403, "forbidden: requires role " + selected->role};
        }
        Headers response_headers;
        if (selected->types.size() > 1) response_headers["Vary"] = "Accept";
        std::optional<std::string> type = negotiate(selected->types, headers);
        if (!type) return {406, "not acceptable: " + join(selected->types, ", "), response_headers};
        std::string body = body_for(*type, selected->name, selected->parameters(segments), query_pairs(query), cookie_pairs(headers));
        std::string etag = etag_for(body);
        auto conditional = headers.find("if-none-match");
        if (conditional != headers.end()) {
            for (std::string candidate : split(conditional->second, ',')) {
                candidate = trim(candidate);
                if (candidate.compare(0, 2, "W/") == 0) candidate = candidate.substr(2);
                if (candidate != "*" && candidate != etag) continue;
                if (lookup == "GET") {
                    response_headers["ETag"] = etag;
                    return {304, "", response_headers};
                }
                return {412, "precondition failed: " + etag, response_headers};
            }
        }
        response_headers["ETag"] = etag;
        return {200, body, response_headers, *type};
    }

    Response dispatch(const std::string& method, const std::string& target, const Headers& headers) {
        static const std::set<std::string> known{"GET", "HEAD", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"};
        if (!known.count(method)) return {501, "not implemented: " + method};
        auto host = headers.find("host");
        if (host == headers.end() || host->second.empty()) return {400, "bad request: missing host"};
        std::string effective = method;
        auto override = headers.find("x-http-method-override");
        if (override != headers.end()) {
            if (method != "POST" || (override->second != "PUT" && override->second != "PATCH" && override->second != "DELETE"))
                return {400, "bad request: method override"};
            effective = override->second;
        }
        auto client_header = headers.find("x-client");
        if (client_header != headers.end() && !client_header->second.empty()) {
            const std::string& name = client_header->second;
            Client& client = clients[name];
            if (limit) {
                int n = limit->first, seconds = limit->second, time = std::stoi(headers.at("x-time"));
                if (!client.initialized) {
                    client.level = n * seconds;
                    client.last_time = time;
                    client.initialized = true;
                }
                client.level = std::min(n * seconds, client.level + (time - client.last_time) * n);
                client.last_time = time;
                if (client.level < seconds) {
                    ++client.limited;
                    int wait = (seconds - client.level + n - 1) / n;
                    return {429, "too many requests: client " + name, {{"Retry-After", std::to_string(wait)}}};
                }
                client.level -= seconds;
            }
            ++client.allowed;
        }
        std::size_t question = target.find('?');
        std::string path = target.substr(0, question);
        std::optional<std::string> query;
        if (question != std::string::npos) query = target.substr(question + 1);
        std::string suffix = query ? "?" + *query : "";
        auto redirect_response = [](int code, const std::string& destination) {
            return Response(code, "redirect to " + destination, {{"Location", destination}});
        };
        std::string normalized = normalize(path);
        if (normalized != path) return redirect_response(308, normalized + suffix);
        for (const Redirect& redirect : redirects) {
            bool applies = path == redirect.source ||
                           (redirect.prefix && path.compare(0, redirect.source.size() + 1, redirect.source + "/") == 0);
            if (applies) return redirect_response(redirect.code, redirect.target + path.substr(redirect.source.size()) + suffix);
        }
        return route_request(effective, path, query, headers);
    }

    Response respond(const std::string& method, const std::string& target, const std::vector<std::string>& lines) {
        if (!valid_escapes(target)) return {400, "bad request: percent escape"};
        Headers headers;
        for (std::size_t i = 0; i < lines.size(); ++i) {
            std::size_t colon = lines[i].find(':');
            if (colon == std::string::npos || !matches(lines[i].substr(0, colon), "[A-Za-z0-9-]+"))
                return {400, "bad request: header line " + std::to_string(i + 1)};
            std::string name = lower(lines[i].substr(0, colon));
            if (headers.count(name)) return {400, "bad request: duplicate header " + name};
            headers.emplace(name, trim(lines[i].substr(colon + 1)));
        }
        Response response = dispatch(method, target, headers);
        auto origin = headers.find("origin");
        if (origin != headers.end() && origins.count(origin->second)) {
            response.headers["Access-Control-Allow-Origin"] = origin->second;
            if (response.status == 204 && headers.count("access-control-request-method"))
                response.headers["Access-Control-Allow-Methods"] = response.headers.at("Allow");
        }
        return response;
    }

    std::string build_url(const std::string& name, const std::vector<std::string>& arguments) const {
        auto found = route_names.find(name);
        if (found == route_names.end()) throw std::runtime_error("unknown route " + name);
        const Route& route = routes[found->second];
        std::set<std::string> parameter_names;
        for (const Piece& piece : route.pieces) if (piece.kind != PieceKind::Literal) parameter_names.insert(piece.text);
        std::map<std::string, std::string> values;
        Pairs query;
        for (const std::string& argument : arguments) {
            std::size_t equals = argument.find('=');
            if (equals == std::string::npos || equals == 0) throw std::runtime_error("bad argument " + argument);
            std::string key = argument.substr(0, equals), value = argument.substr(equals + 1);
            if (!parameter_names.count(key)) query.emplace_back(key, value);
            else if (!values.emplace(key, value).second) throw std::runtime_error("duplicate parameter " + key);
        }
        std::vector<std::string> pieces;
        for (const Piece& piece : route.pieces) {
            if (piece.kind == PieceKind::Literal) {
                pieces.push_back(piece.text);
                continue;
            }
            auto argument = values.find(piece.text);
            if (argument == values.end() && piece.kind != PieceKind::Wildcard)
                throw std::runtime_error("missing parameter " + piece.text);
            std::string value = argument == values.end() ? "" : argument->second;
            if (!piece.accepts(value)) throw std::runtime_error("bad value for " + piece.text);
            if (piece.kind == PieceKind::Wildcard) {
                if (!value.empty()) for (const std::string& part : split(value, '/')) pieces.push_back(encode(part));
            } else pieces.push_back(encode(value));
        }
        std::string url = "/" + join(pieces, "/");
        if (!query.empty()) url += "?" + encoded_pairs(query);
        return url;
    }

    static void write_response(Response response, bool head) {
        static const std::map<int, std::string> reasons{
            {200,"OK"}, {204,"No Content"}, {301,"Moved Permanently"}, {302,"Found"}, {304,"Not Modified"},
            {307,"Temporary Redirect"}, {308,"Permanent Redirect"}, {400,"Bad Request"}, {401,"Unauthorized"},
            {403,"Forbidden"}, {404,"Not Found"}, {405,"Method Not Allowed"}, {406,"Not Acceptable"},
            {412,"Precondition Failed"}, {429,"Too Many Requests"}, {501,"Not Implemented"}
        };
        static const std::vector<std::string> header_order{
            "Location", "Allow", "Retry-After", "WWW-Authenticate", "Access-Control-Allow-Origin",
            "Access-Control-Allow-Methods", "Vary", "ETag", "Content-Type", "Content-Length"
        };
        bool has_body = response.status != 204 && response.status != 304;
        if (has_body) {
            response.headers["Content-Type"] = response.status == 200 ? response.type : "text/plain";
            response.headers["Content-Length"] = std::to_string(response.body.size());
        }
        std::cout << "HTTP/1.1 " << response.status << ' ' << reasons.at(response.status) << '\n';
        for (const std::string& name : header_order) {
            auto header = response.headers.find(name);
            if (header != response.headers.end()) std::cout << name << ": " << header->second << '\n';
        }
        if (has_body && !head) std::cout << response.body << '\n';
    }

public:
    void configuration_line(int number, const std::string& line) {
        try { configure(split(line, ' ')); }
        catch (const std::runtime_error& error) {
            ++config_errors;
            std::cout << "CONFIG ERROR " << number << ": " << error.what() << '\n';
        }
    }

    void finish_configuration() {
        std::cout << "CONFIG routes=" << routes.size() << " tokens=" << tokens.size() << " redirects=" << redirects.size()
                  << " origins=" << origins.size() << " limit=";
        if (limit) std::cout << limit->first << '/' << limit->second;
        else std::cout << "none";
        std::cout << " errors=" << config_errors << '\n';
        for (std::size_t i = 0; i < routes.size(); ++i) {
            if (routes[i].types.empty()) routes[i].types.push_back("application/json");
            ranked.push_back(i);
        }
        std::stable_sort(ranked.begin(), ranked.end(), [&](std::size_t a, std::size_t b) {
            return std::make_tuple(-routes[a].literal_count(), -routes[a].typed_count(), routes[a].wildcard()) <
                   std::make_tuple(-routes[b].literal_count(), -routes[b].typed_count(), routes[b].wildcard());
        });
        for (std::size_t rank = 0; rank < ranked.size(); ++rank) {
            const Route& route = routes[ranked[rank]];
            std::set<std::string> methods = route.methods;
            if (methods.count("GET")) methods.insert("HEAD");
            std::cout << "TABLE " << rank + 1 << ' ' << route.name << ' ' << join(methods, ",") << ' ' << route.pattern
                      << " role=" << (route.role == "none" ? "-" : route.role) << " types=" << join(route.types, ",") << '\n';
        }
    }

    void request(const std::string& line, const std::vector<std::string>& headers) {
        ++requests;
        std::vector<std::string> parts = split(line, ' ');
        bool valid = parts.size() == 3 && matches(parts[0], "[A-Z]{1,16}") && !parts[1].empty() && parts[1][0] == '/' &&
                     parts[1].find('#') == std::string::npos && parts[2] == "HTTP/1.1";
        Response response = valid ? respond(parts[0], parts[1], headers) : Response(400, "bad request: request line");
        ++statuses[response.status];
        std::cout << "REQUEST " << requests << '\n';
        write_response(std::move(response), valid && parts[0] == "HEAD");
    }

    void urlfor(const std::string& line) {
        std::vector<std::string> parts = split(line, ' ');
        try {
            std::string url = build_url(parts[1], std::vector<std::string>(parts.begin() + 2, parts.end()));
            ++url_ok;
            std::cout << "URLFOR " << parts[1] << ' ' << url << '\n';
        } catch (const std::runtime_error& error) {
            ++url_error;
            std::cout << "URLFOR ERROR " << error.what() << '\n';
        }
    }

    void summary() const {
        std::cout << "SUMMARY requests=" << requests << " urlfor_ok=" << url_ok << " urlfor_error=" << url_error << '\n';
        for (const auto& status : statuses) std::cout << "STATUS " << status.first << ' ' << status.second << '\n';
        for (const Route& route : routes) std::cout << "ROUTE " << route.name << ' ' << route.selections << '\n';
        for (const auto& client : clients)
            std::cout << "CLIENT " << client.first << " allowed=" << client.second.allowed << " limited=" << client.second.limited << '\n';
    }
};

int main() {
    Router router;
    std::string line;
    int number = 0;
    while (std::getline(std::cin, line) && line != "REQUESTS") router.configuration_line(++number, line);
    router.finish_configuration();
    while (std::getline(std::cin, line) && line != "END") {
        if (line.compare(0, 7, "URLFOR ") == 0) router.urlfor(line);
        else {
            std::vector<std::string> headers;
            std::string header;
            while (std::getline(std::cin, header) && !header.empty()) headers.push_back(header);
            router.request(line, headers);
        }
    }
    router.summary();
}
