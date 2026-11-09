import kotlin.math.*

object Main {
    data class Sequence(val name: String,val role: String,val observations: IntArray,val truth: IntArray=IntArray(0))
    data class BwRecord(val loglik: Double,val heldout: Double,val maximum: Double,val violation: Boolean)
    data class VtRecord(val logprob: Double,val loglik: Double,val changed: Int)
    data class Composition(val rich: Double,val motif: Double,val island: Boolean)
    class Cv(val candidate: String,folds: Int,k: Int) {
        var correct=0;
        var positions=0;
        val foldCorrect=IntArray(folds);
        val foldPositions=IntArray(folds);
        val foldRecords=IntArray(folds);
        val matrix=Array(k) {
            IntArray(k)
        }
    }
    lateinit var initial: ModelIo.Model;
    lateinit var models: Array<ModelIo.Model>;
    lateinit var params: Map<String,List<String>>;
    val sequences=mutableListOf<Sequence>();
    val train=mutableListOf<Sequence>();
    val test=mutableListOf<Sequence>();
    val rejections=mutableListOf<String>();
    var sequenceRejected=0;
    var labeledRejected=0;
    var segmentState=0;
    var bestHeldout=0;
    var vtIterations=0;
    var vtConverged=false;
    val bwTrace=mutableListOf<BwRecord>();
    val vtTrace=mutableListOf<VtRecord>();
    val candidates=mutableListOf<Cv>();
    lateinit var selected: Cv;
    lateinit var unlabeledDecoded: Array<Array<Inference.Decoding>>;
    lateinit var testDecoded: Array<Array<Inference.Decoding>>;
    lateinit var trainDecoded: Array<Array<Inference.Decoding>>;
    val testCorrect=Array(4) {
        IntArray(2)
    };
    val decodingLines=mutableListOf<String>();
    val segmentLines=mutableListOf<String>()
    fun integer(key: String)=params.getValue(key)[0].toInt()
    fun number(key: String)=params.getValue(key)[0].toDouble()
    fun word(key: String)=params.getValue(key)[0]
    fun f(value: Double)=ModelIo.f(value)
    fun observationError(observed: String): String? {
        for(t in observed.indices) {
            val c=observed[t];
            if(c !in initial.symbols&&c!=initial.missing)return "invalid symbol $c at position ${t+1}"
        };
        return null
    }
    fun lengthError(observed: String): String? {
        if(observed.length<integer("min_sequence_length"))return "too short ${observed.length}";
        val missing=observed.count {
            it==initial.missing
        };
        return if(100*missing>integer("max_missing_percent")*observed.length)"too many missing $missing" else null
    }
    fun observations(text: String)=IntArray(text.length) {
        initial.symbols.indexOf(text[it])
    }
    fun validate(input: ModelIo.Data) {
        val seen=mutableSetOf<String>();
        for(i in input.sequences.indices) {
            val words=input.sequences[i].split(' ');
            val name=words[0];
            val observed=words[1].uppercase();
            var error=if(!seen.add(name))"duplicate name" else observationError(observed);
            if(error==null)error=lengthError(observed);
            if(error!=null) {
                sequenceRejected++;
                rejections+="REJECT sequences.txt line ${i+1} $name $error"
            } else sequences+=Sequence(name,"",observations(observed))
        };
        seen.clear();
        for(i in input.labeled.indices step 2) {
            val words=input.labeled[i].split(' ');
            val name=words[0];
            val role=words[1];
            val observed=words[2].uppercase();
            val labels=input.labeled[i+1];
            var error=if(!seen.add(name))"duplicate name" else observationError(observed);
            if(error==null)for(t in labels.indices)if(labels[t] !in initial.states) {
                error="invalid label ${labels[t]} at position ${t+1}";
                break
            };
            if(error==null&&observed.length!=labels.length)error="length mismatch ${observed.length} ${labels.length}";
            if(error==null)error=lengthError(observed);
            if(error!=null) {
                labeledRejected++;
                rejections+="REJECT labeled.txt line ${i+1} $name $error"
            } else {
                val truth=IntArray(labels.length) {
                    initial.states.indexOf(labels[it])
                };
                val record=Sequence(name,role,observations(observed),truth);
                if(role=="TRAIN")train+=record else test+=record
            }
        }
    }
    fun observed(records: List<Sequence>)=records.map {
        it.observations
    }
    fun pairs(records: List<Sequence>)=records.map {
        Training.Pair(it.observations,it.truth)
    }
    fun maximumChange(a: ModelIo.Model,b: ModelIo.Model): Double {
        var maximum=0.0;
        for(i in a.states.indices) {
            maximum=maxOf(maximum,abs(a.pi[i]-b.pi[i]));
            for(j in a.states.indices)maximum=maxOf(maximum,abs(a.a[i][j]-b.a[i][j]));
            for(c in a.symbols.indices)maximum=maxOf(maximum,abs(a.b[i][c]-b.b[i][c]))
        };
        return maximum
    }
    fun baumWelch() {
        val data=observed(sequences);
        val heldout=observed(train)+observed(test);
        var model=initial;
        bwTrace+=BwRecord(Training.loglik(model,data),Training.loglik(model,heldout),0.0,false);
        bestHeldout=0;
        for(t in 1..integer("iterations")) {
            val next=Training.baumWelch(model,data,number("pseudocount"));
            val loglik=Training.loglik(next,data);
            val held=Training.loglik(next,heldout);
            val previous=bwTrace.last().loglik;
            bwTrace+=BwRecord(loglik,held,maximumChange(model,next),loglik<previous-0.000001*abs(previous));
            if(held>bwTrace[bestHeldout].heldout)bestHeldout=t;
            model=next
        };
        models[1]=model
    }
    fun viterbiPaths(model: ModelIo.Model)=sequences.map {
        Inference.viterbi(model,it.observations).states
    }
    fun viterbiRecord(model: ModelIo.Model,changed: Int): VtRecord {
        var logprob=0.0;
        for(record in sequences)logprob+=Inference.viterbi(model,record.observations).logprob;
        return VtRecord(logprob,Training.loglik(model,observed(sequences)),changed)
    }
    fun viterbiTraining() {
        var model=initial;
        var paths=viterbiPaths(model);
        vtTrace+=viterbiRecord(model,-1);
        for(t in 1..integer("iterations")) {
            val pairs=sequences.indices.map {
                Training.Pair(sequences[it].observations,paths[it])
            };
            model=Training.count(initial,pairs,number("pseudocount"),"VITERBI_TRAINING");
            val next=viterbiPaths(model);
            var changes=0;
            for(i in paths.indices)changes+=paths[i].size-Evaluation.correct(paths[i],next[i]);
            vtTrace+=viterbiRecord(model,changes);
            paths=next;
            vtIterations=t;
            if(changes==0) {
                vtConverged=true;
                break
            }
        };
        models[2]=model
    }
    fun supervised() {
        val folds=integer("folds");
        val k=initial.states.size;
        var best=-1;
        for(candidate in params.getValue("smoothing")) {
            val cv=Cv(candidate,folds,k);
            for(fold in 0 until folds) {
                val training=mutableListOf<Sequence>();
                val validation=mutableListOf<Sequence>();
                for(i in train.indices)if(i%folds==fold)validation+=train[i] else training+=train[i];
                val model=Training.count(initial,pairs(training),candidate.toDouble(),"SUPERVISED");
                for(record in validation) {
                    val path=Inference.viterbi(model,record.observations).states;
                    val correct=Evaluation.correct(record.truth,path);
                    cv.foldRecords[fold]++;
                    cv.foldPositions[fold]+=path.size;
                    cv.foldCorrect[fold]+=correct;
                    cv.positions+=path.size;
                    cv.correct+=correct;
                    Evaluation.accumulate(cv.matrix,record.truth,path)
                }
            };
            candidates+=cv;
            if(cv.correct>best) {
                best=cv.correct;
                selected=cv
            }
        };
        models[3]=Training.count(initial,pairs(train),selected.candidate.toDouble(),"SUPERVISED")
    }
    fun decode(records: List<Sequence>)=Array(4) {
        m->Array(records.size) {
            i->Inference.decode(models[m],records[i].observations)
        }
    }
    fun segments(path: IntArray): List<Evaluation.Interval> {
        val result=mutableListOf<Evaluation.Interval>();
        for(run in Evaluation.runs(path))if(run.state==segmentState) {
            if(result.isNotEmpty()&&run.start-result.last().end-1<=integer("merge_gap")) {
                val last=result.removeLast();
                result+=Evaluation.Interval(last.start,run.end)
            } else result+=Evaluation.Interval(run.start,run.end)
        };
        result.removeAll {
            it.length()<integer("min_segment_length")
        };
        return result
    }
    fun truthRegions(path: IntArray)=Evaluation.runs(path).filter {
        it.state==segmentState
    }.map {
        Evaluation.Interval(it.start,it.end)
    }
    fun composition(observations: IntArray,segment: Evaluation.Interval): Composition {
        var n=0;
        var r=0;
        var q=0;
        var k1=0;
        var k2=0;
        val first=initial.symbols.indexOf(params.getValue("motif")[0][0]);
        val second=initial.symbols.indexOf(params.getValue("motif")[1][0]);
        val rich=params.getValue("rich_symbols").map {
            initial.symbols.indexOf(it[0])
        }.toSet();
        for(t in segment.start-1 until segment.end) {
            val value=observations[t];
            if(value<0)continue;
            n++;
            if(value in rich)r++;
            if(value==first)k1++;
            if(value==second)k2++;
            if(t+1<segment.end&&value==first&&observations[t+1]==second)q++
        };
        val island=k1*k2>0&&100*r>=integer("min_rich_percent")*n&&100*q*n>=integer("min_motif_percent")*k1*k2;
        return Composition(if(n==0)Double.NaN else r.toDouble()/n,if(k1*k2==0)Double.NaN else (q*n).toDouble()/(k1*k2),island)
    }
    fun path(decoding: Inference.Decoding,decoder: Int)=if(decoder==0)decoding.viterbi.states else decoding.posterior
    fun states(path: IntArray)=path.joinToString("") {
        initial.states[it].toString()
    }
    fun symbols(observations: IntArray)=observations.joinToString("") {
        initial.symbols[it].toString()
    }
    fun positions(records: List<Sequence>)=records.sumOf {
        it.observations.size
    }
    fun missing(records: List<Sequence>)=records.sumOf {
        it.observations.count {
            symbol->symbol<0
        }
    }
    fun block(out: MutableList<String>,heading: String) {
        if(out.isNotEmpty())out+="";
        out+=heading
    }

