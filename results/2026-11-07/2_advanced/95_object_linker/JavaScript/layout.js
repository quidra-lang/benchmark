'use strict';

const {belongs, isNobits} = require('./object_parser');

function align(value, alignment) {
  return Math.ceil(value / alignment) * alignment;
}

class OutputSection {
  constructor(segment, name) {
    this.segment = segment;
    this.name = name;
    this.nobits = isNobits(name);
    this.sections = [];
    this.components = [];
    this.veneerNames = new Set();
    this.veneers = new Map();
    this.address = 0;
    this.size = 0;
    this.alignment = 1;
  }
}

class Segment {
  constructor(name, base, length, fill, outputNames) {
    Object.assign(this, {name, base, length, fill});
    this.outputs = outputNames.map(output => new OutputSection(this, output));
    this.memsz = 0;
    this.filesz = 0;
    this.paddr = base;
    this.used = 0;
    this.image = null;
  }
}

function outputFor(section, outputs) {
  return outputs.find(output => belongs(section.name, output.name)) ?? null;
}

function placeSegment(segment) {
  let cursor = segment.base;
  segment.filesz = 0;
  for (const output of segment.outputs) {
    output.alignment = 1;
    for (const component of output.components) output.alignment = Math.max(output.alignment, component.alignment);
    cursor = align(cursor, output.alignment);
    output.address = cursor;
    for (const component of output.components) {
      cursor = align(cursor, component.alignment);
      component.address = cursor;
      cursor += component.size;
    }
    output.size = cursor - output.address;
    if (!output.nobits) segment.filesz = cursor - segment.base;
  }
  segment.memsz = cursor - segment.base;
}

module.exports = {Segment, OutputSection, align, outputFor, placeSegment};
