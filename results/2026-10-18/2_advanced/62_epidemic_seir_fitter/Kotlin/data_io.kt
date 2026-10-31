import java.io.File

object DataIO {
    data class Group(val name: String,val population: Int,val fatality: Double)
    data class Intervention(val day: Int,val multiplier: Double)
    data class Scenario(val name: String,val multiplier: Double)
    data class ContactChange(val name: String,val group: String,val factor: Double)
    class Settings {
        val values=mutableMapOf<String,List<String>>();
        val scenarios=mutableListOf<Scenario>();
        val changes=mutableListOf<ContactChange>()
        fun integer(name: String,index: Int)=values.getValue(name)[index].toInt()
        fun real(name: String,index: Int)=values.getValue(name)[index].toDouble()
        fun integers(name: String)=values.getValue(name).map {
            it.toInt()
        }.toIntArray()
    }
    data class Data(val cases: IntArray,val deaths: IntArray,val groups: List<Group>,val contacts: Array<DoubleArray>,
        val interventions: List<Intervention>,val settings: Settings)
    fun lines(name: String)=File("input",name).readLines()
    fun read(): Data {
        val input=lines("cases.csv");
        val cases=IntArray(input.size-1);
        val deaths=IntArray(cases.size)
        for(i in cases.indices) {
            val w=input[i+1].split(',');
            cases[i]=w[1].toInt();
            deaths[i]=w[2].toInt()
        }
        val groups=mutableListOf<Group>();
        val contacts=mutableListOf<DoubleArray>()
        for(line in lines("population.txt")) {
            val w=line.split(' ');
            if(w[0]=="group")groups.add(Group(w[1],w[2].toInt(),w[3].toDouble())) else contacts.add(w.drop(1).map {
                it.toDouble()
            }.toDoubleArray())
        }
        val interventions=lines("interventions.txt").map {
            val w=it.split(' ');
            Intervention(w[0].toInt(),w[1].toDouble())
        };
        val s=Settings()
        for(line in lines("params.txt")) {
            val w=line.split(' ');
            if(w[0]=="scenario")s.scenarios.add(Scenario(w[1],w[2].toDouble())) else if(w[0]=="contact_change")s.changes.add(ContactChange(w[1],
                w[2],w[3].toDouble())) else s.values[w[0]]=w.drop(1)
        }
        return Data(cases,deaths,groups,contacts.toTypedArray(),interventions,s)
    }
    fun write(name: String,lines: List<String>) {
        File("output").mkdirs();
        File("output",name).writeText(lines.joinToString("\n")+"\n")
    }
}
