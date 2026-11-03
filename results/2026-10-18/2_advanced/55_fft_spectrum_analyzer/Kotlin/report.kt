import java.io.File
import java.math.BigDecimal
import java.math.RoundingMode
import kotlin.math.*

object Report {
    fun f(value: Double): String {
        var result=BigDecimal.valueOf(value).setScale(4,RoundingMode.HALF_UP);
        if(result.signum()==0)result=BigDecimal.ZERO.setScale(4);
        return result.toPlainString()
    }
    fun write(name: String,lines: List<String>) {
        File("output/$name").writeText(lines.joinToString("\n",postfix="\n"),Charsets.US_ASCII)
    }
    fun shades(frames: Spectral.Frames,fs: Int,length: Int,band: Int): List<String> {
        val out=mutableListOf<String>();
        val characters=" .:-=+*#%@";
        for(k in length/2 downTo 0) {
            var line=f(k.toDouble()*fs/length).padStart(9)+" |";
            for(frame in frames.magnitude) {
                val db=20*log10(frame[k]/frames.maximum);
                val level=maxOf(0,9-floor(-db/band).toInt());
                line+=characters[level]
            };
            out+=line+"|"
        };
        return out
    }
}
