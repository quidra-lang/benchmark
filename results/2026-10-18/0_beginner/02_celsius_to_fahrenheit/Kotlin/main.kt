import java.util.Locale

fun main() {
    val temperatures = intArrayOf(-40, -15, -3, 0, 22, 37, 100)
    for (celsius in temperatures) {
        val fahrenheit = celsius * 9.0 / 5.0 + 32
        println("%d C = %.1f F".format(Locale.ROOT, celsius, fahrenheit))
    }
}
