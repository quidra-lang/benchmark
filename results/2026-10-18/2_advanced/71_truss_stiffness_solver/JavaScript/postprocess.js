'use strict';

const {axialStiffness} = require('./assembly');

function axialForces(model, displacement, temperature, removed = null) {
  return model.members.map(member => {
    if (member === removed) return 0;
    const [xi, yi, xj, yj] = member.dofs;
    const extension = (displacement[xj] - displacement[xi]) * member.cos
      + (displacement[yj] - displacement[yi]) * member.sin;
    return axialStiffness(member) * extension - temperature[member.index];
  });
}

function reactions(model, matrix, displacement, force) {
  const result = Array(model.nd).fill(0);
  for (const restrained of model.restrained) {
    let value = 0;
    for (let dof = 0; dof < model.nd; dof++) value += matrix[restrained][dof] * displacement[dof];
    result[restrained] = value - force[restrained];
  }
  return result;
}

function equilibriumMaximum(model, result) {
  const residual = result.external.map((value, dof) => value + result.reactions[dof]);
  for (const member of model.members) {
    const direction = [member.cos, member.sin, -member.cos, -member.sin];
    for (let i = 0; i < 4; i++) residual[member.dofs[i]] += result.forces[member.index] * direction[i];
  }
  let maximum = 0;
  for (const value of residual) maximum = Math.max(maximum, Math.abs(value));
  return maximum;
}

function superpose(combination, results) {
  const result = {name: combination.name, kind: 'combination'};
  for (const field of ['displacement', 'forces', 'reactions', 'external']) {
    const size = results.get(combination.terms[0].name)[field].length;
    const values = Array(size).fill(0);
    for (let index = 0; index < size; index++) {
      for (const term of combination.terms) values[index] += term.factor * results.get(term.name)[field][index];
    }
    result[field] = values;
  }
  return result;
}

module.exports = {axialForces, reactions, equilibriumMaximum, superpose};
