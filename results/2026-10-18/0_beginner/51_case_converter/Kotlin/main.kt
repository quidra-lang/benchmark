fun main() {
    val ids = listOf(
        "user_name", "maxRetryCount", "ShoppingCartItem", "background-color", "get_last_login_time",
        "isEmailAddressValid",
    )
    for (id in ids) {
        val words = id.split(Regex("[_-]|(?=[A-Z])")).filter { it.isNotEmpty() }.map { it.lowercase() }
        val capitals = words.map { it[0].uppercaseChar() + it.substring(1) }
        val camel = words.first() + capitals.drop(1).joinToString("")
        println("$id: snake=${words.joinToString("_")}, camel=$camel, pascal=${capitals.joinToString("")}, kebab=${words.joinToString("-")}")
    }
}
