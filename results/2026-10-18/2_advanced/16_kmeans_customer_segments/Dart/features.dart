import 'dart:math' as math;
import 'transactions.dart';

const featureNames = ['recency', 'frequency', 'monetary', 'basket', 'categories', 'tenure'];
const sqrtFeatures = [false, true, true, true, false, false];

class Customer {
  final String id;
  final List<Order> orders;
  final categorySpend = <String, int>{};
  late final int recency, frequency, spend, categories, tenure;
  late final double monetary, basket;
  Customer(this.id, this.orders, int day) {
    var first = orders.first.day, last = first, total = 0;
    for (final order in orders) {
      first = math.min(first, order.day);
      last = math.max(last, order.day);
      total += order.net;
      for (final row in order.rows) {
        categorySpend[row.category] = (categorySpend[row.category] ?? 0) + row.amount;
      }
    }
    recency = day - last;
    frequency = orders.length;
    spend = total;
    monetary = spend / 100;
    basket = monetary / frequency;
    categories = categorySpend.values.where((value) => value > 0).length;
    tenure = day - first;
  }
  List<double> values() => [recency.toDouble(), frequency.toDouble(), monetary,
      basket, categories.toDouble(), tenure.toDouble()];
  List<double> transformed() {
    final raw = values();
    return [for (var index = 0; index < raw.length; index++)
      sqrtFeatures[index] ? math.sqrt(raw[index]) : raw[index]];
  }
}

List<Customer> eligibleCustomers(List<Order> orders, int day) {
  final groups = ordersByCustomer(orders.where((order) => order.net > 0).toList());
  final ids = groups.keys.toList()..sort();
  return [for (final id in ids) Customer(id, groups[id]!, day)];
}

double orderedSum(Iterable<double> values) => values.fold(0.0, (total, value) => total + value);
double mean(List<double> values) => orderedSum(values) / values.length;
double sampleSD(List<double> values) {
  final average = mean(values);
  var total = 0.0;
  for (final value in values) {
    final difference = value - average;
    total += difference * difference;
  }
  return math.sqrt(total / (values.length - 1));
}

(List<double>, List<double>) standardization(List<List<double>> rows) {
  final columns = [for (var feature = 0; feature < featureNames.length; feature++)
    [for (final row in rows) row[feature]]];
  return (columns.map(mean).toList(), columns.map(sampleSD).toList());
}

List<double> standardize(List<double> values, List<double> means, List<double> sds) =>
    [for (var index = 0; index < values.length; index++)
      sds[index] == 0 ? 0.0 : (values[index] - means[index]) / sds[index]];
double correlation(List<List<double>> points, int first, int second) =>
    orderedSum(points.map((point) => point[first] * point[second])) / (points.length - 1);
