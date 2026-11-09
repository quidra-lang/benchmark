#include "bgp.hpp"
#include <algorithm>
Node *Message::sender() const { return source->owner; }
Node *Message::receiver() const { return source->link->other(source->owner); }
Link *Message::link() const { return source->link; }
bool messageLess(const Message &a, const Message &b) {
    return std::make_tuple(a.time, a.receiver()->number, a.sender()->number, a.serial) <
           std::make_tuple(b.time, b.receiver()->number, b.sender()->number, b.serial);
}
static bool later(const Message &a, const Message &b) { return messageLess(b, a); }
Message MessageQueue::send(int time, Session *session, Prefix value,
                           const std::optional<Attribute> &attribute) {
    Message message{++serial, time + session->link->delay, session, value, attribute};
    heap.push_back(message);
    std::push_heap(heap.begin(), heap.end(), later);
    return message;
}
std::vector<Message> MessageQueue::arrivals(int time) {
    std::vector<Message> result;
    while (!heap.empty() && heap.front().time == time) {
        std::pop_heap(heap.begin(), heap.end(), later);
        result.push_back(std::move(heap.back()));
        heap.pop_back();
    }
    return result;
}
std::vector<Message> MessageQueue::ordered() const {
    std::vector<Message> result = heap;
    std::sort(result.begin(), result.end(), messageLess);
    return result;
}
std::vector<Message> MessageQueue::remove(Link *link) {
    std::vector<Message> result, keep;
    for (const Message &message : ordered())
        if (message.link() == link)
            result.push_back(message);
        else
            keep.push_back(message);
    heap = std::move(keep);
    std::make_heap(heap.begin(), heap.end(), later);
    return result;
}
std::vector<Event> readEvents() {
    std::vector<Event> result = {{0, 0, "INITIAL", "INITIAL", {}}};
    for (const std::string &line : readLines("input/events.txt")) {
        std::vector<std::string> a = words(line);
        std::string kind = a[1];
        if (kind == "LINK" || kind == "POLICY")
            kind += "_" + a[2];
        std::size_t space = line.find(' ');
        result.push_back({static_cast<int>(result.size()), std::stoi(a[0]), kind,
                          line.substr(space + 1),
                          std::vector<std::string>(a.begin() + 1, a.end())});
    }
    return result;
}
Parameters readParameters(Topology &topology) {
    std::vector<std::string> lines = readLines("input/params.txt"), a = words(lines[0]);
    Parameters parameters{
        std::stoi(a[1]), std::stoi(a[2]), std::stoi(a[3]), std::stoi(words(lines[1])[1]), {}};
    for (std::size_t i = 2; i < lines.size(); ++i) {
        a = words(lines[i]);
        parameters.traces.push_back({&topology.nodes.at(std::stoi(a[1])), ip(a[2]), a[2]});
    }
    return parameters;
}
