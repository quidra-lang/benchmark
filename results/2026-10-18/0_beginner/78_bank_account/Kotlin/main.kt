import java.math.BigDecimal
import java.math.RoundingMode


fun main() {
    val transactions = listOf("deposit Emma 1200", "withdraw Leo 4000", "transfer Nina Leo 5000",
        "withdraw Leo 4000", "transfer Emma Nina 2500", "transfer Emma Nina 2000",
        "withdraw Emma 300", "deposit Nina 750", "transfer Leo Emma 3200", "withdraw Nina 9800")
    val balances = sortedMapOf("Nina" to 12000,"Leo" to 3500,"Emma" to 800)
    for ((i,transaction) in transactions.withIndex()) {
        val parts = transaction.split(' ')
        val name = parts[1]
        val amount = parts.last().toInt()
        val success = parts[0] == "deposit" || balances.getValue(name) >= amount
        if (success) {
            if (parts[0] == "deposit") balances[name] = balances.getValue(name) + amount
            else {
                balances[name] = balances.getValue(name) - amount
                if (parts[0] == "transfer") balances[parts[2]] = balances.getValue(parts[2]) + amount
            }
        }
        println("op ${i + 1}: $transaction" + if (success) " ok" else " failed (insufficient funds)")
    }
    for ((name,balance) in balances) println("$name: $balance")
}
