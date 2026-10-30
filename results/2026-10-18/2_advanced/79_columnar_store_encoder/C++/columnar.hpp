#ifndef COLUMNAR_HPP
#define COLUMNAR_HPP
#include <algorithm>
#include <array>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <map>
#include <memory>
#include <numeric>
#include <optional>
#include <set>
#include <sstream>
#include <string>
#include <utility>
#include <vector>
using Number = std::int64_t;
using Bytes = std::vector<std::uint8_t>;
using Numbers = std::vector<Number>;
using Lines = std::vector<std::string>;
template <class... T> std::string text(const T &...values) {
    std::ostringstream out;
    (out << ... << values);
    return out.str();
}
template <class... T> void line(Lines &out, const T &...values) { out.push_back(text(values...)); }
Lines read_lines(const std::string &path), split(const std::string &source, char delimiter = ' ');
std::string join(const Lines &values, const std::string &separator = ",");
void extend(Lines &out, const Lines &lines), append(Bytes &out, const Bytes &bytes);
enum class Type { Int, String, Bool, Date };
const std::array<std::string, 4> type_names{"INT", "STRING", "BOOL", "DATE"};
struct Value {
    bool null = true, unknown = false;
    Number number = 0;
    std::string string;
    static Value integer(Number number) {
        Value v;
        v.null = false;
        v.number = number;
        return v;
    }
    static Value word(std::string string) {
        Value v;
        v.null = false;
        v.string = std::move(string);
        return v;
    }
    bool operator==(const Value &other) const {
        return null == other.null && unknown == other.unknown &&
               (null || (number == other.number && string == other.string));
    }
    bool operator<(const Value &other) const {
        if (null != other.null)
            return null;
        if (null)
            return false;
        if (number != other.number)
            return number < other.number;
        return string < other.string;
    }
};
using Values = std::vector<Value>;
using Row = Values;
using Table = std::vector<Row>;
using Bounds = std::optional<std::pair<Value, Value>>;
struct Column {
    std::string name;
    Type kind;
    bool nullable;
};
struct Options {
    int row_group_size, page_size, dictionary_limit;
    std::vector<int> encoding;
};
struct Inputs {
    std::vector<Column> columns;
    Table rows;
    Options options;
    Lines queries;
    Bytes damaged;
};
Number day_number(const std::string &value);
Value parse_value(Type kind, const std::string &source);
std::string value_text(Type kind, const Value &value, const std::string &null = "NULL");
Inputs read_inputs();
void write_outputs(const std::map<std::string, Lines> &outputs);
struct Reader {
    const Bytes &data;
    std::size_t position = 0;
    int byte();
    Bytes read(std::size_t count);
    std::string string(std::size_t count);
    Number uleb(), zigzag(), integer(bool signed_value = false);
};
void write_uleb(Bytes &out, Number value), write_zigzag(Bytes &out, Number value),
    write_integer(Bytes &out, Number value);
int bits(Number value);
Bytes pack(const Numbers &values, int width), hybrid_encode(const Numbers &values, int width);
Numbers unpack(Reader &reader, int width, int count),
    hybrid_decode(Reader &reader, int width, int count);
Number adler32(const Bytes &data);
std::string hex(const Bytes &data), checksum_text(Number checksum);
extern const std::array<std::string, 5> methods;
std::vector<int> candidates(Type kind);
Bytes delta_encode(const Numbers &values),
    encode_values(Type kind, int method, const Values &values, const Values &dictionary = {});
Numbers delta_decode(Reader &reader);
Values decode_values(Reader &reader, Type kind, int method, int count,
                     const Values &dictionary = {});
Bytes encode_statistics(Type kind, const Bounds &bounds);
Bounds decode_statistics(Reader &reader, Type kind);
struct Literal {
    Type kind;
    Value value;
};
struct Condition {
    std::string operation, name;
    int column = -1;
    std::vector<Literal> literals;
    std::shared_ptr<Condition> left, right;
};
using Cond = std::shared_ptr<Condition>;
struct Item {
    std::string operation, name;
    int column = -1;
};
struct Query {
    std::vector<Item> items;
    bool star = false;
    Cond condition;
    std::optional<std::string> group_name, order_name;
    std::optional<int> group, order, limit;
    bool descending = false, aggregate = false;
    std::vector<int> needed, condition_columns;
    Lines headers;
};
Query parse_query(const std::string &source);
#endif
