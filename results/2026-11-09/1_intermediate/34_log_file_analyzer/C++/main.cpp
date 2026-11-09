#include <algorithm>
#include <array>
#include <cctype>
#include <cstdint>
#include <iomanip>
#include <iostream>
#include <map>
#include <numeric>
#include <regex>
#include <set>
#include <sstream>
#include <stdexcept>
#include <string>
#include <utility>
#include <vector>

using namespace std;

const vector<string> METHODS = {
    "GET", "HEAD", "POST", "PUT", "DELETE", "PATCH", "OPTIONS"
};
const vector<string> REASONS = {
    "fields", "date", "time", "ip", "method", "path", "status", "bytes", "latency"
};
const vector<string> CLASSES = {"1xx", "2xx", "3xx", "4xx", "5xx"};
const vector<string> KEYS = {"METHOD", "STATUS", "IP", "PATH"};
const array<int, 12> MONTH_DAYS = {31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31};
const map<string, vector<string>> FORMS = {
    {"SUMMARY", {}}, {"MALFORMED", {}}, {"STATUS", {}}, {"METHODS", {}},
    {"TOP", {"kind", "limit"}}, {"HOURLY", {}}, {"TIMELINE", {"minutes"}},
    {"BANDWIDTH", {}}, {"VISITORS", {}}, {"LATENCY", {"path"}},
    {"HISTOGRAM", {"width"}}, {"APDEX", {"threshold"}}, {"ERRORS", {}},
    {"SLOWEST", {"limit"}}, {"SESSIONS", {"ip", "minutes"}},
    {"BURST", {"length", "times"}}, {"PEAK", {"length"}}, {"GAPS", {"length"}},
    {"IP", {"ip"}}, {"RANGE", {"date", "time", "date", "time"}},
    {"FILTER", {"key", "value"}}, {"UNFILTER", {"subject"}},
    {"RESET", {}}, {"STATE", {}}
};
const set<string> REQUIRED = {
    "STATUS", "METHODS", "TOP", "HOURLY", "TIMELINE", "BANDWIDTH",
    "VISITORS", "HISTOGRAM", "APDEX", "ERRORS", "SLOWEST", "BURST", "PEAK", "GAPS"
};
const map<string, pair<int, int>> RANGES = {
    {"limit", {1, 100}}, {"minutes", {1, 1440}},
    {"width", {1, 100000}}, {"threshold", {1, 100000}},
    {"length", {1, 86400}}, {"times", {1, 1000}}
};
const map<string, string> ERRORS = {
    {"limit", "invalid number"}, {"minutes", "invalid number"},
    {"width", "invalid number"}, {"threshold", "invalid number"},
    {"length", "invalid number"}, {"times", "invalid number"},
    {"kind", "invalid kind"}, {"path", "invalid path"}, {"ip", "invalid ip"},
    {"date", "invalid timestamp"}, {"time", "invalid timestamp"},
    {"key", "invalid key"}, {"subject", "invalid key"}, {"value", "invalid value"}
};

struct QueryError : runtime_error {
    explicit QueryError(const string &message) : runtime_error(message) {}
};

void require_value(bool condition, const string &message) {
    if (!condition) throw QueryError(message);
}

vector<string> words(const string &line) {
    vector<string> result;
    istringstream stream(line);
    string word;
    while (stream >> word) result.push_back(word);
    return result;
}

vector<string> split(const string &s, char delimiter) {
    vector<string> parts;
    size_t begin = 0;
    for (size_t i = 0; i <= s.size(); ++i) {
        if (i == s.size() || s[i] == delimiter) {
            parts.push_back(s.substr(begin, i - begin));
            begin = i + 1;
        }
    }
    return parts;
}

bool digits(const string &s) {
    return !s.empty() && all_of(s.begin(), s.end(), [](char c) {
        return c >= '0' && c <= '9';
    });
}

bool canonical(const string &s, size_t limit) {
    return s.size() <= limit && digits(s) &&
        (s.size() == 1 || s.front() != '0');
}

bool leap_year(int year) {
    return year % 4 == 0 && (year % 100 != 0 || year % 400 == 0);
}

int year_days(int year) {
    return leap_year(year) ? 366 : 365;
}

