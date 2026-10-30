object Bitstream {
    const val ALPHANUMERIC="0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ $%*+-./:"
    fun binary(value: Int,width: Int)=buildString {
        for(bit in width-1 downTo 0)append((value ushr bit) and 1)
    }
    class Writer {
        private val bits=StringBuilder();
        fun write(value: Int,width: Int) {
            bits.append(binary(value,width))
        };
        fun value()=bits.toString()
    }
    class Reader(val bits: String) {
        var position=0;
        fun remaining()=bits.length-position;
        fun read(width: Int): Int {
            var value=0;
            repeat(width) {
                value=(value shl 1) or (bits[position++]-'0')
            };
            return value
        }
    }
    fun toCodewords(bits: String): IntArray {
        val reader=Reader(bits);
        return IntArray(bits.length/8) {
            reader.read(8)
        }
    }
    fun fromCodewords(words: IntArray)=buildString {
        for(word in words)append(binary(word,8))
    }
    fun hexadecimal(words: IntArray)=buildString {
        for(word in words) {
            append("0123456789abcdef"[word ushr 4]);
            append("0123456789abcdef"[word and 15])
        }
    }
}
