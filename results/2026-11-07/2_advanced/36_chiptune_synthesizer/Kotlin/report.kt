import java.util.Locale
import kotlin.math.abs
object Report {
    data class Statistics(val peak: Int, val minimum: Int, val maximum: Int, val rms: Long, val crossings: Int)
    fun hex2(value: Int) = String.format(Locale.ROOT,"%02X",value)
    fun hex1(value: Int) = value.toString(16).uppercase(Locale.ROOT)
    fun hex8(value: Long) = String.format(Locale.ROOT,"%08X",value)
    fun aligned(value: Int, width: Int) = aligned(value.toLong(),width)
    fun aligned(value: Long, width: Int) = value.toString().padStart(width)
    fun dump(samples: IntArray, size: Int): List<String> {
        val result = mutableListOf<String>();
        for (start in 0 until size step 32) result.add((start until minOf(size,start + 32)).joinToString("") {
            hex2(samples[it])
        });
        return result
    }
    fun adler(samples: IntArray, size: Int): Long {
        var a = 1L;
        var b = 0L;
        for (i in 0 until size) {
            a = (a + samples[i]) % 65521;
            b = (b + a) % 65521
        };
        return b * 65536 + a
    }
    fun isqrt(n: Long): Long {
        var low = 0L;
        var high = 1L;
        while (high <= n / high) high *= 2;
        while (low + 1 < high) {
            val mid = (low + high) / 2;
            if (mid <= n / mid) low = mid else high = mid
        };
        return low
    }
    fun statistics(values: IntArray, start: Int, length: Int, center: Int): Statistics {
        var peak = 0;
        var minimum = Int.MAX_VALUE;
        var maximum = Int.MIN_VALUE;
        var crossings = 0;
        var squares = 0L;
        for (i in start until start + length) {
            val v = (values[i] - center).toLong();
            peak = maxOf(peak,abs(v).toInt());
            minimum = minOf(minimum,values[i]);
            maximum = maxOf(maximum,values[i]);
            squares += v * v;
            if (i > start && (values[i - 1] < center) != (values[i] < center)) crossings++
        };
        return Statistics(peak,minimum,maximum,isqrt(squares / length),crossings)
    }
}
