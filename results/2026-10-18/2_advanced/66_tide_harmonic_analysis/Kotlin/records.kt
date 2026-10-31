import java.io.File
import java.time.*
import java.time.format.DateTimeFormatter
import java.time.temporal.ChronoUnit
import java.util.Locale
import java.util.TreeMap
object Records {
    val format=DateTimeFormatter.ofPattern("uuuu-MM-dd HH:mm",Locale.ROOT)
    data class Constituent(val name: String,val speed: Double)
    class Station(val code: String,val name: String) {
        var rows=0;
        val values=TreeMap<Int,Int?>()
    }
    class Settings {
        lateinit var epoch: LocalDateTime;
        lateinit var start: LocalDateTime;
        var ts=0;
        val values=mutableMapOf<String,List<String>>();
        fun integer(key: String,index: Int)=values.getValue(key)[index].toInt();
        fun real(key: String,index: Int)=values.getValue(key)[index].toDouble();
        fun text(key: String,index: Int)=values.getValue(key)[index]
    }
    data class Data(val settings: Settings,val stations: List<Station>,val constituents: List<Constituent>)
    fun parse(text: String)=LocalDateTime.parse(text,format)
    fun hours(epoch: LocalDateTime,value: LocalDateTime)=ChronoUnit.HOURS.between(epoch,value).toInt()
    fun hour(s: Settings,t: Int)=s.epoch.plusHours(t.toLong()).format(format)
    fun minute(s: Settings,m: Int)=s.epoch.plusMinutes(m.toLong()).format(format)
    fun dateHour(s: Settings,t: Int)=s.epoch.plusHours(t.toLong()).toLocalDate()
    fun dateMinute(s: Settings,m: Int)=s.epoch.plusMinutes(m.toLong()).toLocalDate()
    fun noon(s: Settings,date: LocalDate)=hours(s.epoch,date.atTime(12,0))
    fun read(): Data {
        val s=Settings();
        val stations=mutableListOf<Station>();
        var lines=File("input","params.txt").readLines();
        s.epoch=parse(lines[0].substring(6));
        for(line in lines.drop(1)) {
            val w=line.split(' ');
            if(w[0]=="station")stations.add(Station(w[1],line.substring(12))) else s.values[w[0]]=w.drop(1)
        };
        s.start=parse(s.text("predict",0)+" "+s.text("predict",1));
        s.ts=hours(s.epoch,s.start);
        val constituents=mutableListOf<Constituent>();
        lines=File("input","constituents.txt").readLines();
        for(line in lines.drop(1)) {
            val w=line.split(' ');
            constituents.add(Constituent(w[0],w[1].toDouble()))
        };
        lines=File("input","observations.csv").readLines();
        for(line in lines.drop(1)) {
            val w=line.split(',');
            val station=stations.first {
                it.code==w[0]
            };
            val t=hours(s.epoch,parse(w[1]));
            station.values[t]=if(w[2]=="NA")null else w[2].replace(".","").toInt();
            station.rows++
        };
        return Data(s,stations,constituents)
    }
}
