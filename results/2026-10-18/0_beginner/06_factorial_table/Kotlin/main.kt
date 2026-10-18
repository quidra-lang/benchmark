fun main() {
    var factorial = 1
    for (n in 0..12) {
        if (n > 0) factorial *= n
        println("$n! = $factorial")
    }
}
