#include <algorithm>
#include <array>
#include <bitset>
#include <iostream>
#include <map>
#include <optional>
#include <set>
#include <sstream>
#include <stdexcept>
#include <string>
#include <type_traits>
#include <utility>
#include <variant>
#include <vector>

using Strings = std::vector<std::string>;
using Hash = std::map<std::string, std::string>;
using Members = std::set<std::string>;
using SortedSet = std::map<std::string, int>;
using Value = std::variant<std::string, Strings, Hash, Members, SortedSet>;
using Reply = std::vector<std::string>;
struct Record { Value value; std::optional<int> expiry; };
using Database = std::map<std::string, Record>;

const std::string wrongType = "WRONGTYPE Operation against a key holding the wrong kind of value";
const std::string notInteger = "ERR value is not an integer or out of range";
const std::string overflow = "ERR increment or decrement would overflow";
const std::string syntax = "ERR syntax error";
const std::string positive = "ERR value is out of range, must be positive";
const std::string noKey = "ERR no such key";
struct CommandError : std::runtime_error { using std::runtime_error::runtime_error; };
[[noreturn]] void fail(const std::string& message) { throw CommandError(message); }

std::string upper(std::string value) {
    for (char& c : value) if ('a' <= c && c <= 'z') c = static_cast<char>(c - 'a' + 'A');
    return value;
}
std::string lower(std::string value) {
    for (char& c : value) if ('A' <= c && c <= 'Z') c = static_cast<char>(c - 'A' + 'a');
    return value;
}
int number(const std::string& word, const std::string& message = notInteger) {
    if (word == "0") return 0;
    if (word.empty()) fail(message);
    std::size_t start = word[0] == '-' ? 1 : 0, digits = word.size() - start;
    if (digits < 1 || digits > 9 || word[start] < '1' || word[start] > '9') fail(message);
    int result = 0;
    for (std::size_t index = start; index < word.size(); ++index) {
        if (word[index] < '0' || word[index] > '9') fail(message);
        result = result * 10 + word[index] - '0';
    }
    return start == 1 ? -result : result;
}
int increment(int value, int delta) {
    long long result = static_cast<long long>(value) + delta;
    if (result < -999999999 || result > 999999999) fail(overflow);
    return static_cast<int>(result);
}
std::string quote(const std::string& value) {
    std::string result = "\"";
    for (char c : value) { if (c == '"' || c == '\\') result += '\\'; result += c; }
    return result + '"';
}
Reply status(const std::string& value) { return {value}; }
Reply integer(long long value) { return {"(integer) " + std::to_string(value)}; }
Reply stringReply(const std::optional<std::string>& value) { return {value ? quote(*value) : "(nil)"}; }
Reply arrayReply(const std::vector<std::optional<std::string>>& values) {
    if (values.empty()) return {"(empty array)"};
    Reply result;
    auto width = std::to_string(values.size()).size();
    for (std::size_t index = 0; index < values.size(); ++index) {
        auto label = std::to_string(index + 1);
        result.push_back(std::string(width - label.size(), ' ') + label + ") " + stringReply(values[index])[0]);
    }
    return result;
}
Reply arrayReply(const Strings& values) {
    return arrayReply(std::vector<std::optional<std::string>>(values.begin(), values.end()));
}
template<class Sequence>
Sequence range(const Sequence& sequence, int start, int stop) {
    int size = static_cast<int>(sequence.size());
    if (start < 0) start += size;
    if (stop < 0) stop += size;
    start = std::max(0, start); stop = std::min(size - 1, stop);
    return start <= stop ? Sequence(sequence.begin() + start, sequence.begin() + stop + 1) : Sequence{};
}

std::optional<Strings> splitArguments(const std::string& line) {
    Strings arguments;
    std::size_t position = 0;
    while (position < line.size()) {
        if (line[position] == ' ') { ++position; continue; }
        if (line[position] != '"') {
            auto start = position;
            while (position < line.size() && line[position] != ' ') ++position;
            arguments.push_back(line.substr(start, position - start));
            continue;
        }
        ++position;
        std::string value;
        bool closed = false;
        while (position < line.size()) {
            char character = line[position++];
            if (character == '"') { closed = true; break; }
            if (character == '\\') {
                if (position == line.size() || (line[position] != '"' && line[position] != '\\')) return std::nullopt;
                value += line[position++];
            } else value += character;
        }
        if (!closed || (position < line.size() && line[position] != ' ')) return std::nullopt;
        arguments.push_back(value);
    }
    return arguments;
}

