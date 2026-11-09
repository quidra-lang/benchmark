'use strict';

function parseDice(token) {
    const [count, sides] = token.split('d').map(Number);
    return { count, sides };
}

function resolveAttack(rng, modifier, defense, dice, bonus) {
    const roll = 1 + rng.rnd(20);
    if (roll === 1 || (roll !== 20 && roll + modifier < defense)) return { kind: 'miss', damage: 0 };
    let damage = rng.roll(dice);
    if (roll === 20) damage += rng.roll(dice);
    damage = Math.max(1, damage + bonus);
    return { kind: roll === 20 ? 'critical' : 'hit', damage };
}

module.exports = { parseDice, resolveAttack };
