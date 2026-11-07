import { readFileSync } from 'node:fs';

export type Method = 'forgy' | 'maximin' | 'kmeanspp';
export interface Settings {
  reference: number;
  snapshot: number;
  outcomeDays: number;
  minK: number;
  maxK: number;
  methods: Method[];
  restarts: number;
  iterations: number;
  seed: number;
  subsamples: number;
  percent: number;
  outlierSD: number;
  overdueFactor: number;
  orderBins: number[];
  topCategories: number;
  topCustomers: number;
  periodDays: number;
  periods: number;
}
export interface Transaction {
  customer: string;
  day: number;
  order: string;
  category: string;
  amount: number;
}
export interface Order {
  id: string;
  customer: string;
  day: number;
  net: number;
  rows: Transaction[];
}
export interface TransactionData {
  settings: Settings;
  rows: Transaction[];
  customers: Set<string>;
  count: number;
  duplicates: number;
  zero: number;
}
const readLines = (name: string) => readFileSync(`input/${name}`, 'ascii').split('\n').slice(0, -1);

export function readTransactions(): TransactionData {
  const parameters = new Map(
    readLines('params.txt').map((line) => {
      const [key, ...values] = line.split(' ');
      return [key, values];
    }),
  );
  const values = (key: string) => parameters.get(key)!;
  const number = (key: string) => Number(values(key)[0]);
  const methods = values('METHODS').map((value) => {
    if (value === 'forgy' || value === 'maximin' || value === 'kmeanspp') return value;
    throw new Error('Unknown initialization method');
  });
  const settings: Settings = {
    reference: number('REFERENCE_DAY'),
    snapshot: number('SNAPSHOT_DAY'),
    outcomeDays: number('OUTCOME_DAYS'),
    minK: Number(values('K_RANGE')[0]),
    maxK: Number(values('K_RANGE')[1]),
    methods,
    restarts: number('RESTARTS'),
    iterations: number('MAX_ITERATIONS'),
    seed: number('SEED'),
    subsamples: number('SUBSAMPLES'),
    percent: number('SUBSAMPLE_PERCENT'),
    outlierSD: number('OUTLIER_SD'),
    overdueFactor: number('OVERDUE_FACTOR'),
    orderBins: values('ORDER_BINS').map(Number),
    topCategories: number('TOP_CATEGORIES'),
    topCustomers: number('TOP_CUSTOMERS'),
    periodDays: number('PERIOD_DAYS'),
    periods: number('PERIODS'),
  };
  const records = readLines('transactions.csv').slice(1);
  const seen = new Set<string>();
  const customers = new Set<string>();
  const rows: Transaction[] = [];
  let duplicates = 0;
  let zero = 0;
  for (const text of records) {
    const [customer, day, order, category, amount] = text.split(',');
    customers.add(customer);
    if (seen.has(text)) {
      duplicates++;
      continue;
    }
    seen.add(text);
    if (Number(amount) === 0) {
      zero++;
      continue;
    }
    rows.push({ customer, day: Number(day), order, category, amount: Number(amount) });
  }
  return { settings, rows, customers, count: records.length, duplicates, zero };
}

export function groupOrders(rows: Transaction[], first: number, last: number): Order[] {
  const orders = new Map<string, Order>();
  for (const row of rows) {
    if (row.day < first || row.day > last) continue;
    let order = orders.get(row.order);
    if (!order) {
      order = { id: row.order, customer: row.customer, day: row.day, net: 0, rows: [] };
      orders.set(row.order, order);
    }
    order.day = Math.min(order.day, row.day);
    order.net += row.amount;
    order.rows.push(row);
  }
  return [...orders.values()];
}
