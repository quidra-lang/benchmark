'use strict';

const factors = require('./factors');

function interactionGraph(initial) {
  const graph = new Map();
  for (const factor of initial) {
    for (const variable of factor.variables) if (!graph.has(variable)) graph.set(variable, new Set());
    for (let i = 0; i < factor.variables.length; i++) {
      for (let j = i + 1; j < factor.variables.length; j++) {
        graph.get(factor.variables[i]).add(factor.variables[j]);
        graph.get(factor.variables[j]).add(factor.variables[i]);
      }
    }
  }
  return graph;
}

function metrics(graph, variable) {
  const neighbors = [...graph.get(variable)].sort((a, b) => a - b);
  let fill = 0;
  for (let i = 0; i < neighbors.length; i++) {
    for (let j = i + 1; j < neighbors.length; j++) if (!graph.get(neighbors[i]).has(neighbors[j])) fill++;
  }
  return {variable, neighbors, fill, degree: neighbors.length};
}

function plan(initial, variables, method, given, sizes) {
  const graph = interactionGraph(initial);
  const pending = new Set(variables);
  const steps = [];
  let maximum = 0;
  let total = 0;
  while (pending.size > 0) {
    let choice = null;
    if (method === 'given') choice = metrics(graph, given.find(variable => pending.has(variable)));
    else {
      for (const variable of pending) {
        const candidate = metrics(graph, variable);
        if (choice === null || candidate.fill < choice.fill || (candidate.fill === choice.fill &&
          (candidate.degree < choice.degree || (candidate.degree === choice.degree && variable < choice.variable)))) choice = candidate;
      }
    }
    const scope = [choice.variable, ...choice.neighbors].sort((a, b) => a - b);
    const size = factors.assignmentCount(scope, sizes);
    steps.push({variable: choice.variable, fill: choice.fill, variables: scope, size});
    maximum = Math.max(maximum, size);
    total += size;
    for (let i = 0; i < choice.neighbors.length; i++) {
      const first = choice.neighbors[i];
      for (let j = i + 1; j < choice.neighbors.length; j++) {
        const second = choice.neighbors[j];
        graph.get(first).add(second);
        graph.get(second).add(first);
      }
      graph.get(first).delete(choice.variable);
    }
    graph.delete(choice.variable);
    pending.delete(choice.variable);
  }
  return {steps, maximum, total};
}

function execute(initial, plan, sizes, maximize = false) {
  let sequence = initial.slice();
  const products = [];
  for (const step of plan.steps) {
    const selected = sequence.filter(factor => factor.variables.includes(step.variable));
    sequence = sequence.filter(factor => !factor.variables.includes(step.variable));
    const product = factors.product(selected, sizes);
    if (maximize) products.push({variable: step.variable, factor: product});
    sequence.push(maximize ? factors.maxOut(product, step.variable, sizes) : factors.sumOut(product, step.variable, sizes));
  }
  return {factor: factors.product(sequence, sizes), products};
}

function traceback(result, evidence, sizes) {
  const assignment = Array(sizes.length).fill(0);
  for (const [variable, state] of evidence) assignment[variable] = state;
  for (let index = result.products.length - 1; index >= 0; index--) {
    const {variable, factor} = result.products[index];
    let best = 0;
    assignment[variable] = 0;
    let maximum = factors.valueAt(factor, assignment, sizes);
    for (let state = 1; state < sizes[variable]; state++) {
      assignment[variable] = state;
      const value = factors.valueAt(factor, assignment, sizes);
      if (value > maximum) {
        maximum = value;
        best = state;
      }
    }
    assignment[variable] = best;
  }
  return assignment;
}

module.exports = {interactionGraph, plan, execute, traceback};
