import java.io.File

class Params(
    val referenceDay: Int, val snapshotDay: Int, val outcomeDays: Int, val kMin: Int, val kMax: Int,
    val methods: List<String>, val restarts: Int, val maxIterations: Int, val seed: Long,
    val subsamples: Int, val subsamplePercent: Int, val outlierSd: Double, val overdueFactor: Int,
    val orderBins: IntArray, val topCategories: Int, val topCustomers: Int, val periodDays: Int, val periods: Int
)
data class Transaction(val customer: String, val day: Int, val orderId: String, val category: String, val amount: Int)
class TransactionData {
    var rowCount = 0
    var duplicates = 0
    var free = 0
    val validRows = mutableListOf<Transaction>()
    val customers = sortedSetOf<String>()
}
class Order(row: Transaction) {
    val id = row.orderId
    val customer = row.customer
    var day = row.day
    var net = 0
    val rows = mutableListOf<Transaction>()
    fun add(row: Transaction) {
        day = minOf(day, row.day)
        net += row.amount
        rows.add(row)
    }
    fun valid() = net > 0
}
object Transactions {
    fun lines(path: String): List<String> = File(path).readLines(Charsets.US_ASCII)
    fun readParams(path: String): Params {
        val values = linkedMapOf<String, List<String>>()
        for (line in lines(path)) {
            val fields = line.split(' ')
            values[fields[0]] = fields.drop(1)
        }
        fun value(key: String) = values.getValue(key)[0].toInt()
        return Params(value("REFERENCE_DAY"), value("SNAPSHOT_DAY"), value("OUTCOME_DAYS"), value("K_RANGE"), values.getValue("K_RANGE")[1].toInt(),
            values.getValue("METHODS"), value("RESTARTS"), value("MAX_ITERATIONS"), value("SEED").toLong(), value("SUBSAMPLES"), value("SUBSAMPLE_PERCENT"),
            values.getValue("OUTLIER_SD")[0].toDouble(), value("OVERDUE_FACTOR"), values.getValue("ORDER_BINS").map(String::toInt).toIntArray(),
            value("TOP_CATEGORIES"), value("TOP_CUSTOMERS"), value("PERIOD_DAYS"), value("PERIODS"))
    }
    fun read(path: String): TransactionData {
        val data = TransactionData()
        val seen = mutableSetOf<String>()
        for (line in lines(path).drop(1)) {
            val fields = line.split(',')
            val row = Transaction(fields[0], fields[1].toInt(), fields[2], fields[3], fields[4].toInt())
            data.rowCount++
            data.customers.add(row.customer)
            if (!seen.add(line)) data.duplicates++
            else if (row.amount == 0) data.free++
            else data.validRows.add(row)
        }
        return data
    }
    fun groupOrders(rows: List<Transaction>, first: Int, last: Int): List<Order> {
        val orders = linkedMapOf<String, Order>()
        for (row in rows) if (row.day in first..last) orders.getOrPut(row.orderId) { Order(row) }.add(row)
        return orders.values.toList()
    }
    fun byCustomer(orders: List<Order>): Map<String, List<Order>> {
        val groups = linkedMapOf<String, MutableList<Order>>()
        for (order in orders) groups.getOrPut(order.customer) { mutableListOf() }.add(order)
        return groups
    }
}
