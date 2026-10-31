import kotlin.math.*

private lateinit var data: Dataset.Data
private lateinit var settings: Dataset.Settings
private var classes=0
private var dimension=0
private lateinit var all: IntArray
private lateinit var models: Array<GaussianModels.Model>
private lateinit var test: Array<Array<GaussianModels.Prediction>>
private lateinit var predictions: Array<IntArray>
private lateinit var mainCv: Array<Cv>
private fun train(kind: Int,features: IntArray,rows: List<Dataset.Row>,epsilon: Double=settings.epsilon,
    gamma: Double=settings.gamma,prior: String=settings.prior)=GaussianModels.Model(rows,features,
    classes,kind,prior,epsilon,gamma)
private fun predict(model: GaussianModels.Model,rows: List<Dataset.Row>)=IntArray(rows.size) {
    model.predict(rows[it].values)
}
private fun correct(rows: List<Dataset.Row>,predicted: IntArray)=rows.indices.count {
    rows[it].y==predicted[it]
}
private class Cv(n: Int,foldCount: Int) {
    val predicted=IntArray(n);
    val folds=IntArray(foldCount);
    var correct=0
}
private fun cv(kind: Int,features: IntArray,epsilon: Double=settings.epsilon,gamma: Double=settings.gamma): Cv {
    val result=Cv(data.train.size,settings.folds);
    for(fold in 0 until settings.folds) {
        val rows=data.train.filter {
            it.id%settings.folds!=fold
        };
        val model=train(kind,features,rows,epsilon,gamma);
        for(i in data.train.indices) {
            val r=data.train[i];
            if(r.id%settings.folds!=fold)continue;
            val p=model.predict(r.values);
            result.predicted[i]=p;
            if(p==r.y) {
                result.folds[fold]++;
                result.correct++
            }
        }
    };
    return result
}
private fun features(features: IntArray)=features.joinToString(" ") {
    data.features[it]
}
private fun integers(a: IntArray)=a.joinToString(" ")
private fun summary(m: Evaluation.Measures)="accuracy ${Plot.fraction(m.accuracy)} balanced_accuracy ${Plot.fraction(m.balanced)} kappa ${Plot.fraction(m.kappa)}"
private fun confusion(output: MutableList<String>,m: Evaluation.Measures) {
    for(k in 0 until classes)output+="confusion ${data.classes[k]} ${integers(m.matrix[k])}"
}
private fun comparison(a: String,b: String,rows: List<Dataset.Row>,pa: IntArray,pb: IntArray): String {
    val m=Evaluation.mcnemar(rows,pa,pb);
    return "$a $b b01 ${m.b01} b10 ${m.b10} chi2 ${Plot.real(m.chi2)} significant ${if(m.chi2>3.841)"yes" else "no"}"
}
private data class Distance(val index: Int,val q: Double,val nearest: Int)
private fun sortDistances(values: MutableList<Distance>) {
    values.sortWith(compareByDescending<Distance> {
        it.q
    }.thenBy {
        it.index
    })
}
private fun modelReport() {
    val stats=models[0].statistics;
    val output=mutableListOf("features ${data.features.joinToString(" ")}","classes ${data.classes.joinToString(" ")}","prior_mode ${settings.prior}");
    for(k in 0 until classes)output+="class ${data.classes[k]} letter ${data.classes[k][0].uppercaseChar()} count ${stats.counts[k]} prior ${Plot.real(models[0].priors[k])} mean ${Plot.reals(stats.means[k])}";
    var section=mutableListOf("model NB","smoothing epsilon ${Plot.real(settings.epsilon)} max_variance ${Plot.real(models[0].maxVariance)} added ${Plot.real(models[0].added)}");
    for(k in 0 until classes) {
        val diagonal=DoubleArray(dimension) {
            models[0].covariance[k][it][it]
        };
        section+="class ${data.classes[k]} variance ${Plot.reals(diagonal)} log_det ${Plot.real(models[0].logDet[k])}"
    };
    Plot.section(output,section);
    section=mutableListOf("model LDA","log_det ${Plot.real(models[1].logDet[0])}");
    for(row in models[1].covariance[0])section+="  ${Plot.reals(row)}";
    for(k in 0 until classes) {
        val coefficient=Linalg.backward(models[1].factors[0],Linalg.forward(models[1].factors[0],stats.means[k]));
        val intercept=ln(models[1].priors[k])-Linalg.dot(stats.means[k],coefficient)/2;
        section+="class ${data.classes[k]} intercept ${Plot.real(intercept)} coef ${Plot.reals(coefficient)}"
    };
    Plot.section(output,section);
    section=mutableListOf("model QDA gamma ${Plot.real(settings.gamma)}");
    for(k in 0 until classes) {
        val eigen=Linalg.jacobi(models[2].covariance[k]);
        val order=Linalg.decreasing(eigen.values);
        val sorted=DoubleArray(dimension) {
            eigen.values[order[it]]
        };
        section+="class ${data.classes[k]} log_det ${Plot.real(models[2].logDet[k])} eigenvalues ${Plot.reals(sorted)} condition ${Plot.real(sorted[0]/sorted[dimension-1])}";
        for(row in models[2].covariance[k])section+="  ${Plot.reals(row)}"
    };
    Plot.section(output,section);
    section=mutableListOf("separation");
    for(a in 0 until classes)for(b in a+1 until classes) {
        val delta=DoubleArray(dimension) {
            stats.means[a][it]-stats.means[b][it]
        };
        val mean=Linalg.zeros(dimension);
        for(i in 0 until dimension)for(j in 0 until dimension)mean[i][j]=(models[2].covariance[a][i][j]+models[2].covariance[b][i][j])/2;
        val lower=Linalg.cholesky(mean);
        val distance=Linalg.quadratic(lower,delta)/8+(Linalg.logDet(lower)-(models[2].logDet[a]+models[2].logDet[b])/2)/2;
        section+="${data.classes[a]} ${data.classes[b]} mahalanobis ${Plot.real(sqrt(Linalg.quadratic(models[1].factors[0],delta)))} bhattacharyya ${Plot.real(distance)}"
    };
    Plot.section(output,section);
    val outliers=mutableListOf<Distance>();
    for(i in data.train.indices) {
        val r=data.train[i];
        val q=models[2].distances(r.values)[r.y];
        if(q>settings.theta)outliers+=Distance(i,q,r.y)
    };
    sortDistances(outliers);
    section=mutableListOf("outliers threshold ${Plot.real(settings.theta)}");
    for(d in outliers) {
        val r=data.train[d.index];
        section+="${r.id} ${r.label} q ${Plot.real(d.q)}"
    };
    section+="count ${outliers.size}";
    Plot.section(output,section);
    Plot.write("models.txt",output)
}
private fun predictionsReport() {
    val output=mutableListOf("id,model,actual,predicted,decision,"+data.classes.joinToString(","));
    for(i in data.test.indices)for(k in 0..2) {
        val r=data.test[i];
        val p=test[k][i];
        output+="${r.id},${GaussianModels.NAMES[k]},${r.label},${data.classes[p.predicted]},${data.classes[p.decision]},"+p.posterior.joinToString(",") {
            Plot.real(it)
        }
    };
    Plot.write("predictions.csv",output)
}
private fun evaluate(kind: Int): List<String> {
    val m=Evaluation.measures(data.test,predictions[kind],classes);
    val output=mutableListOf("model ${GaussianModels.NAMES[kind]}");
    confusion(output,m);
    output+=listOf("accuracy ${Plot.fraction(m.accuracy)}","balanced_accuracy ${Plot.fraction(m.balanced)}","kappa ${Plot.fraction(m.kappa)}");
    for(k in 0 until classes)output+="class ${data.classes[k]} support ${m.support[k]} recall ${Plot.fraction(m.recall[k])} precision ${Plot.fraction(m.precision[k])} f1 ${Plot.fraction(m.f1[k])}";
    var loss=0.0;
    for(i in data.test.indices)loss+=test[kind][i].logPosterior[data.test[i].y];
    output+="macro_f1 ${Plot.real(m.macro)}";
    output+="log_loss ${Plot.real(-loss/data.test.size)}";
    output+="errors ${data.test.size-m.correct}";
    for(i in data.test.indices)if(predictions[kind][i]!=data.test[i].y) {
        val r=data.test[i];
        output+="error ${r.id} actual ${r.label} predicted ${data.classes[predictions[kind][i]]} confidence ${Plot.real(test[kind][i].confidence)}"
    };
    val edges=doubleArrayOf(0.0)+settings.edges+doubleArrayOf(1.0);
    var ece=0.0;
    for(bin in 0 until edges.size-1) {
        var count=0;
        var correct=0;
        var sum=0.0;
        for(i in data.test.indices) {
            val confidence=test[kind][i].confidence;
            if(confidence>=edges[bin]&&(confidence<edges[bin+1]||bin==edges.size-2)) {
                count++;
                sum+=confidence;
                if(predictions[kind][i]==data.test[i].y)correct++
            }
        };
        output+="bin ${Plot.real(edges[bin])} ${Plot.real(edges[bin+1])} count $count confidence ${if(count==0)"-" else Plot.real(sum/count)} accuracy ${Plot.ratio(correct.toLong(),count.toLong())}";
        ece+=abs(correct-sum)
    };
    output+="ece ${Plot.real(ece/data.test.size)}";
    for(threshold in settings.reject) {
        var count=0;
        var correct=0;
        for(i in data.test.indices)if(test[kind][i].confidence>=threshold) {
            count++;
            if(predictions[kind][i]==data.test[i].y)correct++
        };
        output+="reject ${Plot.real(threshold)} accepted $count coverage ${Plot.ratio(count.toLong(),data.test.size.toLong())} accuracy ${Plot.ratio(correct.toLong(),count.toLong())}"
    };
    return output
}
private fun bootstrap(): List<String> {
    val n=data.test.size;
    val b=settings.resamples;
    val random=Evaluation.Random(settings.seed.toLong());
    val counts=Array(3) {
        IntArray(b)
    };
    for(r in 0 until b)for(i in 0 until n) {
        val index=(random.draw()%n).toInt();
        for(k in 0..2)if(predictions[k][index]==data.test[index].y)counts[k][r]++
    };
    val output=mutableListOf("bootstrap resamples $b seed ${settings.seed}");
    for(k in 0..2) {
        val sorted=counts[k].sorted();
        var sum=0L;
        for(v in counts[k])sum+=v;
        val tail=b/40;
        output+="${GaussianModels.NAMES[k]} mean ${Plot.real(sum.toDouble()/b/n)} interval ${Plot.ratio(sorted[tail].toLong(),n.toLong())} ${Plot.ratio(sorted[b-tail-1].toLong(),n.toLong())}"
    };
    for(a in 0..2)for(c in a+1..2) {
        var wins=0;
        var ties=0;
        var losses=0;
        for(r in 0 until b)if(counts[a][r]>counts[c][r])wins++ else if(counts[a][r]==counts[c][r])ties++ else losses++;
        output+="${GaussianModels.NAMES[a]} ${GaussianModels.NAMES[c]} wins $wins ties $ties losses $losses"
    };
    return output
}
private fun evaluationReport() {
    val output=mutableListOf("test rows ${data.test.size}");
    for(k in 0..2)Plot.section(output,evaluate(k));
    Plot.section(output,listOf("ensemble soft_vote",summary(Evaluation.measures(data.test,predictions[3],classes))));
    var section=mutableListOf("mcnemar test");
    val names=GaussianModels.NAMES+"ENSEMBLE";
    for(a in 0..3)for(b in a+1..3)section+=comparison(names[a],names[b],data.test,predictions[a],predictions[b]);
    Plot.section(output,section);
    section=mutableListOf("costs");
    for(k in 0..2) {
        var argmax=0.0;
        var decision=0.0;
        var changed=0;
        var correct=0;
        for(i in data.test.indices) {
            val actual=data.test[i].y;
            val p=test[k][i];
            argmax+=data.costs[actual][p.predicted];
            decision+=data.costs[actual][p.decision];
            if(p.decision!=p.predicted)changed++;
            if(p.decision==actual)correct++
        };
        section+="${GaussianModels.NAMES[k]} argmax_total ${Plot.real(argmax)} decision_total ${Plot.real(decision)} changed $changed decision_accuracy ${Plot.ratio(correct.toLong(),data.test.size.toLong())}"
    };
    Plot.section(output,section);
    val novel=mutableListOf<Distance>();
    for(i in data.test.indices) {
        val q=models[2].distances(data.test[i].values);
        val nearest=GaussianModels.argmin(q);
        if(q[nearest]>settings.theta)novel+=Distance(i,q[nearest],nearest)
    };
    sortDistances(novel);
    section=mutableListOf("novelty threshold ${Plot.real(settings.theta)}");
    for(d in novel)section+="${data.test[d.index].id} nearest ${data.classes[d.nearest]} q ${Plot.real(d.q)}";
    section+="count ${novel.size}";
    Plot.section(output,section);
    Plot.section(output,bootstrap());
    val alternative=if(settings.prior=="empirical")"uniform" else "empirical";
    section=mutableListOf("prior_sensitivity alternative $alternative");
    for(k in 0..2) {
        val p=predict(train(k,all,data.train,prior=alternative),data.test);
        val m=Evaluation.measures(data.test,p,classes);
        val changed=p.indices.count {
            p[it]!=predictions[k][it]
        };
        section+="${GaussianModels.NAMES[k]} accuracy ${Plot.fraction(m.accuracy)} balanced_accuracy ${Plot.fraction(m.balanced)} changed $changed"
    };
    Plot.section(output,section);
    section=mutableListOf("learning_curve");
    for(size in settings.curve) {
        val seen=IntArray(classes);
        val rows=mutableListOf<Dataset.Row>();
        for(r in data.train) {
            if(seen[r.y]<size)rows+=r;
            seen[r.y]++
        };
        var line="size $size rows ${rows.size}";
        for(k in 0..2)line+=" ${GaussianModels.NAMES[k]} ${Plot.ratio(correct(data.test,predict(train(k,all,rows),data.test)).toLong(),data.test.size.toLong())}";
        section+=line
    };
    Plot.section(output,section);
    val foldSizes=IntArray(settings.folds);
    for(r in data.train)foldSizes[r.id%settings.folds]++;
    section=mutableListOf("cross_validation folds ${settings.folds}","fold_sizes ${integers(foldSizes)}");
    var best: Dataset.Subset?=null;
    var bestKind=0;
    var bestCorrect=-1;
    for(subset in settings.subsets) {
        section+="subset ${subset.name} features ${features(subset.features)}";
        for(k in 0..2) {
            val result=cv(k,subset.features);
            section+="  ${GaussianModels.NAMES[k]} fold_correct ${integers(result.folds)} correct ${result.correct} accuracy ${Plot.ratio(result.correct.toLong(),data.train.size.toLong())}";
            if(result.correct>bestCorrect||(result.correct==bestCorrect&&subset.features.size<best!!.features.size)) {
                best=subset;
                bestKind=k;
                bestCorrect=result.correct
            }
        }
    };
    val chosenSubset=best!!;
    section+="best subset ${chosenSubset.name} model ${GaussianModels.NAMES[bestKind]} correct $bestCorrect accuracy ${Plot.ratio(bestCorrect.toLong(),data.train.size.toLong())}";
    val refit=correct(data.test,predict(train(bestKind,chosenSubset.features,data.train),data.test));
    section+="refit_test correct $refit accuracy ${Plot.ratio(refit.toLong(),data.test.size.toLong())}";
    Plot.section(output,section);
    section=mutableListOf("mcnemar cross_validation");
    for(a in 0..2)for(b in a+1..2)section+=comparison(GaussianModels.NAMES[a],GaussianModels.NAMES[b],data.train,mainCv[a].predicted,mainCv[b].predicted);
    Plot.section(output,section);
    for(k in 0..2) {
        val m=Evaluation.measures(data.train,mainCv[k].predicted,classes);
        section=mutableListOf("cv_confusion model ${GaussianModels.NAMES[k]}");
        confusion(section,m);
        section+="balanced_accuracy ${Plot.fraction(m.balanced)} kappa ${Plot.fraction(m.kappa)}";
        Plot.section(output,section)
    };
    section=mutableListOf("leave_one_out");
    for(k in 0..2) {
        var correct=0;
        for(i in data.train.indices) {
            val rows=data.train.toMutableList();
            val excluded=rows.removeAt(i);
            if(train(k,all,rows).predict(excluded.values)==excluded.y)correct++
        };
        section+="${GaussianModels.NAMES[k]} correct $correct accuracy ${Plot.ratio(correct.toLong(),data.train.size.toLong())}"
    };
    Plot.section(output,section);
    for(k in 0..2) {
        section=mutableListOf("forward_selection model ${GaussianModels.NAMES[k]}");
        val selected=mutableListOf<Int>();
        var bestStep=0;
        var bestScore=-1;
        while(selected.size<dimension) {
            var chosen=-1;
            var score=-1;
            for(f in 0 until dimension)if(f !in selected) {
                val candidate=(selected+f).toIntArray();
                val result=cv(k,candidate).correct;
                if(result>score) {
                    score=result;
                    chosen=f
                }
            };
            selected+=chosen;
            val step=selected.size;
            section+="step $step add ${data.features[chosen]} correct $score accuracy ${Plot.ratio(score.toLong(),data.train.size.toLong())}";
            if(score>bestScore) {
                bestScore=score;
                bestStep=step
            }
        };
        section+="best_step $bestStep features ${features(selected.take(bestStep).toIntArray())}";
        Plot.section(output,section)
    };
    for(kind in listOf(0,2)) {
        val grid=if(kind==0)settings.smoothing else settings.gammas;
        section=mutableListOf(if(kind==0)"nb_smoothing_path" else "qda_gamma_path");
        var bestScore=-1;
        var bestValue=0.0;
        for(value in grid) {
            val result=cv(kind,all,if(kind==0)value else settings.epsilon,if(kind==2)value else settings.gamma);
            section+="value ${Plot.real(value)} correct ${result.correct} accuracy ${Plot.ratio(result.correct.toLong(),data.train.size.toLong())}";
            if(result.correct>=bestScore) {
                bestScore=result.correct;
                bestValue=value
            }
        };
        val model=train(kind,all,data.train,if(kind==0)bestValue else settings.epsilon,if(kind==2)bestValue else settings.gamma);
        val score=correct(data.test,predict(model,data.test));
        section+="best ${Plot.real(bestValue)} test correct $score accuracy ${Plot.ratio(score.toLong(),data.test.size.toLong())}";
        Plot.section(output,section)
    };
    Plot.write("evaluation.txt",output)
}
private fun letter(k: Int,upper: Boolean): Char {
    val c=data.classes[k][0];
    return if(upper)c.uppercaseChar() else c
}
private fun boundariesReport() {
    val output=mutableListOf<String>();
    for(pair in settings.pairs) {
        var xmin=Double.POSITIVE_INFINITY;
        var xmax=Double.NEGATIVE_INFINITY;
        var ymin=Double.POSITIVE_INFINITY;
        var ymax=Double.NEGATIVE_INFINITY;
        for(r in data.train) {
            xmin=minOf(xmin,r.values[pair[0]]);
            xmax=maxOf(xmax,r.values[pair[0]]);
            ymin=minOf(ymin,r.values[pair[1]]);
            ymax=maxOf(ymax,r.values[pair[1]])
        };
        val width=settings.width;
        val height=settings.height;
        val dx=(xmax-xmin)/(width-1);
        val dy=(ymax-ymin)/(height-1);
        val section=mutableListOf("pair ${features(pair)}","x ${data.features[pair[0]]} ${Plot.real(xmin)} ${Plot.real(xmax)} y ${data.features[pair[1]]} ${Plot.real(ymin)} ${Plot.real(ymax)} grid ${width}x$height");
        val maps=Array(3) {
            Plot.grid(width,height)
        };
        val confidences=Array(height) {
            DoubleArray(width)
        };
        for(k in 0..2) {
            val model=train(k,pair,data.train);
            val map=maps[k];
            val counts=IntArray(classes);
            for(row in 0 until height)for(col in 0 until width) {
                val p=model.inferVector(doubleArrayOf(xmin+col*dx,ymax-row*dy),null);
                map[row][col]=letter(p.predicted,true);
                counts[p.predicted]++;
                if(k==2)confidences[row][col]=p.confidence
            };
            section+="model ${GaussianModels.NAMES[k]} train_accuracy ${Plot.ratio(correct(data.train,predict(model,data.train)).toLong(),data.train.size.toLong())} cv_accuracy ${Plot.ratio(cv(k,pair).correct.toLong(),data.train.size.toLong())}";
            section+=Plot.frame(map);
            var line="cells";
            for(c in 0 until classes)line+=" ${letter(c,true)} ${counts[c]}";
            section+=line
        };
        val agreement=Plot.grid(width,height);
        val uncertainty=Plot.grid(width,height);
        val points=Plot.grid(width,height);
        var disagreement=0;
        for(row in 0 until height)for(col in 0 until width) {
            val distinct=(0..2).map {
                maps[it][row][col]
            }.toSet();
            agreement[row][col]=if(distinct.size==1)'.' else ('0'.code+distinct.size).toChar();
            if(distinct.size>1)disagreement++;
            val u=(1-confidences[row][col])/(1-1.0/classes);
            val level=minOf(9,floor(10*u).toInt());
            uncertainty[row][col]=" .:-=+*#%@"[level]
        };
        for(r in data.train)Plot.place(points,Plot.cell(r.values[pair[0]],xmin,xmax,width),
            height-1-Plot.cell(r.values[pair[1]],ymin,ymax,height),letter(r.y,false));
        section+="agreement";
        section+=Plot.frame(agreement);
        section+="disagreement_cells $disagreement";
        section+="uncertainty QDA";
        section+=Plot.frame(uncertainty);
        section+="points";
        section+=Plot.frame(points);
        Plot.section(output,section)
    };
    Plot.write("boundaries.txt",output)
}
private fun project(values: DoubleArray,directions: Array<DoubleArray>,center: DoubleArray): DoubleArray {
    val result=DoubleArray(2);
    for(t in 0..1)for(j in 0 until dimension)result[t]+=directions[t][j]*(values[j]-center[j]);
    return result
}
private fun nearestCorrect(rows: List<Dataset.Row>,directions: Array<DoubleArray>,center: DoubleArray,centroids: Array<DoubleArray>,dimensions: Int): Int {
    var count=0;
    for(r in rows) {
        val point=project(r.values,directions,center);
        val distance=DoubleArray(classes);
        for(k in 0 until classes)for(t in 0 until dimensions) {
            val difference=point[t]-centroids[k][t];
            distance[k]+=difference*difference
        };
        if(GaussianModels.argmin(distance)==r.y)count++
    };
    return count
}
private fun projectionReport() {
    val stats=models[0].statistics;
    val within=Linalg.zeros(dimension);
    val between=Linalg.zeros(dimension);
    for(a in 0 until dimension)for(b in 0 until dimension)for(k in 0 until classes) {
        within[a][b]+=stats.scatter[k][a][b];
        between[a][b]+=stats.counts[k]*(stats.means[k][a]-stats.center[a])*(stats.means[k][b]-stats.center[b])
    };
    val f=DoubleArray(dimension) {
        j->(between[j][j]/(classes-1))/(within[j][j]/(data.train.size-classes))
    };
    val output=mutableListOf("univariate");
    val rank=Linalg.decreasing(f);
    for(i in 0 until dimension) {
        val j=rank[i];
        output+="rank ${i+1} ${data.features[j]} f ${Plot.real(f[j])} between ${Plot.real(between[j][j])} within ${Plot.real(within[j][j])}"
    };
    val lower=Linalg.cholesky(within);
    val y=Linalg.zeros(dimension);
    val z=Linalg.zeros(dimension);
    val symmetric=Linalg.zeros(dimension);
    for(j in 0 until dimension) {
        val column=DoubleArray(dimension) {
            between[it][j]
        };
        val solved=Linalg.forward(lower,column);
        for(i in 0 until dimension)y[i][j]=solved[i]
    };
    for(i in 0 until dimension) {
        val solved=Linalg.forward(lower,y[i]);
        for(j in 0 until dimension)z[j][i]=solved[j]
    };
    for(a in 0 until dimension)for(b in 0 until dimension)symmetric[a][b]=(z[a][b]+z[b][a])/2;
    val eigen=Linalg.jacobi(symmetric);
    val order=Linalg.decreasing(eigen.values);
    var total=0.0;
    for(value in eigen.values)total+=value;
    val sorted=DoubleArray(dimension) {
        eigen.values[order[it]]
    };
    val ratios=DoubleArray(dimension) {
        sorted[it]/total
    };
    var section=mutableListOf("fisher features ${data.features.joinToString(" ")}","center ${Plot.reals(stats.center)}",
        "sweeps ${eigen.sweeps}","eigenvalues ${Plot.reals(sorted)}","ratios ${Plot.reals(ratios)}");
    val directions=Array(2) {
        DoubleArray(dimension)
    };
    for(t in 0..1) {
        val vector=DoubleArray(dimension) {
            eigen.vectors[it][order[t]]
        };
        val v=Linalg.backward(lower,vector);
        val norm=sqrt(Linalg.dot(v,v));
        var largest=0;
        for(j in 0 until dimension) {
            v[j]/=norm;
            if(abs(v[j])>abs(v[largest]))largest=j
        };
        if(v[largest]<0)for(j in 0 until dimension)v[j]=-v[j];
        directions[t]=v;
        val standardized=DoubleArray(dimension) {
            v[it]*sqrt(models[1].covariance[0][it][it])
        };
        section+="direction ${t+1} ${Plot.reals(v)}";
        section+="standardized ${t+1} ${Plot.reals(standardized)}"
    };
    val centroids=Array(classes) {
        DoubleArray(2)
    };
    for(k in 0 until classes) {
        centroids[k]=project(stats.means[k],directions,stats.center);
        val spread=DoubleArray(2);
        for(t in 0..1) {
            var sum=0.0;
            for(r in data.train)if(r.y==k) {
                val difference=project(r.values,directions,stats.center)[t]-centroids[k][t];
                sum+=difference*difference
            };
            spread[t]=sqrt(sum/stats.counts[k])
        };
        section+="centroid ${data.classes[k]} ${Plot.reals(centroids[k])} spread ${Plot.reals(spread)}"
    };
    for(dims in 1..2)section+="nearest_centroid dims $dims train ${Plot.ratio(nearestCorrect(data.train,directions,stats.center,centroids,dims).toLong(),data.train.size.toLong())} test ${Plot.ratio(nearestCorrect(data.test,directions,stats.center,centroids,dims).toLong(),data.test.size.toLong())}";
    Plot.section(output,section);
    val points=Array(data.train.size) {
        project(data.train[it].values,directions,stats.center)
    };
    val lo1=points.minOf {
        it[0]
    };
    val hi1=points.maxOf {
        it[0]
    };
    val lo2=points.minOf {
        it[1]
    };
    val hi2=points.maxOf {
        it[1]
    };
    val width=settings.plotWidth;
    val height=settings.plotHeight;
    val grid=Plot.grid(width,height);
    for(i in data.train.indices)Plot.place(grid,Plot.cell(points[i][0],lo1,hi1,width),height-1-Plot.cell(points[i][1],
        lo2,hi2,height),letter(data.train[i].y,false));
    for(k in 0 until classes)grid[height-1-Plot.cell(centroids[k][1],lo2,hi2,height)][Plot.cell(centroids[k][0],lo1,hi1,width)]=letter(k,true);
    section=mutableListOf("plot x ${Plot.real(lo1)} ${Plot.real(hi1)} y ${Plot.real(lo2)} ${Plot.real(hi2)} size ${width}x$height");
    section+=Plot.frame(grid);
    Plot.section(output,section);
    Plot.write("projection.txt",output)
}
fun main() {
    data=Dataset.read();
    settings=data.settings;
    classes=data.classes.size;
    dimension=data.features.size;
    all=IntArray(dimension) {
        it
    };
    models=Array(3) {
        train(it,all,data.train)
    };
    mainCv=Array(3) {
        cv(it,all)
    };
    test=Array(3) {
        k->Array(data.test.size) {
            i->models[k].infer(data.test[i].values,data.costs)
        }
    };
    predictions=Array(4) {
        IntArray(data.test.size)
    };
    for(k in 0..2)for(i in data.test.indices)predictions[k][i]=test[k][i].predicted;
    for(i in data.test.indices) {
        val posterior=DoubleArray(classes);
        for(c in 0 until classes) {
            for(k in 0..2)posterior[c]+=test[k][i].posterior[c];
            posterior[c]/=3.0
        };
        predictions[3][i]=GaussianModels.argmax(posterior)
    };
    modelReport();
    predictionsReport();
    evaluationReport();
    boundariesReport();
    projectionReport()
}
