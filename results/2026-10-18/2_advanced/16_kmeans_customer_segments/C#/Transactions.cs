using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;

sealed record Params(int referenceDay, int snapshotDay, int outcomeDays, int kMin, int kMax, List<string> methods,
    int restarts, int maxIterations, long seed, int subsamples, int subsamplePercent, double outlierSd,
    int overdueFactor, int[] orderBins, int topCategories, int topCustomers, int periodDays, int periods);
sealed record Transaction(string customer, int day, string orderId, string category, int amount);
sealed class TransactionData
{
    public int rowCount, duplicates, free;
    public readonly List<Transaction> validRows = new();
    public readonly SortedSet<string> customers = new(StringComparer.Ordinal);
}
sealed class Order
{
    public readonly string id, customer;
    public int day, net;
    public readonly List<Transaction> rows = new();
    public Order(Transaction row) { id = row.orderId; customer = row.customer; day = row.day; }
    public void add(Transaction row) { day = Math.Min(day, row.day); net += row.amount; rows.Add(row); }
    public bool valid() => net > 0;
}
static class Transactions
{
    public static List<string> lines(string path) => File.ReadAllLines(path, Encoding.ASCII).ToList();
    public static Params readParams(string path)
    {
        var values = new Dictionary<string, string[]>(StringComparer.Ordinal);
        foreach (string line in lines(path)) { string[] fields = line.Split(' '); values[fields[0]] = fields.Skip(1).ToArray(); }
        int value(string key) => int.Parse(values[key][0]);
        return new Params(value("REFERENCE_DAY"), value("SNAPSHOT_DAY"), value("OUTCOME_DAYS"), value("K_RANGE"), int.Parse(values["K_RANGE"][1]),
            values["METHODS"].ToList(), value("RESTARTS"), value("MAX_ITERATIONS"), value("SEED"), value("SUBSAMPLES"), value("SUBSAMPLE_PERCENT"),
            double.Parse(values["OUTLIER_SD"][0], System.Globalization.CultureInfo.InvariantCulture), value("OVERDUE_FACTOR"),
            values["ORDER_BINS"].Select(int.Parse).ToArray(), value("TOP_CATEGORIES"), value("TOP_CUSTOMERS"), value("PERIOD_DAYS"), value("PERIODS"));
    }
    public static TransactionData read(string path)
    {
        var data = new TransactionData();
        var seen = new HashSet<string>(StringComparer.Ordinal);
        foreach (string line in lines(path).Skip(1))
        {
            string[] fields = line.Split(',');
            var row = new Transaction(fields[0], int.Parse(fields[1]), fields[2], fields[3], int.Parse(fields[4]));
            data.rowCount++; data.customers.Add(row.customer);
            if (!seen.Add(line)) data.duplicates++;
            else if (row.amount == 0) data.free++;
            else data.validRows.Add(row);
        }
        return data;
    }
    public static List<Order> groupOrders(List<Transaction> rows, int first, int last)
    {
        var byId = new Dictionary<string, Order>(StringComparer.Ordinal);
        var orders = new List<Order>();
        foreach (Transaction row in rows)
        {
            if (row.day < first || row.day > last) continue;
            if (!byId.TryGetValue(row.orderId, out Order order)) { order = new Order(row); byId[row.orderId] = order; orders.Add(order); }
            order.add(row);
        }
        return orders;
    }
    public static Dictionary<string, List<Order>> byCustomer(List<Order> orders)
    {
        var groups = new Dictionary<string, List<Order>>(StringComparer.Ordinal);
        foreach (Order order in orders)
        {
            if (!groups.TryGetValue(order.customer, out var group)) { group = new(); groups[order.customer] = group; }
            group.Add(order);
        }
        return groups;
    }
}
