#include "dungeon.hpp"

Dice parseDice(const std::string& token) { std::size_t separator = token.find('d'); return {std::stoi(token.substr(0, separator)), std::stoi(token.substr(separator + 1))}; }
Attack resolveAttack(Minstd& generator, int toHit, int defense, Dice dice, int bonus) {
    int roll = 1 + generator.rnd(20);
    if (roll == 1) return {AttackOutcome::miss, 0};
    if (roll == 20) { int first = generator.roll(dice), second = generator.roll(dice); return {AttackOutcome::critical, std::max(first + second + bonus, 1)}; }
    if (roll + toHit >= defense) return {AttackOutcome::hit, std::max(generator.roll(dice) + bonus, 1)};
    return {AttackOutcome::miss, 0};
}