enum class PatternKind { Literal, Any, Star, CharacterClass };
struct PatternPart {
    PatternKind kind;
    char literal = 0;
    std::bitset<128> characters;
    bool negated = false;
};
std::vector<PatternPart> parsePattern(const std::string& pattern) {
    std::vector<PatternPart> parts;
    for (std::size_t position = 0; position < pattern.size(); ++position) {
        char character = pattern[position];
        if (character == '\\') {
            if (++position == pattern.size()) fail("ERR invalid pattern");
            parts.push_back({PatternKind::Literal, pattern[position]});
        } else if (character == '[') {
            auto end = pattern.find(']', position + 1);
            if (end == std::string::npos) fail("ERR invalid pattern");
            auto content = pattern.substr(position + 1, end - position - 1);
            PatternPart part{PatternKind::CharacterClass};
            part.negated = !content.empty() && content[0] == '^';
            if (part.negated) content.erase(content.begin());
            if (content.empty()) fail("ERR invalid pattern");
            for (std::size_t index = 0; index < content.size();) {
                if (index + 2 < content.size() && content[index + 1] == '-') {
                    int first = content[index], last = content[index + 2];
                    for (int code = std::min(first, last); code <= std::max(first, last); ++code) part.characters.set(code);
                    index += 3;
                } else part.characters.set(static_cast<unsigned char>(content[index++]));
            }
            parts.push_back(part); position = end;
        } else if (character == '*') parts.push_back({PatternKind::Star});
        else if (character == '?') parts.push_back({PatternKind::Any});
        else parts.push_back({PatternKind::Literal, character});
    }
    return parts;
}
bool matches(const std::vector<PatternPart>& parts, const std::string& value) {
    std::vector<bool> previous(value.size() + 1, false);
    previous[0] = true;
    for (const auto& part : parts) {
        std::vector<bool> current(value.size() + 1, false);
        if (part.kind == PatternKind::Star) {
            current[0] = previous[0];
            for (std::size_t index = 1; index <= value.size(); ++index) current[index] = previous[index] || current[index - 1];
        } else {
            for (std::size_t index = 0; index < value.size(); ++index) {
                bool accepts = part.kind == PatternKind::Any || (part.kind == PatternKind::Literal ? part.literal == value[index]
                    : part.characters.test(static_cast<unsigned char>(value[index])) != part.negated);
                current[index + 1] = previous[index] && accepts;
            }
        }
        previous = std::move(current);
    }
    return previous.back();
}

enum class BoundKind { NegativeInfinity, Finite, PositiveInfinity };
struct Bound {
    BoundKind kind;
    int value = 0;
    bool inclusive = true;
    bool accepts(int score, bool lowerBound) const {
        if (kind == BoundKind::NegativeInfinity) return lowerBound;
        if (kind == BoundKind::PositiveInfinity) return !lowerBound;
        return lowerBound ? (inclusive ? score >= value : score > value) : (inclusive ? score <= value : score < value);
    }
};
Bound scoreBound(const std::string& word) {
    if (word == "-inf") return {BoundKind::NegativeInfinity};
    if (word == "+inf") return {BoundKind::PositiveInfinity};
    bool inclusive = word.empty() || word[0] != '(';
    return {BoundKind::Finite, number(inclusive ? word : word.substr(1), "ERR min or max is not a float"), inclusive};
}

