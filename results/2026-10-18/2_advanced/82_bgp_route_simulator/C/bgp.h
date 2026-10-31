#ifndef BGP_H
#define BGP_H
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#define NO_EXPORT UINT32_C(0xffffff01)
typedef struct {
    uint64_t address;
    int length;
} Prefix;
typedef struct {
    uint32_t *items;
    size_t count;
} Communities;
typedef struct Attribute {
    size_t references;
    int *path;
    size_t path_count;
    int origin, med;
    Communities communities;
} Attribute;
typedef struct Link Link;
typedef struct Session Session;
typedef struct {
    Attribute *attribute;
    Link *link;
    int preference;
    bool local;
} Route;
typedef struct Node {
    int number, index;
    uint64_t router;
    Attribute *origins[100];
    Route rib[100];
    Session *sessions[100];
    int session_count, changes;
} Node;
struct Link {
    char name[13];
    Node *a, *b;
    bool peer, up;
    int delay, mrai, number, downs;
    Session *sessions[2];
};
struct Session {
    Node *owner;
    Link *link;
    Attribute *incoming[100], *outgoing[100];
    bool pending[100];
    int timer, sent, received;
};
typedef struct {
    Node *node;
    int prefix;
    Attribute *attribute;
} Initial;
typedef struct {
    Node nodes[50];
    int node_count, node_order[50];
    Link links[100];
    int link_count;
    Session session_storage[200], *sessions[200];
    int session_count;
    Initial initial[50];
    int initial_count;
    Prefix prefixes[100];
    int prefix_count, prefix_order[100];
} Topology;
typedef struct {
    char *data;
    size_t count, capacity;
} Text;
typedef struct {
    char **items;
    size_t count, capacity;
} Lines;
typedef struct {
    char **items;
    size_t count;
} Words;
void *allocate(size_t);
void *resize(void *, size_t);
char *copy_text(const char *);
char *format_text(const char *, ...);
void text_add(Text *, const char *);
void text_format(Text *, const char *, ...);
char *text_take(Text *);
void lines_add(Lines *, char *);
void lines_free(Lines *);
Words words(char *);
void words_free(Words *);
char *read_line(FILE *);
FILE *open_file(const char *, const char *);
uint64_t ip(const char *);
char *ip_text(uint64_t);
Prefix parse_prefix(const char *);
char *prefix_text(Prefix);
bool contains(Prefix, uint64_t);
int prefix_compare(Prefix, Prefix);
Node *node_named(Topology *, int);
Link *link_named(Topology *, const char *);
Link *between(Topology *, int, int);
Node *other(const Link *, const Node *);
int role(const Link *, const Node *);
Session *session_at(const Link *, const Node *);
const char *role_name(int);
char direction_symbol(int);
int register_prefix(Topology *, Prefix);
void order_prefixes(Topology *);
void read_topology(Topology *);
uint32_t community(const char *);
char *community_text(uint32_t);
bool community_has(const Communities *, uint32_t);
void community_add(Communities *, uint32_t);
void community_remove(Communities *, uint32_t);
Communities communities_copy(const Communities *);
Communities parse_communities(const Words *, size_t);
char *communities_text(const Communities *);
typedef struct {
    bool permit;
    Prefix prefix;
    int low, high;
} PrefixEntry;
typedef struct {
    char name[13];
    PrefixEntry *entries;
    size_t count;
} PrefixList;
typedef enum {
    CONDITION_PREFIX,
    CONDITION_CONTAINS,
    CONDITION_ORIGINAS,
    CONDITION_LENGTH,
    CONDITION_COMMUNITY
} ConditionKind;
typedef struct {
    ConditionKind kind;
    char name[13];
    int low, high;
    uint32_t community;
} Condition;
typedef struct {
    bool add;
    uint32_t community;
} Edit;
typedef struct {
    char name[13], target[13];
    int owner, preference, med, prepend, hits;
    bool importing, active, deny, allow, has_preference, has_med;
    Condition *conditions;
    size_t condition_count;
    Edit *edits;
    size_t edit_count;
} Rule;
typedef struct {
    PrefixList *lists;
    size_t list_count;
    Rule rules[50];
    int rule_count;
} Policies;
void read_policies(Policies *);
Rule *rule_named(Policies *, const char *);
Rule *applied(Policies *, bool, Session *, Prefix, const Attribute *);
void edit_communities(Communities *, const Rule *);
void policies_free(Policies *);
Attribute *attribute_new(void);
Attribute *attribute_copy(const Attribute *);
Attribute *attribute_retain(Attribute *);
void attribute_release(Attribute *);
bool attribute_equal(const Attribute *, const Attribute *);
Route route_retain(Route);
void route_release(Route *);
bool route_equal(Route, Route);
int origin_rank(const char *);
const char *origin_name(int);
int best_route(const Route *, int, const Topology *, const char **);
typedef struct {
    int serial, time, prefix;
    Session *source;
    Attribute *attribute;
} Message;
typedef struct {
    Message *items;
    size_t count, capacity;
    int serial;
} MessageQueue;
typedef struct {
    Message *items;
    size_t count;
} MessageList;
Node *message_sender(const Message *);
Node *message_receiver(const Message *);
int message_compare(const void *, const void *);
Message queue_send(MessageQueue *, int, Session *, int, Attribute *);
MessageList queue_arrivals(MessageQueue *, int);
MessageList queue_ordered(const MessageQueue *);
MessageList queue_remove(MessageQueue *, Link *);
typedef enum {
    EVENT_INITIAL,
    EVENT_ANNOUNCE,
    EVENT_WITHDRAW,
    EVENT_LINK_DOWN,
    EVENT_LINK_UP,
    EVENT_POLICY_ON,
    EVENT_POLICY_OFF
} EventKind;
typedef struct {
    int number, time, prefix;
    EventKind kind;
    char *text;
    Node *node;
    Link *link;
    Rule *rule;
    Attribute *attribute;
} Event;
typedef struct {
    Node *source;
    uint64_t address;
    char text[16];
} Trace;
typedef struct {
    int customer, peer, provider, stepcap;
    Trace traces[20];
    int trace_count;
} Parameters;
int read_events(Topology *, Policies *, Event[51]);
void read_parameters(Topology *, Parameters *);
const char *event_kind_name(EventKind);
char *path_text(const int *, size_t);
char *attribute_text(const Attribute *);
char *route_text(Route);
void write_lines(const char *, const Lines *);
#endif
