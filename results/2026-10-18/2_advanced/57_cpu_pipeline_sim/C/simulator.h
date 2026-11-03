#ifndef SIMULATOR_H
#define SIMULATOR_H
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdbool.h>
#include <stdarg.h>
#include <stdint.h>
#include <sys/stat.h>
typedef long long I;
typedef struct {
    char **data;
    int count, capacity;
} Lines;
extern const char *classes[7], *causes[4], *misses[3], *stages[5];
enum Class { ALU, MUL, LOAD, STORE, BRANCH, JUMP, NOP };
typedef struct {
    I pc, target, address, next;
    int kind, rd, rs1, rs2, line, static_id;
    bool taken;
} Instruction;
typedef struct {
    char name[17], scheme[17];
    int parameters[4];
} Predictor;
typedef struct {
    char name[17];
    bool forwarding, id;
    int latency;
} Variant;
typedef struct {
    int btb, ras, start, end, top, interval, predictor_count, variant_count;
    Predictor predictors[8];
    Variant variants[8];
    char primary_variant[17], primary_predictor[17];
} Config;
typedef struct {
    Lines trace;
    Config config;
} Input;
typedef struct {
    int producer[2];
} Sources;
typedef struct {
    int f, d, x, m, w;
} Timing;
typedef struct {
    int cause, cycles, responsible, waiting, producer;
} Record;
typedef struct {
    Timing *timings;
    Record *records;
    int count, cycles;
    I stalls[4], events[4];
} Run;
typedef struct {
    bool valid;
    I pc, target;
} BTBEntry;
typedef struct {
    BTBEntry *entries;
    int count;
} BTB;
typedef struct {
    I stack[16];
    int depth, count;
} RAS;
typedef struct {
    Predictor definition;
    int *table, *local, *global_table, *chooser, history;
} DirectionPredictor;
void *allocate(size_t count, size_t size);
char *format(const char *pattern, ...);
void line(Lines *lines, const char *pattern, ...);
char *joined(const char *a, const char *b);
Input read_inputs(void);
bool parse_hex(const char *text, I *value);
int parse_register(const char *text);
bool control(Instruction instruction);
Sources *dependencies(const Instruction *instructions, int count);
bool id_resolved(Instruction instruction, Variant variant);
int ready_cycle(Instruction consumer, Instruction producer, Timing time, Variant variant);
int forwarding_path(Instruction consumer, const Timing *producer, Timing time, Variant variant);
Run simulate(const Instruction *instructions, const Sources *sources, int count, Variant variant,
             const bool *flags);
void free_run(Run *run);
BTB btb_create(int entries);
bool btb_lookup(BTB *btb, I pc, I *target);
void btb_insert(BTB *btb, I pc, I target);
void ras_push(RAS *ras, I value);
bool ras_pop(RAS *ras, I *value);
DirectionPredictor direction_create(Predictor definition);
bool direction_predict(DirectionPredictor *predictor, I pc, I target);
void direction_update(DirectionPredictor *predictor, I pc, bool taken);
int storage(Predictor definition);
void direction_free(DirectionPredictor *predictor);
char *decimal(I p, I q), *percentage(I p, I q), *fraction(I p, I q), *hexadecimal(I value),
    *register_name(int value);
char *cycle_heading(int start, int end);
char *diagram_row(int number, I pc, const char *kind, const char *characters,
                  const char *annotation);
void save(const char *name, Lines lines);
#endif
