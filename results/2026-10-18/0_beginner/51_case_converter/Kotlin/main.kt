import java.math.BigDecimal
import java.math.RoundingMode


fun main() {
    for (id in listOf("user_name","maxRetryCount","ShoppingCartItem","background-color","get_last_login_time","isEmailAddressValid")) {
        val words = id.split(Regex("[_-]|(?=[A-Z])")).filter { it.isNotEmpty() }.map { it.lowercase() }
        val capitals = words.map { it[0].uppercaseChar() + it.substring(1) }
        val camel = words.first() + capitals.drop(1).joinToString("")
        println("$id: snake=${words.joinToString("_")}, camel=$camel, pascal=${capitals.joinToString("")}, kebab=${words.joinToString("-")}")
    }
}
