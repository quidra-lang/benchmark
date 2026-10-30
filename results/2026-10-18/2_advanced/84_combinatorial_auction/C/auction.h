#ifndef AUCTION_H
#define AUCTION_H
#include <stdbool.h>
#include <stddef.h>
#include <stdio.h>
typedef long long Money;
typedef struct {
    Money n, d;
} Fraction;
Fraction fraction(Money, Money);
Fraction whole(Money);
Fraction fraction_add(Fraction, Fraction);
Fraction fraction_sub(Fraction, Fraction);
Fraction fraction_mul(Fraction, Fraction);
Fraction fraction_div(Fraction, Fraction);
int fraction_compare(Fraction, Fraction);
char *fraction_text(Fraction, char[64]);
typedef struct {
    char **items;
    size_t count, capacity;
} Lines;
typedef struct {
    char *data;
    size_t count, capacity;
} Text;
typedef struct {
    char **items;
    int count;
} Words;
typedef struct {
    char *name;
    Money reserve;
} Item;
typedef struct {
    char *name, *language, *raw[10];
    int count;
} BidLine;
typedef struct {
    char *name, *offered[12];
    int offered_count;
    BidLine lines[15];
    int line_count;
} RawAuction;
typedef struct {
    char *name;
    Money value, bid;
} Participant;
typedef struct {
    char *kind, *name, *arguments[10];
    int argument_count;
    Participant participants[20];
    int participant_count;
} Group;
typedef struct {
    int max_bundle, max_bids, core_max, saa_increment, round_cap, english_increment, dutch_start,
        dutch_decrement;
    Money seed;
} Parameters;
typedef struct {
    Item items[12];
    int item_count;
    RawAuction auctions[10];
    int auction_count;
    Group groups[20];
    int group_count;
    char *runs[10];
    int run_count;
    Parameters parameters;
    Lines storage;
} Input;
typedef struct {
    int number, bidder, mask, size;
    Money amount, reserve;
    bool exclusive;
} Bid;
typedef struct {
    const Bid *items[150];
    int count;
} Bids;
void read_input(Input *);
typedef struct {
    Money node, welfare;
    Bids bids;
} Improvement;
typedef struct {
    Money welfare;
    Bids bids;
    Money nodes, pruned, leaves, improvements;
    Improvement *records;
    size_t record_count, record_capacity;
    Fraction shares[12], bound;
    int sources[12];
} SearchResult;
SearchResult solve_wdp(const Input *, int, Bids, bool);
Bids greedy_order(Bids);
Bids greedy_select(Bids, int);
int population(int);
typedef struct {
    Money value, without, payment, utility;
    Bids won, alternative;
} VcgPayment;
void vcg_payments(const Input *, int, int, Bids, Bids, Money, VcgPayment[15]);
typedef struct {
    Money payment;
    int rival;
} Critical;
void critical_payments(Bids, Bids, Critical[151]);
typedef struct {
    int mask, members[15], member_count;
    Money welfare;
    Bids bids;
} Coalition;
typedef struct {
    Coalition *items;
    int count;
} Coalitions;
typedef struct {
    int coalition;
    Money payoff, deficit;
    bool minimal;
} Blocking;
typedef struct {
    Blocking *items;
    int count;
} Blockers;
Coalitions coalitions(const Input *, int, int, Bids);
Blockers blockers(const Coalitions *, Money, const Money[15]);
Money gsp_price(const Group *, const int *, int);
Fraction slot_vcg(const Group *, const int *, const Fraction *, int, int);
typedef struct {
    int mask;
    Money value;
} Candidate;
typedef struct {
    Candidate *items;
    int count;
} Candidates;
Candidates candidates(Bids, bool);
Money candidate_value(const Candidates *, int);
typedef struct {
    int winner, steps;
    Money price, drops[20];
} ClockResult;
ClockResult english(const Group *, Money, Money);
ClockResult dutch(const Group *, Money, Money, Money);
void *allocate(size_t);
void *resize(void *, size_t);
char *copy_text(const char *);
char *format_text(const char *, ...);
void text_add(Text *, const char *);
void text_format(Text *, const char *, ...);
char *text_take(Text *);
void lines_add(Lines *, char *);
void line(Lines *, const char *, ...);
void lines_take(Lines *, Lines);
void lines_free(Lines *);
Words words(char *);
FILE *open_file(const char *, const char *);
char *read_line(FILE *);
char *bundle(const Input *, int, const char *);
char *number_list(Bids);
void write_lines(const char *, const Lines *);
#endif
