#ifndef LEDGER_H
#define LEDGER_H
#include <inttypes.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
typedef int64_t Integer;
typedef struct {
    char *data;
    size_t length, capacity;
} Text;
void append(Text *, const char *, ...);
char *format(const char *, ...);
char *copy_text(const char *);
char **split(char *, char, int *);
char *read_line(FILE *);
char *digest(const char *);
char *merkle(char **, int);
char *short_hash(const char *);
typedef struct {
    char *name, *secret, *address;
} Wallet;
typedef struct {
    Wallet *items;
    int count;
} Wallets;
Wallets read_wallets(void);
Wallet *owner(Wallets, const char *);
Wallet *named_wallet(Wallets, const char *);
char *sign_transaction(const char *, int, const char *);
typedef struct {
    char *id;
    int index;
} Reference;
typedef struct {
    char *address;
    Integer amount;
} Output;
typedef struct {
    Reference reference;
    char *address;
    Integer amount;
    int height;
    bool coinbase;
} Coin;
typedef struct {
    Coin *items;
    int count, capacity;
} Utxo;
typedef struct {
    char *text, *id, *body;
    Reference *inputs;
    int input_count;
    Output *outputs;
    int output_count;
    char **signatures;
    int coinbase_height;
} Transaction;
bool same_reference(Reference, Reference);
Coin *find_coin(Utxo *, Reference);
bool mature(Coin, int, int);
Integer output_total(Transaction *);
Transaction *parse_transaction(const char *);
Transaction *payment(Reference *, int, Output *, int, const char *);
Transaction *coinbase(int, Output *, int);
const char *check_transaction(Transaction *, Utxo *, Reference *, int, int, Wallets, int, Integer *);
void apply_transaction(Utxo *, Transaction *, int);
Utxo copy_utxo(Utxo);
typedef struct {
    int height, difficulty;
    Integer time, nonce;
    char *previous, *root, *hash;
    Transaction **transactions;
    int count;
} Block;
char *header_text(Block *);
void hash_header(Block *);
Integer block_size(Block *);
bool proof(Block *);
Block *parse_block(char **, char **, int);
Block *mine_block(int, const char *, Transaction **, int, Integer, int);
const char *context_error(Block *, Integer);
typedef struct Record {
    Block *block;
    struct Record *parent;
    Utxo utxo;
    Integer *transaction_fees, fees, work;
    char *source;
} Record;
Record *make_record(Block *, Record *, Utxo, Integer *, const char *);
Integer reward(int, Integer, int);
Record *ancestor(Record *, int);
Record *fork_point(Record *, Record *);
Record **chain_to(Record *, int *);
Integer median_time(Record *);
int required_difficulty(Record *, int, int, Integer);
#endif
