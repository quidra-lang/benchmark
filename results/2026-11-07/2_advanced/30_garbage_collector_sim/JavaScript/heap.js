'use strict';

function createObject(number, pointers, data) {
    return {
        number, pointers, data, size: 1 + pointers + data,
        fields: Array(pointers).fill(null), address: null, moves: 0, age: 0, references: 0,
    };
}

function addObject(pair, object) {
    pair[0]++;
    pair[1] += object.size;
}

function objectPair(objects) {
    const pair = [0, 0];
    for (const object of objects) addObject(pair, object);
    return pair;
}

function freeBlocks(objects, start, end) {
    const occupied = [...objects].filter(object => object.address >= start && object.address < end);
    occupied.sort((first, second) => first.address - second.address);
    const blocks = [];
    let address = start;
    for (const object of occupied) {
        if (object.address > address) blocks.push({ address, length: object.address - address });
        address = object.address + object.size;
    }
    if (address < end) blocks.push({ address, length: end - address });
    return blocks;
}

function firstFit(blocks, size) {
    const block = blocks.find(candidate => candidate.length >= size);
    return block === undefined ? null : block.address;
}

function freeAmount(blocks) {
    let total = 0;
    let largest = 0;
    for (const block of blocks) {
        total += block.length;
        largest = Math.max(largest, block.length);
    }
    return [total, largest];
}

function collectionRecord(line, request, kind, blocks) {
    return {
        number: 0, line, request, kind, live: [0, 0], freed: [0, 0],
        moved: [0, 0], promoted: [0, 0], stack: 0, work: 0,
        before: freeAmount(blocks), after: [0, 0],
    };
}

function dec2(numerator, denominator) {
    const rounded = Math.floor((200 * numerator + denominator) / (2 * denominator));
    return `${Math.floor(rounded / 100)}.${String(rounded % 100).padStart(2, '0')}`;
}

function pct(numerator, denominator) {
    return denominator === 0 ? '-' : dec2(100 * numerator, denominator);
}

function classTable(values) {
    const counts = [0, 0, 0, 0, 0];
    for (const value of values) {
        const index = value === 1 ? 0 : value <= 3 ? 1 : value <= 7 ? 2 : value <= 15 ? 3 : 4;
        counts[index]++;
    }
    return ['1', '2-3', '4-7', '8-15', '16+'].map((label, index) => `${label}:${counts[index]}`).join(' ');
}

function heapMap(heap, collector, reachable, width) {
    const words = Array(heap.size).fill('.');
    if (collector.half !== undefined) {
        const inactive = collector.half - collector.base;
        words.fill('-', inactive, inactive + collector.half);
    }
    for (const object of heap.objects.values()) {
        const live = reachable.has(object.number);
        const letter = (object.number - 1) % 26;
        words[object.address] = live ? String.fromCharCode(65 + letter) : '#';
        words.fill(live ? String.fromCharCode(97 + letter) : '=', object.address + 1, object.address + object.size);
    }
    const lines = [];
    for (let address = 0; address < heap.size; address += width) {
        lines.push(`${String(address).padStart(4, '0')} ${words.slice(address, address + width).join('')}`);
    }
    return lines;
}

module.exports = { createObject, addObject, objectPair, freeBlocks, firstFit, freeAmount, collectionRecord, dec2, pct, classTable, heapMap };
