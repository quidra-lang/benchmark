'use strict';

function prepareGeometry(members) {
  for (const member of members) {
    const dx = member.end.x - member.start.x;
    const dy = member.end.y - member.start.y;
    member.length = Math.sqrt(dx * dx + dy * dy);
    member.cos = dx / member.length;
    member.sin = dy / member.length;
    member.dofs = member.start.dofs.concat(member.end.dofs);
    member.direction = [-member.cos, -member.sin, member.cos, member.sin];
  }
}

function axialStiffness(member) {
  return member.material.young * member.section.area / member.length;
}

function memberMatrix(member) {
  const k = axialStiffness(member);
  const xx = k * (member.cos * member.cos);
  const xy = k * (member.cos * member.sin);
  const yy = k * (member.sin * member.sin);
  return [[xx, xy, -xx, -xy], [xy, yy, -xy, -yy],
    [-xx, -xy, xx, xy], [-xy, -yy, xy, yy]];
}

function stiffness(model, removed = null) {
  const matrix = Array.from({length: model.nd}, () => Array(model.nd).fill(0));
  for (const member of model.members) {
    if (member === removed) continue;
    const local = memberMatrix(member);
    for (let i = 0; i < 4; i++) {
      for (let j = 0; j < 4; j++) matrix[member.dofs[i]][member.dofs[j]] += local[i][j];
    }
  }
  return matrix;
}

function weight(member) {
  return member.material.density * 9.81 * member.section.area * member.length / 1000000000;
}

function loads(model, loadCase, removed = null) {
  const external = Array(model.nd).fill(0);
  const thermal = Array(model.nd).fill(0);
  const temperature = Array(model.members.length).fill(0);
  let settlement = false;
  for (const load of loadCase.loads) {
    if (load.type === 'FORCE') {
      external[load.node.dofs[0]] += load.x * 1000;
      external[load.node.dofs[1]] += load.y * 1000;
    } else if (load.type === 'TEMPERATURE') {
      const member = load.member;
      if (member === removed) continue;
      const force = member.material.young * member.section.area * member.material.expansion * load.change;
      temperature[member.index] = force;
      for (let i = 0; i < 4; i++) thermal[member.dofs[i]] += force * member.direction[i];
    } else if (load.type === 'SELFWEIGHT') {
      for (const member of model.members) {
        if (member === removed) continue;
        const force = weight(member);
        external[member.dofs[1]] -= force / 2;
        external[member.dofs[3]] -= force / 2;
      }
    } else settlement = true;
  }
  const force = external.map((value, index) => value + thermal[index]);
  return {external, force, temperature, settlement};
}

module.exports = {prepareGeometry, axialStiffness, memberMatrix, stiffness, weight, loads};
