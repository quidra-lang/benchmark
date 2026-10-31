#ifndef IRC_HPP
#define IRC_HPP
#include <algorithm>
#include <array>
#include <deque>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <map>
#include <optional>
#include <set>
#include <sstream>
#include <string>
#include <utility>
#include <vector>
using Names = std::vector<std::string>;
using Lines = Names;
struct Channel;
struct Parsed {
    std::string command;
    Names parameters;
};
Parsed parse(const std::string &raw);
std::string fold(std::string value);
bool digits(const std::string &value), valid_nickname(const std::string &value),
    valid_channel(const std::string &value, int maximum);
bool matches(std::string mask, std::string value);
std::string normalize(const std::string &argument);
struct Client {
    std::string identifier, hostname;
    int connection_time;
    std::optional<std::string> nickname, username;
    std::string realname;
    bool invisible = false, registered = false;
    std::optional<int> registration_time, last_speaking, ping_sent;
    int last_received, tokens;
    std::optional<int> refill_time;
    std::deque<std::string> queue;
    std::vector<Channel *> channels, invites;
    std::string away;
    int received = 0, sent = 0;
    bool active = true;
    Client(std::string identifier, std::string hostname, int time, int capacity)
        : identifier(std::move(identifier)), hostname(std::move(hostname)), connection_time(time),
          last_received(time), tokens(capacity) {};
    std::string addressee() const, prefix() const, mode() const;
    void use_token(int time, int capacity, int interval),
        refill(int time, int capacity, int interval);
};
struct Member {
    Client *client;
    bool op = false, voice = false;
    std::string status() const, display() const;
};
struct Ban {
    std::string mask, setter;
    int time;
};
struct Channel {
    std::string name;
    int created;
    std::vector<Member> members;
    std::string topic, topic_setter;
    int topic_time = 0;
    std::vector<Ban> bans;
    std::set<char> flags{'n', 't'};
    std::string key;
    int limit = 0, peak = 0, messages = 0;
    bool active = true;
    Channel(std::string name, int time) : name(std::move(name)), created(time) {};
    Member *member(const Client *client);
    const Member *member(const Client *client) const;
    void add(Client &client, bool op), remove(Client &client);
    std::string name_list(const Client &viewer) const, mode_display(bool include_key = true) const;
    bool banned(const Client &client) const, can_speak(const Client &client) const;
};
struct Change {
    char sign, character;
    std::optional<std::string> argument;
};
std::vector<Change> channel_items(const std::string &mode, const Names &arguments);
std::string change_string(const std::vector<Change> &changes);
template <class... T> void line(Lines &out, const T &...values) {
    std::ostringstream stream;
    (stream << ... << values);
    out.push_back(stream.str());
}
#endif
