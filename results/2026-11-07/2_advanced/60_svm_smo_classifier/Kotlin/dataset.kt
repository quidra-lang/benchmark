import java.io.File

object Dataset {
    data class Example(val id: String,val point: Kernels.Point,val label: Int)
    class Settings {
        var coefficients=DoubleArray(0);
        var plotX=DoubleArray(0);
        var plotY=DoubleArray(0);
        var learning=IntArray(0)
        var tolerance=0.0;
        var eps=0.0;
        var multiC=0.0;
        var lambda=0.0;
        var maximum=0;
        var folds=0;
        var newton=0;
        var pegasos=0;
        var seed=0;
        var width=0;
        var height=0;
        var multiKernel=""
        val kernels=mutableListOf<Kernels.Kernel>()
    }
    data class Data(val train: List<Example>,val test: List<Example>,val multiTrain: List<Example>,val multiTest: List<Example>,val settings: Settings)
    fun lines(name: String)=File("input",name).readLines()
    fun reals(w: List<String>,first: Int)=w.drop(first).map {
        it.toDouble()
    }.toDoubleArray()
    fun example(w: List<String>)=Example(w[0],Kernels.Point(w[1].toDouble(),w[2].toDouble()),w[3].toInt())
    fun binary(name: String)=lines(name).drop(1).map {
        example(it.split(','))
    }
    fun read(): Data {
        val train=binary("train.csv");
        val test=binary("test.csv");
        val multiTrain=mutableListOf<Example>();
        val multiTest=mutableListOf<Example>()
        for(line in lines("multiclass.csv").drop(1)) {
            val w=line.split(',');
            (if(w[4]=="train")multiTrain else multiTest).add(example(w))
        }
        val s=Settings()
        for(line in lines("params.txt")) {
            val w=line.split(' ');
            when(w[0]) {
                "C_GRID"->s.coefficients=reals(w,1)
                "KERNEL"-> {
                    val kind=w[2];
                    val degree=if(kind=="poly")w[3].toInt() else 0;
                    val gamma=if(kind=="poly")w[4].toDouble() else if(kind=="rbf")w[3].toDouble() else 0.0;
                    val offset=if(kind=="poly")w[5].toDouble() else 0.0;
                    s.kernels.add(Kernels.Kernel(w[1],kind,degree,gamma,offset))
                }
                "TOLERANCE"->s.tolerance=w[1].toDouble()
                "EPS"->s.eps=w[1].toDouble()
                "MAX_PASSES"->s.maximum=w[1].toInt()
                "FOLDS"->s.folds=w[1].toInt()
                "LEARNING_CURVE"->s.learning=w.drop(1).map {
                    it.toInt()
                }.toIntArray()
                "NEWTON_ITERATIONS"->s.newton=w[1].toInt()
                "MULTICLASS"-> {
                    s.multiKernel=w[1];
                    s.multiC=w[2].toDouble()
                }
                "PEGASOS"-> {
                    s.lambda=w[1].toDouble();
                    s.pegasos=w[2].toInt();
                    s.seed=w[3].toInt()
                }
                "PLOT_X"->s.plotX=reals(w,1)
                "PLOT_Y"->s.plotY=reals(w,1)
                "PLOT_SIZE"-> {
                    s.width=w[1].toInt();
                    s.height=w[2].toInt()
                }
            }
        }
        return Data(train,test,multiTrain,multiTest,s)
    }
    fun points(examples: List<Example>)=examples.map {
        it.point
    }
    fun labels(examples: List<Example>)=examples.map {
        it.label
    }.toIntArray()
}