    fun evaluationReport(): List<String> {
        val out=mutableListOf<String>();
        val k=initial.states.size;
        for(m in 0..3)for(decoder in 0..1) {
            block(out,"EVALUATION ${models[m].name} ${if(decoder==0)"VITERBI" else "POSTERIOR"}");
            val matrix=Array(k) {
                IntArray(k)
            };
            val regions=IntArray(4);
            val boundaries=IntArray(4);
            val bins=IntArray(10);
            val binCorrect=IntArray(10);
            val recordCorrect=IntArray(test.size);
            for(r in test.indices) {
                val record=test[r];
                val decoding=testDecoded[m][r];
                val prediction=path(decoding,decoder);
                recordCorrect[r]=Evaluation.correct(record.truth,prediction);
                testCorrect[m][decoder]+=recordCorrect[r];
                Evaluation.accumulate(matrix,record.truth,prediction);
                val rc=Evaluation.regions(segments(prediction),truthRegions(record.truth));
                val bc=Evaluation.boundaryMatches(prediction,record.truth,integer("boundary_tolerance"));
                for(j in 0..3) {
                    regions[j]+=rc[j];
                    boundaries[j]+=bc[j]
                };
                if(decoder==1)for(t in prediction.indices) {
                    val bin=minOf(9,floor(10*decoding.confidence[t]).toInt());
                    bins[bin]++;
                    if(prediction[t]==record.truth[t])binCorrect[bin]++
                }
            };
            out.addAll(Evaluation.matrix(initial.states,matrix));
            out.addAll(Evaluation.metrics(initial.states,matrix));
            out+="REGIONS ${initial.states[segmentState]} predicted ${regions[0]} true ${regions[1]} precision ${Evaluation.fraction(regions[2],regions[0])} recall ${Evaluation.fraction(regions[3],regions[1])}";
            out+="BOUNDARIES predicted ${boundaries[0]} true ${boundaries[1]} precision ${Evaluation.fraction(boundaries[2],boundaries[0])} recall ${Evaluation.fraction(boundaries[3],boundaries[1])}";
            if(decoder==1)for(bin in 0..9)if(bins[bin]>0)out+="CALIBRATION 0.$bin-${if(bin==9)"1.0" else "0.${bin+1}"} positions ${bins[bin]} correct ${binCorrect[bin]} accuracy ${Evaluation.fraction(binCorrect[bin],bins[bin])}";
            for(r in test.indices)out+="RECORD ${test[r].name} length ${test[r].observations.size} correct ${recordCorrect[r]}"
        };
        val folds=integer("folds");
        block(out,"CROSS_VALIDATION folds $folds");
        for(candidate in candidates)out+="SMOOTHING ${candidate.candidate} positions ${candidate.positions} correct ${candidate.correct} accuracy ${Evaluation.fraction(candidate.correct,candidate.positions)}";
        out+="SELECTED ${selected.candidate}";
        for(fold in 0 until folds)out+="FOLD ${fold+1} records ${selected.foldRecords[fold]} positions ${selected.foldPositions[fold]} correct ${selected.foldCorrect[fold]} accuracy ${Evaluation.fraction(selected.foldCorrect[fold],selected.foldPositions[fold])}";
        out.addAll(Evaluation.matrix(initial.states,selected.matrix));
        out.addAll(Evaluation.metrics(initial.states,selected.matrix));
        block(out,"LEARNING_CURVE");
        for(count in 1..train.size) {
            val model=Training.count(initial,pairs(train.take(count)),selected.candidate.toDouble(),"SUPERVISED");
            var correct=0;
            for(record in test)correct+=Evaluation.correct(record.truth,Inference.viterbi(model,record.observations).states);
            out+="RECORDS $count correct $correct accuracy ${Evaluation.fraction(correct,positions(test))}"
        };
        return out
    }
    fun annotate() {
        segmentLines+="sequence,decoder,start,end,length,mean_posterior,support,rich_fraction,motif_ratio,island";
        val random=Sampler.Random(integer("posterior_seed").toLong());
        val posteriorCount=integer("posterior_samples");
        val model=models[1];
        for(r in sequences.indices) {
            val record=sequences[r];
            val decoding=unlabeledDecoded[1][r];
            val paths=mutableListOf<IntArray>();
            var segmentTotal=0;
            for(sample in 0 until posteriorCount) {
                val path=Sampler.posterior(model,decoding.fb.forward,random);
                paths+=path;
                segmentTotal+=segments(path).size
            };
            val differences=record.observations.size-Evaluation.correct(decoding.viterbi.states,decoding.posterior);
            var uncertain=0;
            val confident=states(decoding.posterior).toCharArray();
            val imputed=CharArray(record.observations.size);
            for(t in record.observations.indices) {
                if(decoding.confidence[t]<number("confidence")) {
                    uncertain++;
                    confident[t]='.'
                };
                if(record.observations[t]>=0)imputed[t]=initial.symbols[record.observations[t]] else {
                    val probabilities=DoubleArray(initial.symbols.size);
                    for(c in probabilities.indices)for(i in initial.states.indices)probabilities[c]+=decoding.fb.gamma[t][i]*model.b[i][c];
                    imputed[t]=initial.symbols[Inference.maximum(probabilities)].lowercaseChar()
                }
            };
            decodingLines+="SEQUENCE ${record.name} length ${record.observations.size} loglik ${f(decoding.fb.loglik)} viterbi ${f(decoding.viterbi.logprob)} differences $differences uncertain $uncertain expected_segments ${f(segmentTotal.toDouble()/posteriorCount)}";
            decodingLines+="VITERBI ${states(decoding.viterbi.states)}";
            decodingLines+="POSTERIOR ${states(decoding.posterior)}";
            decodingLines+="CONFIDENT ${confident.concatToString()}";
            decodingLines+="IMPUTED ${imputed.concatToString()}";
            for(decoder in 0..1)for(segment in segments(path(decoding,decoder))) {
                var sum=0.0;
                for(t in segment.start-1 until segment.end)sum+=decoding.fb.gamma[t][segmentState];
                var support=0;
                for(sample in paths) {
                    var count=0;
                    for(t in segment.start-1 until segment.end)if(sample[t]==segmentState)count++;
                    if(2*count>segment.length())support++
                };
                val composition=composition(record.observations,segment);
                segmentLines+="${record.name},${if(decoder==0)"viterbi" else "posterior"},${segment.start},${segment.end},${segment.length()},${f(sum/segment.length())},$support,${f(composition.rich)},${f(composition.motif)},${if(composition.island)"yes" else "no"}"
            }
        }
    }
    fun samples(): List<String> {
        val out=mutableListOf<String>();
        val random=Sampler.Random(integer("sample_seed").toLong());
        var viterbiCorrect=0;
        var posteriorCorrect=0;
        var total=0;
        for(sampleNumber in 1..integer("sample_count")) {
            val sample=Sampler.synthetic(models[1],integer("sample_length"),random);
            val decoding=Inference.decode(models[1],sample.observations);
            val vc=Evaluation.correct(sample.states,decoding.viterbi.states);
            val pc=Evaluation.correct(sample.states,decoding.posterior);
            viterbiCorrect+=vc;
            posteriorCorrect+=pc;
            total+=sample.states.size;
            out+="SAMPLE $sampleNumber loglik ${f(decoding.fb.loglik)} viterbi ${f(decoding.viterbi.logprob)} viterbi_correct $vc posterior_correct $pc";
            out+="STATES ${states(sample.states)}";
            out+="SYMBOLS ${symbols(sample.observations)}";
            out+="VITERBI ${states(decoding.viterbi.states)}";
            out+="POSTERIOR ${states(decoding.posterior)}"
        };
        out+="TOTAL positions $total viterbi_accuracy ${Evaluation.fraction(viterbiCorrect,total)} posterior_accuracy ${Evaluation.fraction(posteriorCorrect,total)}";
        return out
    }
    fun baumTraceReport(): List<String> {
        val out=mutableListOf("iteration,loglik,heldout,change,max_change,status");
        for(t in bwTrace.indices) {
            val row=bwTrace[t];
            val tail=if(t==0)",," else "${f(row.loglik-bwTrace[t-1].loglik)},${ModelIo.real(row.maximum,6)},${if(row.violation)"violation" else "ok"}";
            out+="$t,${f(row.loglik)},${f(row.heldout)},$tail"
        };
        return out
    }
    fun viterbiTraceReport(): List<String> {
        val out=mutableListOf("iteration,logprob,loglik,changed");
        for(t in vtTrace.indices) {
            val row=vtTrace[t];
            out+="$t,${f(row.logprob)},${f(row.loglik)},${if(t==0)"" else row.changed.toString()}"
        };
        return out
    }

