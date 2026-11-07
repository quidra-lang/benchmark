import kotlin.math.*

private lateinit var data: Dataset.Data
private lateinit var settings: Dataset.Settings
private lateinit var variants: List<String>
private lateinit var names: List<String>
private lateinit var train: List<Dataset.Row>
private lateinit var test: List<Dataset.Row>
private var n=0
private var m=0
private var d=0
private var maximum=0
private var selected=0
private lateinit var cvErrors: IntArray
private val folds=mutableListOf<Adaboost.Model>()
private val full=mutableListOf<Adaboost.Model>()
private val models=mutableListOf<Adaboost.Model>()
private val ovr=mutableListOf<Adaboost.Model>()
private val curves=mutableListOf<Curve>()
private lateinit var crossScores: DoubleArray
private lateinit var trainScores: Array<DoubleArray>
private lateinit var testScores: Array<DoubleArray>
private lateinit var samme: Adaboost.Model
private class Generator(seed: Int) {
    var state=seed.toLong();
    fun draw(): Int {
        state=48271*state%2147483647;
        return state.toInt()
    }
}
private fun real(value: Double)=Evaluation.real(value)
private fun ratio(a: Int,b: Int)=Evaluation.ratio(a,b)
private fun fraction(a: Int,b: Int)="$a/$b"
private fun reals(values: DoubleArray)=values.joinToString(" ") {
    real(it)
}
private fun integers(values: IntArray)=values.joinToString(" ")
private fun sum(values: DoubleArray): Double {
    var sum=0.0;
    for(value in values)sum+=value;
    return sum
}
private fun minimum(values: DoubleArray): Double {
    var min=values[0];
    for(value in values)min=minOf(min,value);
    return min
}
private fun maximum(values: DoubleArray): Int {
    var index=0;
    for(i in 1 until values.size)if(values[i]>values[index])index=i;
    return index
}
private fun earliest(values: IntArray): Int {
    var index=0;
    for(i in 1 until values.size)if(values[i]<values[index])index=i;
    return index
}
private fun sortedIndices(values: DoubleArray,descending: Boolean)=values.indices.sortedWith(Comparator {
    a,b->val comparison=if(descending)values[b].compareTo(values[a]) else values[a].compareTo(values[b]);
    if(comparison!=0)comparison else a.compareTo(b)
})
private fun weights(count: Int)=DoubleArray(count) {
    1.0/count
}
private fun score(model: Adaboost.Model,x: DoubleArray,limit: Int): Double {
    var score=0.0;
    for(t in 0 until minOf(limit,model.rounds.size))score+=model.rounds[t].stump.output(x);
    return score
}
private fun scores(model: Adaboost.Model,rows: List<Dataset.Row>,limit: Int)=DoubleArray(rows.size) {
    score(model,rows[it].x,limit)
}
private fun errors(rows: List<Dataset.Row>,scores: DoubleArray)=rows.indices.count {
    Evaluation.prediction(scores[it])!=rows[it].label
}
private fun loss(rows: List<Dataset.Row>,scores: DoubleArray,logit: Boolean): Double {
    var sum=0.0;
    for(i in rows.indices)sum+=if(logit)ln(1+exp(-2*rows[i].label*scores[i])) else exp(-rows[i].label*scores[i]);
    return sum/rows.size
}
private fun magnitude(model: Adaboost.Model,limit: Int): Double {
    var sum=0.0;
    for(t in 0 until minOf(limit,model.rounds.size))sum+=model.rounds[t].stump.magnitude();
    return sum
}
private fun margins(rows: List<Dataset.Row>,scores: DoubleArray,scale: Double)=DoubleArray(rows.size) {
    rows[it].label*scores[it]/scale
}
private fun section(output: MutableList<String>,part: List<String>) {
    if(output.isNotEmpty())output+="";
    output+=part
}
private fun prefix(model: Adaboost.Model,count: Int): Adaboost.Model {
    val result=Adaboost.Model();
    result.rounds+=model.rounds.take(count);
    result.stop=model.stop;
    result.cuts=model.cuts;
    return result
}
private class Curve(model: Adaboost.Model,training: List<Dataset.Row>,testing: List<Dataset.Row>,logit: Boolean) {
    val trainErrors=IntArray(model.rounds.size);
    val testErrors=IntArray(model.rounds.size);
    val trainLoss=DoubleArray(model.rounds.size);
    val testLoss=DoubleArray(model.rounds.size);
    val margin=DoubleArray(model.rounds.size)
    init {
        for(t in model.rounds.indices) {
            val a=scores(model,training,t+1);
            val b=scores(model,testing,t+1);
            trainErrors[t]=errors(training,a);
            testErrors[t]=errors(testing,b);
            trainLoss[t]=loss(training,a,logit);
            testLoss[t]=loss(testing,b,logit);
            margin[t]=minimum(margins(training,a,magnitude(model,t+1)))
        }
    }
}
private fun crossValidate() {
    val count=settings.integer("FOLDS");
    cvErrors=IntArray(maximum);
    for(fold in 0 until count) {
        val validation=(0 until n).count {
            it%count==fold
        };
        val w=DoubleArray(n) {
            if(it%count!=fold)1.0/(n-validation) else 0.0
        };
        val model=Adaboost.discrete(train,w,maximum,1.0);
        folds+=model;
        for(t in 1..maximum)for(i in 0 until n)if(i%count==fold&&Evaluation.prediction(score(model,train[i].x,t))!=train[i].label)cvErrors[t-1]++
    };
    selected=earliest(cvErrors)+1;
    crossScores=DoubleArray(n) {
        score(folds[it%count],train[it].x,selected)
    }
}
private fun trainModels() {
    trainScores=Array(variants.size) {
        doubleArrayOf()
    };
    testScores=Array(variants.size) {
        doubleArrayOf()
    };
    for(v in variants.indices) {
        val variant=variants[v];
        val training=Variants.train(variant,train,settings);
        val model=if(variant=="discrete")prefix(training,selected) else training;
        full+=training;
        models+=model;
        trainScores[v]=scores(model,train,maximum);
        testScores[v]=scores(model,test,maximum);
        curves+=Curve(training,train,test,variant=="logit")
    };
    val classes=settings.integer("CLASSES");
    val rounds=settings.integer("SAMME_ROUNDS");
    samme=Adaboost.samme(data.multiTrain.rows,classes,rounds);
    for(c in 1..classes) {
        val rows=data.multiTrain.rows.map {
            Dataset.Row(it.id,it.x,if(it.label==c)1 else -1)
        };
        ovr+=Adaboost.discrete(rows,weights(rows.size),rounds,1.0)
    }
}
private fun ensembleReport(): List<String> {
    val output=mutableListOf<String>();
    for(v in variants.indices) {
        val variant=variants[v];
        val model=full[v];
        var header="variant $variant rounds ${model.rounds.size} stop ${model.stop}";
        if(variant=="real")header+=" bins ${settings.integer("BINS")} smoothing ${real(settings.number("SMOOTHING"))} convergence ${Evaluation.format(settings.number("CONVERGENCE"),6)}";
        if(variant=="logit")header+=" clip ${real(settings.number("CLIP"))}";
        val part=mutableListOf(header);
        if(variant=="real")for(j in 0 until d)part+="cuts ${names[j]} ${reals(model.cuts[j])}";
        for(t in model.rounds.indices) {
            val round=model.rounds[t];
            val stump=round.stump;
            var line="round ${t+1} feature ${names[stump.feature]}";
            if(variant=="real")line+=" z ${real(round.z)} bound ${real(round.bound)} values ${reals(stump.values)}" else if(variant=="discrete")line+=" threshold ${real(stump.thresholds[0])} polarity ${round.polarity} error ${real(round.error)} alpha ${real(round.alpha)} z ${real(round.z)} bound ${real(round.bound)}" else {
                line+=" threshold ${real(stump.thresholds[0])} left ${real(stump.values[0])} right ${real(stump.values[1])} error ${real(round.error)}";
                if(variant=="logit")line+=" loss ${real(round.loss)}"
            };
            part+=line;
            if(variant=="discrete") {
                val largest=maximum(round.weights);
                var squares=0.0;
                for(w in round.weights)squares+=w*w;
                part+="weights ${t+1} max ${Evaluation.format(round.weights[largest],6)} id ${train[largest].id} ess ${real(1/squares)}"
            }
        };
        if(variant=="discrete") {
            val count=settings.integer("FOLDS");
            part+="cv folds $count selected $selected errors ${fraction(cvErrors[selected-1],n)}";
            for(fold in 0 until count) {
                val modelFold=folds[fold];
                var validation=0;
                var selectedErrors=0;
                var finalErrors=0;
                for(i in 0 until n)if(i%count==fold) {
                    validation++;
                    if(Evaluation.prediction(score(modelFold,train[i].x,selected))!=train[i].label)selectedErrors++;
                    if(Evaluation.prediction(score(modelFold,train[i].x,maximum))!=train[i].label)finalErrors++
                };
                part+="fold ${fold+1} train ${n-validation} validation $validation rounds ${modelFold.rounds.size} stop ${modelFold.stop} selected ${fraction(selectedErrors,validation)} final ${fraction(finalErrors,validation)}"
            };
            part+="cv_errors "+integers(cvErrors)
        };
        section(output,part)
    };
    return output
}
private fun classScores(model: Adaboost.Model,x: DoubleArray,count: Int): DoubleArray {
    val scores=DoubleArray(settings.integer("CLASSES"));
    for(t in 0 until minOf(count,model.rounds.size)) {
        val round=model.rounds[t];
        scores[round.stump.output(x).toInt()-1]+=round.alpha
    };
    return scores
}
private fun multiclass(rows: List<Dataset.Row>,binary: Boolean,limit: Int)=IntArray(rows.size) {
    i->val scores=if(binary)DoubleArray(ovr.size) {
        score(ovr[it],rows[i].x,limit)
    } else classScores(samme,rows[i].x,limit);
    maximum(scores)+1
}
private fun classErrors(rows: List<Dataset.Row>,predictions: IntArray)=rows.indices.count {
    rows[it].label!=predictions[it]
}
private fun curveReport(): List<String> {
    val output=mutableListOf("variant,round,train_error,test_error,train_loss,test_loss,min_margin");
    for(v in variants.indices) {
        val curve=curves[v];
        for(t in curve.trainErrors.indices)output+="${variants[v]},${t+1},${ratio(curve.trainErrors[t],n)},${ratio(curve.testErrors[t],m)},${real(curve.trainLoss[t])},${real(curve.testLoss[t])},${real(curve.margin[t])}"
    };
    for(t in 1..samme.rounds.size)output+="samme,$t,${ratio(classErrors(data.multiTrain.rows,multiclass(data.multiTrain.rows,false,t)),data.multiTrain.rows.size)},${ratio(classErrors(data.multiTest.rows,multiclass(data.multiTest.rows,false,t)),data.multiTest.rows.size)},-,-,-";
    return output
}
private fun predictionReport(): List<String> {
    val output=mutableListOf("id,variant,score,label,"+names.joinToString(","));
    for(i in 0 until m)for(v in variants.indices) {
        val contributions=DoubleArray(d);
        for(round in models[v].rounds)contributions[round.stump.feature]+=round.stump.output(test[i].x);
        var line="${test[i].id},${variants[v]},${real(testScores[v][i])},${Evaluation.prediction(testScores[v][i])}";
        for(value in contributions)line+=","+real(value);
        output+=line
    };
    return output
}
private fun unique(values: List<Double>): List<Double> {
    val result=mutableListOf<Double>();
    for(value in values.sorted())if(result.isEmpty()||value!=result.last())result+=value;
    return result
}
private fun rocReport(): List<String> {
    val output=mutableListOf("variant,threshold,tp,fp");
    for(v in variants.indices) {
        val distinct=unique(testScores[v].toList());
        for(j in distinct.size-1 downTo 0) {
            val threshold=distinct[j];
            var tp=0;
            var fp=0;
            for(i in 0 until m)if(testScores[v][i]>=threshold) {
                if(test[i].label==1)tp++ else fp++
            };
            output+="${variants[v]},${real(threshold)},$tp,$fp"
        }
    };
    return output
}
private class Importance(model: Adaboost.Model,features: Int,multi: Boolean) {
    val values=DoubleArray(features);
    val counts=IntArray(features);
    val order: List<Int>;
    val total: Double
    init {
        for(round in model.rounds) {
            val j=round.stump.feature;
            values[j]+=if(multi)round.alpha else round.stump.magnitude();
            counts[j]++
        };
        total=sum(values);
        order=sortedIndices(values,true)
    }
}
private fun importance(importance: Importance,features: List<String>)=features.indices.map {
    rank->val j=importance.order[rank];
    "${rank+1} ${features[j]} score ${real(importance.values[j])} share ${real(importance.values[j]/importance.total)} rounds ${importance.counts[j]}"
}
private fun marginReport(): List<String> {
    val random=Generator(settings.integers("PERMUTATION")[1]);
    val repeats=settings.integer("PERMUTATION");
    val output=mutableListOf<String>();
    for(v in variants.indices) {
        val model=models[v];
        val scale=magnitude(model,maximum);
        val trainMargin=margins(train,trainScores[v],scale);
        val testMargin=margins(test,testScores[v],scale);
        val part=mutableListOf("variant ${variants[v]} rounds ${model.rounds.size} scale ${real(scale)}",
            "train min ${real(minimum(trainMargin))} mean ${real(sum(trainMargin)/n)}");
        for(threshold in settings.numbers("MARGINS")) {
            val count=Evaluation.le(trainMargin,threshold);
            part+="train le ${real(threshold)} ${fraction(count,n)} ${ratio(count,n)}"
        };
        val histogram=IntArray(20);
        for(margin in trainMargin)histogram[minOf(19,floor((margin+1)*10).toInt())]++;
        part+="histogram "+integers(histogram);
        val hardest=sortedIndices(trainMargin,false);
        for(rank in 0 until 5) {
            val i=hardest[rank];
            part+="hardest ${train[i].id} label ${train[i].label} margin ${real(trainMargin[i])}"
        };
        part+="test min ${real(minimum(testMargin))} mean ${real(sum(testMargin)/m)}";
        for(threshold in settings.numbers("MARGINS")) {
            val count=Evaluation.le(testMargin,threshold);
            part+="test le ${real(threshold)} ${fraction(count,m)} ${ratio(count,m)}"
        };
        for(threshold in settings.numbers("MARGINS")) {
            var count=0;
            var correct=0;
            for(i in 0 until m)if(abs(testMargin[i])>threshold) {
                count++;
                if(Evaluation.prediction(testScores[v][i])==test[i].label)correct++
            };
            part+="test confident ${real(threshold)} ${fraction(count,m)} correct ${fraction(correct,count)} ${ratio(correct,count)}"
        };
        part+="importance";
        part+=importance(Importance(model,d,false),names);
        val base=m-errors(test,testScores[v]);
        part+="permutation repeats $repeats base ${fraction(base,m)}";
        val drops=DoubleArray(d);
        val lows=IntArray(d);
        val highs=IntArray(d);
        for(j in 0 until d) {
            lows[j]=m;
            for(repeat in 0 until repeats) {
                val permutation=IntArray(m) {
                    it
                };
                for(i in m-1 downTo 1) {
                    val other=random.draw()%(i+1);
                    val temporary=permutation[i];
                    permutation[i]=permutation[other];
                    permutation[other]=temporary
                };
                var correct=0;
                for(i in 0 until m) {
                    val x=test[i].x.copyOf();
                    x[j]=test[permutation[i]].x[j];
                    if(Evaluation.prediction(score(model,x,maximum))==test[i].label)correct++
                };
                drops[j]+=base-correct;
                lows[j]=minOf(lows[j],correct);
                highs[j]=maxOf(highs[j],correct)
            }
        };
        val ranked=sortedIndices(drops,true);
        for(rank in 0 until d) {
            val j=ranked[rank];
            part+="${rank+1} ${names[j]} drop ${real(drops[j]/(repeats*m))} min ${fraction(lows[j],m)} max ${fraction(highs[j],m)}"
        };
        section(output,part)
    };
    return output
}
private fun shapeReport(): List<String> {
    val output=mutableListOf<String>();
    for(v in variants.indices) {
        val model=models[v];
        val part=mutableListOf("variant ${variants[v]} rounds ${model.rounds.size}");
        for(j in 0 until d) {
            val stumps=model.rounds.filter {
                it.stump.feature==j
            }.map {
                it.stump
            };
            val values=mutableListOf<Double>();
            for(stump in stumps)values+=stump.thresholds.toList();
            val cuts=unique(values);
            val intervals=DoubleArray(cuts.size+1);
            for(interval in intervals.indices)for(stump in stumps) {
                var bin=0;
                if(interval>0)for(cut in stump.thresholds)if(cut<=cuts[interval-1])bin++;
                intervals[interval]+=stump.values[bin]
            };
            var min=intervals[0];
            var max=min;
            for(value in intervals) {
                min=minOf(min,value);
                max=maxOf(max,value)
            };
            part+="feature ${names[j]} rounds ${stumps.size} cuts ${cuts.size} range ${real(max-min)}";
            for(interval in intervals.indices)part+="interval ${if(interval==0)"-inf" else real(cuts[interval-1])} ${if(interval==cuts.size)"inf" else real(cuts[interval])} value ${real(intervals[interval])}"
        };
        section(output,part)
    };
    return output
}
private fun confusion(rows: List<Dataset.Row>,predictions: IntArray): List<String> {
    val classes=settings.integer("CLASSES");
    val matrix=Evaluation.confusion(rows,predictions,classes);
    val output=mutableListOf("confusion");
    for(row in matrix)output+=integers(row);
    for(c in 0 until classes) {
        var column=0;
        var row=0;
        for(j in 0 until classes) {
            column+=matrix[j][c];
            row+=matrix[c][j]
        };
        output+="class ${c+1} precision ${ratio(matrix[c][c],column)} recall ${ratio(matrix[c][c],row)}"
    };
    return output
}
private fun classErrorLines(training: List<Dataset.Row>,testing: List<Dataset.Row>,trainPredictions: IntArray,testPredictions: IntArray): List<String> {
    val a=classErrors(training,trainPredictions);
    val b=classErrors(testing,testPredictions);
    return listOf("train errors ${fraction(a,training.size)} rate ${ratio(a,training.size)}",
        "test errors ${fraction(b,testing.size)} rate ${ratio(b,testing.size)}")
}
private fun sammeReport(): List<String> {
    val classes=settings.integer("CLASSES");
    val rounds=settings.integer("SAMME_ROUNDS");
    val training=data.multiTrain.rows;
    val testing=data.multiTest.rows;
    val output=mutableListOf("samme classes $classes train ${training.size} test ${testing.size} rounds ${samme.rounds.size} stop ${samme.stop}");
    for(t in samme.rounds.indices) {
        val round=samme.rounds[t];
        val stump=round.stump;
        output+="round ${t+1} feature ${data.multiTrain.names[stump.feature]} threshold ${real(stump.thresholds[0])} left ${stump.values[0].toInt()} right ${stump.values[1].toInt()} error ${real(round.error)} alpha ${real(round.alpha)}"
    };
    val trainSamme=multiclass(training,false,rounds);
    val testSamme=multiclass(testing,false,rounds);
    val trainOvr=multiclass(training,true,rounds);
    val testOvr=multiclass(testing,true,rounds);
    output+=classErrorLines(training,testing,trainSamme,testSamme);
    output+=confusion(testing,testSamme);
    output+="importance";
    output+=importance(Importance(samme,data.multiTrain.names.size,true),data.multiTrain.names);
    output+="";
    output+="ovr classes $classes rounds $rounds";
    for(c in 1..classes) {
        val model=ovr[c-1];
        var positives=0;
        var trainingErrors=0;
        var testingErrors=0;
        for(row in training) {
            if(row.label==c)positives++;
            if(Evaluation.prediction(score(model,row.x,rounds))!=(if(row.label==c)1 else -1))trainingErrors++
        };
        for(row in testing)if(Evaluation.prediction(score(model,row.x,rounds))!=(if(row.label==c)1 else -1))testingErrors++;
        output+="class $c rounds ${model.rounds.size} stop ${model.stop} positives $positives train_errors ${fraction(trainingErrors,training.size)} test_errors ${fraction(testingErrors,testing.size)}"
    };
    output+=classErrorLines(training,testing,trainOvr,testOvr);
    output+=confusion(testing,testOvr);
    var agreement=0;
    for(i in testing.indices)if(testSamme[i]==testOvr[i])agreement++;
    output+="agreement ${fraction(agreement,testing.size)}";
    output+="";
    output+="predictions";
    for(i in testing.indices) {
        val row=testing[i];
        output+="${row.id} class ${row.label} samme ${testSamme[i]} ovr ${testOvr[i]} scores ${reals(classScores(samme,row.x,rounds))}"
    };
    return output
}
private fun metrics(kind: String,variant: String,rounds: Int,rows: List<Dataset.Row>,scores: DoubleArray,logit: Boolean): String {
    var tp=0;
    var fp=0;
    var tn=0;
    var fn=0;
    for(i in rows.indices) {
        val positive=Evaluation.prediction(scores[i])==1;
        if(rows[i].label==1) {
            if(positive)tp++ else fn++
        } else {
            if(positive)fp++ else tn++
        }
    };
    return "$kind $variant rounds $rounds correct ${fraction(tp+tn,rows.size)} accuracy ${ratio(tp+tn,rows.size)} tp $tp fp $fp tn $tn fn $fn precision ${ratio(tp,tp+fp)} recall ${ratio(tp,tp+fn)} f1 ${ratio(2*tp,2*tp+fp+fn)} auc ${real(Evaluation.auc(rows,scores))} loss ${real(loss(rows,scores,logit))}"
}
private fun positives(rows: List<Dataset.Row>)=rows.count {
    it.label==1
}
private fun featureSummary(rows: List<Dataset.Row>,feature: Int): String {
    val values=mutableListOf<Double>();
    var sum=0.0;
    var min=rows[0].x[feature];
    var max=min;
    for(row in rows) {
        val value=row.x[feature];
        values+=value;
        sum+=value;
        min=minOf(min,value);
        max=maxOf(max,value)
    };
    return "${real(min)} ${real(max)} ${real(sum/rows.size)} ${unique(values).size}"
}
private fun summaryReport(): List<String> {
    val output=mutableListOf("data train $n test $m features $d positives ${positives(train)} ${positives(test)}");
    for(j in 0 until d)output+="feature ${names[j]} train ${featureSummary(train,j)} test ${featureSummary(test,j)}";
    output+="cv selected $selected errors ${fraction(cvErrors[selected-1],n)} rate ${ratio(cvErrors[selected-1],n)}";
    output+=metrics("oof","discrete",selected,train,crossScores,false);
    val committeeTrain=DoubleArray(n);
    val committeeTest=DoubleArray(m);
    var rounds=0;
    for(v in variants.indices) {
        val variant=variants[v];
        val model=models[v];
        rounds+=model.rounds.size;
        output+=metrics("train",variant,model.rounds.size,train,trainScores[v],variant=="logit");
        output+=metrics("test",variant,model.rounds.size,test,testScores[v],variant=="logit");
        val scale=magnitude(model,maximum);
        for(i in 0 until n)committeeTrain[i]+=trainScores[v][i]/scale;
        for(i in 0 until m)committeeTest[i]+=testScores[v][i]/scale
    };
    output+=metrics("train","committee",rounds,train,committeeTrain,false);
    output+=metrics("test","committee",rounds,test,committeeTest,false);
    for(v in variants.indices) {
        val curve=curves[v];
        val trainAt=earliest(curve.trainErrors);
        val testAt=earliest(curve.testErrors);
        output+="curve ${variants[v]} rounds ${full[v].rounds.size} train_min ${fraction(curve.trainErrors[trainAt],n)} at ${trainAt+1} test_min ${fraction(curve.testErrors[testAt],m)} at ${testAt+1}"
    };
    val wrong=mutableListOf<String>();
    for(i in 0 until m) {
        var all=true;
        for(v in variants.indices)if(Evaluation.prediction(testScores[v][i])==test[i].label)all=false;
        if(all)wrong+=test[i].id
    };
    output+="all_wrong ${wrong.size}"+(if(wrong.isEmpty())"" else " "+wrong.joinToString(" "));
    output+="agreement";
    for(a in variants.indices)for(b in a+1 until variants.size) {
        var agree=0;
        var first=0;
        var second=0;
        for(i in 0 until m) {
            val x=Evaluation.prediction(testScores[a][i]);
            val y=Evaluation.prediction(testScores[b][i]);
            if(x==y)agree++ else if(x==test[i].label)first++ else second++
        };
        val difference=abs(first-second)-1;
        output+="${variants[a]} ${variants[b]} agree ${fraction(agree,m)} only_first $first only_second $second chi2 ${ratio(difference*difference,first+second)}"
    };
    val bootstrap=settings.integers("BOOTSTRAP");
    val samples=bootstrap[0];
    val random=Generator(bootstrap[1]);
    val correct=Array(variants.size) {
        IntArray(samples)
    };
    for(sample in 0 until samples) {
        val indices=IntArray(m) {
            random.draw()%m
        };
        for(v in variants.indices)for(i in indices)if(Evaluation.prediction(testScores[v][i])==test[i].label)correct[v][sample]++
    };
    output+="bootstrap samples $samples seed ${bootstrap[1]}";
    for(v in variants.indices) {
        val sorted=correct[v].sortedArray();
        var sum=0;
        for(count in correct[v])sum+=count;
        val g=samples/40;
        output+="${variants[v]} mean ${ratio(sum,samples*m)} low ${ratio(sorted[g],m)} high ${ratio(sorted[samples-g-1],m)}"
    };
    for(a in variants.indices)for(b in a+1 until variants.size) {
        var first=0;
        var tie=0;
        var second=0;
        for(sample in 0 until samples) {
            if(correct[a][sample]>correct[b][sample])first++ else if(correct[a][sample]==correct[b][sample])tie++ else second++
        };
        output+="${variants[a]} ${variants[b]} first $first tie $tie second $second"
    };
    for(v in variants.indices) {
        val counts=IntArray(5);
        val positives=IntArray(5);
        val sums=DoubleArray(5);
        var brier=0.0;
        for(i in 0 until m) {
            val probability=1/(1+exp(-2*testScores[v][i]));
            val delta=probability-(if(test[i].label==1)1.0 else 0.0);
            brier+=delta*delta;
            val bin=minOf(4,floor(probability*5).toInt());
            counts[bin]++;
            sums[bin]+=probability;
            if(test[i].label==1)positives[bin]++
        };
        output+="calibration ${variants[v]} brier ${real(brier/m)}";
        val ranges=listOf("0.0-0.2","0.2-0.4","0.4-0.6","0.6-0.8","0.8-1.0");
        for(bin in 0 until 5)output+="bin ${ranges[bin]} count ${counts[bin]} mean ${real(if(counts[bin]==0)Double.NaN else sums[bin]/counts[bin])} positives ${positives[bin]}"
    };
    return output
}
private fun experiment(variant: String,model: Adaboost.Model,training: List<Dataset.Row>,testing: List<Dataset.Row>)="$variant rounds ${model.rounds.size} stop ${model.stop} train_errors ${fraction(errors(training,scores(model,training,maximum)),training.size)} test_errors ${fraction(errors(testing,scores(model,testing,maximum)),testing.size)}"
private fun restrict(rows: List<Dataset.Row>,features: List<Int>)=rows.map {
    row->Dataset.Row(row.id,DoubleArray(features.size) {
        row.x[features[it]]
    },row.label)
}
private fun experimentReport(): List<String> {
    val output=mutableListOf<String>();
    for(q in settings.integers("SIZES")) {
        val count=n*q/100;
        val rows=train.take(count);
        output+="size $q rows $count";
        for(variant in variants) {
            val model=Variants.train(variant,rows,settings);
            output+=experiment(variant,model,rows,test)
        }
    };
    for(shrinkage in settings.numbers("SHRINKAGE")) {
        val model=Adaboost.discrete(train,weights(n),maximum,shrinkage);
        val curve=Curve(model,train,test,false);
        val at=earliest(curve.testErrors);
        output+=experiment("shrinkage "+real(shrinkage),model,train,test)+" test_min ${fraction(curve.testErrors[at],m)} at ${at+1}"
    };
    val importance=Importance(models[variants.indexOf("discrete")],d,false);
    for(count in 1..d) {
        val features=importance.order.take(count).sorted();
        val featureNames=features.map {
            names[it]
        };
        val training=restrict(train,features);
        val testing=restrict(test,features);
        val model=Adaboost.discrete(training,weights(n),selected,1.0);
        output+="top $count features ${featureNames.joinToString(" ")} rounds ${model.rounds.size} train_errors ${fraction(errors(training,scores(model,training,maximum)),n)} test_errors ${fraction(errors(testing,scores(model,testing,maximum)),m)}"
    };
    val noise=settings.integers("NOISE");
    for(qIndex in 1 until noise.size) {
        val q=noise[qIndex];
        val count=n*q/100;
        val random=Generator(noise[0]);
        val permutation=IntArray(n) {
            it
        };
        val flipped=BooleanArray(n);
        for(i in 0 until count) {
            val other=random.draw()%(n-i)+i;
            val temporary=permutation[i];
            permutation[i]=permutation[other];
            permutation[other]=temporary;
            flipped[permutation[i]]=true
        };
        val training=train.indices.map {
            i->val row=train[i];
            Dataset.Row(row.id,row.x,if(flipped[i])-row.label else row.label)
        };
        output+="noise $q flipped $count";
        for(variant in variants) {
            val model=Variants.train(variant,training,settings);
            val curve=Curve(model,training,test,variant=="logit");
            val at=earliest(curve.testErrors);
            var flippedWeight=0.0;
            val weights=model.rounds.last().weights;
            for(i in 0 until n)if(flipped[i])flippedWeight+=weights[i];
            output+=experiment(variant,model,training,test)+" test_min ${fraction(curve.testErrors[at],m)} at ${at+1} flipped_weight ${real(flippedWeight)}"
        }
    };
    return output
}
fun main() {
    data=Dataset.read();
    settings=data.settings;
    variants=settings.variants();
    names=data.train.names;
    train=data.train.rows;
    test=data.test.rows;
    n=train.size;
    m=test.size;
    d=names.size;
    maximum=settings.integer("ROUNDS");
    crossValidate();
    trainModels();
    Evaluation.write("ensemble.txt",ensembleReport());
    Evaluation.write("error_curve.csv",curveReport());
    Evaluation.write("predictions.csv",predictionReport());
    Evaluation.write("roc.csv",rocReport());
    Evaluation.write("margins.txt",marginReport());
    Evaluation.write("shapes.txt",shapeReport());
    Evaluation.write("samme.txt",sammeReport());
    Evaluation.write("summary.txt",summaryReport());
    Evaluation.write("experiments.txt",experimentReport())
}
