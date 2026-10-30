import java.io.File
object ConfigIo {
    data class Scenario(val name: String,val protocol: String,val l1: String,val l2: String,val order: Int)
    data class Region(val name: String,val start: Int,val end: Int)
    class Config {
        var cores=0;
        var line=0;
        var l1Size=0;
        var l1Ways=0;
        var l1Sets=0;
        var l2Size=0;
        var l2Ways=0;
        var l2Sets=0;
        var t1=0;
        var t2=0;
        var tm=0;
        var tb=0;
        var interval=0;
        var top=0;
        var cap=0;
        var primary="";
        val scenarios=mutableListOf<Scenario>();
        val regions=mutableListOf<Region>();
        val watch=mutableListOf<Int>()
    }
    fun decimalInteger(text: String,maximum: Int): Boolean {
        if(text.isEmpty()||maximum>0&&text.length>maximum||text.length>1&&text[0]=='0')return false;
        return text.all {
            it in '0'..'9'
        }
    }
    fun validHexAddress(text: String)=text.length==8&&text.all {
        it in "0123456789abcdef"
    }
    fun hexAddress(value: Int)=value.toString(16).padStart(8,'0')
    fun readConfig(): Config {
        val c=Config();
        for(line in File("input/config.txt").readLines(Charsets.US_ASCII)) {
            val f=line.split(' ');
            when(f[0]) {
                "CORES"->c.cores=f[1].toInt();
                "LINE"->c.line=f[1].toInt();
                "L1"-> {
                    c.l1Size=f[1].toInt();
                    c.l1Ways=f[2].toInt()
                };
                "L2"-> {
                    c.l2Size=f[1].toInt();
                    c.l2Ways=f[2].toInt()
                };
                "LATENCY"-> {
                    c.t1=f[1].toInt();
                    c.t2=f[2].toInt();
                    c.tm=f[3].toInt();
                    c.tb=f[4].toInt()
                };
                "SCENARIO"->c.scenarios.add(Scenario(f[1],f[2],f[3],f[4],c.scenarios.size));
                "PRIMARY"->c.primary=f[1];
                "INTERVAL"->c.interval=f[1].toInt();
                "TOP"->c.top=f[1].toInt();
                "REGION"->c.regions.add(Region(f[1],f[2].toInt(16),f[3].toInt(16)));
                "WATCH"->c.watch.add(f[1].toInt(16)/c.line)
            }
        };
        c.l1Sets=c.l1Size/(c.line*c.l1Ways);
        c.l2Sets=c.l2Size/(c.line*c.l2Ways);
        c.cap=c.l1Sets*c.l1Ways;
        return c
    }
    fun readTrace()=File("input/trace.txt").readLines(Charsets.US_ASCII)
    fun writeLines(name: String,lines: List<String>) {
        File("output").mkdirs();
        File("output/$name").writeText(if(lines.isEmpty())"" else lines.joinToString("\n")+"\n",Charsets.US_ASCII)
    }
}
