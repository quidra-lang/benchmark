#ifndef RAFT_H
#define RAFT_H
#include <stdbool.h>
#include <stdint.h>
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
DEFINE_VECTOR(Lines, char *)
void add_line(Lines *out, const char *format, ...);
typedef struct {
    int64_t state;
    int draws;
} Minstd;
int random_draw(Minstd *random), random_between(Minstd *random, int minimum, int maximum);
typedef enum { OP_NOOP, OP_SET, OP_ADD, OP_DELETE, OP_GET } Operation;
typedef struct {
    Operation kind;
    char key[9];
    int value;
} Command;
typedef struct {
    int term;
    Command command;
    int request;
} Entry;
DEFINE_VECTOR(Entries, Entry)
typedef struct {
    char key[9];
    int value;
} KeyValue;
typedef struct {
    KeyValue items[1000];
    int count;
} Store;
bool entry_equal(const Entry *a, const Entry *b), store_equal(const Store *a, const Store *b);
const char *command_text(const Command *command);
void apply_command(Store *store, const Command *command, char result[32]);
int store_find(const Store *store, const char *key);
typedef enum { FOLLOWER, CANDIDATE, LEADER } Role;
const char *role_name(Role role);
typedef struct {
    int elections, leader_terms, votes_granted, leader_ticks, ae_ok, ae_fail, appended, truncated,
        applies;
} Statistics;
typedef struct {
    int number, term, voted_for;
    Entries log;
    bool up;
    Statistics stats;
    Role role;
    int commit, applied;
    Store store;
    int known_leader;
    uint8_t votes;
    int election_deadline, election_record, next[8], match[8], heartbeat_deadline, quorum_deadline;
    uint8_t heard;
    int transfer_target, transfer_deadline;
    bool transfer_sent;
} Node;
void node_init(Node *node, int number), cancel_transfer(Node *node), reset_volatile(Node *node),
    node_crash(Node *node);
int last_index(const Node *node), last_term(const Node *node), term_at(const Node *node, int index);
bool accepts_log(const Node *node, int index, int term);
typedef struct {
    int nodes, election_min, election_max, heartbeat, batch, quorum, seed, end, retry, attempts,
        sample;
} Settings;
typedef enum {
    CONTROL_CRASH,
    CONTROL_RESTART,
    CONTROL_PARTITION,
    CONTROL_HEAL,
    CONTROL_TRANSFER
} ControlKind;
typedef struct {
    int nodes[7], count;
} Group;
typedef struct {
    int time;
    ControlKind kind;
    int first, second;
    Group groups[7];
    int group_count;
} Control;
typedef enum { COMMITTED, UNCOMMITTED, LOST, FAILED, WAITING } RequestStatus;
const char *status_name(RequestStatus status);
typedef struct {
    int number, time, initial_destination;
    Command command;
    int scheduled, destination, attempts, redirects;
    bool accepted, abandoned;
    int index, term;
    RequestStatus status;
    int latency;
    char result[32];
} Request;
typedef struct {
    Settings settings;
    Control controls[100];
    int control_count;
    Request requests[1000];
    int request_count;
} Input;
void read_cluster(Input *out);
typedef enum { RV, RVR, AE, AER, TN } Type;
const char *type_name(Type type);
typedef struct {
    Type type;
    int source, destination, term, last_index, last_term, previous, previous_term;
    Entry *entries;
    int entry_count, commit;
    bool granted, success;
    int confirmed;
} Message;
typedef enum {
    SENT,
    DELIVERED,
    INFLIGHT,
    PARTITIONED,
    RULE_LOST,
    PERIODIC_LOST,
    DOWN_LOST
} Counter;
typedef int Counters[7];
extern const char *counter_names[7];
typedef struct {
    int type, first, last;
} Drop;
DEFINE_VECTOR(Drops, Drop)
typedef struct {
    int delay, loss, passed;
    Drops drops;
    Counters stats;
} Link;
typedef struct {
    int arrival, source, serial;
    Message message;
} Envelope;
DEFINE_VECTOR(Queue, Envelope)
typedef struct {
    int nodes, serial;
    Link links[8][8];
    int groups[8];
    Counters total, by_type[5];
    Queue queue;
} Network;
void network_init(Network *network, int nodes),
    network_partition(Network *network, const Group *groups, int count),
    network_heal(Network *network);
bool network_separated(const Network *network, int first, int second);
void network_count(Network *network, const Message *message, Counter field, int amount),
    network_send(Network *network, int time, Message message);
bool network_arrival(Network *network, int time, Message *out),
    network_deliver(Network *network, const Message *message, bool destination_up);
void network_free(Network *network);
typedef struct {
    bool valid;
    int term, time;
} CommittedRecord;
typedef struct {
    bool valid;
    Entry entry;
    char result[32];
} AppliedRecord;
typedef struct {
    int violations[5];
    int *leaders;
    size_t leader_capacity;
    CommittedRecord *committed;
    AppliedRecord *applied;
    size_t entry_capacity;
    int committed_count, applied_count, leader_count, elected, log_checks, pair_checks, applies,
        truncations, removed;
} Checker;
void checker_leader(Checker *checker, const Node *node),
    checker_commit(Checker *checker, int index, int term, int time),
    checker_apply(Checker *checker, int index, const Entry *entry, const char *result),
    checker_truncate(Checker *checker, int first, const Entry *entries, int count),
    checker_logs(Checker *checker, const Node *nodes, int count);
Lines checker_lines(const Checker *checker, int maximum_term);
void checker_free(Checker *checker);
#endif
