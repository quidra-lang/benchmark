#include "irc.hpp"

struct Settings {
    std::string name, version, created, description;
    int nicklen, channellen, topiclen, maxchannels, bucket, refill, queue, pingfreq, timeout;
    Names motd;
};
enum class TrafficKind { Connect, Disconnect, Message };
struct Traffic {
    int time;
    std::string identifier, body;
    TrafficKind kind;
};
enum class DisconnectKind { Quit, Closed, Flood, Timeout };
struct Gone {
    int time;
    std::string identifier, addressee, reason;
};
struct Statistics {
    int dropped = 0, queued = 0, processed = 0, discarded = 0, empty = 0, pings = 0, errors = 0;
};
static Names split_list(const std::string &text) {
    Names out;
    std::size_t first = 0;
    for (;;) {
        std::size_t last = text.find(',', first);
        out.push_back(text.substr(first, last == std::string::npos ? last : last - first));
        if (last == std::string::npos)
            break;
        first = last + 1;
    }
    return out;
}
static std::string join(const Names &items, const std::string &separator) {
    std::string out;
    for (int i = 0; i < int(items.size()); ++i) {
        if (i)
            out += separator;
        out += items[i];
    }
    return out;
}
static std::string number3(int value) {
    std::ostringstream out;
    out << std::setw(3) << std::setfill('0') << value;
    return out.str();
}
class Server {
    Settings settings;
    std::vector<Traffic> traffic;
    int end = 0, time = 0;
    std::deque<Client> clients;
    std::deque<Channel> channels;
    std::map<std::string, Client *> by_id;
    std::map<std::string, Channel *> by_channel;
    Lines sent;
    std::map<std::string, int> commands;
    std::map<int, int> numeric_counts;
    std::array<int, 3> line_counts{};
    std::array<int, 4> disconnections{};
    Statistics statistics;
    std::vector<Gone> gone;
    std::pair<int, int> peak_connections{}, peak_registered{};

