#pragma once
#include <algorithm>
#include <cstdint>
#include <map>
#include <memory>
#include <optional>
#include <set>
#include <sstream>
#include <string>
#include <tuple>
#include <utility>
#include <vector>

using Integer = std::int64_t;
using Lines = std::vector<std::string>;
template<class... Parts> std::string text(const Parts&... parts) { std::ostringstream stream; (stream << ... << parts); return stream.str(); }
template<class... Parts> void add(Lines& lines, const Parts&... parts) { lines.push_back(text(parts...)); }
struct SourceLine { int number; std::string text; };
using SourceLines = std::vector<SourceLine>;
struct Header {
    std::vector<std::pair<std::string, std::string>> fields;
    std::vector<int> invalid;
    std::optional<std::string> value(const std::string& name) const;
    int count(const std::string& name) const;
};
struct Token { std::string kind, text; bool spaced; };
using Tokens = std::vector<Token>;
bool whitespace(char character);
std::string lower(std::string value);
std::string strip(std::string value);
std::string stripTrailing(std::string value);
Lines split(const std::string& value, char separator);
Lines words(const std::string& value);
std::string join(const Lines& lines, const std::string& separator);
std::string collapse(const std::string& value);
Header parseFields(const SourceLines& lines);
std::optional<std::string> removeComments(const std::string& value);
std::optional<Tokens> tokenize(const std::string& value, bool mime);
struct DecodedWord { std::string text; bool decoded = false, error = false; };
DecodedWord decodeWord(const std::string& value);
std::pair<std::string, bool> decodeUnstructured(const std::string& value);
struct Parameters { std::string type, subtype; std::map<std::string, std::string> values; };
std::optional<Parameters> parseParameters(const std::string& value, bool subtype);
std::optional<std::string> strictBase64(const std::string& value);
std::optional<std::string> decodeBase64Body(const std::string& value);
std::pair<std::string, bool> decodeQuotedPrintable(const std::string& value);
int hexValue(char character);
struct Mailbox { std::string name, address; };
struct Address { bool group = false; std::vector<Mailbox> mailboxes; };
struct AddressList { std::vector<Address> addresses; bool encodingError = false; };
std::optional<AddressList> parseAddressList(const std::string& value);
struct DateResult { std::optional<Integer> seconds; std::string error; };
DateResult parseDate(const std::string& value);
std::string formatUtc(Integer seconds);
struct Entity {
    std::string number, type = "text", subtype = "plain", disposition, filename, content;
    std::map<std::string, std::string> parameters;
    bool multipart = false;
    std::vector<std::unique_ptr<Entity>> children;
    std::string parameter(const std::string& name) const { std::map<std::string, std::string>::const_iterator found = parameters.find(name); return found == parameters.end() ? "" : found->second; }
};
using SortKey = std::tuple<int, Integer, std::string, int>;
struct Message {
    int number, thread = 0, depth = 0, parent = -1;
    Lines problems, to, cc, references;
    std::optional<Mailbox> sender;
    std::string subject, baseSubject, id;
    bool reply = false;
    std::optional<Integer> date;
    std::unique_ptr<Entity> body;
    SortKey key() const { return {date ? 0 : 1, date.value_or(0), id, number}; }
};
struct Container {
    std::string id;
    int message = -1;
    Container* parent = nullptr;
    std::vector<Container*> children;
    std::optional<std::string> subject;
};
struct ThreadForest { std::vector<std::unique_ptr<Container>> storage; std::vector<Container*> roots; };
ThreadForest buildThreads(const std::vector<Message>& messages);
std::string rootSubject(const Container* root, const std::vector<Message>& messages);
