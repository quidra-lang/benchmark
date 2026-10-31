'use strict';

const fs = require('node:fs');
const readLines = name => fs.readFileSync(`input/${name}`, 'ascii').split('\n').slice(0, -1);

function readTransactions() {
  const parameters = new Map(readLines('params.txt').map(line => {
    const [key, ...values] = line.split(' ');
    return [key, values];
  }));
  const number = key => Number(parameters.get(key)[0]);
  const settings = { reference: number('REFERENCE_DAY'), snapshot: number('SNAPSHOT_DAY'), outcomeDays: number('OUTCOME_DAYS'),
    minK: Number(parameters.get('K_RANGE')[0]), maxK: Number(parameters.get('K_RANGE')[1]), methods: parameters.get('METHODS'),
    restarts: number('RESTARTS'), iterations: number('MAX_ITERATIONS'), seed: number('SEED'), subsamples: number('SUBSAMPLES'),
    percent: number('SUBSAMPLE_PERCENT'), outlierSD: number('OUTLIER_SD'), overdueFactor: number('OVERDUE_FACTOR'),
    orderBins: parameters.get('ORDER_BINS').map(Number), topCategories: number('TOP_CATEGORIES'), topCustomers: number('TOP_CUSTOMERS'),
    periodDays: number('PERIOD_DAYS'), periods: number('PERIODS') };
  const records = readLines('transactions.csv').slice(1), seen = new Set(), customers = new Set(), rows = [];
  let duplicates = 0, zero = 0;
  for (const text of records) {
    const [customer, day, order, category, amount] = text.split(',');
    customers.add(customer);
    if (seen.has(text)) { duplicates++; continue; }
    seen.add(text);
    if (Number(amount) === 0) { zero++; continue; }
    rows.push({ customer, day: Number(day), order, category, amount: Number(amount) });
  }
  return { settings, rows, customers, count: records.length, duplicates, zero };
}

function groupOrders(rows, first, last) {
  const orders = new Map();
  for (const row of rows) {
    if (row.day < first || row.day > last) continue;
    if (!orders.has(row.order)) orders.set(row.order, { id: row.order, customer: row.customer, day: row.day, net: 0, rows: [] });
    const order = orders.get(row.order);
    order.day = Math.min(order.day, row.day);
    order.net += row.amount;
    order.rows.push(row);
  }
  return [...orders.values()];
}

module.exports = { readTransactions, groupOrders };
