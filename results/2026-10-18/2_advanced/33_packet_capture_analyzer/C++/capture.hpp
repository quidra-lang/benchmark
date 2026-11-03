#ifndef CAPTURE_HPP
#define CAPTURE_HPP
#include <algorithm>
#include <array>
#include <cstdint>
#include <fstream>
#include <iomanip>
#include <map>
#include <memory>
#include <optional>
#include <regex>
#include <set>
#include <sstream>
#include <stdexcept>
#include <string>
#include <tuple>
#include <utility>
#include <vector>
using Integer = std::int64_t;
using Bytes = std::vector<unsigned char>;
struct Value {
    Integer number = 0;
    std::string text;
};
struct Packet {
    Integer number = 0, time = 0, length = 0;
    Bytes raw, remaining;
    std::string reason;
    std::vector<std::string> layers;
    std::map<std::string, std::vector<Value>> fields;
    std::vector<std::pair<Integer, std::string>> dns_answers;
    Integer duplicate_origin = 0, duplicate_count = 0;
    void n(const std::string &name, Integer value, bool append = false);
    void s(const std::string &name, const std::string &value, bool append = false);
    void flag(const std::string &name);
    bool has(const std::string &name) const;
    Integer num(const std::string &name) const;
    std::string str(const std::string &name) const;
};
std::string decimal(Integer value);
std::string hex(Integer value, int width = 0);
std::string seconds(Integer time);
std::string join(const std::vector<std::string> &values, const std::string &delimiter);
std::vector<std::string> read_lines(const std::string &path);
Integer read_integer(const Bytes &data, std::size_t position, std::size_t count);
Bytes slice(const Bytes &data, std::size_t first, std::size_t last);
std::string checksum(const Bytes &data);
std::string mac(Integer address);
std::string ipv4(Integer address);
Bytes ethernet(Packet &packet, const Bytes &data);
void arp(Packet &packet, const Bytes &data);
Bytes internet(Packet &packet, const Bytes &data);
Bytes icmp(Packet &packet, const Bytes &data);
Bytes udp(Packet &packet, const Bytes &data);
Bytes tcp(Packet &packet, const Bytes &data);
void dns(Packet &packet, const Bytes &data);
std::string type_name(Integer type);
std::string rcode_name(Integer code);
std::vector<Packet> read_capture();
std::vector<std::string> dump_lines(const Bytes &data);
struct Endpoint {
    Integer address = 0, port = 0;
    bool operator==(const Endpoint &other) const {
        return address == other.address && port == other.port;
    }
    bool operator<(const Endpoint &other) const {
        return std::tie(address, port) < std::tie(other.address, other.port);
    }
};
struct Side {
    std::optional<Integer> isn, mss, ws, base, expected;
    Integer advanced = 0, packets = 0, payload = 0;
    std::set<std::pair<Integer, Integer>> intervals;
    std::optional<std::array<Integer, 4>> previous_ack;
    std::array<Integer, 4> marks{};
};
struct Event {
    Integer packet;
    int side, mark;
    Integer seq, length;
};
struct Stream {
    Endpoint client, server;
    std::string state;
    std::vector<std::pair<std::string, Integer>> history;
    Integer start = 0, end = 0, packets = 0, bytes = 0, f2 = 0;
    std::array<std::optional<Integer>, 3> handshake;
    std::array<Side, 2> sides;
    std::vector<Event> events;
    int first_close = -1;
};
extern const std::array<std::string, 4> mark_names;
void track(Packet &packet, std::vector<Stream> &streams);
struct Conversation {
    int kind;
    Endpoint a, b;
    Integer first, start, end;
    std::array<Integer, 2> packets{}, bytes{};
};
struct EndpointTotals {
    Integer address;
    std::array<Integer, 2> packets{}, bytes{};
};
std::vector<Conversation> conversations(const std::vector<Packet> &packets);
std::vector<EndpointTotals> endpoints(const std::vector<Packet> &packets);
std::string endpoint(Endpoint value, bool port = true);
#endif
