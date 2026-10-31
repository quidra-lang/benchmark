#ifndef DEFENSE_H
#define DEFENSE_H
#include <stdbool.h>
#include <stdio.h>

#define MAX_CELLS 1200
#define MAX_TOWERS 2000

typedef struct { int x, y; } Point;
typedef struct {
    int width, height, exit, spawn_count, spawns[9];
    char terrain[MAX_CELLS];
} Grid;
typedef struct { int distance[MAX_CELLS]; } DistanceField;
typedef enum { GROUND, AIR, BOTH } Targets;
typedef enum { FIRST, LAST, STRONGEST, WEAKEST, CLOSEST } TargetMode;
typedef struct {
    int cost, range, power, interval, shot_speed, splash;
    int slow_rate, slow_time, burn_amount, burn_time;
} Level;
typedef struct {
    char name[13], symbol;
    Targets targets;
    int level_count;
    Level levels[5];
} TowerType;
typedef struct Tower Tower;
typedef struct { int strength, remaining; Tower *source; } Effect;
typedef struct EnemyType {
    char name[13], symbol;
    Targets movement;
    int hp, armor, speed, bounty, lives, regen, split_count;
    struct EnemyType *split_into;
    int spawned, kills, leaks, damage;
} EnemyType;
typedef struct {
    int number, multiplier, max_hp, hp;
    EnemyType *kind;
    Effect slow, burn;
    bool alive;
    int cell, next_cell, progress;
    Point point;
} Enemy;
typedef struct {
    EnemyType *kind;
    int spawn, count, delay, interval, multiplier;
} Group;
struct Tower {
    int number, cell, level, ready, investment, built, sold;
    TargetMode mode;
    TowerType *kind;
    int shots, hits, fizzles, kills, damage;
};
typedef struct {
    int number, target;
    Tower *tower;
    Targets targets;
    Level performance;
    Point position, aim;
} Projectile;

extern const char *target_mode_names[5];
Grid read_grid(const char *path);
bool grid_inside(const Grid *grid, int x, int y);
bool grid_rock(const Grid *grid, int cell);
bool grid_water(const Grid *grid, int cell);
bool grid_buildable(const Grid *grid, int cell);
Point cell_center(const Grid *grid, int cell);
int neighbor(const Grid *grid, int cell, int direction);
void build_distance_field(const Grid *grid, const bool blocked[MAX_CELLS], DistanceField *field);
int field_direction(const Grid *grid, const DistanceField *field, int cell);
int next_cell(const Grid *grid, const DistanceField *field, int cell);
int field_path(const Grid *grid, const DistanceField *field, int start, int cells[MAX_CELLS]);
int integer_sqrt(int value);
int squared_distance(Point first, Point second);
Point advance_point(Point point, Point goal, int step, bool *arrived);
int damage_dealt(int hp, int power, int armor);
void receive_effect(Effect *effect, int strength, int duration, Tower *source);
void advance_effect(Effect *effect);
bool fly_projectile(Projectile *projectile);
Targets parse_targets(const char *text);
void parse_tower_type(const char *line, TowerType *kind);
void parse_level(const char *line, Level *level);
Tower make_tower(int number, TowerType *kind, int cell, int tick);
const Level *tower_level(const Tower *tower);
bool can_aim(Targets targets, const Enemy *enemy);
bool in_range(const Tower *tower, const Grid *grid, Point point);
int parse_target_mode(const char *text);
int select_target(const Tower *tower, const Enemy *enemies, const int *living, int count, const Grid *grid, const DistanceField *field);
EnemyType *find_enemy_type(EnemyType *types, int count, const char *name);
void parse_enemy_type(const char *line, EnemyType *types, int count, EnemyType *kind);
void parse_group(const char *line, EnemyType *types, int count, Group *group);
Enemy make_enemy(int number, EnemyType *kind, int multiplier);
Enemy split_enemy(const Enemy *parent, int number);
Point enemy_position(const Enemy *enemy, const Grid *grid);
int occupied_cell(const Enemy *enemy, const Grid *grid);
int remaining_distance(const Enemy *enemy, const Grid *grid, const DistanceField *field);
int slowed_speed(const Enemy *enemy);
#endif