enum class Group { Text, Lists, Hashes, Sets, SortedSets, Keys, Control };
struct CommandSpec { Group group; int minimum, maximum, parity; };
const std::map<std::string, CommandSpec> commands = [] {
    std::map<std::string, CommandSpec> result;
    auto add = [&](Group group, const std::string& names, int minimum, int maximum, int parity = -1) {
        std::istringstream words(names);
        for (std::string word; words >> word;) result.emplace(word, CommandSpec{group, minimum, maximum, parity});
    };
    add(Group::Text, "SET", 2, -1);
    add(Group::Text, "GET INCR DECR STRLEN", 1, 1);
    add(Group::Text, "MSET", 2, -1, 0);
    add(Group::Text, "MGET", 1, -1);
    add(Group::Text, "INCRBY DECRBY APPEND", 2, 2);
    add(Group::Text, "GETRANGE", 3, 3);
    add(Group::Lists, "LPUSH RPUSH", 2, -1);
    add(Group::Lists, "LPOP RPOP", 1, 2);
    add(Group::Lists, "LRANGE LSET LREM LTRIM", 3, 3);
    add(Group::Lists, "LLEN", 1, 1);
    add(Group::Lists, "LINDEX", 2, 2);
    add(Group::Lists, "LINSERT", 4, 4);
    add(Group::Hashes, "HSET", 3, -1, 1);
    add(Group::Hashes, "HGET HEXISTS", 2, 2);
    add(Group::Hashes, "HDEL", 2, -1);
    add(Group::Hashes, "HGETALL HLEN HKEYS HVALS", 1, 1);
    add(Group::Hashes, "HINCRBY", 3, 3);
    add(Group::Sets, "SADD SREM", 2, -1);
    add(Group::Sets, "SISMEMBER", 2, 2);
    add(Group::Sets, "SMEMBERS SCARD", 1, 1);
    add(Group::Sets, "SINTER SUNION SDIFF", 1, -1);
    add(Group::Sets, "SINTERSTORE SUNIONSTORE SDIFFSTORE", 2, -1);
    add(Group::SortedSets, "ZADD", 3, -1, 1);
    add(Group::SortedSets, "ZSCORE ZRANK", 2, 2);
    add(Group::SortedSets, "ZINCRBY", 3, 3);
    add(Group::SortedSets, "ZREM", 2, -1);
    add(Group::SortedSets, "ZCARD", 1, 1);
    add(Group::SortedSets, "ZRANGE ZRANGEBYSCORE", 3, 4);
    add(Group::Keys, "DEL EXISTS", 1, -1);
    add(Group::Keys, "TYPE KEYS TTL PERSIST TICK", 1, 1);
    add(Group::Keys, "RENAME RENAMENX", 2, 2);
    add(Group::Keys, "EXPIRE", 2, 3);
    add(Group::Keys, "TIME DBSIZE FLUSH INFO", 0, 0);
    add(Group::Control, "BEGIN COMMIT ROLLBACK", 0, 0);
    add(Group::Control, "SNAPSHOT RESTORE", 1, 1);
    return result;
}();

class Store {
    Database database;
    int time = 0;
    std::vector<Database> transactions;
    std::map<std::string, Database> snapshots;

