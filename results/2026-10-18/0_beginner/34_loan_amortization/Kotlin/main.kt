import java.math.BigDecimal
import java.math.RoundingMode


fun main() {
    var balance = 1000000; var month = 0; var totalInterest = 0; var totalPaid = 0
    while (balance > 0) {
        month++
        val interest = balance / 100; val payment = minOf(50000, balance + interest); val principal = payment - interest
        balance -= principal; totalInterest += interest; totalPaid += payment
        println("month $month: interest=$interest principal=$principal balance=$balance")
    }
    println("total interest: $totalInterest")
    println("total paid: $totalPaid")
}
