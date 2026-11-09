import kotlin.math.*

object Svm {
    lateinit var data: Dataset.Data;
    lateinit var settings: Dataset.Settings;
    lateinit var points: List<Kernels.Point>;
    lateinit var trainLabels: IntArray;
    lateinit var testLabels: IntArray
    val matrices=mutableListOf<Array<DoubleArray>>()
    fun f(x: Double,digits: Int=4)=Evaluation.fixed(x,digits)
    fun yes(value: Boolean)=if(value)"yes" else "no"
    fun info(m: Smo.Model)="passes ${m.passes()} steps ${m.steps} converged ${yes(m.converged)}"
    fun support(model: Smo.Model): IntArray {
        val counts=IntArray(3);
        for(a in model.alpha)if(a>0) {
            counts[0]++;
            counts[if(a==model.c)1 else 2]++
        };
        return counts
    }
    fun sv(m: Smo.Model): String {
        val c=support(m);
        return "support_vectors ${c[0]} bound ${c[1]} free ${c[2]}"
    }
    fun selectPoints(indices: List<Int>)=indices.map {
        points[it]
    }
    fun selectLabels(original: IntArray,indices: List<Int>)=IntArray(indices.size) {
        original[indices[it]]
    }
    data class FoldResult(val model: Smo.Model,val train: Int,val test: Int,val correct: Int)
    class CrossValidation(val kernel: Int,val c: Double,size: Int) {
        var correct=0;
        var sv=0;
        var passes=0;
        var steps=0;
        val decisions=DoubleArray(size);
        val folds=mutableListOf<FoldResult>()
    }
    fun crossValidation(kernel: Int,c: Double): CrossValidation {
        val result=CrossValidation(kernel,c,points.size)
        for(fold in Evaluation.folds(points.size,settings.folds)) {
            val model=Smo.train(selectPoints(fold.train),selectLabels(trainLabels,fold.train),
                settings.kernels[kernel],Kernels.submatrix(matrices[kernel],fold.train),c,settings);
            var correct=0
            for(i in fold.test) {
                val value=model.decision(points[i]);
                result.decisions[i]=value;
                if(Evaluation.sign(value)==trainLabels[i])correct++
            }
            result.folds.add(FoldResult(model,fold.train.size,fold.test.size,correct));
            result.correct+=correct;
            result.sv+=support(model)[0];
            result.passes+=model.passes();
            result.steps+=model.steps
        }
        return result
    }
    fun objectives(model: Smo.Model,alpha: DoubleArray): DoubleArray {
        var sum=0.0;
        var q=0.0;
        val raw=model.raw(alpha);
        for(i in alpha.indices) {
            sum+=alpha[i];
            q+=alpha[i]*model.labels[i]*raw[i]
        };
        return doubleArrayOf(q,sum-q/2)
    }
    class Final(val model: Smo.Model) {
        val train=model.training();
        val test=model.decisions(data.test);
        val w=DoubleArray(2)
        var alignment=0.0;
        var equality=0.0;
        var norm=0.0;
        var dual=0.0;
        var primal=0.0;
        var maxViolation=0.0;
        var radius=0.0;
        var auc=0.0;
        var positiveMean=0.0;
        var negativeMean=0.0
        val supportByClass=IntArray(4);
        var violations=0;
        var estimated=0;
        var correct=0;
        var inside=0;
        lateinit var counts: Evaluation.Counts
    }
    fun evaluate(model: Smo.Model): Final {
        val result=Final(model);
        val n=trainLabels.size;
        var sy=0.0;
        var sg=0.0;
        var hinge=0.0;
        var minimum=Double.MAX_VALUE;
        var maximum=-Double.MAX_VALUE
        for(i in 0 until n)for(j in 0 until n) {
            val value=model.matrix[i][j];
            sy+=trainLabels[i]*trainLabels[j]*value;
            sg+=value*value;
            minimum=minOf(minimum,value);
            if(i==j)maximum=maxOf(maximum,value)
        }
        result.alignment=sy/(n*sqrt(sg));
        result.radius=maximum-minimum
        for(i in 0 until n) {
            val a=model.alpha[i];
            val residual=trainLabels[i]*result.train[i]-1;
            val violation=if(a==0.0)maxOf(0.0,-residual) else if(a==model.c)maxOf(0.0,residual) else abs(residual)
            if(violation>settings.tolerance)result.violations++;
            result.maxViolation=maxOf(result.maxViolation,violation);
            val slack=maxOf(0.0,1-trainLabels[i]*result.train[i]);
            hinge+=slack;
            if(2*a*result.radius+slack>=1)result.estimated++
            result.equality+=a*trainLabels[i];
            result.w[0]+=a*trainLabels[i]*points[i].x;
            result.w[1]+=a*trainLabels[i]*points[i].y
            if(a>0)result.supportByClass[(if(trainLabels[i]==1)0 else 2)+(if(a==model.c)0 else 1)]++
        }
        val objective=objectives(model,model.alpha);
        result.norm=sqrt(objective[0]);
        result.dual=objective[1];
        result.primal=objective[0]/2+model.c*hinge
        result.correct=Evaluation.correct(trainLabels,result.train);
        result.counts=Evaluation.counts(testLabels,result.test);
        result.auc=Evaluation.auc(testLabels,result.test)
        var positive=0;
        var negative=0
        for(i in testLabels.indices) {
            val v=result.test[i];
            if(abs(v)<1)result.inside++;
            if(testLabels[i]==1) {
                positive++;
                result.positiveMean+=v
            } else {
                negative++;
                result.negativeMean+=v
            }
        }
        result.positiveMean/=positive;
        result.negativeMean/=negative
        return result
    }
    fun finalLines(result: Final): List<String> {
        val m=result.model;
        val kernel=m.kernel;
        val n=trainLabels.size;
        val t=testLabels.size;
        val cls=result.supportByClass;
        val counts=result.counts
        val lines=mutableListOf("model ${kernel.name}","kernel ${kernel.description()}","C ${f(m.c)}",
            "alignment ${f(result.alignment,6)}","passes ${m.passes()} full ${m.fullPasses} nonbound ${m.nonboundPasses} converged ${yes(m.converged)}",
            "examined ${m.examined} steps ${m.steps}","choice heuristic ${m.choices[0]} nonbound_loop ${m.choices[1]} full_loop ${m.choices[2]}",
            "clipping none ${m.clipping[0]} lower ${m.clipping[1]} upper ${m.clipping[2]}",
            sv(m),"b ${f(m.b,6)}","equality ${f(result.equality,6)}")
        if(kernel.kind=="linear")lines.add("w ${f(result.w[0],6)} ${f(result.w[1],6)}")
        lines.add("sv_by_class positive bound ${cls[0]} free ${cls[1]} negative bound ${cls[2]} free ${cls[3]}")
        lines.add("norm ${f(result.norm,6)} margin ${f(2/result.norm,6)}");
        lines.add("dual_objective ${f(result.dual,6)}");
        lines.add("primal_objective ${f(result.primal,6)}");
        lines.add("duality_gap ${f(result.primal-result.dual,6)}")
        lines.add("kkt_violations ${result.violations} max ${f(result.maxViolation,6)}");
        lines.add("xi_alpha radius ${f(result.radius,6)} errors ${result.estimated}/$n accuracy ${Evaluation.ratio(n-result.estimated,n)}")
        lines.add("train correct ${result.correct}/$n accuracy ${Evaluation.ratio(result.correct,n)}")
        lines.add("test correct ${counts.correct()}/$t accuracy ${Evaluation.ratio(counts.correct(),t)} tp ${counts.tp} fp ${counts.fp} tn ${counts.tn} fn ${counts.fn}")
        lines.add("test precision ${Evaluation.ratio(counts.tp,counts.tp+counts.fp)} recall ${Evaluation.ratio(counts.tp,counts.tp+counts.fn)} f1 ${Evaluation.ratio(2*counts.tp,2*counts.tp+counts.fp+counts.fn)} auc ${f(result.auc)}")
        lines.add("test inside_margin ${result.inside}");
        lines.add("test mean_decision positive ${f(result.positiveMean)} negative ${f(result.negativeMean)}")
        for(i in 0 until n)if(m.alpha[i]>0)lines.add("sv ${data.train[i].id} y ${trainLabels[i]} alpha ${f(m.alpha[i],6)} f ${f(result.train[i])} ${if(m.alpha[i]==m.c)"bound" else "free"}")
        return lines
    }
    fun log(model: Smo.Model): List<String> {
        val lines=mutableListOf("training_log ${model.kernel.name}");
        var i=0
        while(i<model.records.size) {
            var pass=model.records[i]
            if(pass.full) {
                lines.add("pass ${i+1} full examined ${pass.examined} changed ${pass.changed} dual_objective ${f(objectives(model,pass.alpha!!)[1],6)}");
                i++
            }
            else {
                val first=i+1;
                var examined=0;
                var changed=0;
                while(i<model.records.size&&!model.records[i].full) {
                    pass=model.records[i];
                    examined+=pass.examined;
                    changed+=pass.changed;
                    i++
                };
                lines.add("passes $first-$i nonbound examined $examined changed $changed")
            }
        }
        return lines
    }
    fun paths(selected: Smo.Model): List<String> {
        val lines=mutableListOf("c_path ${selected.kernel.name}")
        for(c in settings.coefficients) {
            val m=if(c==selected.c)selected else Smo.train(points,trainLabels,selected.kernel,selected.matrix,c,settings);
            val objective=objectives(m,m.alpha)
            lines.add("C ${f(c)} ${sv(m)} dual_objective ${f(objective[1],6)} train ${Evaluation.correct(trainLabels,m.training())}/${points.size} test ${Evaluation.correct(testLabels,m.decisions(data.test))}/${testLabels.size} ${info(m)}")
        }
        return lines
    }
    fun learning(selected: Smo.Model): List<String> {
        val lines=mutableListOf("learning_curve ${selected.kernel.name} C ${f(selected.c)}")
        for(fraction in settings.learning) {
            val size=points.size*fraction/100;
            val indices=(0 until size).toList();
            val labels=selectLabels(trainLabels,indices);
            val m=Smo.train(selectPoints(indices),labels,selected.kernel,Kernels.submatrix(selected.matrix,indices),selected.c,settings)
            lines.add("size $size support_vectors ${support(m)[0]} train ${Evaluation.correct(labels,m.training())}/$size test ${Evaluation.correct(testLabels,m.decisions(data.test))}/${testLabels.size} ${info(m)}")
        }
        return lines
    }
    fun probability(value: Double,a: Double,b: Double)=1/(1+exp(a*value+b))
    fun nll(values: DoubleArray,targets: DoubleArray,a: Double,b: Double): Double {
        var sum=0.0;
        for(i in values.indices) {
            val p=probability(values[i],a,b);
            sum+=targets[i]*ln(p)+(1-targets[i])*ln(1-p)
        };
        return -sum
    }
    class Calibration(size: Int) {
        var a=0.0;
        var b=0.0;
        val probabilities=DoubleArray(size);
        val lines=mutableListOf<String>()
    }
    fun calibrate(selected: CrossValidation,model: Final): Calibration {
        val result=Calibration(testLabels.size);
        val positives=trainLabels.count {
            it==1
        };
        val negatives=trainLabels.size-positives
        val targets=DoubleArray(trainLabels.size) {
            if(trainLabels[it]==1)(positives+1.0)/(positives+2) else 1.0/(negatives+2)
        }
        result.b=ln((negatives+1.0)/(positives+1));
        result.lines.add("calibration ${model.model.kernel.name} C ${f(selected.c)} positives $positives negatives $negatives")
        result.lines.add("start A ${f(0.0,6)} B ${f(result.b,6)} nll ${f(nll(selected.decisions,targets,0.0,result.b),6)}")
        for(iteration in 1..settings.newton) {
            var g1=0.0;
            var g2=0.0;
            var h11=0.0;
            var h21=0.0;
            var h22=0.0
            for(i in targets.indices) {
                val v=selected.decisions[i];
                val p=probability(v,result.a,result.b);
                g1+=v*(targets[i]-p);
                g2+=targets[i]-p;
                h11+=v*v*p*(1-p);
                h21+=v*p*(1-p);
                h22+=p*(1-p)
            }
            val det=h11*h22-h21*h21;
            result.a=result.a-(h22*g1-h21*g2)/det;
            result.b=result.b-(h11*g2-h21*g1)/det
            result.lines.add("iteration $iteration A ${f(result.a,6)} B ${f(result.b,6)} nll ${f(nll(selected.decisions,targets,result.a,result.b),6)}")
        }
        val m=testLabels.size;
        val count=IntArray(5);
        val positive=IntArray(5);
        val sum=DoubleArray(5);
        var logLoss=0.0;
        var brier=0.0
        for(i in 0 until m) {
            val p=probability(model.test[i],result.a,result.b);
            result.probabilities[i]=p;
            logLoss+=if(testLabels[i]==1)ln(p) else ln(1-p)
            val error=p-(if(testLabels[i]==1)1 else 0);
            brier+=error*error;
            val bin=minOf(4,floor(p*5).toInt());
            count[bin]++;
            sum[bin]+=p;
            if(testLabels[i]==1)positive[bin]++
        }
        result.lines.add("test log_loss ${f(-logLoss/m,6)} brier ${f(brier/m,6)}")
        val ranges=arrayOf("0.0-0.2","0.2-0.4","0.4-0.6","0.6-0.8","0.8-1.0")
        for(i in 0..4)result.lines.add("bin ${ranges[i]} count ${count[i]} mean_probability ${if(count[i]==0)"-" else f(sum[i]/count[i])} positive_rate ${Evaluation.ratio(positive[i],count[i])}")
        val closest=(0 until m).sortedWith(compareBy<Int> {
            abs(model.test[it])
        }.thenBy {
            it
        })
        for(i in closest.take(5))result.lines.add("closest ${data.test[i].id} label ${testLabels[i]} decision ${f(model.test[i])} probability ${f(result.probabilities[i])}")
        return result
    }
    fun linear(weights: DoubleArray,point: Kernels.Point)=weights[0]*point.x+weights[1]*point.y+weights[2]
    fun linearValues(weights: DoubleArray,examples: List<Dataset.Example>)=DoubleArray(examples.size) {
        linear(weights,examples[it].point)
    }
    class Pegasos(size: Int) {
        val weights=DoubleArray(3);
        val average=DoubleArray(3);
        var test=DoubleArray(size);
        val lines=mutableListOf<String>()
    }
    fun trainPegasos(comparison: Final): Pegasos {
        val result=Pegasos(testLabels.size);
        result.lines.add("pegasos lambda ${f(settings.lambda)} iterations ${settings.pegasos} seed ${settings.seed}")
        var state=settings.seed.toLong();
        var updates=0;
        val n=points.size;
        val sums=DoubleArray(3)
        for(t in 1..settings.pegasos) {
            state=48271*state%2147483647;
            val i=(state%n).toInt();
            val eta=1/(settings.lambda*t);
            val sigma=1-eta*settings.lambda;
            val update=trainLabels[i]*linear(result.weights,points[i])<1
            val coordinates=doubleArrayOf(points[i].x,points[i].y,1.0)
            for(j in 0..2) {
                result.weights[j]=if(update)sigma*result.weights[j]+eta*trainLabels[i]*coordinates[j] else sigma*result.weights[j];
                sums[j]+=result.weights[j]
            };
            if(update)updates++
            if(t%(settings.pegasos/10)==0) {
                val values=linearValues(result.weights,data.train);
                var hinge=0.0;
                for(j in 0 until n)hinge+=maxOf(0.0,1-trainLabels[j]*values[j]);
                val w=result.weights
                val objective=settings.lambda/2*(w[0]*w[0]+w[1]*w[1]+w[2]*w[2])+hinge/n;
                result.lines.add("checkpoint $t objective ${f(objective,6)} train ${Evaluation.correct(trainLabels,values)}/$n")
            }
        }
        for(j in 0..2)result.average[j]=sums[j]/settings.pegasos;
        result.test=linearValues(result.weights,data.test)
        val train=Evaluation.correct(trainLabels,linearValues(result.weights,data.train));
        val test=Evaluation.correct(testLabels,result.test);
        val average=Evaluation.correct(testLabels,linearValues(result.average,data.test))
        val agreement=testLabels.indices.count {
            Evaluation.sign(result.test[it])==Evaluation.sign(comparison.test[it])
        }
        val w=result.weights;
        val v=comparison.w;
        val cosine=(w[0]*v[0]+w[1]*v[1])/(sqrt(w[0]*w[0]+w[1]*w[1])*sqrt(v[0]*v[0]+v[1]*v[1]))
        result.lines.add("updates $updates");
        result.lines.add("w ${f(w[0],6)} ${f(w[1],6)} bias ${f(w[2],6)}")
        result.lines.add("train correct $train/$n accuracy ${Evaluation.ratio(train,n)}");
        result.lines.add("test correct $test/${testLabels.size} accuracy ${Evaluation.ratio(test,testLabels.size)}")
        val a=result.average;
        result.lines.add("average w ${f(a[0],6)} ${f(a[1],6)} bias ${f(a[2],6)} test correct $average/${testLabels.size}")
        result.lines.add("compare ${comparison.model.kernel.name} cosine ${f(cosine,6)} test_agreement $agreement/${testLabels.size}")
        return result
    }