    template<class T> T readValue(const std::string& key) const {
        auto found = database.find(key);
        if (found == database.end()) return T{};
        auto value = std::get_if<T>(&found->second.value);
        if (!value) fail(wrongType);
        return *value;
    }
    void replace(const std::string& key, Value value, std::optional<int> expiry = std::nullopt) {
        bool emptyCollection = std::visit([](const auto& content) {
            using T = std::decay_t<decltype(content)>;
            if constexpr (std::is_same_v<T, std::string>) return false;
            else return content.empty();
        }, value);
        if (emptyCollection) database.erase(key);
        else database.insert_or_assign(key, Record{std::move(value), expiry});
    }
    void update(const std::string& key, Value value) {
        auto found = database.find(key);
        replace(key, std::move(value), found == database.end() ? std::nullopt : found->second.expiry);
    }
    int purge() {
        int removed = 0;
        for (auto iterator = database.begin(); iterator != database.end();) {
            if (iterator->second.expiry && *iterator->second.expiry <= time) {
                iterator = database.erase(iterator); ++removed;
            } else ++iterator;
        }
        return removed;
    }
    Reply textCommand(const std::string& command, const Strings& args) {
        const auto& key = args[0];
        if (command == "SET") {
            Members options;
            std::optional<std::string> secondsWord;
            for (std::size_t index = 2; index < args.size(); ++index) {
                auto option = upper(args[index]);
                if (option != "NX" && option != "XX" && option != "EX" && option != "KEEPTTL" && option != "GET") fail(syntax);
                if (!options.insert(option).second) fail(syntax);
                if (option == "EX") {
                    if (++index == args.size()) fail(syntax);
                    secondsWord = args[index];
                }
            }
            if ((options.count("NX") && options.count("XX")) || (options.count("EX") && options.count("KEEPTTL"))) fail(syntax);
            std::optional<int> expiry;
            if (secondsWord) {
                int seconds = number(*secondsWord);
                if (seconds <= 0) fail("ERR invalid expire time in 'set' command");
                expiry = time + seconds;
            }
            auto found = database.find(key);
            bool exists = found != database.end();
            std::optional<std::string> old;
            if (options.count("GET")) {
                auto value = readValue<std::string>(key);
                if (exists) old = value;
            }
            if (options.count("KEEPTTL") && exists) expiry = found->second.expiry;
            bool changed = !(options.count("NX") && exists) && !(options.count("XX") && !exists);
            if (changed) replace(key, args[1], expiry);
            if (options.count("GET")) return stringReply(old);
            return changed ? status("OK") : stringReply(std::nullopt);
        }
        if (command == "MSET") {
            for (std::size_t index = 0; index < args.size(); index += 2) replace(args[index], args[index + 1]);
            return status("OK");
        }
        if (command == "MGET") {
            std::vector<std::optional<std::string>> output;
            for (const auto& name : args) {
                auto found = database.find(name);
                const auto* value = found == database.end() ? nullptr : std::get_if<std::string>(&found->second.value);
                output.push_back(value ? std::optional<std::string>(*value) : std::nullopt);
            }
            return arrayReply(output);
        }
        if (command == "INCR" || command == "DECR" || command == "INCRBY" || command == "DECRBY") {
            int delta = args.size() == 2 ? number(args[1]) : 1;
            if (command == "DECR" || command == "DECRBY") delta = -delta;
            auto value = readValue<std::string>(key);
            int result = increment(database.count(key) ? number(value) : 0, delta);
            update(key, std::to_string(result));
            return integer(result);
        }
        if (command == "GETRANGE") {
            int start = number(args[1]), stop = number(args[2]);
            return stringReply(range(readValue<std::string>(key), start, stop));
        }
        auto value = readValue<std::string>(key);
        if (command == "GET") return stringReply(database.count(key) ? std::optional<std::string>(value) : std::nullopt);
        if (command == "STRLEN") return integer(value.size());
        value += args[1];
        update(key, value);
        return integer(value.size());
    }
    Reply listCommand(const std::string& command, const Strings& args) {
        const auto& key = args[0];
        if (command == "LPOP" || command == "RPOP") {
            bool counted = args.size() == 2;
            int count = counted ? number(args[1], positive) : 1;
            if (count < 0) fail(positive);
            auto values = readValue<Strings>(key);
            if (!database.count(key)) return stringReply(std::nullopt);
            count = std::min(count, static_cast<int>(values.size()));
            Strings removed;
            for (int index = 0; index < count; ++index) {
                if (command == "LPOP") { removed.push_back(values.front()); values.erase(values.begin()); }
                else { removed.push_back(values.back()); values.pop_back(); }
            }
            update(key, values);
            return counted ? arrayReply(removed) : stringReply(removed[0]);
        }
        if (command == "LRANGE" || command == "LTRIM") {
            int start = number(args[1]), stop = number(args[2]);
            auto values = range(readValue<Strings>(key), start, stop);
            if (command == "LRANGE") return arrayReply(values);
            update(key, values);
            return status("OK");
        }
        if (command == "LINDEX" || command == "LSET") {
            int index = number(args[1]);
            auto values = readValue<Strings>(key);
            int size = static_cast<int>(values.size());
            if (index < 0) index += size;
            bool inside = 0 <= index && index < size;
            if (command == "LINDEX") return stringReply(inside ? std::optional<std::string>(values[index]) : std::nullopt);
            if (!database.count(key)) fail(noKey);
            if (!inside) fail("ERR index out of range");
            values[index] = args[2];
            update(key, values);
            return status("OK");
        }
        if (command == "LREM") {
            int count = number(args[1]);
            auto values = readValue<Strings>(key);
            if (count < 0) std::reverse(values.begin(), values.end());
            int limit = count == 0 ? static_cast<int>(values.size()) : (count < 0 ? -count : count);
            int removed = 0;
            Strings kept;
            for (const auto& value : values) {
                if (value == args[2] && removed < limit) ++removed;
                else kept.push_back(value);
            }
            if (count < 0) std::reverse(kept.begin(), kept.end());
            update(key, kept);
            return integer(removed);
        }
        if (command == "LINSERT") {
            auto where = upper(args[1]);
            if (where != "BEFORE" && where != "AFTER") fail(syntax);
            auto values = readValue<Strings>(key);
            if (!database.count(key)) return integer(0);
            auto pivot = std::find(values.begin(), values.end(), args[2]);
            if (pivot == values.end()) return integer(-1);
            values.insert(pivot + (where == "AFTER" ? 1 : 0), args[3]);
            update(key, values);
            return integer(values.size());
        }
        auto values = readValue<Strings>(key);
        if (command == "LLEN") return integer(values.size());
        for (std::size_t index = 1; index < args.size(); ++index) {
            if (command == "LPUSH") values.insert(values.begin(), args[index]);
            else values.push_back(args[index]);
        }
        update(key, values);
        return integer(values.size());
    }
    Reply hashCommand(const std::string& command, const Strings& args) {
        const auto& key = args[0];
        if (command == "HINCRBY") {
            int delta = number(args[2]);
            auto fields = readValue<Hash>(key);
            auto found = fields.find(args[1]);
            int old = found == fields.end() ? 0 : number(found->second, "ERR hash value is not an integer");
            int result = increment(old, delta);
            fields[args[1]] = std::to_string(result);
            update(key, fields);
            return integer(result);
        }
        auto fields = readValue<Hash>(key);
        if (command == "HSET") {
            int added = 0;
            for (std::size_t index = 1; index < args.size(); index += 2) {
                if (!fields.count(args[index])) ++added;
                fields[args[index]] = args[index + 1];
            }
            update(key, fields);
            return integer(added);
        }
        if (command == "HGET") {
            auto found = fields.find(args[1]);
            return stringReply(found == fields.end() ? std::nullopt : std::optional<std::string>(found->second));
        }
        if (command == "HDEL") {
            int removed = 0;
            for (std::size_t index = 1; index < args.size(); ++index) removed += static_cast<int>(fields.erase(args[index]));
            update(key, fields);
            return integer(removed);
        }
        if (command == "HLEN") return integer(fields.size());
        if (command == "HEXISTS") return integer(fields.count(args[1]));
        Strings output;
        for (const auto& [field, value] : fields) {
            if (command != "HVALS") output.push_back(field);
            if (command != "HKEYS") output.push_back(value);
        }
        return arrayReply(output);
    }
    Reply setCommand(const std::string& command, const Strings& args) {
        bool storing = command.find("STORE") != std::string::npos;
        std::string operation = storing ? command.substr(0, command.size() - 5) : command;
        if (operation == "SINTER" || operation == "SUNION" || operation == "SDIFF") {
            std::vector<Members> sources;
            for (std::size_t index = storing ? 1 : 0; index < args.size(); ++index) sources.push_back(readValue<Members>(args[index]));
            Members result = sources[0];
            for (std::size_t index = 1; index < sources.size(); ++index) {
                if (operation == "SUNION") result.insert(sources[index].begin(), sources[index].end());
                else {
                    for (auto member = result.begin(); member != result.end();) {
                        bool present = sources[index].count(*member) != 0;
                        if ((operation == "SINTER" && !present) || (operation == "SDIFF" && present)) member = result.erase(member);
                        else ++member;
                    }
                }
            }
            if (storing) { replace(args[0], result); return integer(result.size()); }
            return arrayReply(Strings(result.begin(), result.end()));
        }
        auto members = readValue<Members>(args[0]);
        if (command == "SCARD") return integer(members.size());
        if (command == "SMEMBERS") return arrayReply(Strings(members.begin(), members.end()));
        if (command == "SISMEMBER") return integer(members.count(args[1]));
        int changed = 0;
        for (std::size_t index = 1; index < args.size(); ++index) {
            if (command == "SADD") changed += members.insert(args[index]).second ? 1 : 0;
            else changed += static_cast<int>(members.erase(args[index]));
        }
        update(args[0], members);
        return integer(changed);
    }
    Reply sortedSetCommand(const std::string& command, const Strings& args) {
        const auto& key = args[0];
        if (command == "ZADD") {
            std::vector<int> scores;
            for (std::size_t index = 1; index < args.size(); index += 2) scores.push_back(number(args[index]));
            auto members = readValue<SortedSet>(key);
            int added = 0;
            for (std::size_t index = 0; index < scores.size(); ++index) {
                const auto& member = args[2 * index + 2];
                if (!members.count(member)) ++added;
                members[member] = scores[index];
            }
            update(key, members);
            return integer(added);
        }
        if (command == "ZINCRBY") {
            int delta = number(args[1]);
            auto members = readValue<SortedSet>(key);
            int result = increment(members.count(args[2]) ? members.at(args[2]) : 0, delta);
            members[args[2]] = result;
            update(key, members);
            return stringReply(std::to_string(result));
        }
        bool byIndex = command == "ZRANGE", byScore = command == "ZRANGEBYSCORE";
        bool withScores = args.size() == 4;
        int start = 0, stop = 0;
        Bound minimum{BoundKind::NegativeInfinity}, maximum{BoundKind::PositiveInfinity};
        if (byIndex || byScore) {
            if (withScores && upper(args[3]) != "WITHSCORES") fail(syntax);
            if (byIndex) { start = number(args[1]); stop = number(args[2]); }
            else { minimum = scoreBound(args[1]); maximum = scoreBound(args[2]); }
        }
        auto members = readValue<SortedSet>(key);
        if (command == "ZSCORE") {
            auto found = members.find(args[1]);
            return stringReply(found == members.end() ? std::nullopt : std::optional<std::string>(std::to_string(found->second)));
        }
        if (command == "ZREM") {
            int removed = 0;
            for (std::size_t index = 1; index < args.size(); ++index) removed += static_cast<int>(members.erase(args[index]));
            update(key, members);
            return integer(removed);
        }
        if (command == "ZCARD") return integer(members.size());
        std::vector<std::pair<std::string, int>> ordered(members.begin(), members.end());
        std::sort(ordered.begin(), ordered.end(), [](const auto& left, const auto& right) {
            return left.second != right.second ? left.second < right.second : left.first < right.first;
        });
        if (command == "ZRANK") {
            for (std::size_t index = 0; index < ordered.size(); ++index) if (ordered[index].first == args[1]) return integer(index);
            return stringReply(std::nullopt);
        }
        if (byIndex) ordered = range(ordered, start, stop);
        Strings output;
        for (const auto& [member, score] : ordered) {
            if (byScore && (!minimum.accepts(score, true) || !maximum.accepts(score, false))) continue;
            output.push_back(member);
            if (withScores) output.push_back(std::to_string(score));
        }
        return arrayReply(output);
    }
    Reply keyCommand(const std::string& command, const Strings& args) {
        if (command == "DEL" || command == "EXISTS") {
            int count = 0;
            for (const auto& key : args) count += static_cast<int>(command == "DEL" ? database.erase(key) : database.count(key));
            return integer(count);
        }
        if (command == "KEYS") {
            auto pattern = parsePattern(args[0]);
            Strings output;
            for (const auto& [key, record] : database) if (matches(pattern, key)) output.push_back(key);
            return arrayReply(output);
        }
        if (command == "EXPIRE") {
            std::string condition = args.size() == 3 ? upper(args[2]) : "";
            if (args.size() == 3 && condition != "NX" && condition != "XX" && condition != "GT" && condition != "LT") fail("ERR Unsupported option " + args[2]);
            int seconds = number(args[1]);
            auto found = database.find(args[0]);
            if (found == database.end()) return integer(0);
            auto old = found->second.expiry;
            int expiry = time + seconds;
            bool rejected = (condition == "NX" && old) || (condition == "XX" && !old)
                || (condition == "GT" && (!old || expiry <= *old)) || (condition == "LT" && old && expiry >= *old);
            if (rejected) return integer(0);
            if (seconds <= 0) database.erase(found);
            else found->second.expiry = expiry;
            return integer(1);
        }
        if (command == "TICK") {
            int seconds = number(args[0]);
            if (seconds <= 0) fail(positive);
            time += seconds;
            return integer(purge());
        }
        if (command == "TIME") return integer(time);
        if (command == "DBSIZE") return integer(database.size());
        if (command == "FLUSH") { database.clear(); return status("OK"); }
        if (command == "INFO") {
            std::array<int, 5> counts{};
            int expires = 0;
            for (const auto& [key, record] : database) { ++counts[record.value.index()]; if (record.expiry) ++expires; }
            return status("keys=" + std::to_string(database.size()) + ",expires=" + std::to_string(expires)
                + ",string=" + std::to_string(counts[0]) + ",list=" + std::to_string(counts[1])
                + ",hash=" + std::to_string(counts[2]) + ",set=" + std::to_string(counts[3])
                + ",zset=" + std::to_string(counts[4]) + ",time=" + std::to_string(time)
                + ",depth=" + std::to_string(transactions.size()) + ",snapshots=" + std::to_string(snapshots.size()));
        }
        auto found = database.find(args[0]);
        if (command == "TYPE") {
            const std::array<std::string, 5> names{"string", "list", "hash", "set", "zset"};
            return status(found == database.end() ? "none" : names[found->second.value.index()]);
        }
        if (command == "TTL") return integer(found == database.end() ? -2 : (found->second.expiry ? *found->second.expiry - time : -1));
        if (command == "PERSIST") {
            if (found == database.end() || !found->second.expiry) return integer(0);
            found->second.expiry.reset();
            return integer(1);
        }
        if (found == database.end()) fail(noKey);
        if (command == "RENAMENX" && database.count(args[1])) return integer(0);
        if (args[0] != args[1]) {
            database.insert_or_assign(args[1], found->second);
            database.erase(found);
        }
        return command == "RENAME" ? status("OK") : integer(1);
    }
    Reply controlCommand(const std::string& command, const Strings& args) {
        if (command == "BEGIN") { transactions.push_back(database); return status("OK"); }
        if (command == "COMMIT" || command == "ROLLBACK") {
            if (transactions.empty()) fail("ERR no transaction");
            if (command == "ROLLBACK") database = std::move(transactions.back());
            transactions.pop_back();
            if (command == "ROLLBACK") purge();
            return status("OK");
        }
        if (command == "SNAPSHOT") { snapshots.insert_or_assign(args[0], database); return status("OK"); }
        auto found = snapshots.find(args[0]);
        if (found == snapshots.end()) fail("ERR no such snapshot");
        database = found->second;
        purge();
        return status("OK");
    }

public:
    Reply execute(const std::string& line) {
        auto parsed = splitArguments(line);
        if (!parsed || parsed->empty()) return status("Invalid argument(s)");
        auto command = upper((*parsed)[0]);
        auto found = commands.find(command);
        if (found == commands.end()) fail("ERR unknown command '" + (*parsed)[0] + "'");
        Strings args(parsed->begin() + 1, parsed->end());
        const auto& specification = found->second;
        int count = static_cast<int>(args.size());
        if (count < specification.minimum || (specification.maximum >= 0 && count > specification.maximum)
            || (specification.parity >= 0 && count % 2 != specification.parity)) {
            fail("ERR wrong number of arguments for '" + lower(command) + "' command");
        }
        switch (specification.group) {
            case Group::Text: return textCommand(command, args);
            case Group::Lists: return listCommand(command, args);
            case Group::Hashes: return hashCommand(command, args);
            case Group::Sets: return setCommand(command, args);
            case Group::SortedSets: return sortedSetCommand(command, args);
            case Group::Keys: return keyCommand(command, args);
            case Group::Control: return controlCommand(command, args);
        }
        throw std::logic_error("invalid command group");
    }
};

int main() {
    std::ios::sync_with_stdio(false);
    std::cin.tie(nullptr);
    std::string line;
    if (!std::getline(std::cin, line)) return 0;
    int count = std::stoi(line);
    Store store;
    for (int index = 0; index < count; ++index) {
        std::getline(std::cin, line);
        try {
            for (const auto& output : store.execute(line)) std::cout << output << '\n';
        } catch (const CommandError& error) {
            std::cout << "(error) " << error.what() << '\n';
        }
    }
}
