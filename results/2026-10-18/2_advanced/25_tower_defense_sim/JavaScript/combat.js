'use strict';

function isqrt(value) {
    let root = Math.floor(Math.sqrt(value));
    while ((root + 1) * (root + 1) <= value) root++;
    while (root * root > value) root--;
    return root;
}

function squaredDistance(first, second) {
    const dx = first.x - second.x;
    const dy = first.y - second.y;
    return dx * dx + dy * dy;
}

function advancePoint(point, target, speed) {
    const dx = target.x - point.x;
    const dy = target.y - point.y;
    const distance = dx * dx + dy * dy;
    if (distance <= speed * speed) return { point: { ...target }, arrived: true };
    const length = isqrt(distance);
    const movement = value => value >= 0 ? Math.floor(value * speed / length) : -Math.floor(-value * speed / length);
    return { point: { x: point.x + movement(dx), y: point.y + movement(dy) }, arrived: false };
}

function newEffect() {
    return { strength: 0, remaining: 0, source: null };
}

function receiveEffect(effect, strength, duration, source = null) {
    if (strength > effect.strength) {
        effect.strength = strength;
        effect.remaining = duration;
        effect.source = source;
    } else if (strength === effect.strength) effect.remaining = Math.max(effect.remaining, duration);
}

function advanceEffect(effect) {
    effect.remaining--;
    if (effect.remaining === 0) {
        effect.strength = 0;
        effect.source = null;
    }
}

function armoredDamage(hitPoints, power, armor) {
    return Math.min(hitPoints, Math.max(1, power - armor));
}

function createProjectile(number, tower, target, point, aim) {
    return {
        number, tower, target, point: { ...point }, aim: { ...aim },
        performance: { ...tower.type.levels[tower.level - 1] }, targets: tower.type.targets,
    };
}

function moveProjectile(projectile, targetPosition) {
    if (targetPosition !== null) projectile.aim = { ...targetPosition };
    if (projectile.performance.shotSpeed === 0) return true;
    const moved = advancePoint(projectile.point, projectile.aim, projectile.performance.shotSpeed);
    projectile.point = moved.point;
    return moved.arrived;
}

module.exports = { isqrt, squaredDistance, advancePoint, newEffect, receiveEffect, advanceEffect, armoredDamage, createProjectile, moveProjectile };
