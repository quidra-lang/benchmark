import java.io.File
import java.util.Locale

object Report {
    fun decimal(p: Int,q: Int): String {
        val n=(2*p*10000+q)/(2*q);
        return "${n/10000}.${(n%10000).toString().padStart(4,'0')}"
    }
    fun percentage(p: Int,q: Int): String {
        if(q==0)return "-";
        val n=(2*p*10000+q)/(2*q);
        return "${n/100}.${(n%100).toString().padStart(2,'0')}"
    }
    fun fraction(p: Int,q: Int): String {
        var a=p;
        var b=q;
        while(b!=0) {
            val t=a%b;
            a=b;
            b=t
        };
        return "${p/a}/${q/a}"
    }
    fun hex(value: Int)=value.toString(16).padStart(8,'0')
    fun register(value: Int)=if(value<0)"-" else "r$value"
    fun heading(first: Int,last: Int)="cycle"+" ".repeat(18)+(first..last).joinToString("") {
        (it%10).toString()
    }
    fun row(number: Int,pc: Int,kind: String,cells: String,annotation: String): String {
        val identifier=if(number<0)"-" else number.toString()
        return "${identifier.padStart(6)} ${hex(pc)} ${kind.padEnd(6)} $cells$annotation"
    }
    fun write(name: String,lines: List<String>) {
        File("output").mkdirs();
        File("output",name).writeText(lines.joinToString("\n")+"\n")
    }
}
