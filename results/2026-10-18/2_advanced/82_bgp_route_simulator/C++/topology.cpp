#include "bgp.hpp"
#include <algorithm>
#include <sstream>
#include <stdexcept>
std::uint64_t ip(const std::string &text) {
    std::istringstream input(text);
    std::uint64_t result = 0;
    std::string part;
    while (std::getline(input, part, '.'))
        result = result * 256 + std::stoull(part);
    return result;
}
std::string ipText(std::uint64_t value) {
    return std::to_string(value >> 24) + "." + std::to_string((value >> 16) & 255) + "." +
           std::to_string((value >> 8) & 255) + "." + std::to_string(value & 255);
}
Prefix prefix(const std::string &text) {
    std::size_t slash = text.find('/');
    return {ip(text.substr(0, slash)), std::stoi(text.substr(slash + 1))};
}
bool Prefix::contains(std::uint64_t value) const {
    return address >> (32 - length) == value >> (32 - length);
}
std::string Prefix::text() const { return ipText(address) + "/" + std::to_string(length); }
Node *Link::other(const Node *node) const { return node == a ? b : a; }
int Link::role(const Node *node) const { return peer ? 1 : node == a ? 0 : 2; }
Session *Link::session(const Node *node) const { return sessions[node == a ? 0 : 1]; }
const char *roleName(int role) {
    static const char *names[] = {"customer", "peer", "provider"};
    return names[role];
}
char directionSymbol(int role) { return "DPU"[role]; }
Link *Topology::named(const std::string &name) {
    for (Link &link : links)
        if (link.name == name)
            return &link;
    throw std::runtime_error("unknown link");
}
Link *Topology::between(int a, int b) {
    for (Session *session : nodes.at(a).sessions)
        if (session->link->other(session->owner)->number == b)
            return session->link;
    throw std::runtime_error("missing link");
}
Topology readTopology() {
    Topology topology;
    topology.links.reserve(100);
    topology.sessionStorage.reserve(200);
    for (const std::string &line : readLines("input/topology.txt")) {
        std::vector<std::string> a = words(line);
        if (a[0] == "AS") {
            Node node;
            node.number = std::stoi(a[1]);
            node.router = ip(a[2]);
            topology.nodes.emplace(node.number, std::move(node));
        } else if (a[0] == "LINK") {
            Link link;
            link.name = a[1];
            link.a = &topology.nodes.at(std::stoi(a[2]));
            link.b = &topology.nodes.at(std::stoi(a[3]));
            link.peer = a[4] == "P2P";
            link.delay = std::stoi(a[5]);
            link.mrai = std::stoi(a[6]);
            link.number = static_cast<int>(topology.links.size());
            topology.links.push_back(std::move(link));
            Link *stored = &topology.links.back();
            for (int side = 0; side < 2; ++side) {
                Node *node = side == 0 ? stored->a : stored->b;
                Session session;
                session.owner = node;
                session.link = stored;
                topology.sessionStorage.push_back(std::move(session));
                stored->sessions[side] = &topology.sessionStorage.back();
                node->sessions.push_back(stored->sessions[side]);
            }
        } else {
            Attribute attribute;
            attribute.origin = originRank(a[3]);
            attribute.communities = communities(a, 4);
            topology.initial.push_back(
                {&topology.nodes.at(std::stoi(a[1])), prefix(a[2]), std::move(attribute)});
        }
    }
    for (std::pair<const int, Node> &entry : topology.nodes)
        for (Session *session : entry.second.sessions)
            topology.sessions.push_back(session);
    return topology;
}
