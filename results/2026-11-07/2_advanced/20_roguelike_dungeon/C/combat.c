#include "dungeon.h"

Dice parse_dice(const char *token) { return (Dice){atoi(token), atoi(strchr(token, 'd') + 1)}; }

Attack resolve_attack(Minstd *rng, int to_hit, int defense, Dice dice, int bonus) {
    int rolled = 1 + rnd(rng, 20);
    if (rolled == 1 || (rolled != 20 && rolled + to_hit < defense)) return (Attack){MISS, 0};
    int damage = roll_dice(rng, dice);
    enum AttackOutcome outcome = HIT;
    if (rolled == 20) { outcome = CRITICAL; damage += roll_dice(rng, dice); }
    damage += bonus;
    return (Attack){outcome, damage < 1 ? 1 : damage};
}
