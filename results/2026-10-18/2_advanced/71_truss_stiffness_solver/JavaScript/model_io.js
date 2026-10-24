'use strict';

const fs = require('node:fs');

function lines(name) {
  return fs.readFileSync('input/' + name, 'ascii').slice(0, -1).split('\n');
}

function csv(name) {
  return lines(name).slice(1).map(line => line.split(','));
}

function readModel() {
  const nodes = csv('nodes.csv').map(([id, x, y], index) => ({id: Number(id), x: Number(x), y: Number(y), index}));
  const nodeById = new Map(nodes.map(node => [node.id, node]));
  const sections = csv('sections.csv').map(([name, area, inertia]) => ({name, area: Number(area), inertia: Number(inertia)}));
  const sectionByName = new Map(sections.map(section => [section.name, section]));
  const materials = csv('materials.csv').map(([name, young, yieldStress, density, expansion]) =>
    ({name, young: Number(young), yieldStress: Number(yieldStress), density: Number(density), expansion: Number(expansion)}));
  const materialByName = new Map(materials.map(material => [material.name, material]));
  const members = csv('members.csv').map(([id, start, end, section, material, group], index) =>
    ({id: Number(id), start: nodeById.get(Number(start)), end: nodeById.get(Number(end)),
      section: sectionByName.get(section), material: materialByName.get(material), group, index}));
  const memberById = new Map(members.map(member => [member.id, member]));
  const supports = csv('supports.csv').map(([node, fixX, fixY, dx, dy]) =>
    ({node: nodeById.get(Number(node)), fixed: [fixX === '1', fixY === '1'], prescribed: [Number(dx), Number(dy)]}));
  const cases = [];
  const combinations = [];
  let current = null;
  for (const line of lines('loads.txt')) {
    const fields = line.split(' ');
    const type = fields[0];
    if (type === 'LOADCASE') {
      current = {name: fields[1], loads: []};
      cases.push(current);
    } else if (type === 'END') current = null;
    else if (type === 'COMBINATION') {
      const terms = [];
      for (let i = 2; i < fields.length; i += 2) terms.push({name: fields[i], factor: Number(fields[i + 1])});
      combinations.push({name: fields[1], terms});
    } else if (type === 'FORCE') {
      current.loads.push({type, node: nodeById.get(Number(fields[1])), x: Number(fields[2]), y: Number(fields[3])});
    } else if (type === 'TEMPERATURE') {
      current.loads.push({type, member: memberById.get(Number(fields[1])), change: Number(fields[2])});
    } else current.loads.push({type});
  }
  const params = {influences: [], drawings: []};
  for (const line of lines('params.txt')) {
    const fields = line.split(' ');
    const values = fields.slice(1);
    switch (fields[0]) {
      case 'deck': params.deck = values.map(id => nodeById.get(Number(id))); break;
      case 'influence': params.influences.push(memberById.get(Number(values[0]))); break;
      case 'vehicle': {
        const axles = [];
        for (let i = 1; i < values.length; i += 2) axles.push({offset: Number(values[i]), load: Number(values[i + 1])});
        params.vehicle = {step: Number(values[0]), axles};
        break;
      }
      case 'rating': params.rating = {name: values[0], dead: Number(values[1]), live: Number(values[2])}; break;
      case 'slenderness': params.slenderness = {compression: Number(values[0]), tension: Number(values[1])}; break;
      case 'deflection': params.deflection = {name: values[0], ratio: Number(values[1])}; break;
      case 'vibration': params.vibration = {name: values[0], modes: Number(values[1]), iterations: Number(values[2])}; break;
      case 'removal': params.removal = values[0]; break;
      case 'drawing': params.drawings.push({name: values[0], magnification: Number(values[1]), width: Number(values[2]), height: Number(values[3])}); break;
      case 'utilization_map': params.utilizationMap = {width: Number(values[0]), height: Number(values[1])}; break;
    }
  }
  return {nodes, members, sections, materials, supports, cases, combinations, params};
}

module.exports = {readModel};
