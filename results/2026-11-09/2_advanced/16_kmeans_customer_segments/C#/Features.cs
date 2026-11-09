using System;
using System.Collections.Generic;
using System.Linq;

sealed class Customer
{
    public readonly string id;
    public readonly List<Order> orders;
    public readonly int recency, frequency, spend, categories, tenure;
    public readonly double monetary, basket;
    public readonly SortedDictionary<string, int> categorySpend = new(StringComparer.Ordinal);
    public Customer(string id, List<Order> orders, int day)
    {
        this.id = id; this.orders = orders;
        int latest = int.MinValue, earliest = int.MaxValue, total = 0;
        foreach (Order order in orders)
        {
            latest = Math.Max(latest, order.day); earliest = Math.Min(earliest, order.day); total += order.net;
            foreach (Transaction row in order.rows) categorySpend[row.category] = categorySpend.GetValueOrDefault(row.category) + row.amount;
        }
        recency = day - latest; frequency = orders.Count; spend = total; monetary = spend / 100.0; basket = monetary / frequency;
        categories = categorySpend.Values.Count(value => value > 0); tenure = day - earliest;
    }
    public double[] values() => [recency, frequency, monetary, basket, categories, tenure];
    public double[] transformed()
    {
        double[] result = values();
        for (int f = 0; f < result.Length; f++) if (Features.SQRT[f]) result[f] = Math.Sqrt(result[f]);
        return result;
    }
}
sealed record Standardization(double[] means, double[] sds);
static class Features
{
    public static readonly List<string> NAMES = ["recency", "frequency", "monetary", "basket", "categories", "tenure"];
    public static readonly bool[] SQRT = [false, true, true, true, false, false];
    public static List<Customer> eligible(List<Order> orders, int day)
    {
        var groups = Transactions.byCustomer(orders.Where(order => order.valid()).ToList());
        return groups.Keys.OrderBy(id => id, StringComparer.Ordinal).Select(id => new Customer(id, groups[id], day)).ToList();
    }
    public static double sum(double[] values) { double total = 0; foreach (double value in values) total += value; return total; }
    public static double mean(double[] values) => sum(values) / values.Length;
    public static double sampleSd(double[] values)
    {
        double average = mean(values), total = 0;
        foreach (double value in values) { double difference = value - average; total += difference * difference; }
        return Math.Sqrt(total / (values.Length - 1));
    }
    public static Standardization standardization(List<double[]> rows)
    {
        double[] means = new double[6], sds = new double[6];
        for (int f = 0; f < 6; f++)
        {
            double[] column = new double[rows.Count];
            for (int i = 0; i < column.Length; i++) column[i] = rows[i][f];
            means[f] = mean(column); sds[f] = sampleSd(column);
        }
        return new Standardization(means, sds);
    }
    public static double[] standardize(double[] values, double[] means, double[] sds)
    {
        double[] point = new double[values.Length];
        for (int f = 0; f < point.Length; f++) point[f] = sds[f] == 0 ? 0 : (values[f] - means[f]) / sds[f];
        return point;
    }
    public static double correlation(List<double[]> points, int first, int second)
    {
        double total = 0;
        foreach (double[] point in points) total += point[first] * point[second];
        return total / (points.Count - 1);
    }
}