    data class Statistics(val counts: IntArray,val runs: IntArray,val positions: Int)
    fun statistics(paths: List<IntArray>): Statistics {
        val k=initial.states.size;
        val counts=IntArray(k);
        val runs=IntArray(k);
        var positions=0;
        for(path in paths) {
            positions+=path.size;
            for(state in path)counts[state]++;
            for(run in Evaluation.runs(path))runs[run.state]++
        };
        return Statistics(counts,runs,positions)
    }
    fun truthStatistics(out: MutableList<String>,role: String,records: List<Sequence>) {
        val stats=statistics(records.map {
            it.truth
        });
        for(i in initial.states.indices)out+="TRUTH $role ${initial.states[i]} occupancy ${f(stats.counts[i].toDouble()/stats.positions)} mean_run ${f(if(stats.runs[i]==0)Double.NaN else stats.counts[i].toDouble()/stats.runs[i])}"
    }
    fun stationary(model: ModelIo.Model): DoubleArray {
        val k=model.states.size;
        val system=Array(k) {
            DoubleArray(k+1)
        };
        for(row in 0 until k-1)for(column in 0 until k)system[row][column]=model.a[column][row]-if(row==column)1.0 else 0.0;
        for(column in 0 until k)system[k-1][column]=1.0;
        system[k-1][k]=1.0;
        for(column in 0 until k) {
            var pivot=column;
            for(row in column+1 until k)if(abs(system[row][column])>abs(system[pivot][column]))pivot=row;
            val swap=system[column];
            system[column]=system[pivot];
            system[pivot]=swap;
            val scale=system[column][column];
            for(c in column..k)system[column][c]/=scale;
            for(row in 0 until k)if(row!=column) {
                val value=system[row][column];
                for(c in column..k)system[row][c]-=value*system[column][c]
            }
        };
        return DoubleArray(k) {
            system[it][k]
        }
    }
    data class Alignment(val mapping: IntArray,val correct: Int)
    fun permutations(matrix: Array<IntArray>,depth: Int,current: IntArray,used: BooleanArray,best: IntArray,greatest: IntArray) {
        val k=current.size;
        if(depth==k) {
            var count=0;
            for(j in 0 until k)count+=matrix[current[j]][j];
            if(count>greatest[0]) {
                greatest[0]=count;
                current.copyInto(best)
            };
            return
        };
        for(i in 0 until k)if(!used[i]) {
            used[i]=true;
            current[depth]=i;
            permutations(matrix,depth+1,current,used,best,greatest);
            used[i]=false
        }
    }
    fun alignment(m: Int): Alignment {
        val k=initial.states.size;
        val matrix=Array(k) {
            IntArray(k)
        };
        for(r in train.indices)Evaluation.accumulate(matrix,train[r].truth,trainDecoded[m][r].viterbi.states);
        val best=IntArray(k);
        val greatest=intArrayOf(-1);
        permutations(matrix,0,IntArray(k),BooleanArray(k),best,greatest);
        return Alignment(best,greatest[0])
    }
    fun report(): List<String> {
        val out=mutableListOf("INPUT");
        val total=positions(sequences);
        val missingCount=missing(sequences);
        val observedCount=total-missingCount;
        out+="SEQUENCES accepted ${sequences.size} rejected $sequenceRejected positions $total missing $missingCount";
        out+="LABELED train ${train.size} test ${test.size} rejected $labeledRejected positions ${positions(train)+positions(test)} missing ${missing(train)+missing(test)}";
        out.addAll(rejections);
        val symbolCounts=IntArray(initial.symbols.size);
        for(record in sequences)for(symbol in record.observations)if(symbol>=0)symbolCounts[symbol]++;
        var compositionText="COMPOSITION";
        for(c in symbolCounts.indices)compositionText+=" ${initial.symbols[c]} ${f(symbolCounts[c].toDouble()/observedCount)}";
        out+=compositionText;
        truthStatistics(out,"TRAIN",train);
        truthStatistics(out,"TEST",test);
        val violations=bwTrace.count {
            it.violation
        };
        block(out,"TRAINING BAUM_WELCH iterations ${integer("iterations")} initial_loglik ${f(bwTrace.first().loglik)} final_loglik ${f(bwTrace.last().loglik)} violations $violations best_heldout_iteration $bestHeldout");
        out+="TRAINING VITERBI_TRAINING iterations $vtIterations converged ${if(vtConverged)"yes" else "no"}";
        out+="TRAINING SUPERVISED smoothing ${selected.candidate}";
        val preference=IntArray(4);
        for(r in sequences.indices) {
            var best=0;
            for(m in 1..3)if(unlabeledDecoded[m][r].fb.loglik>unlabeledDecoded[best][r].fb.loglik)best=m;
            preference[best]++
        };
        var line="PREFERENCE";
        for(m in 0..3)line+=" ${models[m].name} ${preference[m]}";
        out+=line;
        for(a in 0..3)for(b in a+1..3) {
            var correct=0;
            for(r in sequences.indices)correct+=Evaluation.correct(unlabeledDecoded[a][r].viterbi.states,unlabeledDecoded[b][r].viterbi.states);
            out+="AGREEMENT ${models[a].name} ${models[b].name} ${Evaluation.fraction(correct,total)}"
        };
        for(decoder in 0..1) {
            var best=0;
            for(m in 1..3)if(testCorrect[m][decoder]>testCorrect[best][decoder])best=m;
            out+="BEST ${if(decoder==0)"VITERBI" else "POSTERIOR"} ${models[best].name} accuracy ${Evaluation.fraction(testCorrect[best][decoder],positions(test))}"
        };
        for(m in 0..3) {
            val model=models[m];
            block(out,"MODEL ${model.name}");
            var loglik=0.0;
            var testLoglik=0.0;
            val paths=mutableListOf<IntArray>();
            var count=0;
            var length=0;
            var islands=0;
            for(r in sequences.indices) {
                val decoding=unlabeledDecoded[m][r];
                loglik+=decoding.fb.loglik;
                val path=decoding.viterbi.states;
                paths+=path;
                for(segment in segments(path)) {
                    count++;
                    length+=segment.length();
                    if(composition(sequences[r].observations,segment).island)islands++
                }
            };
            for(r in test.indices)testLoglik+=testDecoded[m][r].fb.loglik;
            out+="LOGLIK unlabeled ${f(loglik)} per_symbol ${f(loglik/observedCount)} test ${f(testLoglik)}";
            out+="SEGMENTS count $count mean_length ${f(if(count==0)Double.NaN else length.toDouble()/count)} islands $islands";
            val alignment=alignment(m);
            line="ALIGNMENT";
            for(i in initial.states.indices)line+=" ${initial.states[i]}=${initial.states[alignment.mapping[i]]}";
            out+=line+" agreement ${Evaluation.fraction(alignment.correct,positions(train))}";
            val stats=statistics(paths);
            val stationaryDistribution=stationary(model);
            for(i in initial.states.indices)out+="STATE ${initial.states[i]} stationary ${f(stationaryDistribution[i])} duration ${f(1/(1-model.a[i][i]))} occupancy ${f(stats.counts[i].toDouble()/stats.positions)} mean_run ${f(if(stats.runs[i]==0)Double.NaN else stats.counts[i].toDouble()/stats.runs[i])}"
        };
        return out
    }
    @JvmStatic fun main(args: Array<String>) {
        val data=ModelIo.read();
        initial=data.model;
        params=data.params;
        models=Array(4) {
            initial
        };
        segmentState=initial.states.indexOf(word("segment_state")[0]);
        validate(data);
        baumWelch();
        viterbiTraining();
        supervised();
        unlabeledDecoded=decode(sequences);
        testDecoded=decode(test);
        trainDecoded=decode(train);
        val evaluation=evaluationReport();
        annotate();
        val trained=mutableListOf<String>();
        for(m in 1..3) {
            if(trained.isNotEmpty())trained+="";
            trained.addAll(ModelIo.format(models[m]))
        };
        ModelIo.write("trained_model.txt",trained);
        ModelIo.write("loglik_trace.csv",baumTraceReport());
        ModelIo.write("viterbi_trace.csv",viterbiTraceReport());
        ModelIo.write("decodings.txt",decodingLines);
        ModelIo.write("segments.csv",segmentLines);
        ModelIo.write("samples.txt",samples());
        ModelIo.write("evaluation.txt",evaluation);
        ModelIo.write("report.txt",report())
    }
}
