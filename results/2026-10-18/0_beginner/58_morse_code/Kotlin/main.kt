fun main() {
    val alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    val codes = ".- -... -.-. -.. . ..-. --. .... .. .--- -.- .-.. -- -. --- .--. --.- .-. ... - ..- ...- .-- -..- -.-- --.. ----- .---- ..--- ...-- ....- ..... -.... --... ---.. ----.".split(' ')
    val reverse = codes.zip(alphabet.toList()).toMap()
    val message = "MEET ME AT PIER 9 AT 1745"
    val encoded = message.split(' ')
        .joinToString(" / ") { word -> word.map { codes[alphabet.indexOf(it)] }.joinToString(" ") }
    val decoded = encoded.split(" / ")
        .joinToString(" ") { word -> word.split(' ').joinToString("") { reverse[it]!!.toString() } }
    println(encoded)
    println(decoded)
}
