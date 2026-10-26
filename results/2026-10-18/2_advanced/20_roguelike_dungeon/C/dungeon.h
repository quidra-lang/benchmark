#ifndef DUNGEON_H
#define DUNGEON_H
#include <stdbool.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>
#include <sys/stat.h>
#include <errno.h>

typedef struct { char **items; int count, capacity; } Lines;
typedef struct { char *data; size_t size, capacity; } Text;
typedef struct { long long state; } Minstd;
typedef struct { int count, sides; } Dice;
enum AttackOutcome { MISS, HIT, CRITICAL };
typedef struct { enum AttackOutcome outcome; int damage; } Attack;
enum ItemClass { WEAPON, ARMOR, POTION, SCROLL, FOOD, GOLD, AMULET };
typedef struct {
    char *name; char symbol; int min_depth, max_depth, weight;
    Dice hp, damage; int to_hit, defense, speed, xp;
    bool erratic, stationary, regenerates, poisonous;
} MonsterType;
typedef struct {
    enum ItemClass category; char *name, *effect; int min_depth, max_depth, weight;
    Dice dice; int to_hit, armor, poison_turns, nutrition;
} ItemType;
typedef struct { int number; MonsterType *kind; int x, y, hp, max_hp, energy; bool asleep, was_visible; } Monster;
typedef struct { ItemType *kind; int x, y, amount, bonus; bool ground; } Item;
typedef struct { int x, y, width, height; } Room;
typedef struct { int room, x, y; } RoomCell;
typedef struct {
    int depth, width, height; char *terrain, *memory;
    Room rooms[64]; int room_count;
    int arrival_x, arrival_y, arrival_room, target_x, target_y;
    Monster *monsters; int monster_count;
    Item **items; int item_count, items_placed, kills, picked;
} Level;
typedef struct {
    long long generation_seed, game_seed;
    int width, height, min_size, max_split, room_min, room_max, levels;
    int monster_base, monster_step, item_base, item_step, sleep_chance, wake_chance;
    int radius, max_hp, regen, food_start, food_max, food_hungry, food_weak, pack_limit;
    Dice hitdie; char **start; int start_count; int *xp, xp_count, *checkpoints, checkpoint_count;
} Config;
void *allocate(size_t bytes);
char *format(const char *pattern, ...);
void text_add(Text *text, const char *pattern, ...);
void add_line(Lines *lines, const char *pattern, ...);
long long draw(Minstd *rng);
int rnd(Minstd *rng, int limit);
int roll_dice(Minstd *rng, Dice dice);
int select_weight(Minstd *rng, const int *weights, int count);
Dice parse_dice(const char *token);
Attack resolve_attack(Minstd *rng, int to_hit, int defense, Dice dice, int bonus);
MonsterType parse_monster_type(char **tokens);
ItemType parse_item_type(char **tokens);
char item_symbol(const Item *item);
char *display_name(const Item *item);
char *reference_name(const Item *item);
Monster *monster_at(Level *level, int x, int y);
Item *item_at(Level *level, int x, int y);
Level generate_level(int depth, const Config *config, Minstd *rng);
RoomCell draw_interior_cell(const Level *level, Minstd *rng, int room);
RoomCell draw_room_cell(const Level *level, Minstd *rng);
extern const int direction_x[8], direction_y[8];
extern const char *direction_names[8];
bool passable(const Level *level, int x, int y);
bool can_move(const Level *level, int x, int y, int dx, int dy);
bool *field_of_view(const Level *level, int px, int py, int radius);
int *distances(const Level *level, int px, int py);
#endif
