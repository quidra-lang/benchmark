data class Reference(val txid: String, val index: Int) : Comparable<Reference> {
    override fun compareTo(other: Reference): Int = compareValuesBy(this, other, Reference::txid, Reference::index)
    override fun toString(): String = "$txid:$index"
}
data class Payment(val address: String, val amount: Int) {
    override fun toString(): String = "$address:$amount"
}
data class Coin(val address: String, val amount: Int, val height: Int, val coinbase: Boolean) {
    fun mature(at: Int, maturity: Int): Boolean = !coinbase || height == 0 || at >= height + maturity
}
data class Check(val reason: String?, val fee: Int)
class Transaction(val text: String, val inputs: List<Reference>, val outputs: List<Payment>, val signatures: List<String>, val coinbaseHeight: Int?) {
    val txid = Hashing.digest(text)
    val size get() = text.length
    val coinbase get() = coinbaseHeight != null
    val body get() = text.substringBefore(";sig=")
    val total get() = outputs.sumOf {
        it.amount
    }
}
object Transactions {
    fun parse(text: String): Transaction {
        val fields = text.split(";")
        val outputs = fields[1].removePrefix("out=").split(",").map {
            val pair = it.split(":");
            Payment(pair[0], pair[1].toInt())
        }
        if (fields[0].startsWith("cb=")) return Transaction(text, emptyList(), outputs, emptyList(), fields[0].drop(3).toInt())
        val inputs = fields[0].removePrefix("in=").split(",").map {
            val pair = it.split(":");
            Reference(pair[0], pair[1].toInt())
        }
        return Transaction(text, inputs, outputs, fields[2].drop(4).split(","), null)
    }
    fun create(inputs: List<Reference>, outputs: List<Payment>, secret: String): Transaction {
        val body = "in=${inputs.joinToString(",")};out=${outputs.joinToString(",")}"
        val signatures = inputs.indices.map {
            Wallets.sign(secret, it, body)
        }
        return Transaction("$body;sig=${signatures.joinToString(",")}", inputs.toList(), outputs, signatures, null)
    }
    fun coinbase(height: Int, outputs: List<Payment>): Transaction = Transaction("cb=$height;out=${outputs.joinToString(",")}",
         emptyList(), outputs, emptyList(), height)
    fun check(transaction: Transaction, utxo: Map<Reference, Coin>, spent: Set<Reference>, height: Int, owners: Map<String, Wallet>, maturity: Int): Check {
        for (output in transaction.outputs) if (output.address !in owners || output.amount == 0) return Check("bad-output", 0)
        val seen = mutableSetOf<Reference>()
        var total = 0
        for ((i, reference) in transaction.inputs.withIndex()) {
            if (reference in spent || reference in seen) return Check("double-spend", 0)
            val coin = utxo[reference] ?: return Check("missing-input", 0)
            if (!coin.mature(height, maturity)) return Check("immature", 0)
            if (transaction.signatures[i] != Wallets.sign(owners.getValue(coin.address).secret, i, transaction.body)) return Check("bad-sig", 0)
            seen.add(reference)
            total += coin.amount
        }
        return if (total < transaction.total) Check("overspend", 0) else Check(null, total - transaction.total)
    }
    fun apply(utxo: MutableMap<Reference, Coin>, transaction: Transaction, height: Int) {
        for (reference in transaction.inputs) utxo.remove(reference)
        for ((i, output) in transaction.outputs.withIndex()) utxo[Reference(transaction.txid,
             i)] = Coin(output.address, output.amount, height, transaction.coinbase)
    }
}
