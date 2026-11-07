#include "irc.h"
Client *client_create(const char *identifier, const char *hostname, int time, int capacity) {
    Client *out = calloc(1, sizeof *out);
    strcpy(out->identifier, identifier);
    strcpy(out->hostname, hostname);
    out->connection_time = out->last_received = time;
    out->registration_time = out->last_speaking = out->ping_sent = out->refill_time = -1;
    out->tokens = capacity;
    out->active = true;
    return out;
}
const char *client_addressee(const Client *client) {
    return client->nick_set ? client->nickname : "*";
}
const char *client_prefix(const Client *client) {
    static char buffers[32][512];
    static unsigned index;
    char *out = buffers[index++ % 32];
    snprintf(out, 512, "%s!%s@%s", client_addressee(client),
             client->user_set ? client->username : "*", client->hostname);
    return out;
}
const char *client_mode(const Client *client) { return client->invisible ? "+i" : "+"; }
void client_use_token(Client *client, int time, int capacity, int interval) {
    if (client->tokens == capacity)
        client->refill_time = time + interval;
    --client->tokens;
}
void client_refill(Client *client, int time, int capacity, int interval) {
    if (client->refill_time == time) {
        ++client->tokens;
        client->refill_time = client->tokens < capacity ? time + interval : -1;
    }
}
