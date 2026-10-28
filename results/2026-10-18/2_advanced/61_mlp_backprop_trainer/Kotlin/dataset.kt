import java.io.File

object Dataset {
    data class Image(val id: String,val label: Int,val pixels: String,val values: DoubleArray)
    data class Run(val name: String,val network: String,val optimizer: String,val eta: Double,
        val lambda: Double,val momentum: Double,val beta1: Double,val beta2: Double,val epsilon: Double)
    class Settings {
        var seed=0;
        var batch=0;
        var epochs=0;
        var patience=0;
        var decayStep=0;
        var stride=0;
        var bins=0;
        var gamma=0.0;
        var prune=IntArray(0);
        var noise=IntArray(0);
        val runs=mutableListOf<Run>()
    }
    data class Data(val width: Int,val height: Int,val train: List<Image>,val test: List<Image>,val networks: List<Network>,val settings: Settings)
    class Generator(seed: Int) {
        var state=seed.toLong()
        fun draw(): Int {
            state=48271*state%2147483647;
            return state.toInt()
        }
        fun shuffle(order: IntArray) {
            for(i in order.lastIndex downTo 1) {
                val j=draw()%(i+1);
                val temp=order[i];
                order[i]=order[j];
                order[j]=temp
            }
        }
    }
    fun lines(name: String)=File("input",name).readLines()
    fun image(id: String,label: Int,pixels: String)=Image(id,label,pixels,DoubleArray(pixels.length) {
        if(pixels[it]=='1')1.0 else 0.0
    })
    fun images(name: String)=lines(name).drop(1).map {
        val w=it.split(',');
        image(w[0],w[1].toInt(),w[2])
    }
    fun integers(words: List<String>)=words.drop(1).map {
        it.toInt()
    }.toIntArray()
    fun read(): Data {
        val definitions=lines("network.txt");
        val header=definitions[0].split(' ');
        val width=header[1].toInt();
        val height=header[2].toInt();
        val networks=mutableListOf<Network>()
        var name: String?=null;
        val sizes=mutableListOf<Int>();
        val activations=mutableListOf<String>()
        for(i in 1..definitions.size) {
            val line=if(i==definitions.size)"" else definitions[i]
            if(line.isEmpty()) {
                val networkName=name;
                if(networkName!=null) {
                    networks.add(Network(networkName,width*height,sizes.toIntArray(),activations.toTypedArray()));
                    name=null;
                    sizes.clear();
                    activations.clear()
                };
                continue
            }
            val w=line.split(' ');
            if(w[0]=="NETWORK")name=w[1] else {
                sizes.add(w[1].toInt());
                activations.add(w[2])
            }
        }
        var current: Network?=null;
        var parameter=0
        for(line in lines("weights.txt")) {
            if(line.isEmpty())continue;
            val w=line.split(' ')
            if(w[0]=="NETWORK") {
                current=networks.first {
                    it.name==w[1]
                };
                parameter=0
            }
            else if(w[0]=="W"||w[0]=="B")for(j in 1 until w.size)current!!.initial[parameter++]=w[j].toDouble()
        }
        val s=Settings()
        for(line in lines("params.txt")) {
            val w=line.split(' ');
            when(w[0]) {
                "SEED"->s.seed=w[1].toInt()
                "BATCH_SIZE"->s.batch=w[1].toInt()
                "MAX_EPOCHS"->s.epochs=w[1].toInt()
                "PATIENCE"->s.patience=w[1].toInt()
                "LR_STEP"-> {
                    s.decayStep=w[1].toInt();
                    s.gamma=w[2].toDouble()
                }
                "GRADIENT_CHECK_STRIDE"->s.stride=w[1].toInt()
                "CALIBRATION_BINS"->s.bins=w[1].toInt()
                "PRUNE"->s.prune=integers(w)
                "NOISE"->s.noise=integers(w)
                "RUN"-> {
                    val opt=w[3];
                    s.runs.add(Run(w[1],w[2],opt,w[4].toDouble(),w[5].toDouble(),if(opt=="MOMENTUM")w[6].toDouble() else 0.0,
                        if(opt=="ADAM")w[6].toDouble() else 0.0,if(opt=="ADAM")w[7].toDouble() else 0.0,
                        if(opt=="ADAM")w[8].toDouble() else 0.0))
                }
            }
        }
        return Data(width,height,images("train.csv"),images("test.csv"),networks,s)
    }
}
