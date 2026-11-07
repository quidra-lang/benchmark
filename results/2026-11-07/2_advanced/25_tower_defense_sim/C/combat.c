#include "defense.h"

int integer_sqrt(int value) {
    int low = 0, high = value <= 1 ? value : value / 2 + 1;
    while (low < high) {
        int middle = low + (high - low + 1) / 2;
        if (middle <= value / middle) low = middle;
        else high = middle - 1;
    }
    return low;
}

int squared_distance(Point first, Point second) {
    int dx = first.x - second.x, dy = first.y - second.y;
    return dx * dx + dy * dy;
}

Point advance_point(Point point, Point goal, int step, bool *arrived) {
    int squared = squared_distance(point, goal);
    *arrived = squared <= step * step;
    if (*arrived) return goal;
    int length = integer_sqrt(squared);
    return (Point){point.x + (goal.x - point.x) * step / length, point.y + (goal.y - point.y) * step / length};
}

int damage_dealt(int hp, int power, int armor) {
    int damage = power - armor;
    if (damage < 1) damage = 1;
    return damage < hp ? damage : hp;
}

void receive_effect(Effect *effect, int strength, int duration, Tower *source) {
    if (strength > effect->strength) {
        effect->strength = strength;
        effect->remaining = duration;
        effect->source = source;
    } else if (strength == effect->strength && duration > effect->remaining) {
        effect->remaining = duration;
    }
}

void advance_effect(Effect *effect) {
    if (--effect->remaining == 0) {
        effect->strength = 0;
        effect->source = NULL;
    }
}

bool fly_projectile(Projectile *projectile) {
    if (projectile->performance.shot_speed == 0) return true;
    bool arrived;
    projectile->position = advance_point(projectile->position, projectile->aim, projectile->performance.shot_speed, &arrived);
    return arrived;
}
