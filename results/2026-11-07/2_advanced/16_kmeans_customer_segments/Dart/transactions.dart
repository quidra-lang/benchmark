import 'dart:io';
import 'dart:math' as math;

List<String> readLines(String path) => File(path).readAsLinesSync();

class Params {
  final int referenceDay, snapshotDay, outcomeDays, kMin, kMax, restarts,
      maxIterations, seed, subsamples, subsamplePercent, overdueFactor,
      topCategories, topCustomers, periodDays, periods;
  final double outlierSD;
  final List<String> methods;
  final List<int> orderBins;
  Params(Map<String, List<String>> values)
      : referenceDay = int.parse(values['REFERENCE_DAY']![0]),
        snapshotDay = int.parse(values['SNAPSHOT_DAY']![0]),
        outcomeDays = int.parse(values['OUTCOME_DAYS']![0]),
        kMin = int.parse(values['K_RANGE']![0]), kMax = int.parse(values['K_RANGE']![1]),
        methods = values['METHODS']!, restarts = int.parse(values['RESTARTS']![0]),
        maxIterations = int.parse(values['MAX_ITERATIONS']![0]), seed = int.parse(values['SEED']![0]),
        subsamples = int.parse(values['SUBSAMPLES']![0]),
        subsamplePercent = int.parse(values['SUBSAMPLE_PERCENT']![0]),
        outlierSD = double.parse(values['OUTLIER_SD']![0]),
        overdueFactor = int.parse(values['OVERDUE_FACTOR']![0]),
        orderBins = values['ORDER_BINS']!.map(int.parse).toList(),
        topCategories = int.parse(values['TOP_CATEGORIES']![0]),
        topCustomers = int.parse(values['TOP_CUSTOMERS']![0]),
        periodDays = int.parse(values['PERIOD_DAYS']![0]), periods = int.parse(values['PERIODS']![0]);
}

class Row {
  final String customer, orderID, category;
  final int day, amount;
  Row(List<String> fields) : customer = fields[0], day = int.parse(fields[1]),
      orderID = fields[2], category = fields[3], amount = int.parse(fields[4]);
}

class TransactionData {
  var rowCount = 0, duplicates = 0, free = 0;
  final validRows = <Row>[];
  final customers = <String>{};
}

class Order {
  final String id, customer;
  int day, net = 0;
  final rows = <Row>[];
  Order(Row row) : id = row.orderID, customer = row.customer, day = row.day;
  void add(Row row) {
    day = math.min(day, row.day);
    net += row.amount;
    rows.add(row);
  }
}

Params readParams() {
  final values = <String, List<String>>{};
  for (final line in readLines('input/params.txt')) {
    final fields = line.split(' ');
    values[fields[0]] = fields.sublist(1);
  }
  return Params(values);
}

TransactionData readTransactions() {
  final data = TransactionData(), seen = <String>{};
  for (final line in readLines('input/transactions.csv').skip(1)) {
    final row = Row(line.split(','));
    data.rowCount++;
    data.customers.add(row.customer);
    if (!seen.add(line)) data.duplicates++;
    else if (row.amount == 0) data.free++;
    else data.validRows.add(row);
  }
  return data;
}

List<Order> groupOrders(List<Row> rows, int first, int last) {
  final orders = <String, Order>{};
  for (final row in rows) {
    if (first <= row.day && row.day <= last) {
      orders.putIfAbsent(row.orderID, () => Order(row)).add(row);
    }
  }
  return orders.values.toList();
}

Map<String, List<Order>> ordersByCustomer(List<Order> orders) {
  final groups = <String, List<Order>>{};
  for (final order in orders) {
    groups.putIfAbsent(order.customer, () => []).add(order);
  }
  return groups;
}
