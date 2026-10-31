#ifndef SIMULATION_H
#define SIMULATION_H
#include <stdio.h>
#include <stdlib.h>
#include <stdbool.h>
#include <string.h>
#include <stdarg.h>
#include <stdint.h>
#include <sys/stat.h>
typedef long long I;
typedef struct {
    int *data, count, capacity;
} Ids;
typedef struct {
    char **data;
    int count, capacity;
} Lines;
typedef struct {
    I state, draws;
} Random;
typedef struct {
    int source, destination, minimum, maximum, sequence, last_arrival, messages, markers, buffered,
        max_delay, entries;
    bool fifo;
    I previous[6];
} Channel;
typedef struct {
    int count;
    char names[6][7];
    Channel channels[6][6];
} Topology;
enum ActionKind { A_LOCAL, A_SEND, A_TRANSFER, A_BROADCAST, A_SNAPSHOT };
typedef struct {
    int kind, destination;
    char argument[9], tag[9];
    I amount;
} Action;
typedef struct {
    int start, period;
    Action action;
} Timed;
typedef struct {
    char tag[9];
    Action action;
} Rule;
typedef struct {
    I balance;
    Timed *at;
    Rule *on;
    int at_count, at_capacity, on_count, on_capacity;
} Script;
typedef struct {
    I initial, balance, lamport, in, out, refused, minimum, clock[6], broadcast[6];
    Ids events, delivered, hold, reorder[6];
    int next[6], max_held, counts[5];
} Process;
typedef struct {
    int process, local, time, type, peer, message, copy;
    I lamport, balance, amount, clock[6];
    char label[9];
} Event;
typedef struct {
    int source, send;
    char tag[9];
    I amount;
    bool broadcast;
    I stamp[6];
    Ids copies;
} Message;
typedef struct {
    int message, source, destination, packet, received, delivery;
    bool fifo_wait, causal_wait;
    Ids missing;
} Copy;
typedef struct {
    int source, destination, sequence, dispatch, arrival, copy, snapshot;
} Packet;
typedef struct {
    bool present;
    int time;
    char *reason;
    I balance, lamport, clock[6];
    Ids pending;
} SnapshotRecord;
typedef struct {
    int sent, accepted;
    Ids copies;
} SnapshotChannel;
typedef struct {
    int process, time;
} Ignored;
typedef struct {
    char name[4];
    int start, complete, accepted;
    SnapshotRecord records[6];
    SnapshotChannel channels[6][6];
    Ignored *ignored;
    int ignored_count, ignored_capacity;
} Snapshot;
typedef struct {
    I cut[6];
} Cut;
typedef struct {
    char first[16], second[16];
} Compare;
typedef struct {
    I seed;
    int end, cutcount;
    Compare *compare;
    int compare_count, compare_capacity;
    Cut *cuts;
    int cut_count, cut_capacity;
    I *predicates;
    int predicate_count, predicate_capacity;
} Params;
typedef struct {
    bool snapshot;
    int process, index, time;
} Timeline;
typedef struct {
    int time, process, packet;
    I creation;
    Action action;
} Item;
typedef struct {
    Topology topology;
    Script *scripts;
    Params *params;
    bool raw;
    int time;
    I creation;
    Random random;
    Process processes[6];
    Event *events;
    int event_count;
    Message *messages;
    int message_count;
    Copy *copies;
    int copy_count;
    Packet *packets;
    int packet_count, packet_capacity;
    Snapshot **snapshots;
    int snapshot_count, snapshot_capacity;
    Timeline *timeline;
    int timeline_count, timeline_capacity;
    Item *queue;
    int queue_count, queue_capacity;
} Simulation;
void *allocate(size_t count, size_t size);
void grow(void **data, int *capacity, size_t size);
void append_id(Ids *ids, int value);
void remove_id(Ids *ids, int index);
char *format(const char *pattern, ...);
void line(Lines *lines, const char *pattern, ...);
char *joined(const char *first, const char *second);
Lines read_lines(const char *path);
int process_index(const Topology *topology, const char *name);
Topology read_topology(void);
I random_draw(Random *random);
void dispatch(Channel *channel, int time, bool marker, const I *clock, int count, Random *random,
              int *sequence, int *arrival);
char *delay_text(Channel channel);
void local_clock(Process *process, int own);
void receive_clock(Process *process, int own, const Event *sent, int count);
bool less_equal(const I *first, const I *second, int count);
int relation(const I *first, const I *second, int count);
bool deliverable(const I *stamp, const I *received, int source, int count);
Ids missing(const I *stamp, const I *received, int source, int count);
char *vector_text(const I *value, int count);
Script *read_scripts(const Topology *topology);
void initialize(Simulation *simulation);
void schedule_actions(Simulation *simulation);
void enqueue(Simulation *simulation, Item item);
I balance_at_cut(const Simulation *simulation, int process, I count);
Snapshot *new_snapshot(const char *name, int time);
void record_state(Snapshot *snapshot, int process, const Process *state, int time,
                  const char *reason);
void accept_marker(Snapshot *snapshot, int source, int destination, int time, int count);
void snapshot_cut(const Snapshot *snapshot, I *cut, int count);
typedef struct {
    Ids orphans, transit;
    I balances, money;
} CutDetails;
CutDetails cut_details(const Simulation *simulation, const I *cut);
Ids *graph_edges(const Simulation *simulation);
Ids graph_path(int source, int target, const Ids *graph, int count);
typedef struct {
    I ordered, concurrent, same, inversions, pairs[6][6];
} Concurrency;
Concurrency concurrency(const Simulation *simulation);
typedef struct {
    int process, first, second;
} Violation;
typedef struct {
    Violation *races, *violations;
    int race_count, race_capacity, violation_count, violation_capacity;
    I fifo;
} Orders;
Orders orders(const Simulation *simulation);
typedef struct {
    I cuts;
    bool definite;
} Predicate;
typedef struct {
    I limits[6], *levels, product, consistent;
    int level_count;
    Predicate *predicates;
} Enumeration;
Enumeration enumerate_cuts(const Simulation *simulation);
#endif
