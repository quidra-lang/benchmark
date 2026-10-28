import java.io.File

object Dataset {
    class Row(val id: Int,val values: DoubleArray,val label: String) {
        var y=0
    }
    data class Subset(val name: String,val features: IntArray)
    class Settings {
        var prior="";
        var epsilon=0.0;
        var gamma=0.0;
        var theta=0.0;
        var smoothing=doubleArrayOf();
        var gammas=doubleArrayOf();
        var edges=doubleArrayOf();
        var reject=doubleArrayOf();
        var folds=0;
        var resamples=0;
        var seed=0;
        var width=0;
        var height=0;
        var plotWidth=0;
        var plotHeight=0;
        var curve=intArrayOf();
        val subsets=mutableListOf<Subset>();
        val pairs=mutableListOf<IntArray>()
    }
    data class Data(val features: List<String>,val classes: List<String>,val train: List<Row>,
        val test: List<Row>,val costs: Array<DoubleArray>,val settings: Settings)
    private fun lines(name: String)=File("input/$name").readLines(Charsets.US_ASCII)
    private fun rows(lines: List<String>)=lines.drop(1).map {
        val w=it.split(',');
        Row(w[0].toInt(),w.subList(1,w.lastIndex).map(String::toDouble).toDoubleArray(),w.last())
    }
    fun read(): Data {
        val training=lines("train.csv");
        val header=training[0].split(',');
        val features=header.subList(1,header.lastIndex);
        val train=rows(training);
        val test=rows(lines("test.csv"));
        val classes=train.map {
            it.label
        }.toSortedSet().toList();
        for(row in train)row.y=classes.indexOf(row.label);
        for(row in test)row.y=classes.indexOf(row.label);
        val costs=Linalg.zeros(classes.size);
        val costLines=lines("costs.csv");
        val columns=costLines[0].split(',');
        for(line in costLines.drop(1)) {
            val w=line.split(',');
            val actual=classes.indexOf(w[0]);
            for(j in 1 until w.size)costs[actual][classes.indexOf(columns[j])]=w[j].toDouble()
        };
        val s=Settings();
        for(line in lines("params.txt")) {
            val w=line.split(' ');
            when(w[0]) {
                "PRIOR"->s.prior=w[1];
                "VAR_SMOOTHING"->s.epsilon=w[1].toDouble();
                "SMOOTHING_GRID"->s.smoothing=w.drop(1).map(String::toDouble).toDoubleArray();
                "QDA_GAMMA"->s.gamma=w[1].toDouble();
                "GAMMA_GRID"->s.gammas=w.drop(1).map(String::toDouble).toDoubleArray();
                "CV_FOLDS"->s.folds=w[1].toInt();
                "CALIBRATION_EDGES"->s.edges=w.drop(1).map(String::toDouble).toDoubleArray();
                "REJECT_THRESHOLDS"->s.reject=w.drop(1).map(String::toDouble).toDoubleArray();
                "CURVE"->s.curve=w.drop(1).map(String::toInt).toIntArray();
                "OUTLIER_THRESHOLD"->s.theta=w[1].toDouble();
                "BOOTSTRAP"-> {
                    s.resamples=w[1].toInt();
                    s.seed=w[2].toInt()
                };
                "MAP_SIZE"-> {
                    s.width=w[1].toInt();
                    s.height=w[2].toInt()
                };
                "PLOT_SIZE"-> {
                    s.plotWidth=w[1].toInt();
                    s.plotHeight=w[2].toInt()
                };
                "SUBSET"->s.subsets+=Subset(w[1],w.drop(2).map {
                    features.indexOf(it)
                }.toIntArray());
                "PAIR"->s.pairs+=w.drop(1).map {
                    features.indexOf(it)
                }.toIntArray()
            }
        };
        return Data(features,classes,train,test,costs,s)
    }
}
