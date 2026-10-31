#ifndef BGP_HPP
#define BGP_HPP
#include <array>
#include <cstdint>
#include <map>
#include <optional>
#include <set>
#include <string>
#include <tuple>
#include <vector>
struct Prefix {
    std::uint64_t address = 0;
    int length = 0;
    bool contains(std::uint64_t) const;
    std::string text() const;
    bool operator<(const Prefix &p) const {
        return std::tie(address, length) < std::tie(p.address, p.length);
    }
    bool operator==(const Prefix &p) const { return address == p.address && length == p.length; }
};
std::uint64_t ip(const std::string &);
std::string ipText(std::uint64_t);
Prefix prefix(const std::string &);
struct Attribute {
    std::vector<int> path;
    int origin = 0, med = 0;
    std::set<std::uint32_t> communities;
    bool operator==(const Attribute &) const;
};
struct Link;
struct Session;
struct Route {
    Attribute attribute;
    bool local = false;
    int preference = 0;
    Link *link = nullptr;
    bool operator==(const Route &) const;
};
struct Node {
    int number = 0;
    std::uint64_t router = 0;
    std::map<Prefix, Attribute> origins;
    std::map<Prefix, Route> rib;
    std::vector<Session *> sessions;
    int changes = 0;
};
struct Link {
    std::string name;
    Node *a = nullptr, *b = nullptr;
    bool peer = false, up = true;
    int delay = 0, mrai = 0, number = 0, downs = 0;
    std::array<Session *, 2> sessions{};
    Node *other(const Node *) const;
    int role(const Node *) const;
    Session *session(const Node *) const;
};
struct Session {
    Node *owner = nullptr;
    Link *link = nullptr;
    std::map<Prefix, Attribute> incoming, outgoing;
    std::set<Prefix> pending;
    int timer = -1, sent = 0, received = 0;
};
struct Initial {
    Node *node;
    Prefix prefix;
    Attribute attribute;
};
struct Topology {
    std::map<int, Node> nodes;
    std::vector<Link> links;
    std::vector<Session> sessionStorage;
    std::vector<Session *> sessions;
    std::vector<Initial> initial;
    Link *named(const std::string &);
    Link *between(int, int);
};
Topology readTopology();
const char *roleName(int);
char directionSymbol(int);
constexpr std::uint32_t noExport = 0xffffff01u;
std::uint32_t community(const std::string &);
std::string communityText(std::uint32_t);
std::set<std::uint32_t> communities(const std::vector<std::string> &, std::size_t);
std::string communitiesText(const std::set<std::uint32_t> &);
struct PrefixEntry {
    bool permit;
    Prefix prefix;
    int low, high;
};
struct Condition {
    std::string kind, value;
};
struct Edit {
    bool add;
    std::uint32_t community;
};
struct Rule {
    std::string name, direction, target;
    int owner = 0, preference = 0, med = 0, prepend = 0, hits = 0;
    bool active = false, deny = false, allow = false, hasPreference = false, hasMed = false;
    std::vector<Condition> conditions;
    std::vector<Edit> edits;
    std::set<std::uint32_t> edit(std::set<std::uint32_t>) const;
};
struct Policies {
    std::map<std::string, std::vector<PrefixEntry>> lists;
    std::vector<Rule> rules;
    bool permitted(const std::string &, Prefix) const;
    Rule *applied(const std::string &, Session *, Prefix, const Attribute &);
    Rule *named(const std::string &);
};
Policies readPolicies();
std::pair<Route, std::string> bestRoute(std::vector<Route>, const Topology &);
struct Message {
    int serial, time;
    Session *source;
    Prefix prefix;
    std::optional<Attribute> attribute;
    Node *sender() const;
    Node *receiver() const;
    Link *link() const;
};
bool messageLess(const Message &, const Message &);
struct MessageQueue {
    std::vector<Message> heap;
    int serial = 0;
    Message send(int, Session *, Prefix, const std::optional<Attribute> &);
    std::vector<Message> arrivals(int);
    std::vector<Message> ordered() const;
    std::vector<Message> remove(Link *);
};
struct Event {
    int number, time;
    std::string kind, text;
    std::vector<std::string> args;
};
struct Trace {
    Node *source;
    std::uint64_t address;
    std::string text;
};
struct Parameters {
    int customer, peer, provider, stepcap;
    std::vector<Trace> traces;
};
std::vector<Event> readEvents();
Parameters readParameters(Topology &);
std::vector<std::string> readLines(const std::string &);
std::vector<std::string> words(const std::string &);
std::string join(const std::vector<std::string> &, const std::string &);
std::string pathText(const std::vector<int> &);
std::string attributeText(const Attribute &);
std::string routeText(const std::optional<Route> &);
const char *originName(int);
int originRank(const std::string &);
void writeLines(const std::string &, const std::vector<std::string> &);
#endif