int month_days(int year, int month) {
    return month == 2 && leap_year(year) ? 29 : MONTH_DAYS[month - 1];
}

bool valid_date(const string &s) {
    if (s.size() != 10 || s[4] != '-' || s[7] != '-') return false;
    string value = s.substr(0, 4) + s.substr(5, 2) + s.substr(8, 2);
    if (!digits(value)) return false;
    int year = stoi(s.substr(0, 4));
    int month = stoi(s.substr(5, 2));
    int day = stoi(s.substr(8, 2));
    return year >= 2000 && year <= 2059 && month >= 1 && month <= 12 &&
        day >= 1 && day <= month_days(year, month);
}

bool valid_time(const string &s) {
    if (s.size() != 8 || s[2] != ':' || s[5] != ':') return false;
    if (!digits(s.substr(0, 2) + s.substr(3, 2) + s.substr(6, 2))) return false;
    return stoi(s.substr(0, 2)) < 24 && stoi(s.substr(3, 2)) < 60 &&
        stoi(s.substr(6, 2)) < 60;
}

bool valid_ip(const string &ip) {
    vector<string> parts = split(ip, '.');
    if (parts.size() != 4) return false;
    for (const string &part : parts)
        if (!canonical(part, 3) || stoi(part) > 255) return false;
    return true;
}

bool valid_status(const string &s) {
    return s.size() == 3 && digits(s) && stoi(s) >= 100 && stoi(s) <= 599;
}

bool contains(const vector<string> &values, const string &s) {
    return find(values.begin(), values.end(), s) != values.end();
}

bool filter_value(const string &key, const string &value) {
    if (key == "METHOD") return contains(METHODS, value);
    if (key == "STATUS") return contains(CLASSES, value) || valid_status(value);
    if (key == "IP") return valid_ip(value);
    return !value.empty() && value[0] == '/';
}

bool valid_argument(const string &kind, const string &value,
                    const vector<string> &args) {
    auto range = RANGES.find(kind);
    if (range != RANGES.end()) {
        return canonical(value, 6) && stoi(value) >= range->second.first &&
            stoi(value) <= range->second.second;
    }
    if (kind == "kind") return value == "PATHS" || value == "IPS";
    if (kind == "path") return !value.empty() && value[0] == '/';
    if (kind == "ip") return valid_ip(value);
    if (kind == "date") return valid_date(value);
    if (kind == "time") return valid_time(value);
    if (kind == "key") return contains(KEYS, value);
    if (kind == "subject") return value == "RANGE" || contains(KEYS, value);
    return filter_value(args[0], value);
}

string malformed_reason(const vector<string> &fields) {
    if (fields.size() != 8) return "fields";
    if (!valid_date(fields[0])) return "date";
    if (!valid_time(fields[1])) return "time";
    if (!valid_ip(fields[2])) return "ip";
    if (!contains(METHODS, fields[3])) return "method";
    if (fields[4].empty() || fields[4][0] != '/') return "path";
    if (!valid_status(fields[5])) return "status";
    if (!canonical(fields[6], 8)) return "bytes";
    if (!canonical(fields[7], 6)) return "latency";
    return "";
}

int64_t seconds_of(const string &date, const string &clock) {
    int year = stoi(date.substr(0, 4));
    int month = stoi(date.substr(5, 2));
    int64_t days = stoi(date.substr(8, 2)) - 1;
    for (int y = 2000; y < year; ++y) days += year_days(y);
    for (int m = 1; m < month; ++m) days += month_days(year, m);
    return days * 86400 + stoi(clock.substr(0, 2)) * 3600 +
        stoi(clock.substr(3, 2)) * 60 + stoi(clock.substr(6, 2));
}

string interval_label(int64_t seconds) {
    int64_t days = seconds / 86400;
    int64_t minutes = seconds % 86400 / 60;
    int year = 2000;
    while (days >= year_days(year)) days -= year_days(year++);
    int month = 1;
    while (days >= month_days(year, month)) days -= month_days(year, month++);
    ostringstream out;
    out << setfill('0') << setw(4) << year << "-" << setw(2) << month
        << "-" << setw(2) << days + 1 << " "
        << setw(2) << minutes / 60 << ":" << setw(2) << minutes % 60;
    return out.str();
}

