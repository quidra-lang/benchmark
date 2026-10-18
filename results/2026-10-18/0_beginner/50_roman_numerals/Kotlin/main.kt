fun main() {
    val values = intArrayOf(1000,900,500,400,100,90,50,40,10,9,5,4,1)
    val digitValues = intArrayOf(1,5,10,50,100,500,1000)
    val symbols = listOf("M","CM","D","CD","C","XC","L","XL","X","IX","V","IV","I")
    for (n in intArrayOf(9,14,49,94,444,1994,2768,3999)) {
        var remaining = n
        val roman = StringBuilder()
        for (i in values.indices) while (remaining >= values[i]) {
            roman.append(symbols[i])
            remaining -= values[i]
        }
        var decoded = 0
        for (i in roman.indices) {
            val value = digitValues["IVXLCDM".indexOf(roman[i])]
            val next = if (i + 1 < roman.length) digitValues["IVXLCDM".indexOf(roman[i + 1])] else 0
            decoded += if (value < next) -value else value
        }
        println("$n -> $roman -> $decoded")
    }
}
