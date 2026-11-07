const fs = require('node:fs');

function compareNames(first, second) {
  return Number(first > second) - Number(first < second);
}

function compareItemsets(first, second) {
  for (let index = 0; index < Math.min(first.length, second.length); index += 1) {
    const order = compareNames(first[index], second[index]);
    if (order !== 0) return order;
  }
  return first.length - second.length;
}

function itemsetKey(items) {
  return items.join('+');
}

function contains(items, subset) {
  return subset.every(item => items.has(item));
}

function readCsv(path) {
  return fs.readFileSync(path, 'ascii').slice(0, -1).split('\n').slice(1)
    .map((line, index) => ({ line: index + 2, fields: line.split(',') }));
}

class Product {
  constructor(name, category, price) {
    this.name = name;
    this.category = category;
    this.price = price;
  }
}

class Transaction {
  constructor(tid, customer, day) {
    this.tid = tid;
    this.customer = customer;
    this.day = day;
    this.units = new Map();
  }

  add(item) {
    const previous = this.units.get(item) ?? 0;
    this.units.set(item, previous + 1);
    return previous > 0;
  }
}

function buildBasket(transaction) {
  return { tid: transaction.tid, customer: transaction.customer, day: transaction.day,
    units: transaction.units, items: new Set(transaction.units.keys()) };
}

function extendBasket(basket, products) {
  const items = new Set(basket.items);
  for (const item of basket.items) items.add(products.get(item).category);
  return items;
}

module.exports = { Product, Transaction, readCsv, buildBasket, extendBasket, contains,
  compareNames, compareItemsets, itemsetKey };
