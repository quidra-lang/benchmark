'use strict';

function determinant({a, b, c}) {
    return a * c - b * b;
}

function quadratic({x, y}, component) {
    const {mx, my, a, b, c} = component;
    const dx = x - mx;
    const dy = y - my;
    return (c * dx * dx - 2 * b * dx * dy + a * dy * dy) / determinant(component);
}

function logWeighted(point, component) {
    return Math.log(component.w) - Math.log(2 * Math.PI)
        - Math.log(determinant(component)) / 2 - quadratic(point, component) / 2;
}

function eigen({a, b, c}) {
    const h = (a + c) / 2;
    const half = (a - c) / 2;
    const g = Math.sqrt(half * half + b * b);
    const lambda1 = h + g;
    const lambda2 = h - g;
    let ux;
    let uy;
    if (b === 0) {
        [ux, uy] = a >= c ? [1, 0] : [0, 1];
    } else {
        const [vx, vy] = a >= c ? [lambda1 - c, b] : [b, lambda1 - a];
        const length = Math.sqrt(vx * vx + vy * vy);
        ux = (vx < 0 ? -vx : vx) / length;
        uy = (vx < 0 ? -vy : vy) / length;
    }
    return {lambda1, lambda2, ux, uy, angle: Math.atan2(uy, ux) * 180 / Math.PI};
}

function bhattacharyya(first, second) {
    const average = {
        mx: first.mx, my: first.my,
        a: (first.a + second.a) / 2,
        b: (first.b + second.b) / 2,
        c: (first.c + second.c) / 2
    };
    return quadratic({x: second.mx, y: second.my}, average) / 8
        + Math.log(determinant(average)
            / Math.sqrt(determinant(first) * determinant(second))) / 2;
}

module.exports = {determinant, quadratic, logWeighted, eigen, bhattacharyya};
