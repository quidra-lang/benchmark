import java.io.File

object Dataset {
    data class Subject(val id: Int,val group: String,val time: Int,val event: Int,val age: Int,val sex: String,val stage: Int)
    class Settings {
        var groups=listOf<String>();
        var subgroups=listOf<String>();
        var covariates=listOf<String>();
        var strata="";
        var report=intArrayOf();
        var tau=0;
        var lifeWidth=0;
        var lifeCount=0;
        var landmark=0;
        var residuals=0;
        var width=0;
        var height=0;
        var horizon=0;
        var divisions=0
    }
    data class Data(val subjects: List<Subject>,val settings: Settings)
    fun read(): Data {
        val subjects=File("input/subjects.csv").readLines(Charsets.US_ASCII).drop(1).map {
            val w=it.split(',');
            Subject(w[0].toInt(),w[1],w[2].toInt(),w[3].toInt(),w[4].toInt(),w[5],w[6].toInt())
        }.sortedBy {
            it.id
        };
        val s=Settings();
        for(line in File("input/params.txt").readLines(Charsets.US_ASCII)) {
            val w=line.split(' ');
            when(w[0]) {
                "GROUPS"->s.groups=w.drop(1);
                "REPORT_TIMES"->s.report=w.drop(1).map(String::toInt).toIntArray();
                "TAU"->s.tau=w[1].toInt();
                "LIFE_TABLE"-> {
                    s.lifeWidth=w[1].toInt();
                    s.lifeCount=w[2].toInt()
                };
                "STRATA"->s.strata=w[1];
                "SUBGROUPS"->s.subgroups=w.drop(1);
                "LANDMARK"->s.landmark=w[1].toInt();
                "COX"->s.covariates=w.drop(1);
                "RESIDUALS"->s.residuals=w[1].toInt();
                "PLOT"-> {
                    s.width=w[1].toInt();
                    s.height=w[2].toInt();
                    s.horizon=w[3].toInt();
                    s.divisions=w[4].toInt()
                }
            }
        };
        return Data(subjects,s)
    }
}
