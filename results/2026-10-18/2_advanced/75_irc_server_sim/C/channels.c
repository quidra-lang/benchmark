#include "irc.h"
Channel *channel_create(int number, const char *name, int time) {
    Channel *out = calloc(1, sizeof *out);
    out->number = number;
    strcpy(out->name, name);
    out->created = time;
    out->flag_n = out->flag_t = true;
    out->active = true;
    return out;
}
Member *channel_member(Channel *channel, int client) {
    for (int i = 0; i < channel->member_count; ++i)
        if (channel->members[i].client == client)
            return &channel->members[i];
    return NULL;
}
const Member *channel_member_const(const Channel *channel, int client) {
    for (int i = 0; i < channel->member_count; ++i)
        if (channel->members[i].client == client)
            return &channel->members[i];
    return NULL;
}
void channel_add(Channel *channel, Client *client, int client_number, bool op) {
    channel->members[channel->member_count++] = (Member){client_number, op, false};
    client->channels[client->channel_count++] = channel->number;
    if (channel->member_count > channel->peak)
        channel->peak = channel->member_count;
}
void channel_remove(Channel *channel, Client *client, int client_number) {
    for (int i = 0; i < channel->member_count; ++i)
        if (channel->members[i].client == client_number) {
            memmove(channel->members + i, channel->members + i + 1,
                    (size_t)(channel->member_count - i - 1) * sizeof *channel->members);
            --channel->member_count;
            break;
        }
    for (int i = 0; i < client->channel_count; ++i)
        if (client->channels[i] == channel->number) {
            memmove(client->channels + i, client->channels + i + 1,
                    (size_t)(client->channel_count - i - 1) * sizeof *client->channels);
            --client->channel_count;
            break;
        }
}
const char *member_status(const Member *member) {
    return member->op ? "@" : member->voice ? "+" : "";
}
char *channel_names(const Channel *channel, Client *const *clients, int viewer) {
    bool inside = channel_member_const(channel, viewer) != NULL;
    size_t size = 1;
    for (int i = 0; i < channel->member_count; ++i) {
        const Member *m = &channel->members[i];
        if (inside || !clients[m->client]->invisible)
            size += strlen(member_status(m)) + strlen(clients[m->client]->nickname) + 1;
    }
    char *out = malloc(size);
    size_t p = 0;
    for (int i = 0; i < channel->member_count; ++i) {
        const Member *m = &channel->members[i];
        if (inside || !clients[m->client]->invisible) {
            if (p)
                out[p++] = ' ';
            p += (size_t)snprintf(out + p, size - p, "%s%s", member_status(m),
                                  clients[m->client]->nickname);
        }
    }
    out[p] = 0;
    return out;
}
bool channel_banned(const Channel *channel, const Client *client) {
    for (size_t i = 0; i < channel->bans.count; ++i)
        if (matches(channel->bans.items[i].mask, client_prefix(client)))
            return true;
    return false;
}
bool channel_can_speak(const Channel *channel, const Client *client, int number) {
    const Member *m = channel_member_const(channel, number);
    bool privileged = m && (m->op || m->voice);
    return (m || !channel->flag_n) && (!channel->flag_m || privileged) &&
           (privileged || !channel_banned(channel, client));
}
bool channel_flag(const Channel *channel, char flag) {
    return flag == 'i'   ? channel->flag_i
           : flag == 'm' ? channel->flag_m
           : flag == 'n' ? channel->flag_n
                         : channel->flag_t;
}
void channel_set_flag(Channel *channel, char flag, bool value) {
    if (flag == 'i')
        channel->flag_i = value;
    else if (flag == 'm')
        channel->flag_m = value;
    else if (flag == 'n')
        channel->flag_n = value;
    else
        channel->flag_t = value;
}
const char *channel_mode_display(const Channel *channel, bool include_key) {
    static char buffers[32][512];
    static unsigned index;
    char *out = buffers[index++ % 32];
    int n = 0;
    out[n++] = '+';
    for (const char *p = "iklmnt"; *p; ++p) {
        bool present = *p == 'k'   ? channel->key[0] != 0
                       : *p == 'l' ? channel->limit != 0
                                   : channel_flag(channel, *p);
        if (present)
            out[n++] = *p;
    }
    out[n] = 0;
    if (include_key && channel->key[0])
        n += snprintf(out + n, 512 - (size_t)n, " %s", channel->key);
    if (channel->limit)
        n += snprintf(out + n, 512 - (size_t)n, " %d", channel->limit);
    return out;
}
