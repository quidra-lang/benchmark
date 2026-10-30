#include "columnar.hpp"
Lines read_lines(const std::string &path) {
    std::ifstream file(path);
    Lines out;
    std::string source;
    while (std::getline(file, source))
        out.push_back(source);
    return out;
}
Lines split(const std::string &source, char delimiter) {
    Lines out;
    std::size_t start = 0;
    for (;;) {
        std::size_t end = source.find(delimiter, start);
        out.push_back(source.substr(start, end == std::string::npos ? end : end - start));
        if (end == std::string::npos)
            return out;
        start = end + 1;
    }
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
void extend(Lines &out, const Lines &lines) { out.insert(out.end(), lines.begin(), lines.end()); }
void append(Bytes &out, const Bytes &bytes) { out.insert(out.end(), bytes.begin(), bytes.end()); }
static bool leap(int year) { return year % 4 == 0 && (year % 100 != 0 || year % 400 == 0); }
static int month_days(int year, int month) {
    const int days[] = {31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31};
    return days[month - 1] + (month == 2 && leap(year));
}
static Number before_year(int year) {
    Number y = year - 1;
    return 365 * y + y / 4 - y / 100 + y / 400;
}
Number day_number(const std::string &value) {
    int year = std::stoi(value.substr(0, 4)), month = std::stoi(value.substr(5, 2)),
        day = std::stoi(value.substr(8, 2));
    Number result = before_year(year) - before_year(1970) + day - 1;
    for (int m = 1; m < month; ++m)
        result += month_days(year, m);
    return result;
}
Value parse_value(Type kind, const std::string &source) {
    if (source.empty())
        return {};
    if (kind == Type::String)
        return Value::word(source);
    if (kind == Type::Bool)
        return Value::integer(source == "true");
    return Value::integer(kind == Type::Date ? day_number(source) : std::stoll(source));
}
std::string value_text(Type kind, const Value &value, const std::string &null) {
    if (value.unknown)
        return "?";
    if (value.null)
        return null;
    if (kind == Type::String)
        return value.string;
    if (kind == Type::Bool)
        return value.number ? "true" : "false";
    if (kind == Type::Int)
        return std::to_string(value.number);
    int year = 1970, month = 1;
    Number day = value.number;
    while (day < 0) {
        --year;
        day += leap(year) ? 366 : 365;
    }
    while (day >= (leap(year) ? 366 : 365)) {
        day -= leap(year) ? 366 : 365;
        ++year;
    }
    while (day >= month_days(year, month)) {
        day -= month_days(year, month);
        ++month;
    }
    std::ostringstream out;
    out << std::setw(4) << std::setfill('0') << year << '-' << std::setw(2) << month << '-'
        << std::setw(2) << day + 1;
    return out.str();
}
Inputs read_inputs() {
    Inputs out;
    for (const std::string &source : read_lines("input/schema.txt")) {
        Lines f = split(source);
        int kind = int(std::find(type_names.begin(), type_names.end(), f[1]) - type_names.begin());
        out.columns.push_back({f[0], Type(kind), f[2] == "NULLABLE"});
    }
    Lines rows = read_lines("input/table.csv");
    for (std::size_t i = 1; i < rows.size(); ++i) {
        Lines fields = split(rows[i], ',');
        Row row;
        for (std::size_t c = 0; c < out.columns.size(); ++c)
            row.push_back(parse_value(out.columns[c].kind, fields[c]));
        out.rows.push_back(std::move(row));
    }
    Lines options = read_lines("input/options.txt");
    out.options.row_group_size = std::stoi(split(options[0])[1]);
    out.options.page_size = std::stoi(split(options[1])[1]);
    out.options.dictionary_limit = std::stoi(split(options[2])[1]);
    for (std::size_t i = 3; i < options.size(); ++i) {
        std::string method = split(options[i])[2];
        out.options.encoding.push_back(
            method == "AUTO"
                ? -1
                : int(std::find(methods.begin(), methods.end(), method) - methods.begin()));
    }
    out.queries = read_lines("input/queries.txt");
    for (const std::string &source : read_lines("input/damaged.hex"))
        for (std::size_t i = 0; i < source.size(); i += 2)
            out.damaged.push_back(std::uint8_t(std::stoi(source.substr(i, 2), nullptr, 16)));
    return out;
}
void write_outputs(const std::map<std::string, Lines> &outputs) {
    std::filesystem::create_directories("output");
    for (const auto &output : outputs) {
        std::ofstream file("output/" + output.first);
        for (const std::string &source : output.second)
            file << source << '\n';
    }
}
