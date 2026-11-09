'use strict';

const PI = 3.141592653589793;

function buckling(member, section = member.section) {
  return PI * PI * member.material.young * section.inertia / (member.length * member.length);
}

function utilization(member, force, section = member.section) {
  const stress = Math.abs(force / section.area) / member.material.yieldStress;
  const compression = Math.max(0, -force) / buckling(member, section);
  return Math.max(stress, compression);
}

function slenderness(member, section = member.section) {
  return member.length / Math.sqrt(section.inertia / section.area);
}

function slendernessLimit(member, combinations, limits) {
  return combinations.some(result => result.forces[member.index] < 0) ? limits.compression : limits.tension;
}

function selectSection(group, catalogue, combinations, limits) {
  for (const section of catalogue) {
    let acceptable = true;
    for (const member of group.members) {
      if (slenderness(member, section) > slendernessLimit(member, combinations, limits)) {
        acceptable = false;
        break;
      }
      for (const result of combinations) {
        if (utilization(member, result.forces[member.index], section) > 1) {
          acceptable = false;
          break;
        }
      }
      if (!acceptable) break;
    }
    if (acceptable) return section;
  }
  return catalogue.at(-1);
}

module.exports = {buckling, utilization, slenderness, slendernessLimit, selectSection};
