import Foundation

struct Params {
    let referenceDay: Int
    let snapshotDay: Int
    let outcomeDays: Int
    let kMin: Int
    let kMax: Int
    let methods: [String]
    let restarts: Int
    let maxIterations: Int
    let seed: Int64
    let subsamples: Int
    let subsamplePercent: Int
    let outlierSD: Double
    let overdueFactor: Int
    let orderBins: [Int64]
    let topCategories: Int
    let topCustomers: Int
    let periodDays: Int
    let periods: Int
}

struct TransactionRow {
    let customer: String
    let day: Int
    let orderID: String
    let category: String
    let amount: Int64
}

struct TransactionData {
    let rowCount: Int
    let duplicates: Int
    let free: Int
    let validRows: [TransactionRow]
    let customers: Set<String>
}

struct Order {
    let customer: String
    var day: Int
    var net: Int64
    var rows: [TransactionRow]
}

func asciiLess(_ first: String, _ second: String) -> Bool {
    first.utf8.lexicographicallyPrecedes(second.utf8)
}

func readLines(_ path: String) throws -> [String] {
    try String(contentsOfFile: path, encoding: .utf8).split(separator: "\n").map(String.init)
}

func readParams(_ path: String) throws -> Params {
    let entries = try readLines(path).map { $0.split(separator: " ").dropFirst().map(String.init) }
    func value(_ line: Int) -> Int { Int(entries[line][0])! }
    return Params(referenceDay: value(0), snapshotDay: value(1), outcomeDays: value(2),
        kMin: value(3), kMax: Int(entries[3][1])!, methods: entries[4], restarts: value(5),
        maxIterations: value(6), seed: Int64(entries[7][0])!, subsamples: value(8),
        subsamplePercent: value(9), outlierSD: Double(entries[10][0])!, overdueFactor: value(11),
        orderBins: entries[12].map { Int64($0)! }, topCategories: value(13), topCustomers: value(14),
        periodDays: value(15), periods: value(16))
}

func readTransactions(_ path: String) throws -> TransactionData {
    var seen: Set<String> = []
    var customers: Set<String> = []
    var validRows: [TransactionRow] = []
    var rowCount = 0
    var duplicates = 0
    var free = 0
    for line in try readLines(path).dropFirst() {
        let fields = line.split(separator: ",").map(String.init)
        let row = TransactionRow(customer: fields[0], day: Int(fields[1])!, orderID: fields[2],
            category: fields[3], amount: Int64(fields[4])!)
        rowCount += 1
        customers.insert(row.customer)
        if !seen.insert(line).inserted { duplicates += 1 }
        else if row.amount == 0 { free += 1 }
        else { validRows.append(row) }
    }
    return TransactionData(rowCount: rowCount, duplicates: duplicates, free: free, validRows: validRows, customers: customers)
}

func groupOrders(_ rows: [TransactionRow], _ first: Int, _ last: Int) -> [Order] {
    var orders: [Order] = []
    var indices: [String: Int] = [:]
    for row in rows where first <= row.day && row.day <= last {
        if indices[row.orderID] == nil {
            indices[row.orderID] = orders.count
            orders.append(Order(customer: row.customer, day: row.day, net: 0, rows: []))
        }
        let index = indices[row.orderID]!
        orders[index].day = min(orders[index].day, row.day)
        orders[index].net += row.amount
        orders[index].rows.append(row)
    }
    return orders
}

func ordersByCustomer(_ orders: [Order]) -> [String: [Order]] {
    var grouped: [String: [Order]] = [:]
    for order in orders { grouped[order.customer, default: []].append(order) }
    return grouped
}
