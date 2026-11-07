#include "irc.hpp"
std::string Member::status() const { return op ? "@" : voice ? "+" : ""; }
std::string Member::display() const { return status() + *client->nickname; }
Member *Channel::member(const Client *client) {
    for (Member &m : members)
        if (m.client == client)
            return &m;
    return nullptr;
}
const Member *Channel::member(const Client *client) const {
    for (const Member &m : members)
        if (m.client == client)
            return &m;
    return nullptr;
}
void Channel::add(Client &client, bool op) {
    members.push_back({&client, op, false});
    client.channels.push_back(this);
    peak = std::max(peak, int(members.size()));
}
void Channel::remove(Client &client) {
    auto found = std::find_if(members.begin(), members.end(),
                              [&](const Member &m) { return m.client == &client; });
    members.erase(found);
    auto joined = std::find(client.channels.begin(), client.channels.end(), this);
    client.channels.erase(joined);
}
std::string Channel::name_list(const Client &viewer) const {
    bool inside = member(&viewer) != nullptr;
    std::string out;
    for (const Member &m : members)
        if (inside || !m.client->invisible) {
            if (!out.empty())
                out += ' ';
            out += m.display();
        }
    return out;
}
bool Channel::banned(const Client &client) const {
    for (const Ban &ban : bans)
        if (matches(ban.mask, client.prefix()))
            return true;
    return false;
}
bool Channel::can_speak(const Client &client) const {
    const Member *m = member(&client);
    bool privileged = m && (m->op || m->voice);
    return (m || !flags.count('n')) && (!flags.count('m') || privileged) &&
           (privileged || !banned(client));
}
std::string Channel::mode_display(bool include_key) const {
    std::string out = "+";
    for (char c : std::string("iklmnt")) {
        bool present = c == 'k' ? !key.empty() : c == 'l' ? limit != 0 : flags.count(c) != 0;
        if (present)
            out += c;
    }
    if (include_key && !key.empty())
        out += ' ' + key;
    if (limit)
        out += ' ' + std::to_string(limit);
    return out;
}
