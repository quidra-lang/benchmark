'use strict';

const { parseDice } = require('./combat');

function monsterType(tokens) {
    const [name, symbol, minDepth, maxDepth, weight, hp, toHit, defense, damage, speed, xp, traits] = tokens;
    return { name, symbol, minDepth: Number(minDepth), maxDepth: Number(maxDepth), weight: Number(weight),
        hp: parseDice(hp), toHit: Number(toHit), defense: Number(defense), damage: parseDice(damage),
        speed: Number(speed), xp: Number(xp), traits };
}

function itemType(tokens) {
    const [kind, name, minDepth, maxDepth, weight, ...args] = tokens;
    const type = { kind, name, minDepth: Number(minDepth), maxDepth: Number(maxDepth), weight: Number(weight) };
    if (kind === 'weapon') Object.assign(type, { damage: parseDice(args[0]), toHit: Number(args[1]) });
    else if (kind === 'armor') type.armor = Number(args[0]);
    else if (kind === 'gold') type.dice = parseDice(args[0]);
    else if (kind === 'food') type.satiation = Number(args[0]);
    else {
        type.effect = args[0];
        if (args[0] === 'heal') type.dice = parseDice(args[1]);
        if (args[0] === 'poison') type.poison = Number(args[1]);
    }
    return type;
}

function makeMonster(type, id, cell, hp, asleep) {
    return { type, id, x: cell.x, y: cell.y, hp, maxHp: hp, asleep, energy: 0, wasVisible: false };
}

function makeItem(type, amount = 0) { return { type, bonus: 0, amount }; }

const SYMBOLS = { weapon: ')', armor: '[', potion: '!', scroll: '?', food: '%', gold: '$', amulet: '"' };

function itemSymbol(item) { return SYMBOLS[item.type.kind]; }

function displayName(item) {
    const name = item.type.name.replace(/_/g, ' ');
    if (item.type.kind === 'weapon' || item.type.kind === 'armor') return `+${item.bonus} ${name}`;
    if (item.type.kind === 'gold') return `${item.amount} gold`;
    return name;
}

function referenceName(item) { return item.type.kind === 'gold' ? displayName(item) : 'the ' + displayName(item); }

module.exports = { monsterType, itemType, makeMonster, makeItem, itemSymbol, displayName, referenceName };
