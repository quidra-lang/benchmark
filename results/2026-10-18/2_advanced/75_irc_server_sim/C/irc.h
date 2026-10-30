#ifndef IRC_H
#define IRC_H
#include <stdbool.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#define DEFINE_VECTOR(Name, Type)                                                                  \
    typedef struct {                                                                               \
        Type *items;                                                                               \
        size_t count, capacity;                                                                    \
    } Name;                                                                                        \
    static inline void Name##_append(Name *list, Type value) {                                     \
        if (list->count == list->capacity) {                                                       \
            list->capacity = list->capacity ? 2 * list->capacity : 4;                              \
            list->items = realloc(list->items, list->capacity * sizeof *list->items);              \
        }                                                                                          \
        list->items[list->count++] = value;                                                        \
    }
typedef struct {
    char command[401], parameters[15][401];
    int count;
} Parsed;
void parse(const char *raw, Parsed *out), fold(const char *value, char *out);
bool rfc_equal(const char *a, const char *b), digits(const char *value),
    valid_nickname(const char *value), valid_channel(const char *value, int maximum);
bool matches(const char *mask, const char *value);
void normalize(const char *argument, char out[406]);
typedef struct {
    char identifier[9], hostname[64], nickname[31], username[401], realname[401];
    bool nick_set, user_set, invisible, registered, active;
    int number, connection_time, registration_time, last_received, last_speaking, ping_sent, tokens,
        refill_time;
    char *queue[100];
    int queue_count, channels[20], channel_count, invites[100], invite_count;
    char away[401];
    int received, sent;
} Client;
DEFINE_VECTOR(Clients, Client *)
Client *client_create(const char *identifier, const char *hostname, int time, int capacity);
const char *client_addressee(const Client *client), *client_prefix(const Client *client),
    *client_mode(const Client *client);
void client_use_token(Client *client, int time, int capacity, int interval),
    client_refill(Client *client, int time, int capacity, int interval);
typedef struct {
    int client;
    bool op, voice;
} Member;
typedef struct {
    char mask[406], setter[31];
    int time;
} Ban;
DEFINE_VECTOR(Bans, Ban)
typedef struct {
    int number;
    char name[51];
    int created;
    Member members[100];
    int member_count;
    char topic[301], topic_setter[31];
    int topic_time;
    Bans bans;
    bool flag_i, flag_m, flag_n, flag_t;
    char key[401];
    int limit, peak, messages;
    bool active;
} Channel;
DEFINE_VECTOR(Channels, Channel *)
Channel *channel_create(int number, const char *name, int time);
Member *channel_member(Channel *channel, int client);
const Member *channel_member_const(const Channel *channel, int client);
void channel_add(Channel *channel, Client *client, int client_number, bool op),
    channel_remove(Channel *channel, Client *client, int client_number);
const char *member_status(const Member *member);
char *channel_names(const Channel *channel, Client *const *clients, int viewer);
bool channel_banned(const Channel *channel, const Client *client),
    channel_can_speak(const Channel *channel, const Client *client, int number),
    channel_flag(const Channel *channel, char flag);
void channel_set_flag(Channel *channel, char flag, bool value);
const char *channel_mode_display(const Channel *channel, bool include_key);
typedef struct {
    char sign, character;
    bool has_argument;
    char argument[406];
} Change;
DEFINE_VECTOR(Changes, Change)
Changes channel_items(const char *mode, const Parsed *parameters, int first_argument);
char *change_string(const Changes *changes);
#endif