    void read_inputs() {
        std::map<std::string, std::string> values;
        std::ifstream server("input/server.txt");
        std::string text;
        while (std::getline(server, text)) {
            auto space = text.find(' ');
            std::string key = text.substr(0, space), value = text.substr(space + 1);
            if (key == "MOTD")
                settings.motd.push_back(value);
            else
                values[key] = value;
        }
        settings.name = values["NAME"];
        settings.version = values["VERSION"];
        settings.created = values["CREATED"];
        settings.description = values["DESCRIPTION"];
        settings.nicklen = std::stoi(values["NICKLEN"]);
        settings.channellen = std::stoi(values["CHANNELLEN"]);
        settings.topiclen = std::stoi(values["TOPICLEN"]);
        settings.maxchannels = std::stoi(values["MAXCHANNELS"]);
        settings.bucket = std::stoi(values["BUCKET"]);
        settings.refill = std::stoi(values["REFILL"]);
        settings.queue = std::stoi(values["QUEUE"]);
        settings.pingfreq = std::stoi(values["PINGFREQ"]);
        settings.timeout = std::stoi(values["TIMEOUT"]);
        std::ifstream input("input/traffic.txt");
        while (std::getline(input, text)) {
            auto first = text.find(' '), second = text.find(' ', first + 1);
            Traffic record{std::stoi(text.substr(0, first)),
                           text.substr(first + 1, second - first - 1), text.substr(second + 1),
                           TrafficKind::Message};
            if (record.body == "DISCONNECT")
                record.kind = TrafficKind::Disconnect;
            else if (record.body.rfind("CONNECT ", 0) == 0) {
                std::string host = record.body.substr(8);
                bool valid = !host.empty() && host.size() <= 63;
                for (char c : host)
                    if (!((c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') ||
                          (c >= '0' && c <= '9') || c == '.' || c == '-'))
                        valid = false;
                if (valid)
                    record.kind = TrafficKind::Connect;
            }
            ++line_counts[int(record.kind)];
            traffic.push_back(record);
        }
        end = traffic.back().time;
    }
    std::vector<Client *> active_clients() {
        std::vector<Client *> out;
        for (Client &client : clients)
            if (client.active)
                out.push_back(&client);
        return out;
    }
    void send(Client &client, const std::string &text) {
        line(sent, time, " ", client.identifier, " ", text);
        ++client.sent;
    }
    void numeric(Client &client, int number, const std::string &content) {
        ++numeric_counts[number];
        send(client, ":" + settings.name + " " + number3(number) + " " + client.addressee() + " " +
                         content);
    }
    void error(Client &client, int number, const std::string &value = "") {
        std::string content;
        switch (number) {
        case 401:
            content = value + " :No such nick/channel";
            break;
        case 403:
            content = value + " :No such channel";
            break;
        case 404:
            content = value + " :Cannot send to channel";
            break;
        case 405:
            content = value + " :You have joined too many channels";
            break;
        case 409:
            content = ":No origin specified";
            break;
        case 411:
            content = ":No recipient given (" + value + ")";
            break;
        case 412:
            content = ":No text to send";
            break;
        case 421:
            content = value + " :Unknown command";
            break;
        case 431:
            content = ":No nickname given";
            break;
        case 432:
            content = value + " :Erroneous nickname";
            break;
        case 433:
            content = value + " :Nickname is already in use";
            break;
        case 442:
            content = value + " :You're not on that channel";
            break;
        case 451:
            content = ":You have not registered";
            break;
        case 461:
            content = value + " :Not enough parameters";
            break;
        case 462:
            content = ":You may not reregister";
            break;
        case 467:
            content = value + " :Channel key already set";
            break;
        case 471:
            content = value + " :Cannot join channel (+l)";
            break;
        case 473:
            content = value + " :Cannot join channel (+i)";
            break;
        case 474:
            content = value + " :Cannot join channel (+b)";
            break;
        case 475:
            content = value + " :Cannot join channel (+k)";
            break;
        case 482:
            content = value + " :You're not channel operator";
            break;
        case 501:
            content = ":Unknown MODE flag";
            break;
        case 502:
            content = ":Cannot change mode for other users";
            break;
        }
        numeric(client, number, content);
    }
    bool require(Client &client, const Names &parameters, std::size_t count,
                 const std::string &command) {
        if (parameters.size() >= count)
            return true;
        error(client, 461, command);
        return false;
    }
    void broadcast(Channel &channel, const std::string &text, const Client *exclude = nullptr) {
        for (const Member &member : channel.members)
            if (member.client != exclude)
                send(*member.client, text);
    }
    void send_peers(Client &client, const std::string &text) {
        std::set<Client *> peers;
        for (Channel *channel : client.channels)
            for (const Member &member : channel->members)
                peers.insert(member.client);
        for (Client &other : clients)
            if (other.active && &other != &client && peers.count(&other))
                send(other, text);
    }
    Client *find_user(const std::string &nickname) {
        std::string name = fold(nickname);
        for (Client &client : clients)
            if (client.active && client.registered && fold(*client.nickname) == name)
                return &client;
        return nullptr;
    }
    Channel *find_channel(const std::string &name) {
        auto found = by_channel.find(fold(name));
        return found == by_channel.end() ? nullptr : found->second;
    }
    std::string joined_channels(const Client &client, const std::string &separator) const {
        Names out;
        for (Channel *channel : client.channels)
            out.push_back(channel->member(&client)->status() + channel->name);
        return join(out, separator);
    }
    void remove_member(Client &client, Channel &channel) {
        channel.remove(client);
        if (channel.members.empty()) {
            by_channel.erase(fold(channel.name));
            channel.active = false;
            for (Client &other : clients)
                if (other.active)
                    other.invites.erase(
                        std::remove(other.invites.begin(), other.invites.end(), &channel),
                        other.invites.end());
        }
    }
    void disconnect(Client &client, const std::string &reason, DisconnectKind kind) {
        if (kind != DisconnectKind::Closed) {
            send(client, "ERROR :Closing Link: " + client.addressee() + "[" + client.hostname +
                             "] (" + reason + ")");
            ++statistics.errors;
        }
        if (client.registered)
            send_peers(client, ":" + client.prefix() + " QUIT :" + reason);
        auto joined = client.channels;
        for (Channel *channel : joined)
            remove_member(client, *channel);
        statistics.discarded += int(client.queue.size());
        client.queue.clear();
        by_id.erase(client.identifier);
        client.active = false;
        gone.push_back({time, client.identifier, client.addressee(), reason});
        ++disconnections[int(kind)];
    }
    void complete_registration(Client &client) {
        if (client.registered || !client.nickname || !client.username)
            return;
        client.registered = true;
        client.registration_time = time;
        client.last_speaking = time;
        int registered = 0;
        for (const Client &other : clients)
            registered += other.active && other.registered;
        if (registered > peak_registered.first)
            peak_registered = {registered, time};
        numeric(client, 1, ":Welcome to the Internet Relay Network " + client.prefix());
        numeric(client, 2,
                ":Your host is " + settings.name + ", running version " + settings.version);
        numeric(client, 3, ":This server was created " + settings.created);
        numeric(client, 4, settings.name + " " + settings.version + " i biklmnotv");
        numeric(client, 5,
                "CASEMAPPING=rfc1459 CHANTYPES=# NICKLEN=" + std::to_string(settings.nicklen) +
                    " CHANNELLEN=" + std::to_string(settings.channellen) +
                    " TOPICLEN=" + std::to_string(settings.topiclen) +
                    " CHANLIMIT=#:" + std::to_string(settings.maxchannels) +
                    " CHANMODES=b,k,l,imnt PREFIX=(ov)@+ :are supported by this server");
        numeric(client, 375, ":- " + settings.name + " Message of the day -");
        for (const std::string &motd : settings.motd)
            numeric(client, 372, ":- " + motd);
        numeric(client, 376, ":End of /MOTD command.");
        if (client.invisible)
            send(client, ":" + *client.nickname + " MODE " + *client.nickname + " :+i");
    }
    void names_reply(Client &client, Channel &channel) {
        std::string names = channel.name_list(client);
        if (!names.empty())
            numeric(client, 353, "= " + channel.name + " :" + names);
        numeric(client, 366, channel.name + " :End of /NAMES list.");
    }
    void topic_replies(Client &client, const Channel &channel) {
        numeric(client, 332, channel.name + " :" + channel.topic);
        numeric(client, 333,
                channel.name + " " + channel.topic_setter + " " +
                    std::to_string(channel.topic_time));
    }
    void away_reply(Client &client, const Client &user) {
        numeric(client, 301, *user.nickname + " :" + user.away);
    }
    void nick(Client &client, const Names &p) {
        if (p.empty() || p[0].empty()) {
            error(client, 431);
            return;
        }
        std::string nickname = p[0].substr(0, settings.nicklen);
        if (!valid_nickname(nickname)) {
            error(client, 432, nickname);
            return;
        }
        if (client.nickname && *client.nickname == nickname)
            return;
        for (const Client &other : clients)
            if (other.active && &other != &client && other.nickname &&
                fold(*other.nickname) == fold(nickname)) {
                error(client, 433, nickname);
                return;
            }
        if (client.registered) {
            std::string text = ":" + client.prefix() + " NICK :" + nickname;
            send(client, text);
            send_peers(client, text);
        }
        client.nickname = nickname;
        complete_registration(client);
    }
    void user(Client &client, const Names &p) {
        if (client.username) {
            error(client, 462);
            return;
        }
        if (!require(client, p, 4, "USER"))
            return;
        client.username = p[0];
        client.realname = p[3];
        client.invisible = digits(p[1]) && p[1].size() <= 3 && (std::stoi(p[1]) / 8) % 2 == 1;
        complete_registration(client);
    }
    void join_channels(Client &client, const Names &p) {
        if (!require(client, p, 1, "JOIN"))
            return;
        if (p[0] == "0") {
            auto joined = client.channels;
            for (Channel *channel : joined) {
                broadcast(*channel, ":" + client.prefix() + " PART " + channel->name);
                remove_member(client, *channel);
            }
            return;
        }
        Names names = split_list(p[0]), keys = p.size() > 1 ? split_list(p[1]) : Names{};
        for (int i = 0; i < int(names.size()); ++i) {
            const std::string &name = names[i];
            std::string key = i < int(keys.size()) ? keys[i] : "";
            if (!valid_channel(name, settings.channellen)) {
                error(client, 403, name);
                continue;
            }
            Channel *channel = find_channel(name);
            if (channel && channel->member(&client))
                continue;
            if (client.channels.size() >= std::size_t(settings.maxchannels)) {
                error(client, 405, name);
                continue;
            }
            if (!channel) {
                channels.emplace_back(name, time);
                channel = &channels.back();
                by_channel[fold(name)] = channel;
            } else {
                bool invited = std::find(client.invites.begin(), client.invites.end(), channel) !=
                               client.invites.end();
                int failure = 0;
                if (channel->banned(client) && !invited)
                    failure = 474;
                else if (channel->flags.count('i') && !invited)
                    failure = 473;
                else if (!channel->key.empty() && key != channel->key)
                    failure = 475;
                else if (channel->limit && channel->members.size() >= std::size_t(channel->limit))
                    failure = 471;
                if (failure) {
                    error(client, failure, channel->name);
                    continue;
                }
            }
            client.invites.erase(std::remove(client.invites.begin(), client.invites.end(), channel),
                                 client.invites.end());
            bool first = channel->members.empty();
            channel->add(client, first);
            broadcast(*channel, ":" + client.prefix() + " JOIN " + channel->name);
            if (!channel->topic.empty())
                topic_replies(client, *channel);
            names_reply(client, *channel);
        }
    }
    void part(Client &client, const Names &p) {
        if (!require(client, p, 1, "PART"))
            return;
        std::string suffix = p.size() > 1 && !p[1].empty() ? " :" + p[1] : "";
        for (const std::string &name : split_list(p[0])) {
            Channel *channel = find_channel(name);
            if (!channel)
                error(client, 403, name);
            else if (!channel->member(&client))
                error(client, 442, channel->name);
            else {
                broadcast(*channel, ":" + client.prefix() + " PART " + channel->name + suffix);
                remove_member(client, *channel);
            }
        }
    }
    void message(Client &client, const Names &p, const std::string &command) {
        bool replies = command == "PRIVMSG";
        if (replies)
            client.last_speaking = time;
        if (p.empty() || p[0].empty()) {
            if (replies)
                error(client, 411, command);
            return;
        }
        if (p.size() < 2 || p[1].empty()) {
            if (replies)
                error(client, 412);
            return;
        }
        for (const std::string &target : split_list(p[0])) {
            if (!target.empty() && target[0] == '#') {
                Channel *channel = find_channel(target);
                if (!channel) {
                    if (replies)
                        error(client, 401, target);
                } else if (!channel->can_speak(client)) {
                    if (replies)
                        error(client, 404, channel->name);
                } else {
                    ++channel->messages;
                    broadcast(*channel,
                              ":" + client.prefix() + " " + command + " " + channel->name + " :" +
                                  p[1],
                              &client);
                }
            } else {
                Client *recipient = find_user(target);
                if (!recipient) {
                    if (replies)
                        error(client, 401, target);
                    continue;
                }
                send(*recipient, ":" + client.prefix() + " " + command + " " +
                                     *recipient->nickname + " :" + p[1]);
                if (replies && !recipient->away.empty())
                    away_reply(client, *recipient);
            }
        }
    }
    void topic(Client &client, const Names &p) {
        if (!require(client, p, 1, "TOPIC"))
            return;
        Channel *channel = find_channel(p[0]);
        if (!channel) {
            error(client, 403, p[0]);
            return;
        }
        Member *member = channel->member(&client);
        if (!member) {
            error(client, 442, channel->name);
            return;
        }
        if (p.size() == 1) {
            if (channel->topic.empty())
                numeric(client, 331, channel->name + " :No topic is set");
            else
                topic_replies(client, *channel);
            return;
        }
        if (channel->flags.count('t') && !member->op) {
            error(client, 482, channel->name);
            return;
        }
        channel->topic = p[1].substr(0, settings.topiclen);
        channel->topic_setter = *client.nickname;
        channel->topic_time = time;
        broadcast(*channel,
                  ":" + client.prefix() + " TOPIC " + channel->name + " :" + channel->topic);
    }
    void names(Client &client, const Names &p) {
        if (p.empty()) {
            numeric(client, 366, "* :End of /NAMES list.");
            return;
        }
        for (const std::string &name : split_list(p[0])) {
            Channel *channel = find_channel(name);
            if (channel)
                names_reply(client, *channel);
            else
                numeric(client, 366, name + " :End of /NAMES list.");
        }
    }
    void whois(Client &client, const Names &p) {
        if (p.empty()) {
            error(client, 431);
            return;
        }
        Client *target = find_user(p[0]);
        if (!target) {
            error(client, 401, p[0]);
            numeric(client, 318, p[0] + " :End of /WHOIS list.");
            return;
        }
        numeric(client, 311,
                *target->nickname + " " + *target->username + " " + target->hostname +
                    " * :" + target->realname);
        if (!target->channels.empty())
            numeric(client, 319, *target->nickname + " :" + joined_channels(*target, " "));
        numeric(client, 312, *target->nickname + " " + settings.name + " :" + settings.description);
        if (!target->away.empty())
            away_reply(client, *target);
        numeric(client, 317,
                *target->nickname + " " + std::to_string(time - *target->last_speaking) + " " +
                    std::to_string(*target->registration_time) + " :seconds idle, signon time");
        numeric(client, 318, *target->nickname + " :End of /WHOIS list.");
    }
    void invite(Client &client, const Names &p) {
        if (!require(client, p, 2, "INVITE"))
            return;
        Client *target = find_user(p[0]);
        if (!target) {
            error(client, 401, p[0]);
            return;
        }
        Channel *channel = find_channel(p[1]);
        if (!channel) {
            error(client, 403, p[1]);
            return;
        }
        Member *member = channel->member(&client);
        if (!member) {
            error(client, 442, channel->name);
            return;
        }
        if (channel->member(target)) {
            numeric(client, 443,
                    *target->nickname + " " + channel->name + " :is already on channel");
            return;
        }
        if (channel->flags.count('i') && !member->op) {
            error(client, 482, channel->name);
            return;
        }
        if (std::find(target->invites.begin(), target->invites.end(), channel) ==
            target->invites.end())
            target->invites.push_back(channel);
        numeric(client, 341, *target->nickname + " " + channel->name);
        if (!target->away.empty())
            away_reply(client, *target);
        send(*target,
             ":" + client.prefix() + " INVITE " + *target->nickname + " :" + channel->name);
    }
    void kick(Client &client, const Names &p) {
        if (!require(client, p, 2, "KICK"))
            return;
        Channel *channel = find_channel(p[0]);
        if (!channel) {
            error(client, 403, p[0]);
            return;
        }
        Member *member = channel->member(&client);
        if (!member) {
            error(client, 442, channel->name);
            return;
        }
        if (!member->op) {
            error(client, 482, channel->name);
            return;
        }
        Client *target = find_user(p[1]);
        if (!target) {
            error(client, 401, p[1]);
            return;
        }
        if (!channel->member(target)) {
            numeric(client, 441,
                    *target->nickname + " " + channel->name + " :They aren't on that channel");
            return;
        }
        std::string reason = p.size() > 2 && !p[2].empty() ? p[2] : *client.nickname;
        broadcast(*channel, ":" + client.prefix() + " KICK " + channel->name + " " +
                                *target->nickname + " :" + reason);
        remove_member(*target, *channel);
    }
    void user_mode(Client &client, const Names &p) {
        Client *target = find_user(p[0]);
        if (!target) {
            error(client, 401, p[0]);
            return;
        }
        if (target != &client) {
            error(client, 502);
            return;
        }
        if (p.size() == 1) {
            numeric(client, 221, client.mode());
            return;
        }
        char sign = '+';
        bool unknown = false;
        std::vector<Change> changes;
        for (char character : p[1]) {
            if (character == '+' || character == '-')
                sign = character;
            else if (character == 'i') {
                bool desired = sign == '+';
                if (client.invisible != desired) {
                    client.invisible = desired;
                    changes.push_back({sign, character, {}});
                }
            } else
                unknown = true;
        }
        if (!changes.empty())
            send(client, ":" + *client.nickname + " MODE " + *client.nickname + " :" +
                             change_string(changes));
        if (unknown)
            error(client, 501);
    }
    std::optional<Change> apply_channel_mode(Client &client, Channel &channel, const Change &item) {
        bool adding = item.sign == '+';
        char character = item.character;
        bool changed = false;
        std::optional<std::string> argument;
        if (character == 'o' || character == 'v') {
            Client *target = find_user(*item.argument);
            if (!target) {
                error(client, 401, *item.argument);
                return {};
            }
            Member *member = channel.member(target);
            if (!member) {
                numeric(client, 441,
                        *target->nickname + " " + channel.name + " :They aren't on that channel");
                return {};
            }
            bool &privilege = character == 'o' ? member->op : member->voice;
            if (privilege != adding) {
                privilege = adding;
                changed = true;
                argument = *target->nickname;
            }
        } else if (character == 'b') {
            std::string mask = normalize(*item.argument);
            auto found = std::find_if(channel.bans.begin(), channel.bans.end(),
                                      [&](const Ban &ban) { return fold(ban.mask) == fold(mask); });
            if (adding && found == channel.bans.end()) {
                channel.bans.push_back({mask, *client.nickname, time});
                changed = true;
                argument = mask;
            } else if (!adding && found != channel.bans.end()) {
                argument = found->mask;
                channel.bans.erase(found);
                changed = true;
            }
        } else if (character == 'k') {
            if (adding) {
                if (!channel.key.empty())
                    error(client, 467, channel.name);
                else {
                    channel.key = *item.argument;
                    changed = true;
                    argument = *item.argument;
                }
            } else if (!channel.key.empty()) {
                channel.key.clear();
                changed = true;
                argument = "*";
            }
        } else if (character == 'l') {
            if (adding) {
                int limit = std::stoi(*item.argument);
                if (channel.limit != limit) {
                    channel.limit = limit;
                    changed = true;
                    argument = std::to_string(limit);
                }
            } else if (channel.limit) {
                channel.limit = 0;
                changed = true;
            }
        } else {
            bool present = channel.flags.count(character) != 0;
            if (present != adding) {
                if (adding)
                    channel.flags.insert(character);
                else
                    channel.flags.erase(character);
                changed = true;
            }
        }
        if (changed)
            return Change{item.sign, character, argument};
        return {};
    }
    void channel_mode(Client &client, const Names &p) {
        Channel *channel = find_channel(p[0]);
        if (!channel) {
            error(client, 403, p[0]);
            return;
        }
        if (p.size() == 1) {
            numeric(client, 324,
                    channel->name + " " +
                        channel->mode_display(channel->member(&client) != nullptr));
            numeric(client, 329, channel->name + " " + std::to_string(channel->created));
            return;
        }
        Names arguments(p.begin() + 2, p.end());
        auto items = channel_items(p[1], arguments);
        const Member *member = channel->member(&client);
        bool authorized = member && member->op, bans_sent = false, denial_sent = false;
        std::vector<Change> changes;
        for (const Change &item : items) {
            char character = item.character;
            if (std::string("biklmnotv").find(character) == std::string::npos) {
                numeric(client, 472,
                        std::string(1, character) + " :is unknown mode char to me for " +
                            channel->name);
                continue;
            }
            if (character == 'b' && !item.argument) {
                if (item.sign == '+' && !bans_sent) {
                    for (const Ban &ban : channel->bans)
                        numeric(client, 367,
                                channel->name + " " + ban.mask + " " + ban.setter + " " +
                                    std::to_string(ban.time));
                    numeric(client, 368, channel->name + " :End of channel ban list");
                    bans_sent = true;
                }
                continue;
            }
            if (!item.argument && (character == 'o' || character == 'v' ||
                                   (item.sign == '+' && (character == 'k' || character == 'l'))))
                continue;
            if (!authorized) {
                if (!denial_sent) {
                    error(client, 482, channel->name);
                    denial_sent = true;
                }
                continue;
            }
            auto change = apply_channel_mode(client, *channel, item);
            if (change)
                changes.push_back(*change);
        }
        if (!changes.empty())
            broadcast(*channel, ":" + client.prefix() + " MODE " + channel->name + " " +
                                    change_string(changes));
    }
    void process(Client &client, const std::string &raw) {
        ++statistics.processed;
        Parsed parsed = parse(raw);
        const std::string &command = parsed.command;
        const Names &p = parsed.parameters;
        if (command.empty()) {
            ++statistics.empty;
            return;
        }
        ++commands[command];
        if (!client.registered && command != "NICK" && command != "USER" && command != "PING" &&
            command != "PONG" && command != "QUIT") {
            error(client, 451);
            return;
        }
        if (command == "NICK")
            nick(client, p);
        else if (command == "USER")
            user(client, p);
        else if (command == "PING") {
            if (p.empty() || p[0].empty())
                error(client, 409);
            else
                send(client, ":" + settings.name + " PONG " + settings.name + " :" + p[0]);
        } else if (command == "PONG")
            return;
        else if (command == "QUIT")
            disconnect(client, p.empty() || p[0].empty() ? "Client Quit" : "Quit: " + p[0],
                       DisconnectKind::Quit);
        else if (command == "JOIN")
            join_channels(client, p);
        else if (command == "PART")
            part(client, p);
        else if (command == "PRIVMSG" || command == "NOTICE")
            message(client, p, command);
        else if (command == "TOPIC")
            topic(client, p);
        else if (command == "NAMES")
            names(client, p);
        else if (command == "WHOIS")
            whois(client, p);
        else if (command == "AWAY") {
            client.away = p.empty() ? "" : p[0];
            numeric(client, client.away.empty() ? 305 : 306,
                    client.away.empty() ? ":You are no longer marked as being away"
                                        : ":You have been marked as being away");
        } else if (command == "INVITE")
            invite(client, p);
        else if (command == "KICK")
            kick(client, p);
        else if (command == "MODE") {
            if (require(client, p, 1, "MODE")) {
                if (!p[0].empty() && p[0][0] == '#')
                    channel_mode(client, p);
                else
                    user_mode(client, p);
            }
        } else
            error(client, 421, command);
    }
    void arrival(const Traffic &record) {
        if (record.kind == TrafficKind::Connect) {
            clients.emplace_back(record.identifier, record.body.substr(8), time, settings.bucket);
            by_id[record.identifier] = &clients.back();
            int count = int(by_id.size());
            if (count > peak_connections.first)
                peak_connections = {count, time};
            return;
        }
        auto found = by_id.find(record.identifier);
        Client *client = found == by_id.end() ? nullptr : found->second;
        if (record.kind == TrafficKind::Disconnect) {
            if (client)
                disconnect(*client, "Remote host closed the connection", DisconnectKind::Closed);
            return;
        }
        if (!client) {
            ++statistics.dropped;
            return;
        }
        ++client->received;
        client->last_received = time;
        client->ping_sent.reset();
        if (client->queue.empty() && client->tokens >= 1) {
            client->use_token(time, settings.bucket, settings.refill);
            process(*client, record.body);
        } else if (client->queue.size() >= std::size_t(settings.queue)) {
            ++statistics.discarded;
            disconnect(*client, "Excess Flood", DisconnectKind::Flood);
        } else {
            client->queue.push_back(record.body);
            ++statistics.queued;
        }
    }
    Lines channel_report() const {
        Lines out;
        int count = 0, members = 0, bans = 0;
        for (const Channel &channel : channels)
            if (channel.active) {
                ++count;
                members += int(channel.members.size());
                bans += int(channel.bans.size());
                line(out, "CHANNEL ", channel.name, " created ", channel.created, " members ",
                     channel.members.size(), " peak ", channel.peak, " messages ", channel.messages,
                     " modes ", channel.mode_display());
                if (channel.topic.empty())
                    out.push_back("TOPIC none");
                else
                    line(out, "TOPIC ", channel.topic_setter, " ", channel.topic_time, " ",
                         channel.topic);
                for (const Ban &ban : channel.bans)
                    line(out, "BAN ", ban.mask, " ", ban.setter, " ", ban.time);
                Names names;
                for (const Member &member : channel.members)
                    names.push_back(member.display());
                line(out, "MEMBERS ", join(names, " "));
            }
        line(out, "TOTAL channels ", count, " members ", members, " bans ", bans);
        return out;
    }
    Lines client_report() const {
        Lines out;
        int count = 0, registered = 0, invisible = 0, away = 0;
        for (const Client &client : clients)
            if (client.active) {
                ++count;
                registered += client.registered;
                invisible += client.invisible;
                away += !client.away.empty();
                std::string joined = joined_channels(client, ",");
                Names invites;
                for (const Channel *channel : client.invites)
                    invites.push_back(channel->name);
                line(out, "CLIENT ", client.identifier, " ", client.addressee(), " ",
                     client.username.value_or("*"), " ", client.hostname, " ", client.mode(),
                     " connected ", client.connection_time, " signon ",
                     client.registered ? std::to_string(*client.registration_time) : "-",
                     " received ", client.received, " sent ", client.sent, " tokens ",
                     client.tokens, " queue ", client.queue.size(), " channels ",
                     joined.empty() ? "none" : joined, " invites ",
                     invites.empty() ? "none" : join(invites, ","));
                if (!client.away.empty())
                    line(out, "AWAY ", client.identifier, " ", client.away);
            }
        line(out, "TOTAL clients ", count, " registered ", registered, " invisible ", invisible,
             " away ", away);
        return out;
    }
    Lines statistics_report() const {
        Lines out;
        int pending = 0;
        for (const Client &client : clients)
            if (client.active)
                pending += int(client.queue.size());
        int numerics = 0;
        for (const auto &entry : numeric_counts)
            numerics += entry.second;
        line(out, "END ", end);
        line(out, "LINES total ", traffic.size(), " connect ", line_counts[0], " disconnect ",
             line_counts[1], " messages ", line_counts[2]);
        line(out, "MESSAGES dropped ", statistics.dropped, " queued ", statistics.queued,
             " processed ", statistics.processed, " discarded ", statistics.discarded, " pending ",
             pending, " empty ", statistics.empty);
        line(out, "SENT lines ", sent.size(), " numerics ", numerics, " pings ", statistics.pings,
             " errors ", statistics.errors);
        for (const auto &entry : commands)
            line(out, "COMMAND ", entry.first, " ", entry.second);
        for (const auto &entry : numeric_counts)
            line(out, "NUMERIC ", number3(entry.first), " ", entry.second);
        line(out, "PEAK connections ", peak_connections.first, " at ", peak_connections.second);
        line(out, "PEAK registered ", peak_registered.first, " at ", peak_registered.second);
        line(out, "DISCONNECTS quit ", disconnections[0], " closed ", disconnections[1], " flood ",
             disconnections[2], " timeout ", disconnections[3]);
        for (const Gone &record : gone)
            line(out, "GONE ", record.time, " ", record.identifier, " ", record.addressee, " ",
                 record.reason);
        return out;
    }
    void write(const std::string &name, const Lines &lines) const {
        std::ofstream file("output/" + name);
        for (const std::string &text : lines)
            file << text << '\n';
    }

  public:
    void run() {
        read_inputs();
        std::size_t position = 0;
        for (time = 0; time <= end; ++time) {
            for (Client *client : active_clients()) {
                client->refill(time, settings.bucket, settings.refill);
                while (client->active && !client->queue.empty() && client->tokens >= 1) {
                    client->use_token(time, settings.bucket, settings.refill);
                    std::string raw = client->queue.front();
                    client->queue.pop_front();
                    process(*client, raw);
                }
            }
            while (position < traffic.size() && traffic[position].time == time)
                arrival(traffic[position++]);
            for (Client *client : active_clients()) {
                if (client->ping_sent) {
                    if (time - *client->ping_sent >= settings.timeout)
                        disconnect(*client,
                                   "Ping timeout: " + std::to_string(time - client->last_received) +
                                       " seconds",
                                   DisconnectKind::Timeout);
                } else if (time - client->last_received >= settings.pingfreq) {
                    send(*client, "PING :" + settings.name);
                    ++statistics.pings;
                    client->ping_sent = time;
                }
            }
        }
        std::filesystem::create_directories("output");
        write("sent.txt", sent);
        write("channels.txt", channel_report());
        write("clients.txt", client_report());
        write("stats.txt", statistics_report());
    }
};
int main() { Server().run(); }
