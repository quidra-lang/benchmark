object Substitution {
    fun mod(number: Int, modulus: Int = 26): Int =
        ((number % modulus) + modulus) % modulus

    fun inverse(value: Int): Int =
        (1..25).first { (it * value) % 26 == 1 }

    fun apply(text: String, cipher: String, key: String, encrypt: Boolean): String {
        val pair = if (cipher == "affine") key.split(",") else emptyList()
        val a = if (pair.isEmpty()) 1 else pair[0].toInt()
        val b = when (cipher) {
            "caesar" -> key.toInt()
            "affine" -> pair[1].toInt()
            else -> 0
        }
        val inverse = if (cipher == "affine") inverse(a) else 1
        val plaintext = ArrayList<Int>()
        val result = StringBuilder(text.length)
        var index = 0
        for (c in text) {
            if (!Scoring.letter(c)) {
                result.append(c)
                continue
            }
            val x = Scoring.value(c)
            val shift = when (cipher) {
                "vigenere" -> Scoring.value(key[index % key.length])
                "autokey" -> if (index < key.length) Scoring.value(key[index])
                    else plaintext[index - key.length]
                else -> 0
            }
            val y = when (cipher) {
                "caesar" -> mod(x + if (encrypt) b else -b)
                "affine" -> if (encrypt) mod(a * x + b) else mod(inverse * (x - b))
                "vigenere", "autokey" -> mod(x + if (encrypt) shift else -shift)
                else -> error("unknown substitution cipher")
            }
            plaintext.add(if (encrypt) x else y)
            result.append((if (c in 'a'..'z') 'a'.code + y else 'A'.code + y).toChar())
            index++
        }
        return result.toString()
    }
}
