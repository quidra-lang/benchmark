#include "irc.h"

typedef struct {
    char name[81], version[81], created[81], description[81];
    int nicklen, channellen, topiclen, maxchannels, bucket, refill, queue, pingfreq, timeout;
    char motd[20][81];
    int motd_count;
} Settings;
typedef enum { CONNECT_LINE, DISCONNECT_LINE, MESSAGE_LINE } TrafficKind;
typedef struct {
    int time;
    char identifier[9], body[401];
    TrafficKind kind;
} Traffic;
DEFINE_VECTOR(TrafficList, Traffic)
typedef enum { QUIT_KIND, CLOSED_KIND, FLOOD_KIND, TIMEOUT_KIND } DisconnectKind;
typedef struct {
    int time;
    char identifier[9], addressee[31], reason[407];
} Gone;
DEFINE_VECTOR(GoneList, Gone)
typedef struct {
    char *name;
    int count;
} CommandCount;
DEFINE_VECTOR(Commands, CommandCount)
typedef struct {
    int dropped, queued, processed, discarded, empty, pings, errors;
} Statistics;
typedef struct {
    Settings settings;
    TrafficList traffic;
    int end, time;
    Clients clients;
    Channels channels;
    int active_clients[100], client_count, active_channels[100], channel_count;
    FILE *sent;
    int sent_count, numeric_counts[1000], line_counts[3], disconnections[4];
    Commands commands;
    Statistics statistics;
    GoneList gone;
    int peak_connections, peak_connection_time, peak_registered, peak_registered_time;
} Server;
typedef struct {
    char *data;
    size_t count, capacity;
} Text;
static void text_add(Text *text, const char *format, ...) {
    va_list args, copy;
    va_start(args, format);
    va_copy(copy, args);
    size_t n = (size_t)vsnprintf(NULL, 0, format, copy);
    va_end(copy);
    if (text->count + n + 1 > text->capacity) {
        text->capacity = text->count + n + 128;
        text->data = realloc(text->data, text->capacity);
    }
    vsnprintf(text->data + text->count, n + 1, format, args);
    va_end(args);
    text->count += n;
}
static char *copy_string(const char *text) {
    size_t n = strlen(text) + 1;
    char *out = malloc(n);
    memcpy(out, text, n);
    return out;
}
static char *formatted(const char *format, va_list args) {
    va_list copy;
    va_copy(copy, args);
    int count = vsnprintf(NULL, 0, format, copy);
    va_end(copy);
    char *out = malloc((size_t)count + 1);
    vsnprintf(out, (size_t)count + 1, format, args);
    return out;
}
DEFINE_VECTOR(Names, char *)
static Names split_list(const char *text) {
    Names out = {0};
    const char *first = text;
    for (;;) {
        const char *last = strchr(first, ',');
        size_t n = last ? (size_t)(last - first) : strlen(first);
        char *part = malloc(n + 1);
        memcpy(part, first, n);
        part[n] = 0;
        Names_append(&out, part);
        if (!last)
            break;
        first = last + 1;
    }
    return out;
}
static void free_names(Names *names) {
    for (size_t i = 0; i < names->count; ++i)
        free(names->items[i]);
    free(names->items);
}
static void send_line(Server *s, Client *client, const char *text) {
    fprintf(s->sent, "%d %s %s\n", s->time, client->identifier, text);
    ++s->sent_count;
    ++client->sent;
}
static void sendf(Server *s, Client *client, const char *format, ...) {
    va_list args;
    va_start(args, format);
    char *text = formatted(format, args);
    va_end(args);
    send_line(s, client, text);
    free(text);
}
static void numeric(Server *s, Client *client, int code, const char *format, ...) {
    va_list args;
    va_start(args, format);
    char *content = formatted(format, args);
    va_end(args);
    ++s->numeric_counts[code];
    sendf(s, client, ":%s %03d %s %s", s->settings.name, code, client_addressee(client), content);
    free(content);
}
static void error(Server *s, Client *client, int code, const char *value) {
    switch (code) {
    case 401:
        numeric(s, client, code, "%s :No such nick/channel", value);
        break;
    case 403:
        numeric(s, client, code, "%s :No such channel", value);
        break;
    case 404:
        numeric(s, client, code, "%s :Cannot send to channel", value);
        break;
    case 405:
        numeric(s, client, code, "%s :You have joined too many channels", value);
        break;
    case 409:
        numeric(s, client, code, ":No origin specified");
        break;
    case 411:
        numeric(s, client, code, ":No recipient given (%s)", value);
        break;
    case 412:
        numeric(s, client, code, ":No text to send");
        break;
    case 421:
        numeric(s, client, code, "%s :Unknown command", value);
        break;
    case 431:
        numeric(s, client, code, ":No nickname given");
        break;
    case 432:
        numeric(s, client, code, "%s :Erroneous nickname", value);
        break;
    case 433:
        numeric(s, client, code, "%s :Nickname is already in use", value);
        break;
    case 442:
        numeric(s, client, code, "%s :You're not on that channel", value);
        break;
    case 451:
        numeric(s, client, code, ":You have not registered");
        break;
    case 461:
        numeric(s, client, code, "%s :Not enough parameters", value);
        break;
    case 462:
        numeric(s, client, code, ":You may not reregister");
        break;
    case 467:
        numeric(s, client, code, "%s :Channel key already set", value);
        break;
    case 471:
        numeric(s, client, code, "%s :Cannot join channel (+l)", value);
        break;
    case 473:
        numeric(s, client, code, "%s :Cannot join channel (+i)", value);
        break;
    case 474:
        numeric(s, client, code, "%s :Cannot join channel (+b)", value);
        break;
    case 475:
        numeric(s, client, code, "%s :Cannot join channel (+k)", value);
        break;
    case 482:
        numeric(s, client, code, "%s :You're not channel operator", value);
        break;
    case 501:
        numeric(s, client, code, ":Unknown MODE flag");
        break;
    case 502:
        numeric(s, client, code, ":Cannot change mode for other users");
        break;
    }
}
static bool require(Server *s, Client *client, const Parsed *p, int count, const char *command) {
    if (p->count >= count)
        return true;
    error(s, client, 461, command);
    return false;
}
static void broadcastf(Server *s, Channel *channel, int exclude, const char *format, ...) {
    va_list args;
    va_start(args, format);
    char *text = formatted(format, args);
    va_end(args);
    for (int i = 0; i < channel->member_count; ++i)
        if (channel->members[i].client != exclude)
            send_line(s, s->clients.items[channel->members[i].client], text);
    free(text);
}
static void peersf(Server *s, Client *client, const char *format, ...) {
    va_list args;
    va_start(args, format);
    char *text = formatted(format, args);
    va_end(args);
    bool *peers = calloc(s->clients.count, sizeof *peers);
    for (int i = 0; i < client->channel_count; ++i) {
        Channel *ch = s->channels.items[client->channels[i]];
        for (int j = 0; j < ch->member_count; ++j)
            peers[ch->members[j].client] = true;
    }
    for (int i = 0; i < s->client_count; ++i) {
        int number = s->active_clients[i];
        if (number != client->number && peers[number])
            send_line(s, s->clients.items[number], text);
    }
    free(peers);
    free(text);
}
static Client *find_id(Server *s, const char *identifier) {
    for (int i = 0; i < s->client_count; ++i) {
        Client *client = s->clients.items[s->active_clients[i]];
        if (!strcmp(client->identifier, identifier))
            return client;
    }
    return NULL;
}
static Client *find_user(Server *s, const char *nickname) {
    for (int i = 0; i < s->client_count; ++i) {
        Client *client = s->clients.items[s->active_clients[i]];
        if (client->registered && rfc_equal(client->nickname, nickname))
            return client;
    }
    return NULL;
}
static Channel *find_channel(Server *s, const char *name) {
    for (int i = 0; i < s->channel_count; ++i) {
        Channel *channel = s->channels.items[s->active_channels[i]];
        if (rfc_equal(channel->name, name))
            return channel;
    }
    return NULL;
}
static char *joined_channels(Server *s, const Client *client, const char *separator) {
    Text text = {0};
    for (int i = 0; i < client->channel_count; ++i) {
        Channel *ch = s->channels.items[client->channels[i]];
        if (i)
            text_add(&text, "%s", separator);
        text_add(&text, "%s%s", member_status(channel_member(ch, client->number)), ch->name);
    }
    return text.data ? text.data : copy_string("");
}
static void remove_member(Server *s, Client *client, Channel *channel) {
    channel_remove(channel, client, client->number);
    if (channel->member_count)
        return;
    channel->active = false;
    for (int i = 0; i < s->channel_count; ++i)
        if (s->active_channels[i] == channel->number) {
            memmove(s->active_channels + i, s->active_channels + i + 1,
                    (size_t)(s->channel_count - i - 1) * sizeof *s->active_channels);
            --s->channel_count;
            break;
        }
    for (int i = 0; i < s->client_count; ++i) {
        Client *other = s->clients.items[s->active_clients[i]];
        for (int j = 0; j < other->invite_count; ++j)
            if (other->invites[j] == channel->number) {
                memmove(other->invites + j, other->invites + j + 1,
                        (size_t)(other->invite_count - j - 1) * sizeof *other->invites);
                --other->invite_count;
                break;
            }
    }
}
static void disconnect(Server *s, Client *client, const char *reason, DisconnectKind kind) {
    if (kind != CLOSED_KIND) {
        sendf(s, client, "ERROR :Closing Link: %s[%s] (%s)", client_addressee(client),
              client->hostname, reason);
        ++s->statistics.errors;
    }
    if (client->registered)
        peersf(s, client, ":%s QUIT :%s", client_prefix(client), reason);
    while (client->channel_count)
        remove_member(s, client, s->channels.items[client->channels[0]]);
    s->statistics.discarded += client->queue_count;
    for (int i = 0; i < client->queue_count; ++i)
        free(client->queue[i]);
    client->queue_count = 0;
    for (int i = 0; i < s->client_count; ++i)
        if (s->active_clients[i] == client->number) {
            memmove(s->active_clients + i, s->active_clients + i + 1,
                    (size_t)(s->client_count - i - 1) * sizeof *s->active_clients);
            --s->client_count;
            break;
        }
    client->active = false;
    Gone record = {0};
    record.time = s->time;
    strcpy(record.identifier, client->identifier);
    strcpy(record.addressee, client_addressee(client));
    strcpy(record.reason, reason);
    GoneList_append(&s->gone, record);
    ++s->disconnections[kind];
}
static void complete_registration(Server *s, Client *client) {
    if (client->registered || !client->nick_set || !client->user_set)
        return;
    client->registered = true;
    client->registration_time = client->last_speaking = s->time;
    int registered = 0;
    for (int i = 0; i < s->client_count; ++i)
        registered += s->clients.items[s->active_clients[i]]->registered;
    if (registered > s->peak_registered) {
        s->peak_registered = registered;
        s->peak_registered_time = s->time;
    }
    numeric(s, client, 1, ":Welcome to the Internet Relay Network %s", client_prefix(client));
    numeric(s, client, 2, ":Your host is %s, running version %s", s->settings.name,
            s->settings.version);
    numeric(s, client, 3, ":This server was created %s", s->settings.created);
    numeric(s, client, 4, "%s %s i biklmnotv", s->settings.name, s->settings.version);
    numeric(
        s, client, 5,
        "CASEMAPPING=rfc1459 CHANTYPES=# NICKLEN=%d CHANNELLEN=%d TOPICLEN=%d CHANLIMIT=#:%d CHANMODES=b,k,l,imnt PREFIX=(ov)@+ :are supported by this server",
        s->settings.nicklen, s->settings.channellen, s->settings.topiclen, s->settings.maxchannels);
    numeric(s, client, 375, ":- %s Message of the day -", s->settings.name);
    for (int i = 0; i < s->settings.motd_count; ++i)
        numeric(s, client, 372, ":- %s", s->settings.motd[i]);
    numeric(s, client, 376, ":End of /MOTD command.");
    if (client->invisible)
        sendf(s, client, ":%s MODE %s :+i", client->nickname, client->nickname);
}
static void names_reply(Server *s, Client *client, Channel *channel) {
    char *names = channel_names(channel, s->clients.items, client->number);
    if (names[0])
        numeric(s, client, 353, "= %s :%s", channel->name, names);
    numeric(s, client, 366, "%s :End of /NAMES list.", channel->name);
    free(names);
}
static void topic_replies(Server *s, Client *client, Channel *channel) {
    numeric(s, client, 332, "%s :%s", channel->name, channel->topic);
    numeric(s, client, 333, "%s %s %d", channel->name, channel->topic_setter, channel->topic_time);
}
static void away_reply(Server *s, Client *client, Client *user) {
    numeric(s, client, 301, "%s :%s", user->nickname, user->away);
}
static void nick(Server *s, Client *client, const Parsed *p) {
    if (p->count == 0 || p->parameters[0][0] == 0) {
        error(s, client, 431, "");
        return;
    }
    char nickname[31];
    size_t length = strlen(p->parameters[0]);
    if (length > (size_t)s->settings.nicklen)
        length = (size_t)s->settings.nicklen;
    memcpy(nickname, p->parameters[0], length);
    nickname[length] = 0;
    if (!valid_nickname(nickname)) {
        error(s, client, 432, nickname);
        return;
    }
    if (client->nick_set && !strcmp(client->nickname, nickname))
        return;
    for (int i = 0; i < s->client_count; ++i) {
        Client *other = s->clients.items[s->active_clients[i]];
        if (other != client && other->nick_set && rfc_equal(other->nickname, nickname)) {
            error(s, client, 433, nickname);
            return;
        }
    }
    if (client->registered) {
        sendf(s, client, ":%s NICK :%s", client_prefix(client), nickname);
        peersf(s, client, ":%s NICK :%s", client_prefix(client), nickname);
    }
    strcpy(client->nickname, nickname);
    client->nick_set = true;
    complete_registration(s, client);
}
static void user(Server *s, Client *client, const Parsed *p) {
    if (client->user_set) {
        error(s, client, 462, "");
        return;
    }
    if (!require(s, client, p, 4, "USER"))
        return;
    strcpy(client->username, p->parameters[0]);
    strcpy(client->realname, p->parameters[3]);
    client->user_set = true;
    client->invisible = digits(p->parameters[1]) && strlen(p->parameters[1]) <= 3 &&
                        (atoi(p->parameters[1]) / 8) % 2 == 1;
    complete_registration(s, client);
}
static void join_channels(Server *s, Client *client, const Parsed *p) {
    if (!require(s, client, p, 1, "JOIN"))
        return;
    if (!strcmp(p->parameters[0], "0")) {
        while (client->channel_count) {
            Channel *ch = s->channels.items[client->channels[0]];
            broadcastf(s, ch, -1, ":%s PART %s", client_prefix(client), ch->name);
            remove_member(s, client, ch);
        }
        return;
    }
    Names names = split_list(p->parameters[0]), keys = {0};
    if (p->count > 1)
        keys = split_list(p->parameters[1]);
    for (size_t i = 0; i < names.count; ++i) {
        const char *name = names.items[i], *key = i < keys.count ? keys.items[i] : "";
        if (!valid_channel(name, s->settings.channellen)) {
            error(s, client, 403, name);
            continue;
        }
        Channel *ch = find_channel(s, name);
        if (ch && channel_member(ch, client->number))
            continue;
        if (client->channel_count >= s->settings.maxchannels) {
            error(s, client, 405, name);
            continue;
        }
        if (!ch) {
            ch = channel_create((int)s->channels.count, name, s->time);
            Channels_append(&s->channels, ch);
            s->active_channels[s->channel_count++] = ch->number;
        } else {
            bool invited = false;
            for (int j = 0; j < client->invite_count; ++j)
                if (client->invites[j] == ch->number)
                    invited = true;
            int failure = 0;
            if (channel_banned(ch, client) && !invited)
                failure = 474;
            else if (ch->flag_i && !invited)
                failure = 473;
            else if (ch->key[0] && strcmp(key, ch->key))
                failure = 475;
            else if (ch->limit && ch->member_count >= ch->limit)
                failure = 471;
            if (failure) {
                error(s, client, failure, ch->name);
                continue;
            }
        }
        for (int j = 0; j < client->invite_count; ++j)
            if (client->invites[j] == ch->number) {
                memmove(client->invites + j, client->invites + j + 1,
                        (size_t)(client->invite_count - j - 1) * sizeof *client->invites);
                --client->invite_count;
                break;
            }
        bool first = ch->member_count == 0;
        channel_add(ch, client, client->number, first);
        broadcastf(s, ch, -1, ":%s JOIN %s", client_prefix(client), ch->name);
        if (ch->topic[0])
            topic_replies(s, client, ch);
        names_reply(s, client, ch);
    }
    free_names(&names);
    free_names(&keys);
}
static void part(Server *s, Client *client, const Parsed *p) {
    if (!require(s, client, p, 1, "PART"))
        return;
    Names names = split_list(p->parameters[0]);
    for (size_t i = 0; i < names.count; ++i) {
        Channel *ch = find_channel(s, names.items[i]);
        if (!ch)
            error(s, client, 403, names.items[i]);
        else if (!channel_member(ch, client->number))
            error(s, client, 442, ch->name);
        else {
            if (p->count > 1 && p->parameters[1][0])
                broadcastf(s, ch, -1, ":%s PART %s :%s", client_prefix(client), ch->name,
                           p->parameters[1]);
            else
                broadcastf(s, ch, -1, ":%s PART %s", client_prefix(client), ch->name);
            remove_member(s, client, ch);
        }
    }
    free_names(&names);
}
static void message(Server *s, Client *client, const Parsed *p, const char *command) {
    bool replies = !strcmp(command, "PRIVMSG");
    if (replies)
        client->last_speaking = s->time;
    if (p->count == 0 || p->parameters[0][0] == 0) {
        if (replies)
            error(s, client, 411, command);
        return;
    }
    if (p->count < 2 || p->parameters[1][0] == 0) {
        if (replies)
            error(s, client, 412, "");
        return;
    }
    Names targets = split_list(p->parameters[0]);
    for (size_t i = 0; i < targets.count; ++i) {
        const char *target = targets.items[i];
        if (target[0] == '#') {
            Channel *ch = find_channel(s, target);
            if (!ch) {
                if (replies)
                    error(s, client, 401, target);
            } else if (!channel_can_speak(ch, client, client->number)) {
                if (replies)
                    error(s, client, 404, ch->name);
            } else {
                ++ch->messages;
                broadcastf(s, ch, client->number, ":%s %s %s :%s", client_prefix(client), command,
                           ch->name, p->parameters[1]);
            }
        } else {
            Client *recipient = find_user(s, target);
            if (!recipient) {
                if (replies)
                    error(s, client, 401, target);
                continue;
            }
            sendf(s, recipient, ":%s %s %s :%s", client_prefix(client), command,
                  recipient->nickname, p->parameters[1]);
            if (replies && recipient->away[0])
                away_reply(s, client, recipient);
        }
    }
    free_names(&targets);
}
static void topic(Server *s, Client *client, const Parsed *p) {
    if (!require(s, client, p, 1, "TOPIC"))
        return;
    Channel *ch = find_channel(s, p->parameters[0]);
    if (!ch) {
        error(s, client, 403, p->parameters[0]);
        return;
    }
    Member *member = channel_member(ch, client->number);
    if (!member) {
        error(s, client, 442, ch->name);
        return;
    }
    if (p->count == 1) {
        if (ch->topic[0])
            topic_replies(s, client, ch);
        else
            numeric(s, client, 331, "%s :No topic is set", ch->name);
        return;
    }
    if (ch->flag_t && !member->op) {
        error(s, client, 482, ch->name);
        return;
    }
    size_t length = strlen(p->parameters[1]);
    if (length > (size_t)s->settings.topiclen)
        length = (size_t)s->settings.topiclen;
    memcpy(ch->topic, p->parameters[1], length);
    ch->topic[length] = 0;
    strcpy(ch->topic_setter, client->nickname);
    ch->topic_time = s->time;
    broadcastf(s, ch, -1, ":%s TOPIC %s :%s", client_prefix(client), ch->name, ch->topic);
}
static void names(Server *s, Client *client, const Parsed *p) {
    if (p->count == 0) {
        numeric(s, client, 366, "* :End of /NAMES list.");
        return;
    }
    Names targets = split_list(p->parameters[0]);
    for (size_t i = 0; i < targets.count; ++i) {
        Channel *ch = find_channel(s, targets.items[i]);
        if (ch)
            names_reply(s, client, ch);
        else
            numeric(s, client, 366, "%s :End of /NAMES list.", targets.items[i]);
    }
    free_names(&targets);
}
static void whois(Server *s, Client *client, const Parsed *p) {
    if (p->count == 0) {
        error(s, client, 431, "");
        return;
    }
    Client *target = find_user(s, p->parameters[0]);
    if (!target) {
        error(s, client, 401, p->parameters[0]);
        numeric(s, client, 318, "%s :End of /WHOIS list.", p->parameters[0]);
        return;
    }
    numeric(s, client, 311, "%s %s %s * :%s", target->nickname, target->username, target->hostname,
            target->realname);
    if (target->channel_count) {
        char *joined = joined_channels(s, target, " ");
        numeric(s, client, 319, "%s :%s", target->nickname, joined);
        free(joined);
    }
    numeric(s, client, 312, "%s %s :%s", target->nickname, s->settings.name,
            s->settings.description);
    if (target->away[0])
        away_reply(s, client, target);
    numeric(s, client, 317, "%s %d %d :seconds idle, signon time", target->nickname,
            s->time - target->last_speaking, target->registration_time);
    numeric(s, client, 318, "%s :End of /WHOIS list.", target->nickname);
}
static void invite(Server *s, Client *client, const Parsed *p) {
    if (!require(s, client, p, 2, "INVITE"))
        return;
    Client *target = find_user(s, p->parameters[0]);
    if (!target) {
        error(s, client, 401, p->parameters[0]);
        return;
    }
    Channel *ch = find_channel(s, p->parameters[1]);
    if (!ch) {
        error(s, client, 403, p->parameters[1]);
        return;
    }
    Member *member = channel_member(ch, client->number);
    if (!member) {
        error(s, client, 442, ch->name);
        return;
    }
    if (channel_member(ch, target->number)) {
        numeric(s, client, 443, "%s %s :is already on channel", target->nickname, ch->name);
        return;
    }
    if (ch->flag_i && !member->op) {
        error(s, client, 482, ch->name);
        return;
    }
    bool invited = false;
    for (int i = 0; i < target->invite_count; ++i)
        if (target->invites[i] == ch->number)
            invited = true;
    if (!invited)
        target->invites[target->invite_count++] = ch->number;
    numeric(s, client, 341, "%s %s", target->nickname, ch->name);
    if (target->away[0])
        away_reply(s, client, target);
    sendf(s, target, ":%s INVITE %s :%s", client_prefix(client), target->nickname, ch->name);
}
static void kick(Server *s, Client *client, const Parsed *p) {
    if (!require(s, client, p, 2, "KICK"))
        return;
    Channel *ch = find_channel(s, p->parameters[0]);
    if (!ch) {
        error(s, client, 403, p->parameters[0]);
        return;
    }
    Member *member = channel_member(ch, client->number);
    if (!member) {
        error(s, client, 442, ch->name);
        return;
    }
    if (!member->op) {
        error(s, client, 482, ch->name);
        return;
    }
    Client *target = find_user(s, p->parameters[1]);
    if (!target) {
        error(s, client, 401, p->parameters[1]);
        return;
    }
    if (!channel_member(ch, target->number)) {
        numeric(s, client, 441, "%s %s :They aren't on that channel", target->nickname, ch->name);
        return;
    }
    const char *reason = p->count > 2 && p->parameters[2][0] ? p->parameters[2] : client->nickname;
    broadcastf(s, ch, -1, ":%s KICK %s %s :%s", client_prefix(client), ch->name, target->nickname,
               reason);
    remove_member(s, target, ch);
}
static void user_mode(Server *s, Client *client, const Parsed *p) {
    Client *target = find_user(s, p->parameters[0]);
    if (!target) {
        error(s, client, 401, p->parameters[0]);
        return;
    }
    if (target != client) {
        error(s, client, 502, "");
        return;
    }
    if (p->count == 1) {
        numeric(s, client, 221, "%s", client_mode(client));
        return;
    }
    Changes changes = {0};
    char sign = '+';
    bool unknown = false;
    for (const char *c = p->parameters[1]; *c; ++c) {
        if (*c == '+' || *c == '-')
            sign = *c;
        else if (*c == 'i') {
            bool desired = sign == '+';
            if (client->invisible != desired) {
                client->invisible = desired;
                Change change = {0};
                change.sign = sign;
                change.character = 'i';
                Changes_append(&changes, change);
            }
        } else
            unknown = true;
    }
    if (changes.count) {
        char *text = change_string(&changes);
        sendf(s, client, ":%s MODE %s :%s", client->nickname, client->nickname, text);
        free(text);
    }
    if (unknown)
        error(s, client, 501, "");
    free(changes.items);
}
static bool apply_channel_mode(Server *s, Client *client, Channel *channel, const Change *item,
                               Change *out) {
    memset(out, 0, sizeof *out);
    out->sign = item->sign;
    out->character = item->character;
    bool adding = item->sign == '+';
    char c = item->character;
    bool changed = false;
    if (c == 'o' || c == 'v') {
        Client *target = find_user(s, item->argument);
        if (!target) {
            error(s, client, 401, item->argument);
            return false;
        }
        Member *member = channel_member(channel, target->number);
        if (!member) {
            numeric(s, client, 441, "%s %s :They aren't on that channel", target->nickname,
                    channel->name);
            return false;
        }
        bool *privilege = c == 'o' ? &member->op : &member->voice;
        if (*privilege != adding) {
            *privilege = adding;
            changed = true;
            out->has_argument = true;
            strcpy(out->argument, target->nickname);
        }
    } else if (c == 'b') {
        char mask[406];
        normalize(item->argument, mask);
        size_t found = channel->bans.count;
        for (size_t i = 0; i < channel->bans.count; ++i)
            if (rfc_equal(channel->bans.items[i].mask, mask)) {
                found = i;
                break;
            }
        if (adding && found == channel->bans.count) {
            Ban ban = {0};
            strcpy(ban.mask, mask);
            strcpy(ban.setter, client->nickname);
            ban.time = s->time;
            Bans_append(&channel->bans, ban);
            changed = true;
            out->has_argument = true;
            strcpy(out->argument, mask);
        } else if (!adding && found < channel->bans.count) {
            out->has_argument = true;
            strcpy(out->argument, channel->bans.items[found].mask);
            memmove(channel->bans.items + found, channel->bans.items + found + 1,
                    (channel->bans.count - found - 1) * sizeof *channel->bans.items);
            --channel->bans.count;
            changed = true;
        }
    } else if (c == 'k') {
        if (adding) {
            if (channel->key[0])
                error(s, client, 467, channel->name);
            else {
                strcpy(channel->key, item->argument);
                changed = true;
                out->has_argument = true;
                strcpy(out->argument, item->argument);
            }
        } else if (channel->key[0]) {
            channel->key[0] = 0;
            changed = true;
            out->has_argument = true;
            strcpy(out->argument, "*");
        }
    } else if (c == 'l') {
        if (adding) {
            int limit = atoi(item->argument);
            if (channel->limit != limit) {
                channel->limit = limit;
                changed = true;
                out->has_argument = true;
                snprintf(out->argument, sizeof out->argument, "%d", limit);
            }
        } else if (channel->limit) {
            channel->limit = 0;
            changed = true;
        }
    } else if (channel_flag(channel, c) != adding) {
        channel_set_flag(channel, c, adding);
        changed = true;
    }
    return changed;
}
static void channel_mode(Server *s, Client *client, const Parsed *p) {
    Channel *channel = find_channel(s, p->parameters[0]);
    if (!channel) {
        error(s, client, 403, p->parameters[0]);
        return;
    }
    if (p->count == 1) {
        numeric(s, client, 324, "%s %s", channel->name,
                channel_mode_display(channel, channel_member(channel, client->number) != NULL));
        numeric(s, client, 329, "%s %d", channel->name, channel->created);
        return;
    }
    Changes items = channel_items(p->parameters[1], p, 2), changes = {0};
    const Member *member = channel_member(channel, client->number);
    bool authorized = member && member->op, bans_sent = false, denial_sent = false;
    for (size_t i = 0; i < items.count; ++i) {
        const Change *item = &items.items[i];
        char c = item->character;
        if (!strchr("biklmnotv", c)) {
            numeric(s, client, 472, "%c :is unknown mode char to me for %s", c, channel->name);
            continue;
        }
        if (c == 'b' && !item->has_argument) {
            if (item->sign == '+' && !bans_sent) {
                for (size_t j = 0; j < channel->bans.count; ++j) {
                    Ban *ban = &channel->bans.items[j];
                    numeric(s, client, 367, "%s %s %s %d", channel->name, ban->mask, ban->setter,
                            ban->time);
                }
                numeric(s, client, 368, "%s :End of channel ban list", channel->name);
                bans_sent = true;
            }
            continue;
        }
        if (!item->has_argument &&
            (c == 'o' || c == 'v' || (item->sign == '+' && (c == 'k' || c == 'l'))))
            continue;
        if (!authorized) {
            if (!denial_sent) {
                error(s, client, 482, channel->name);
                denial_sent = true;
            }
            continue;
        }
        Change change;
        if (apply_channel_mode(s, client, channel, item, &change))
            Changes_append(&changes, change);
    }
    if (changes.count) {
        char *text = change_string(&changes);
        broadcastf(s, channel, -1, ":%s MODE %s %s", client_prefix(client), channel->name, text);
        free(text);
    }
    free(items.items);
    free(changes.items);
}
static void count_command(Server *s, const char *command) {
    for (size_t i = 0; i < s->commands.count; ++i)
        if (!strcmp(s->commands.items[i].name, command)) {
            ++s->commands.items[i].count;
            return;
        }
    Commands_append(&s->commands, (CommandCount){copy_string(command), 1});
}
static void process(Server *s, Client *client, const char *raw) {
    ++s->statistics.processed;
    Parsed p;
    parse(raw, &p);
    const char *command = p.command;
    if (!*command) {
        ++s->statistics.empty;
        return;
    }
    count_command(s, command);
    if (!client->registered && strcmp(command, "NICK") && strcmp(command, "USER") &&
        strcmp(command, "PING") && strcmp(command, "PONG") && strcmp(command, "QUIT")) {
        error(s, client, 451, "");
        return;
    }
    if (!strcmp(command, "NICK"))
        nick(s, client, &p);
    else if (!strcmp(command, "USER"))
        user(s, client, &p);
    else if (!strcmp(command, "PING")) {
        if (p.count == 0 || p.parameters[0][0] == 0)
            error(s, client, 409, "");
        else
            sendf(s, client, ":%s PONG %s :%s", s->settings.name, s->settings.name,
                  p.parameters[0]);
    } else if (!strcmp(command, "PONG"))
        return;
    else if (!strcmp(command, "QUIT")) {
        char reason[407];
        if (p.count && p.parameters[0][0])
            snprintf(reason, sizeof reason, "Quit: %s", p.parameters[0]);
        else
            strcpy(reason, "Client Quit");
        disconnect(s, client, reason, QUIT_KIND);
    } else if (!strcmp(command, "JOIN"))
        join_channels(s, client, &p);
    else if (!strcmp(command, "PART"))
        part(s, client, &p);
    else if (!strcmp(command, "PRIVMSG") || !strcmp(command, "NOTICE"))
        message(s, client, &p, command);
    else if (!strcmp(command, "TOPIC"))
        topic(s, client, &p);
    else if (!strcmp(command, "NAMES"))
        names(s, client, &p);
    else if (!strcmp(command, "WHOIS"))
        whois(s, client, &p);
    else if (!strcmp(command, "AWAY")) {
        strcpy(client->away, p.count ? p.parameters[0] : "");
        numeric(s, client, client->away[0] ? 306 : 305,
                client->away[0] ? ":You have been marked as being away"
                                : ":You are no longer marked as being away");
    } else if (!strcmp(command, "INVITE"))
        invite(s, client, &p);
    else if (!strcmp(command, "KICK"))
        kick(s, client, &p);
    else if (!strcmp(command, "MODE")) {
        if (require(s, client, &p, 1, "MODE")) {
            if (p.parameters[0][0] == '#')
                channel_mode(s, client, &p);
            else
                user_mode(s, client, &p);
        }
    } else
        error(s, client, 421, command);
}
static void arrival(Server *s, const Traffic *record) {
    if (record->kind == CONNECT_LINE) {
        Client *client =
            client_create(record->identifier, record->body + 8, s->time, s->settings.bucket);
        client->number = (int)s->clients.count;
        Clients_append(&s->clients, client);
        s->active_clients[s->client_count++] = client->number;
        if (s->client_count > s->peak_connections) {
            s->peak_connections = s->client_count;
            s->peak_connection_time = s->time;
        }
        return;
    }
    Client *client = find_id(s, record->identifier);
    if (record->kind == DISCONNECT_LINE) {
        if (client)
            disconnect(s, client, "Remote host closed the connection", CLOSED_KIND);
        return;
    }
    if (!client) {
        ++s->statistics.dropped;
        return;
    }
    ++client->received;
    client->last_received = s->time;
    client->ping_sent = -1;
    if (client->queue_count == 0 && client->tokens >= 1) {
        client_use_token(client, s->time, s->settings.bucket, s->settings.refill);
        process(s, client, record->body);
    } else if (client->queue_count >= s->settings.queue) {
        ++s->statistics.discarded;
        disconnect(s, client, "Excess Flood", FLOOD_KIND);
    } else {
        client->queue[client->queue_count++] = copy_string(record->body);
        ++s->statistics.queued;
    }
}
static void read_inputs(Server *s) {
    FILE *file = fopen("input/server.txt", "r");
    char line[512];
    while (fgets(line, sizeof line, file)) {
        line[strcspn(line, "\n")] = 0;
        char *space = strchr(line, ' ');
        *space = 0;
        const char *value = space + 1;
        Settings *p = &s->settings;
        if (!strcmp(line, "NAME"))
            strcpy(p->name, value);
        else if (!strcmp(line, "VERSION"))
            strcpy(p->version, value);
        else if (!strcmp(line, "CREATED"))
            strcpy(p->created, value);
        else if (!strcmp(line, "DESCRIPTION"))
            strcpy(p->description, value);
        else if (!strcmp(line, "NICKLEN"))
            p->nicklen = atoi(value);
        else if (!strcmp(line, "CHANNELLEN"))
            p->channellen = atoi(value);
        else if (!strcmp(line, "TOPICLEN"))
            p->topiclen = atoi(value);
        else if (!strcmp(line, "MAXCHANNELS"))
            p->maxchannels = atoi(value);
        else if (!strcmp(line, "BUCKET"))
            p->bucket = atoi(value);
        else if (!strcmp(line, "REFILL"))
            p->refill = atoi(value);
        else if (!strcmp(line, "QUEUE"))
            p->queue = atoi(value);
        else if (!strcmp(line, "PINGFREQ"))
            p->pingfreq = atoi(value);
        else if (!strcmp(line, "TIMEOUT"))
            p->timeout = atoi(value);
        else
            strcpy(p->motd[p->motd_count++], value);
    }
    fclose(file);
    file = fopen("input/traffic.txt", "r");
    while (fgets(line, sizeof line, file)) {
        line[strcspn(line, "\n")] = 0;
        char *first = strchr(line, ' '), *second = strchr(first + 1, ' ');
        *first = *second = 0;
        Traffic record = {0};
        record.time = atoi(line);
        strcpy(record.identifier, first + 1);
        strcpy(record.body, second + 1);
        record.kind = MESSAGE_LINE;
        if (!strcmp(record.body, "DISCONNECT"))
            record.kind = DISCONNECT_LINE;
        else if (!strncmp(record.body, "CONNECT ", 8)) {
            const char *host = record.body + 8;
            bool valid = strlen(host) >= 1 && strlen(host) <= 63;
            for (const char *p = host; *p; ++p)
                if (!((*p >= 'A' && *p <= 'Z') || (*p >= 'a' && *p <= 'z') ||
                      (*p >= '0' && *p <= '9') || *p == '.' || *p == '-'))
                    valid = false;
            if (valid)
                record.kind = CONNECT_LINE;
        }
        ++s->line_counts[record.kind];
        TrafficList_append(&s->traffic, record);
    }
    fclose(file);
    s->end = s->traffic.items[s->traffic.count - 1].time;
}
static FILE *output(const char *name) {
    char path[128];
    snprintf(path, sizeof path, "output/%s", name);
    return fopen(path, "w");
}
static void channel_report(const Server *s, FILE *out) {
    int members = 0, bans = 0;
    for (int i = 0; i < s->channel_count; ++i) {
        Channel *ch = s->channels.items[s->active_channels[i]];
        members += ch->member_count;
        bans += (int)ch->bans.count;
        fprintf(out, "CHANNEL %s created %d members %d peak %d messages %d modes %s\n", ch->name,
                ch->created, ch->member_count, ch->peak, ch->messages,
                channel_mode_display(ch, true));
        if (ch->topic[0])
            fprintf(out, "TOPIC %s %d %s\n", ch->topic_setter, ch->topic_time, ch->topic);
        else
            fputs("TOPIC none\n", out);
        for (size_t j = 0; j < ch->bans.count; ++j) {
            Ban *ban = &ch->bans.items[j];
            fprintf(out, "BAN %s %s %d\n", ban->mask, ban->setter, ban->time);
        }
        fputs("MEMBERS", out);
        for (int j = 0; j < ch->member_count; ++j) {
            Member *member = &ch->members[j];
            fprintf(out, " %s%s", member_status(member),
                    s->clients.items[member->client]->nickname);
        }
        fputc('\n', out);
    }
    fprintf(out, "TOTAL channels %d members %d bans %d\n", s->channel_count, members, bans);
}
static void client_report(Server *s, FILE *out) {
    int registered = 0, invisible = 0, away = 0;
    for (int i = 0; i < s->client_count; ++i) {
        Client *client = s->clients.items[s->active_clients[i]];
        registered += client->registered;
        invisible += client->invisible;
        away += client->away[0] != 0;
        char *joined = joined_channels(s, client, ",");
        fprintf(out, "CLIENT %s %s %s %s %s connected %d signon ", client->identifier,
                client_addressee(client), client->user_set ? client->username : "*",
                client->hostname, client_mode(client), client->connection_time);
        if (client->registered)
            fprintf(out, "%d", client->registration_time);
        else
            fputc('-', out);
        fprintf(out, " received %d sent %d tokens %d queue %d channels %s invites ",
                client->received, client->sent, client->tokens, client->queue_count,
                client->channel_count ? joined : "none");
        free(joined);
        if (client->invite_count == 0)
            fputs("none", out);
        for (int j = 0; j < client->invite_count; ++j) {
            if (j)
                fputc(',', out);
            fputs(s->channels.items[client->invites[j]]->name, out);
        }
        fputc('\n', out);
        if (client->away[0])
            fprintf(out, "AWAY %s %s\n", client->identifier, client->away);
    }
    fprintf(out, "TOTAL clients %d registered %d invisible %d away %d\n", s->client_count,
            registered, invisible, away);
}
static int command_compare(const void *left, const void *right) {
    return strcmp(((const CommandCount *)left)->name, ((const CommandCount *)right)->name);
}
static void statistics_report(Server *s, FILE *out) {
    int pending = 0, numerics = 0;
    for (int i = 0; i < s->client_count; ++i)
        pending += s->clients.items[s->active_clients[i]]->queue_count;
    for (int i = 0; i < 1000; ++i)
        numerics += s->numeric_counts[i];
    fprintf(out, "END %d\nLINES total %zu connect %d disconnect %d messages %d\n", s->end,
            s->traffic.count, s->line_counts[0], s->line_counts[1], s->line_counts[2]);
    Statistics *p = &s->statistics;
    fprintf(out, "MESSAGES dropped %d queued %d processed %d discarded %d pending %d empty %d\n",
            p->dropped, p->queued, p->processed, p->discarded, pending, p->empty);
    fprintf(out, "SENT lines %d numerics %d pings %d errors %d\n", s->sent_count, numerics,
            p->pings, p->errors);
    if (s->commands.count > 1)
        qsort(s->commands.items, s->commands.count, sizeof *s->commands.items, command_compare);
    for (size_t i = 0; i < s->commands.count; ++i)
        fprintf(out, "COMMAND %s %d\n", s->commands.items[i].name, s->commands.items[i].count);
    for (int i = 0; i < 1000; ++i)
        if (s->numeric_counts[i])
            fprintf(out, "NUMERIC %03d %d\n", i, s->numeric_counts[i]);
    fprintf(out, "PEAK connections %d at %d\nPEAK registered %d at %d\n", s->peak_connections,
            s->peak_connection_time, s->peak_registered, s->peak_registered_time);
    fprintf(out, "DISCONNECTS quit %d closed %d flood %d timeout %d\n", s->disconnections[0],
            s->disconnections[1], s->disconnections[2], s->disconnections[3]);
    for (size_t i = 0; i < s->gone.count; ++i) {
        Gone *record = &s->gone.items[i];
        fprintf(out, "GONE %d %s %s %s\n", record->time, record->identifier, record->addressee,
                record->reason);
    }
}
int main(void) {
    Server *s = calloc(1, sizeof *s);
    read_inputs(s);
    mkdir("output", 0777);
    s->sent = output("sent.txt");
    size_t position = 0;
    for (s->time = 0; s->time <= s->end; ++s->time) {
        int present[100], count = s->client_count;
        memcpy(present, s->active_clients, (size_t)count * sizeof *present);
        for (int i = 0; i < count; ++i) {
            Client *client = s->clients.items[present[i]];
            client_refill(client, s->time, s->settings.bucket, s->settings.refill);
            while (client->active && client->queue_count && client->tokens >= 1) {
                client_use_token(client, s->time, s->settings.bucket, s->settings.refill);
                char *raw = client->queue[0];
                memmove(client->queue, client->queue + 1,
                        (size_t)(client->queue_count - 1) * sizeof *client->queue);
                --client->queue_count;
                process(s, client, raw);
                free(raw);
            }
        }
        while (position < s->traffic.count && s->traffic.items[position].time == s->time)
            arrival(s, &s->traffic.items[position++]);
        count = s->client_count;
        memcpy(present, s->active_clients, (size_t)count * sizeof *present);
        for (int i = 0; i < count; ++i) {
            Client *client = s->clients.items[present[i]];
            if (client->ping_sent >= 0) {
                if (s->time - client->ping_sent >= s->settings.timeout) {
                    char reason[64];
                    snprintf(reason, sizeof reason, "Ping timeout: %d seconds",
                             s->time - client->last_received);
                    disconnect(s, client, reason, TIMEOUT_KIND);
                }
            } else if (s->time - client->last_received >= s->settings.pingfreq) {
                sendf(s, client, "PING :%s", s->settings.name);
                ++s->statistics.pings;
                client->ping_sent = s->time;
            }
        }
    }
    fclose(s->sent);
    FILE *file = output("channels.txt");
    channel_report(s, file);
    fclose(file);
    file = output("clients.txt");
    client_report(s, file);
    fclose(file);
    file = output("stats.txt");
    statistics_report(s, file);
    fclose(file);
    for (size_t i = 0; i < s->clients.count; ++i) {
        Client *client = s->clients.items[i];
        for (int j = 0; j < client->queue_count; ++j)
            free(client->queue[j]);
        free(client);
    }
    free(s->clients.items);
    for (size_t i = 0; i < s->channels.count; ++i) {
        free(s->channels.items[i]->bans.items);
        free(s->channels.items[i]);
    }
    free(s->channels.items);
    for (size_t i = 0; i < s->commands.count; ++i)
        free(s->commands.items[i].name);
    free(s->commands.items);
    free(s->traffic.items);
    free(s->gone.items);
    free(s);
    return 0;
}