string normalize_path(const string &raw) {
    string path = raw.substr(0, raw.find('?'));
    vector<string> parts;
    for (const string &part : split(path, '/')) {
        if (part == "..") {
            if (!parts.empty()) parts.pop_back();
        } else if (!part.empty() && part != ".") {
            parts.push_back(part);
        }
    }
    for (string &part : parts) {
        if (digits(part)) {
            part = "{id}";
        } else if (part.size() >= 8 &&
                   all_of(part.begin(), part.end(), [](char c) {
                       return (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f');
                   }) &&
                   any_of(part.begin(), part.end(), [](char c) {
                       return c >= '0' && c <= '9';
                   })) {
            part = "{hex}";
        }
    }
    string result = "/";
    for (size_t i = 0; i < parts.size(); ++i) {
        if (i > 0) result += "/";
        result += parts[i];
    }
    return result;
}

bool ip_less(const string &a, const string &b) {
    vector<string> x = split(a, '.');
    vector<string> y = split(b, '.');
    for (size_t i = 0; i < 4; ++i) {
        if (stoi(x[i]) != stoi(y[i])) return stoi(x[i]) < stoi(y[i]);
    }
    return false;
}

bool status_matches(const string &filter, int status) {
    return contains(CLASSES, filter) ? status / 100 == filter[0] - '0'
        : status == stoi(filter);
}

string decimal(int64_t numerator, int64_t denominator, int places) {
    int64_t scale = places == 1 ? 10 : places == 2 ? 100 : 1000;
    int64_t value = numerator * scale / denominator;
    ostringstream out;
    out << value / scale << "." << setfill('0') << setw(places) << value % scale;
    return out.str();
}

string percent(int numerator, int denominator) {
    return decimal(static_cast<int64_t>(numerator) * 100, denominator, 2) + "%";
}

string bar(int n, int maximum) {
    return string((n * 30 + maximum - 1) / maximum, '#');
}

string bytes_text(int64_t size) {
    if (size >= 1073741824) return decimal(size, 1073741824, 1) + "GB";
    if (size >= 1048576) return decimal(size, 1048576, 1) + "MB";
    if (size >= 1024) return decimal(size, 1024, 1) + "KB";
    return to_string(size) + "B";
}

struct Record {
    int line;
    string date, timestamp, ip, method, path;
    int hour, status, latency;
    int64_t seconds, bytes;
};

Record make_record(int number, const vector<string> &fields) {
    return {
        number, fields[0], fields[0] + " " + fields[1],
        fields[2], fields[3], normalize_path(fields[4]),
        stoi(fields[1].substr(0, 2)), stoi(fields[5]), stoi(fields[7]),
        seconds_of(fields[0], fields[1]), stoll(fields[6])
    };
}

template <class Key>
map<string, vector<Record>> group_by(const vector<Record> &records, Key key) {
    map<string, vector<Record>> result;
    for (const Record &row : records) result[key(row)].push_back(row);
    return result;
}

template <class Key>
map<string, int> count_by(const vector<Record> &records, Key key) {
    map<string, int> result;
    for (const Record &row : records) result[key(row)]++;
    return result;
}

vector<string> by_count(const map<string, int> &counts, bool ip_order = false) {
    vector<string> names;
    for (const auto &entry : counts) names.push_back(entry.first);
    sort(names.begin(), names.end(), [&](const string &a, const string &b) {
        if (counts.at(a) != counts.at(b)) return counts.at(a) > counts.at(b);
        return ip_order ? ip_less(a, b) : a < b;
    });
    return names;
}

int64_t sum_bytes(const vector<Record> &records) {
    int64_t total = 0;
    for (const Record &r : records) total += r.bytes;
    return total;
}

int64_t sum_latency(const vector<Record> &records) {
    int64_t total = 0;
    for (const Record &r : records) total += r.latency;
    return total;
}

array<int, 5> class_counts(const vector<Record> &records) {
    array<int, 5> counts{};
    for (const Record &r : records) counts[r.status / 100 - 1]++;
    return counts;
}

struct Buckets {
    int64_t first;
    vector<int> counts;
};

Buckets bucket_counts(const vector<int64_t> &values) {
    auto low_high = minmax_element(values.begin(), values.end());
    int64_t first = *low_high.first;
    int64_t last = *low_high.second;
    require_value(last - first + 1 <= 60, "too many buckets");
    Buckets result{first, vector<int>(last - first + 1, 0)};
    for (int64_t value : values) result.counts[value - first]++;
    return result;
}

int percentile(const vector<int> &sorted, int rank) {
    return sorted[(rank * sorted.size() + 99) / 100 - 1];
}

struct Window {
    int count = 0;
    Record first{}, last{};
};

Window window_peak(const vector<Record> &records, int width) {
    Window result;
    size_t first = 0;
    for (size_t last = 0; last < records.size(); ++last) {
        while (records[last].seconds - records[first].seconds >= width) ++first;
        if (static_cast<int>(last - first + 1) > result.count) {
            result.count = last - first + 1;
            result.first = records[first];
            result.last = records[last];
        }
    }
    return result;
}

struct Apdex {
    int count = 0, satisfied = 0, tolerating = 0, frustrated = 0;
    int64_t points = 0, total = 0;
    string notation, rating;
};

Apdex apdex_score(const vector<Record> &records, int threshold) {
    Apdex result;
    result.count = records.size();
    for (const Record &r : records) {
        if (r.status >= 500) continue;
        if (r.latency <= threshold) ++result.satisfied;
        else if (r.latency <= 4 * threshold) ++result.tolerating;
    }
    result.frustrated = result.count - result.satisfied - result.tolerating;
    result.points = result.satisfied * 2LL + result.tolerating;
    result.total = result.count * 2LL;
    result.rating = result.points * 100 >= result.total * 94 ? "excellent" :
        result.points * 100 >= result.total * 85 ? "good" :
        result.points * 100 >= result.total * 70 ? "fair" :
        result.points * 100 >= result.total * 50 ? "poor" : "unacceptable";
    result.notation = decimal(result.points, result.total, 3);
    return result;
}

class Analyzer {
    vector<Record> records;
    vector<pair<int, string>> malformed;
    int line_count = 0;
    map<string, string> filters;
    bool has_range = false;
    int64_t from = 0, through = 0;
    string from_label, through_label;
    vector<string> output;

    template <class... Args>
    void emit(const Args &...args) {
        ostringstream out;
        bool first = true;
        ((out << (first ? "" : " ") << args, first = false), ...);
        output.push_back(out.str());
    }

    void emit_vector(const vector<string> &parts) {
        ostringstream out;
        for (size_t i = 0; i < parts.size(); ++i) {
            if (i > 0) out << " ";
            out << parts[i];
        }
        output.push_back(out.str());
    }

    vector<Record> selected() const {
        vector<Record> result;
        for (const Record &r : records) {
            if (has_range && (r.seconds < from || r.seconds > through)) continue;
            if (!filters.at("METHOD").empty() && filters.at("METHOD") != r.method) continue;
            if (!filters.at("STATUS").empty() &&
                !status_matches(filters.at("STATUS"), r.status)) continue;
            if (!filters.at("IP").empty() && filters.at("IP") != r.ip) continue;
            if (!filters.at("PATH").empty() && filters.at("PATH") != r.path) continue;
            result.push_back(r);
        }
        return result;
    }

    void bar_line(const string &label, int count, int maximum) {
        if (count == 0) emit(label, count);
        else emit(label, count, bar(count, maximum));
    }

    void run(const string &name, const vector<string> &a, const vector<Record> &rows) {
        if (name == "SUMMARY") {
            set<string> ips, paths;
            for (const Record &r : rows) {
                ips.insert(r.ip);
                paths.insert(r.path);
            }
            emit("SUMMARY", "lines", line_count, "valid", records.size(),
                "malformed", malformed.size());
            emit("requests", rows.size(), "bytes", sum_bytes(rows),
                "ips", ips.size(), "paths", paths.size());
            if (rows.empty()) emit("span", "none");
            else emit("span", rows.front().timestamp, rows.back().timestamp,
                rows.back().seconds - rows.front().seconds);

        } else if (name == "MALFORMED") {
            emit("MALFORMED", malformed.size());
            for (const string &reason : REASONS) {
                vector<string> parts = {reason};
                int n = 0;
                for (const auto &row : malformed) {
                    if (row.second == reason) {
                        parts.push_back(to_string(row.first));
                        ++n;
                    }
                }
                if (n > 0) {
                    parts.insert(parts.begin() + 1, to_string(n));
                    emit_vector(parts);
                }
            }

        } else if (name == "STATUS") {
            emit("STATUS", rows.size());
            auto class_count = class_counts(rows);
            for (int i = 0; i < 5; ++i)
                emit(CLASSES[i], class_count[i], percent(class_count[i], rows.size()));
            map<int, int> status;
            for (const Record &r : rows) status[r.status]++;
            for (const auto &entry : status)
                emit(entry.first, entry.second, percent(entry.second, rows.size()));

        } else if (name == "METHODS") {
            emit("METHODS", rows.size());
            auto counts = count_by(rows, [](const Record &r) { return r.method; });
            for (const string &method : by_count(counts))
                emit(method, counts[method], percent(counts[method], rows.size()));

        } else if (name == "TOP") {
            const string &kind = a[0];
            auto counts = count_by(rows, [&](const Record &r) {
                return kind == "PATHS" ? r.path : r.ip;
            });
            vector<string> names = by_count(counts, kind == "IPS");
            int shown = min(stoi(a[1]), static_cast<int>(names.size()));
            emit("TOP", kind, shown, "of", names.size());
            int rank = 0;
            for (int i = 0; i < shown; ++i) {
                if (i == 0 || counts[names[i]] != counts[names[i-1]]) rank = i+1;
                emit(rank, names[i], counts[names[i]], percent(counts[names[i]], rows.size()));
            }

        } else if (name == "HOURLY") {
            array<int, 24> counts{};
            for (const Record &r : rows) counts[r.hour]++;
            int maximum = *max_element(counts.begin(), counts.end());
            int first = find(counts.begin(), counts.end(), maximum) - counts.begin();
            ostringstream hour;
            hour << setfill('0') << setw(2) << first;
            emit("HOURLY", rows.size(), "peak", hour.str(), maximum);
            for (int i = 0; i < 24; ++i) {
                ostringstream label;
                label << setfill('0') << setw(2) << i;
                bar_line(label.str(), counts[i], maximum);
            }

        } else if (name == "TIMELINE") {
            int minutes = stoi(a[0]);
            int64_t width = minutes * 60LL;
            vector<int64_t> bucket_numbers;
            for (const Record &r : rows) bucket_numbers.push_back(r.seconds / width);
            Buckets buckets = bucket_counts(bucket_numbers);
            emit("TIMELINE", minutes, buckets.counts.size());
            int maximum = *max_element(buckets.counts.begin(), buckets.counts.end());
            for (size_t i = 0; i < buckets.counts.size(); ++i)
                bar_line(interval_label((buckets.first + i) * width),
                    buckets.counts[i], maximum);

        } else if (name == "BANDWIDTH") {
            auto days = group_by(rows, [](const Record &r) { return r.date; });
            int64_t total = sum_bytes(rows);
            emit("BANDWIDTH", days.size(), total, bytes_text(total));
            for (const auto &entry : days) {
                int64_t bytes = sum_bytes(entry.second);
                emit(entry.first, entry.second.size(), bytes, bytes_text(bytes));
            }

        } else if (name == "VISITORS") {
            map<string, string> first_date;
            for (const Record &r : rows) {
                if (first_date.find(r.ip) == first_date.end() || r.date < first_date[r.ip])
                    first_date[r.ip] = r.date;
            }
            auto days = group_by(rows, [](const Record &r) { return r.date; });
            emit("VISITORS", days.size(), first_date.size());
            for (const auto &entry : days) {
                set<string> ips;
                for (const Record &r : entry.second) ips.insert(r.ip);
                int fresh = 0;
                for (const string &ip : ips)
                    if (first_date[ip] == entry.first) ++fresh;
                emit(entry.first, "unique", ips.size(), "new", fresh,
                    "returning", ips.size() - fresh);
            }

        } else if (name == "LATENCY") {
            string label = a.empty() ? "all" : normalize_path(a[0]);
            vector<int> values;
            for (const Record &r : rows)
                if (a.empty() || r.path == label) values.push_back(r.latency);
            if (values.empty()) {
                emit("LATENCY", "no records");
            } else {
                sort(values.begin(), values.end());
                int n = values.size(), trim = n / 10;
                int64_t total = accumulate(values.begin(), values.end(), int64_t{0});
                int64_t trimmed_total = accumulate(
                    values.begin() + trim, values.end() - trim, int64_t{0});
                emit("LATENCY", label, "count", n, "min", values.front(),
                    "p50", percentile(values, 50), "p90", percentile(values, 90),
                    "p99", percentile(values, 99), "max", values.back(),
                    "mean", decimal(total, n, 2),
                    "trimmed", decimal(trimmed_total, n - trim * 2, 2));
            }

        } else if (name == "HISTOGRAM") {
            int width = stoi(a[0]);
            vector<int64_t> bucket_numbers;
            for (const Record &r : rows) bucket_numbers.push_back(r.latency / width);
            Buckets buckets = bucket_counts(bucket_numbers);
            emit("HISTOGRAM", width, buckets.counts.size());
            int maximum = *max_element(buckets.counts.begin(), buckets.counts.end());
            for (size_t i = 0; i < buckets.counts.size(); ++i) {
                int64_t low = (buckets.first + i) * width;
                bar_line(to_string(low) + "-" + to_string(low + width - 1),
                    buckets.counts[i], maximum);
            }

        } else if (name == "APDEX") {
            int threshold = stoi(a[0]);
            Apdex overall = apdex_score(rows, threshold);
            emit("APDEX", threshold, overall.notation, overall.rating,
                "satisfied", overall.satisfied, "tolerating", overall.tolerating,
                "frustrated", overall.frustrated);
            struct Item { string path; Apdex score; };
            vector<Item> paths;
            auto groups = group_by(rows, [](const Record &r) { return r.path; });
            for (const auto &entry : groups)
                paths.push_back({entry.first, apdex_score(entry.second, threshold)});
            sort(paths.begin(), paths.end(), [](const Item &a, const Item &b) {
                int64_t left = a.score.points * b.score.total;
                int64_t right = b.score.points * a.score.total;
                if (left != right) return left < right;
                if (a.score.count != b.score.count)
                    return a.score.count > b.score.count;
                return a.path < b.path;
            });
            for (const Item &item : paths)
                emit(item.path, item.score.notation, item.score.rating, item.score.count);

        } else if (name == "ERRORS") {
            int failed = 0;
            for (const Record &r : rows) if (r.status >= 400) ++failed;
            emit("ERRORS", failed, "of", rows.size(), percent(failed, rows.size()));
            struct Item { string path; int count, client, server; };
            vector<Item> paths;
            auto groups = group_by(rows, [](const Record &r) { return r.path; });
            for (const auto &entry : groups) {
                int client = 0, server = 0;
                for (const Record &r : entry.second) {
                    if (r.status / 100 == 4) ++client;
                    if (r.status / 100 == 5) ++server;
                }
                if (client + server > 0)
                    paths.push_back({entry.first, static_cast<int>(entry.second.size()),
                                     client, server});
            }
            sort(paths.begin(), paths.end(), [](const Item &a, const Item &b) {
                int64_t af = a.client + a.server, bf = b.client + b.server;
                if (bf * a.count != af * b.count)
                    return bf * a.count < af * b.count;
                if (af != bf) return bf > af;
                return a.path < b.path;
            });
            for (const Item &row : paths)
                emit(row.path, row.count, row.client, row.server,
                    percent(row.client + row.server, row.count));

        } else if (name == "SLOWEST") {
            struct Item {
                string method, path;
                int count, maximum;
                int64_t total;
            };
            vector<Item> endpoints;
            auto groups = group_by(rows, [](const Record &r) {
                return r.method + "\1" + r.path;
            });
            for (const auto &entry : groups) {
                size_t point = entry.first.find('\1');
                int maximum = 0;
                for (const Record &r : entry.second)
                    maximum = max(maximum, r.latency);
                endpoints.push_back({
                    entry.first.substr(0, point), entry.first.substr(point + 1),
                    static_cast<int>(entry.second.size()), maximum, sum_latency(entry.second)
                });
            }
            sort(endpoints.begin(), endpoints.end(), [](const Item &a, const Item &b) {
                if (b.total * a.count != a.total * b.count)
                    return b.total * a.count < a.total * b.count;
                if (a.maximum != b.maximum) return a.maximum > b.maximum;
                if (a.path != b.path) return a.path < b.path;
                return a.method < b.method;
            });
            int shown = min(stoi(a[0]), static_cast<int>(endpoints.size()));
            emit("SLOWEST", shown, "of", endpoints.size());
            for (int i = 0; i < shown; ++i) {
                const Item &e = endpoints[i];
                emit(i+1, e.method, e.path, "count", e.count,
                    "avg", decimal(e.total, e.count, 2), "max", e.maximum);
            }

        } else if (name == "SESSIONS") {
            string ip = a[0];
            int minutes = a.size() == 2 ? stoi(a[1]) : 30;
            vector<Record> found;
            for (const Record &r : rows) if (r.ip == ip) found.push_back(r);
            if (found.empty()) {
                emit("SESSIONS", "no records");
            } else {
                vector<vector<Record>> sessions{{found.front()}};
                for (size_t i = 1; i < found.size(); ++i) {
                    if (found[i].seconds - found[i-1].seconds <= minutes * 60)
                        sessions.back().push_back(found[i]);
                    else sessions.push_back({found[i]});
                }
                int64_t duration = 0;
                for (const auto &session : sessions)
                    duration += session.back().seconds - session.front().seconds;
                emit("SESSIONS", ip, "timeout", minutes, "count", sessions.size(),
                    "requests", found.size(),
                    "avg_duration", decimal(duration, sessions.size(), 1),
                    "avg_requests", decimal(found.size(), sessions.size(), 1));
                for (size_t i = 0; i < sessions.size(); ++i) {
                    const auto &session = sessions[i];
                    set<string> paths;
                    for (const Record &r : session) paths.insert(r.path);
                    emit(i+1, session.front().timestamp, session.back().timestamp,
                        session.back().seconds - session.front().seconds,
                        session.size(), paths.size());
                }
            }

        } else if (name == "BURST") {
            int width = stoi(a[0]), threshold = stoi(a[1]);
            vector<Record> failed;
            for (const Record &r : rows)
                if (r.status >= 400) failed.push_back(r);
            auto groups = group_by(failed, [](const Record &r) { return r.ip; });
            struct Item { string ip; Window window; };
            vector<Item> bursts;
            for (const auto &entry : groups) {
                Window peak = window_peak(entry.second, width);
                if (peak.count >= threshold) bursts.push_back({entry.first, peak});
            }
            sort(bursts.begin(), bursts.end(), [](const Item &a, const Item &b) {
                if (a.window.count != b.window.count)
                    return a.window.count > b.window.count;
                return ip_less(a.ip, b.ip);
            });
            emit("BURST", width, threshold, bursts.size());
            for (const Item &item : bursts)
                emit(item.ip, item.window.count,
                    item.window.first.timestamp, item.window.last.timestamp);

        } else if (name == "PEAK") {
            int width = stoi(a[0]);
            Window peak = window_peak(rows, width);
            emit("PEAK", width, peak.count,
                peak.first.timestamp, peak.last.timestamp);

        } else if (name == "GAPS") {
            int width = stoi(a[0]);
            vector<pair<Record, Record>> gaps;
            for (size_t i = 1; i < rows.size(); ++i) {
                if (rows[i].seconds - rows[i-1].seconds >= width)
                    gaps.push_back({rows[i-1], rows[i]});
            }
            emit("GAPS", width, gaps.size());
            for (const auto &gap : gaps)
                emit(gap.first.timestamp, gap.second.timestamp,
                    gap.second.seconds - gap.first.seconds);

        } else if (name == "IP") {
            string ip = a[0];
            vector<Record> found;
            for (const Record &r : rows) if (r.ip == ip) found.push_back(r);
            if (found.empty()) {
                emit("IP", "no records");
            } else {
                auto paths = count_by(found, [](const Record &r) { return r.path; });
                int failures = 0;
                for (const Record &r : found) if (r.status >= 400) ++failures;
                emit("IP", ip, "requests", found.size(), "bytes", sum_bytes(found),
                    "errors", failures, "paths", paths.size());
                emit("first", found.front().timestamp, "last", found.back().timestamp);
                auto methods = count_by(found, [](const Record &r) { return r.method; });
                vector<string> method_parts{"methods"};
                for (const string &method : by_count(methods)) {
                    method_parts.push_back(method);
                    method_parts.push_back(to_string(methods[method]));
                }
                emit_vector(method_parts);
                auto grouped_classes = class_counts(found);
                vector<string> class_parts{"classes"};
                for (size_t i = 0; i < CLASSES.size(); ++i) {
                    class_parts.push_back(CLASSES[i]);
                    class_parts.push_back(to_string(grouped_classes[i]));
                }
                emit_vector(class_parts);
                auto ranking = by_count(paths);
                for (size_t i = 0; i < ranking.size() && i < 3; ++i)
                    emit("path", ranking[i], paths[ranking[i]]);
            }

        } else if (name == "RANGE") {
            int64_t first = seconds_of(a[0], a[1]);
            int64_t last = seconds_of(a[2], a[3]);
            require_value(first <= last, "invalid range");
            from = first;
            through = last;
            from_label = a[0] + " " + a[1];
            through_label = a[2] + " " + a[3];
            has_range = true;
            emit("RANGE", from_label, through_label, "active", selected().size());

        } else if (name == "FILTER") {
            const string &key = a[0];
            string value = key == "PATH" ? normalize_path(a[1]) : a[1];
            filters[key] = value;
            emit("FILTER", key, value, "active", selected().size());

        } else if (name == "UNFILTER") {
            const string &key = a[0];
            if (key == "RANGE") {
                require_value(has_range, "not filtered");
                has_range = false;
            } else {
                require_value(!filters[key].empty(), "not filtered");
                filters[key].clear();
            }
            emit("UNFILTER", key, "active", selected().size());

        } else if (name == "RESET") {
            has_range = false;
            for (const string &key : KEYS) filters[key].clear();
            emit("RESET", "active", selected().size());

        } else if (name == "STATE") {
            vector<string> parts{
                "STATE", "active", to_string(rows.size()), "range",
                has_range ? from_label + " " + through_label : "-"
            };
            for (const string &key : KEYS) {
                string lowered = key;
                transform(lowered.begin(), lowered.end(), lowered.begin(),
                          [](unsigned char c) { return tolower(c); });
                parts.push_back(lowered);
                parts.push_back(filters[key].empty() ? "-" : filters[key]);
            }
            emit_vector(parts);
        }
    }

public:
    explicit Analyzer(const vector<string> &lines) : line_count(lines.size()) {
        for (size_t i = 0; i < lines.size(); ++i) {
            vector<string> fields = words(lines[i]);
            string reason = malformed_reason(fields);
            if (!reason.empty()) malformed.push_back({static_cast<int>(i+1), reason});
            else records.push_back(make_record(i+1, fields));
        }
        sort(records.begin(), records.end(), [](const Record &a, const Record &b) {
            return a.seconds < b.seconds ||
                (a.seconds == b.seconds && a.line < b.line);
        });
        for (const string &key : KEYS) filters[key] = "";
    }

    void execute(const string &line) {
        vector<string> parts = words(line);
        string name = parts.empty() ? "" : parts.front();
        vector<string> args;
        if (!parts.empty()) args.assign(parts.begin()+1, parts.end());
        try {
            auto form = FORMS.find(name);
            require_value(form != FORMS.end(), "unknown query");
            const auto &expected = form->second;
            bool optional = (name == "LATENCY" || name == "SESSIONS") &&
                args.size() + 1 == expected.size();
            require_value(args.size() == expected.size() || optional, "wrong arguments");
            for (size_t i = 0; i < args.size(); ++i)
                require_value(valid_argument(expected[i], args[i], args),
                    ERRORS.at(expected[i]));
            vector<Record> rows = selected();
            if (REQUIRED.count(name) && rows.empty()) emit(name, "no records");
            else run(name, args, rows);
        } catch (const QueryError &error) {
            emit("ERROR", error.what());
        }
    }

    void finish() const {
        for (const string &line : output) cout << line << '\n';
    }
};

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);

    vector<string> logs, queries;
    bool query_part = false;
    string line;
    while (getline(cin, line)) {
        if (!query_part) {
            if (line == "---") query_part = true;
            else logs.push_back(line);
        } else if (line == "END") {
            break;
        } else {
            queries.push_back(line);
        }
    }

    Analyzer analyzer(logs);
    for (const string &query : queries) analyzer.execute(query);
    analyzer.finish();
}
