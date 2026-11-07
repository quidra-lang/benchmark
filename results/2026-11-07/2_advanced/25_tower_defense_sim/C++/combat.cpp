#include "defense.hpp"

Integer integerSqrt(Integer value) {
    if (value == 0) return 0;
    Integer low = 1, high = 1;
    while (high <= value / high) high *= 2;
    while (low + 1 < high) {
        Integer middle = low + (high - low) / 2;
        if (middle <= value / middle) low = middle;
        else high = middle;
    }
    return low;
}
Integer squaredDistance(Point first, Point second) {
    Integer dx = first.x - second.x, dy = first.y - second.y;
    return dx * dx + dy * dy;
}
std::pair<Point, bool> advance(Point point, Point goal, Integer step) {
    Integer dx = goal.x - point.x, dy = goal.y - point.y;
    Integer squared = dx * dx + dy * dy;
    if (squared <= step * step) return {goal, true};
    Integer length = integerSqrt(squared);
    return {{point.x + dx * step / length, point.y + dy * step / length}, false};
}
Integer damageDealt(Integer hp, Integer power, Integer armor) { return std::min(hp, std::max(Integer{1}, power - armor)); }
bool Effect::active() const { return remaining > 0; }
void Effect::receive(Integer amount, Integer duration, std::size_t tower) {
    if (amount > strength) { strength = amount; remaining = duration; source = tower; }
    else if (amount == strength) remaining = std::max(remaining, duration);
}
void Effect::advanceTime() {
    --remaining;
    if (remaining == 0) { strength = 0; source = 0; }
}
bool Projectile::fly() {
    if (speed == 0) return true;
    std::pair<Point, bool> result = advance(position, aim, speed);
    position = result.first;
    return result.second;
}