    fun mcnemar(models: List<Final>,pegasos: Pegasos): List<String> {
        val names=models.map {it.model.kernel.name}.toMutableList()
        names.add("pegasos")
        val decisions=models.map {it.test}.toMutableList()
        decisions.add(pegasos.test)
        val lines=mutableListOf("mcnemar")
        for(a in names.indices)for(b in a+1 until names.size) {
            var first=0;
            var second=0
            for(i in testLabels.indices) {
                val x=Evaluation.sign(decisions[a][i])==testLabels[i];
                val y=Evaluation.sign(decisions[b][i])==testLabels[i];
                if(x&&!y)first++;
                if(y&&!x)second++
            }
            val difference=abs(first-second)-1;
            lines.add("${names[a]} ${names[b]} only_first $first only_second $second chi2 ${if(first+second==0)"-" else f((difference*difference).toDouble()/(first+second))}")
        }
        return lines
    }
    fun classify(models: Multiclass.Models,examples: List<Dataset.Example>)=examples.map {
        models.classify(it.point)
    }
    fun multiSummary(name: String,examples: List<Dataset.Example>,predictions: List<Multiclass.Classification>): String {
        var rest=0;
        var pair=0;
        var agreement=0;
        var ties=0
        for(i in examples.indices) {
            val c=predictions[i];
            if(c.rest==examples[i].label)rest++;
            if(c.pair==examples[i].label)pair++;
            if(c.rest==c.pair)agreement++;
            if(c.tied)ties++
        }
        val n=examples.size;
        return "$name ovr $rest/$n ${Evaluation.ratio(rest,n)} ovo $pair/$n ${Evaluation.ratio(pair,n)} agreement $agreement/$n vote_ties $ties"
    }
    fun values(values: DoubleArray)=values.joinToString(" ") {
        f(it)
    }
    fun multiclass(models: Multiclass.Models): List<String> {
        val train=data.multiTrain;
        val test=data.multiTest;
        val trainPredictions=classify(models,train);
        val testPredictions=classify(models,test);
        val n=train.size;
        val m=test.size
        val lines=mutableListOf("multiclass kernel ${settings.multiKernel} C ${f(settings.multiC)} classes 3 train $n test $m","ovr")
        for(k in 1..3) {
            val model=models.rest[k-1];
            val positive=model.labels.count {
                it==1
            };
            var correct=0
            for(i in 0 until m)if(Evaluation.sign(testPredictions[i].restValues[k-1])==(if(test[i].label==k)1 else -1))correct++
            lines.add("model $k-rest examples $n positives $positive ${sv(model)} b ${f(model.b,6)} ${info(model)} test $correct/$m")
        }
        lines.add("ovo")
        for(k in 0..2) {
            val a=Multiclass.PAIRS[k][0];
            val b=Multiclass.PAIRS[k][1];
            val model=models.pairs[k];
            val positive=model.labels.count {
                it==1
            };
            var correct=0;
            var count=0
            for(i in 0 until m) {
                val y=test[i].label;
                if(y!=a&&y!=b)continue;
                count++;
                if(Evaluation.sign(testPredictions[i].pairValues[k])==(if(y==a)1 else -1))correct++
            }
            lines.add("model $a-$b examples ${model.labels.size} positives $positive ${sv(model)} b ${f(model.b,6)} ${info(model)} test $correct/$count")
        }
        lines.add("predictions");
        val rest=IntArray(m);
        val pair=IntArray(m)
        for(i in 0 until m) {
            val example=test[i];
            val c=testPredictions[i];
            rest[i]=c.rest;
            pair[i]=c.pair;
            val votes=c.votes
            lines.add("${example.id} class ${example.label} ovr ${values(c.restValues)} pred ${c.rest} ovo ${values(c.pairValues)} votes ${votes[0]} ${votes[1]} ${votes[2]} pred ${c.pair}")
        }
        lines.add(multiSummary("train",train,trainPredictions));
        lines.add(multiSummary("test",test,testPredictions));
        lines.add("confusion ovr");
        lines.addAll(Evaluation.confusionLines(Evaluation.confusion(Dataset.labels(test),rest)));
        lines.add("confusion ovo");
        lines.addAll(Evaluation.confusionLines(Evaluation.confusion(Dataset.labels(test),pair)))
        return lines
    }
    fun center(row: Int,column: Int): Kernels.Point {
        val dx=(settings.plotX[1]-settings.plotX[0])/settings.width;
        val dy=(settings.plotY[1]-settings.plotY[0])/settings.height;
        return Kernels.Point(settings.plotX[0]+(column+0.5)*dx,settings.plotY[1]-(row+0.5)*dy)
    }
    fun locate(point: Kernels.Point): IntArray {
        val dx=(settings.plotX[1]-settings.plotX[0])/settings.width;
        val dy=(settings.plotY[1]-settings.plotY[0])/settings.height;
        return intArrayOf(floor((settings.plotY[1]-point.y)/dy).toInt(),floor((point.x-settings.plotX[0])/dx).toInt())
    }
    fun inside(cell: IntArray)=cell[0]>=0&&cell[0]<settings.height&&cell[1]>=0&&cell[1]<settings.width
    fun frame(lines: MutableList<String>,cells: Array<CharArray>) {
        val border="+"+"-".repeat(settings.width)+"+";
        lines.add(border);
        for(row in cells)lines.add("|"+row.concatToString()+"|");
        lines.add(border)
    }
    fun plots(models: List<Final>,selected: Int,calibration: Calibration,multi: Multiclass.Models): List<String> {
        val w=settings.width;
        val h=settings.height;
        val model=models[selected]
        val lines=mutableListOf("binary ${model.model.kernel.name} C ${f(model.model.c)}","x ${f(settings.plotX[0])} ${f(settings.plotX[1])} y ${f(settings.plotY[0])} ${f(settings.plotY[1])} grid ${w}x$h")
        val binary=Array(h) {
            CharArray(w)
        };
        val probabilityGrid=Array(h) {
            CharArray(w)
        };
        val multiclass=Array(h) {
            CharArray(w)
        }
        val assigned=Array(h) {
            IntArray(w) {
                -1
            }
        };
        val multiAssigned=Array(h) {
            IntArray(w) {
                -1
            }
        }
        val decisions=Array(models.size) {
            DoubleArray(w*h)
        };
        val levels=IntArray(10);
        val positive=IntArray(models.size)
        for(r in 0 until h)for(c in 0 until w) {
            val point=center(r,c)
            for(i in models.indices) {
                val value=models[i].model.decision(point);
                decisions[i][r*w+c]=value;
                if(Evaluation.sign(value)==1)positive[i]++
            }
            val value=decisions[selected][r*w+c];
            binary[r][c]=if(value>=1)'+' else if(value>0)'.' else if(value> -1)'-' else ' '
            val level=minOf(9,floor(probability(value,calibration.a,calibration.b)*10).toInt());
            probabilityGrid[r][c]=('0'.code+level).toChar();
            levels[level]++
            val prediction=multi.classify(point);
            multiclass[r][c]=if(prediction.rest!=prediction.pair)'?' else if(prediction.rest==1)' ' else if(prediction.rest==2)'.' else ':'
        }
        var outside=0;
        var multiOutside=0
        for(i in data.train.indices) {
            val cell=locate(data.train[i].point);
            if(!inside(cell)) {
                outside++;
                continue
            };
            val old=assigned[cell[0]][cell[1]];
            if(old<0||model.model.alpha[i]>0&&model.model.alpha[old]==0.0)assigned[cell[0]][cell[1]]=i
        }
        for(i in data.multiTrain.indices) {
            val cell=locate(data.multiTrain[i].point);
            if(!inside(cell)) {
                multiOutside++;
                continue
            };
            if(multiAssigned[cell[0]][cell[1]]<0)multiAssigned[cell[0]][cell[1]]=i
        }
        var pointCount=0;
        var multiPoints=0;
        val binaryCounts=IntArray(4);
        val multiCounts=IntArray(4)
        for(r in 0 until h)for(c in 0 until w) {
            var i=assigned[r][c]
            if(i>=0) {
                pointCount++;
                val support=model.model.alpha[i]>0;
                binary[r][c]=if(trainLabels[i]==1)(if(support)'X' else 'x') else (if(support)'O' else 'o')
            }
            else {
                val index=when(binary[r][c]) {
                    '+'->0;
                    '.'->1;
                    '-'->2;
                    else->3
                };
                binaryCounts[index]++
            }
            i=multiAssigned[r][c]
            if(i>=0) {
                multiPoints++;
                multiclass[r][c]=('0'.code+data.multiTrain[i].label).toChar()
            }
            else {
                val index=when(multiclass[r][c]) {
                    ' '->0;
                    '.'->1;
                    ':'->2;
                    else->3
                };
                multiCounts[index]++
            }
        }
        frame(lines,binary);
        lines.add("cells outer_positive ${binaryCounts[0]} inner_positive ${binaryCounts[1]} inner_negative ${binaryCounts[2]} outer_negative ${binaryCounts[3]} points $pointCount outside $outside")
        lines.add("");
        lines.add("probability ${model.model.kernel.name} A ${f(calibration.a,6)} B ${f(calibration.b,6)}");
        frame(lines,probabilityGrid);
        lines.add("levels "+levels.joinToString(" "));
        lines.add("");
        lines.add("grid_agreement")
        for(a in models.indices)for(b in a+1 until models.size) {
            val count=(0 until w*h).count {
                Evaluation.sign(decisions[a][it])==Evaluation.sign(decisions[b][it])
            };
            lines.add("${settings.kernels[a].name} ${settings.kernels[b].name} $count/${w*h} positive ${positive[a]} ${positive[b]}")
        }
        lines.add("");
        lines.add("multiclass ${settings.multiKernel} C ${f(settings.multiC)}");
        frame(lines,multiclass)
        lines.add("cells class1 ${multiCounts[0]} class2 ${multiCounts[1]} class3 ${multiCounts[2]} disagree ${multiCounts[3]} points $multiPoints outside $multiOutside")
        return lines
    }
    fun compare(a: CrossValidation,b: CrossValidation): Int {
        var order=b.correct.compareTo(a.correct);
        if(order==0)order=a.c.compareTo(b.c);
        return if(order!=0)order else a.kernel.compareTo(b.kernel)
    }
    fun part(lines: MutableList<String>,section: List<String>) {
        if(lines.isNotEmpty())lines.add("");
        lines.addAll(section)
    }
    fun run() {
        data=Dataset.read();
        settings=data.settings;
        points=Dataset.points(data.train);
        trainLabels=Dataset.labels(data.train);
        testLabels=Dataset.labels(data.test)
        val grid=mutableListOf<CrossValidation>();
        val best=mutableListOf<CrossValidation>();
        val kernelCount=settings.kernels.size
        for(k in 0 until kernelCount) {
            matrices.add(settings.kernels[k].matrix(points));
            var chosen: CrossValidation?=null
            for(c in settings.coefficients) {
                val cv=crossValidation(k,c);
                grid.add(cv);
                if(chosen==null||cv.correct>chosen.correct)chosen=cv
            };
            best.add(chosen!!)
        }
        var selected=best[0];
        for(cv in best)if(compare(cv,selected)<0)selected=cv
        val ranked=grid.sortedWith(Comparator {
            a,b->compare(a,b)
        });
        val models=mutableListOf<Final>();
        var linear=-1;
        var multiKernel: Kernels.Kernel?=null
        for(k in 0 until kernelCount) {
            val kernel=settings.kernels[k];
            models.add(evaluate(Smo.train(points,trainLabels,kernel,matrices[k],best[k].c,settings)));
            if(linear<0&&kernel.kind=="linear")linear=k;
            if(kernel.name==settings.multiKernel)multiKernel=kernel
        }
        val selectedModel=models[selected.kernel];
        val calibration=calibrate(selected,selectedModel);
        val pegasos=trainPegasos(models[linear]);
        val multi=Multiclass.Models(data.multiTrain,multiKernel!!,settings.multiC,settings)
        val modelLines=mutableListOf("cross_validation folds ${settings.folds} examples ${points.size}")
        for(cv in best)modelLines.add("best ${settings.kernels[cv.kernel].name} C ${f(cv.c)} correct ${cv.correct}/${points.size} accuracy ${Evaluation.ratio(cv.correct,points.size)}")
        modelLines.add("selected ${selectedModel.model.kernel.name} C ${f(selected.c)}");
        modelLines.add("ranking")
        for((i,cv) in ranked.withIndex())modelLines.add("${i+1} ${settings.kernels[cv.kernel].name} C ${f(cv.c)} correct ${cv.correct}/${points.size}")
        modelLines.add("cv_detail ${selectedModel.model.kernel.name} C ${f(selected.c)}")
        for((i,fold) in selected.folds.withIndex())modelLines.add("fold ${i+1} train ${fold.train} test ${fold.test} correct ${fold.correct} support_vectors ${support(fold.model)[0]} ${info(fold.model)}")
        for(model in models)part(modelLines,finalLines(model));
        part(modelLines,log(selectedModel.model));
        part(modelLines,paths(selectedModel.model));
        part(modelLines,learning(selectedModel.model));
        part(modelLines,calibration.lines);
        part(modelLines,pegasos.lines);
        part(modelLines,mcnemar(models,pegasos))
        var header="kernel,C";
        for(i in 1..settings.folds)header+=",fold$i"
        val cvLines=mutableListOf("$header,correct,accuracy,support_vectors,passes,steps")
        for(cv in grid) {
            var line="${settings.kernels[cv.kernel].name},${f(cv.c)}";
            for(fold in cv.folds)line+=",${fold.correct}";
            cvLines.add("$line,${cv.correct},${Evaluation.ratio(cv.correct,points.size)},${cv.sv},${cv.passes},${cv.steps}")
        }
        header="id,label";
        for(kernel in settings.kernels)header+=",${kernel.name}"
        val predictionLines=mutableListOf("$header,pegasos,predicted,probability")
        for(i in data.test.indices) {
            var line="${data.test[i].id},${testLabels[i]}";
            for(model in models)line+=",${f(model.test[i])}";
            predictionLines.add("$line,${f(pegasos.test[i])},${Evaluation.sign(selectedModel.test[i])},${f(calibration.probabilities[i])}")
        }
        Evaluation.write("model.txt",modelLines);
        Evaluation.write("cv_grid.csv",cvLines);
        Evaluation.write("predictions.csv",predictionLines);
        Evaluation.write("multiclass.txt",multiclass(multi));
        Evaluation.write("decision_plot.txt",plots(models,selected.kernel,calibration,multi))
    }
}
fun main()=Svm.run()
