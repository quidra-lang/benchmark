#include "simulation.hpp"
I Random::draw() {
    state = 48271 * state % 2147483647;
    ++draws;
    return state;
}
int Topology::index(const std::string &name) const {
    return int(std::find(names.begin(), names.end(), name) - names.begin());
}
Topology read_topology() {
    Topology out;
    std::ifstream input("input/topology.txt");
    std::string text, key, name;
    std::getline(input, text);
    std::istringstream header(text);
    header >> key;
    while (header >> name)
        out.names.push_back(name);
    const int n = int(out.names.size());
    out.channels.resize(n * n);
    while (std::getline(input, text)) {
        std::istringstream row(text);
        std::string source, destination, type;
        Channel channel;
        row >> key >> source >> destination >> type >> channel.minimum;
        channel.maximum = channel.minimum;
        row >> channel.maximum;
        channel.source = out.index(source);
        channel.destination = out.index(destination);
        channel.fifo = type == "FIFO";
        channel.previous.assign(n, 0);
        out.channels[channel.source * n + channel.destination] = channel;
    }
    return out;
}
std::pair<int, int> dispatch(Channel &channel, int time, bool marker, const Vector &clock,
                             Random &random) {
    ++channel.sequence;
    const I delay =
        channel.minimum + (channel.minimum == channel.maximum
                               ? 0
                               : random.draw() % (channel.maximum - channel.minimum + 1));
    int arrival = time + int(delay);
    if (channel.fifo)
        arrival = std::max(arrival, channel.last_arrival);
    channel.last_arrival = std::max(channel.last_arrival, arrival);
    channel.max_delay = std::max(channel.max_delay, arrival - time);
    if (marker)
        ++channel.markers;
    else {
        ++channel.messages;
        for (int i = 0; i < int(clock.size()); ++i)
            channel.entries += clock[i] != channel.previous[i];
        channel.previous = clock;
    }
    return {channel.sequence, arrival};
}
std::string delay_text(const Channel &channel) {
    return std::to_string(channel.minimum) +
           (channel.minimum == channel.maximum ? "" : "-" + std::to_string(channel.maximum));
}
