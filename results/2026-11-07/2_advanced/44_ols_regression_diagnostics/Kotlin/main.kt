import java.io.File
import kotlin.math.*

private lateinit var data: Dataframe.Data
private lateinit var settings: Dataframe.Settings
private val analyses=mutableListOf<Analysis>()
private fun real(value: Double)=Inference.real(value)
private fun pvalue(value: Double)=Inference.pvalue(value)
private fun integer(value: Int)=value.toString()
private fun write(name: String,lines: List<String>) {
    File("output/$name").writeText(lines.joinToString("\n",postfix="\n"),Charsets.US_ASCII)
}
private data class TableRow(val fields: List<String>,val mark: String)
private fun plain(vararg fields: String)=TableRow(fields.toList(),"")
private fun marked(mark: String,vararg fields: String)=TableRow(fields.toList(),mark)
private fun table(header: List<String>,rows: List<TableRow>): List<String> {
    val widths=IntArray(header.size);
    val all=listOf(TableRow(header,""))+rows;
    for(row in all)for(c in row.fields.indices)widths[c]=maxOf(widths[c],row.fields[c].length);
    return all.map {
        row->var line="";
        for(c in row.fields.indices) {
            val field=row.fields[c];
            val padding=" ".repeat(widths[c]-field.length);
            line+=if(c==0)field+padding else "  "+padding+field
        };
        if(row.mark.isNotEmpty())line+=" "+row.mark;
        line.trimEnd()
    }
}
private class Stats(fit: QrSolver.Fit,y: DoubleArray,w: DoubleArray) {
    val n=y.size;
    val rank=fit.rank;
    val degrees=n-rank;
    val sigma=sqrt(fit.rss/degrees);
    var sumWeights=0.0;
    var total=0.0;
    val r2: Double;
    val adjusted: Double;
    val f: Double;
    val fp: Double;
    val likelihood: Double;
    val aic: Double;
    val bic: Double;
    var press=0.0;
    val predicted: Double
    init {
        var weighted=0.0;
        var logWeights=0.0;
        for(i in 0 until n) {
            sumWeights+=w[i];
            weighted+=w[i]*y[i];
            logWeights+=ln(w[i])
        };
        val mean=weighted/sumWeights;
        for(i in 0 until n)total+=w[i]*(y[i]-mean)*(y[i]-mean);
        r2=1-fit.rss/total;
        adjusted=1-(1-r2)*(n-1)/degrees;
        f=if(rank>1)((total-fit.rss)/(rank-1))/(fit.rss/degrees) else Double.NaN;
        fp=if(rank>1)Inference.pf(f,rank-1,degrees) else Double.NaN;
        likelihood=0.5*(logWeights-n*(ln(2*3.141592653589793)+1-ln(n.toDouble())+ln(fit.rss)));
        aic=-2*likelihood+2*(rank+1);
        bic=-2*likelihood+ln(n.toDouble())*(rank+1);
        for(i in 0 until n) {
            val v=fit.epsilon[i]/(1-fit.leverage[i]);
            press+=v*v
        };
        predicted=1-press/total
    }
}
private class Subfit(design: Formula.Design,val mask: Int) {
    val indices=design.indices(mask);
    val x=design.matrix(indices);
    val fit=QrSolver.fit(x,design.y,design.w,settings.number("RANK_TOL"));
    val stats=Stats(fit,design.y,design.w)
}
private class Analysis(model: Formula.Model) {
    val design=Formula.Design(model,data.frame);
    val cache=mutableMapOf<Int,Subfit>();
    val mask=(1 shl model.terms.size)-1;
    val full=fitted(mask);
    val diagnostics=Diagnostics.compute(full.x,design.y,design.w,full.fit,full.stats.sigma,full.stats.degrees,settings);
    val critical=Inference.quantile(settings.number("CONFIDENCE"),full.stats.degrees);
    val acceptedIndex=IntArray(design.columns.size) {
        -1
    };
    var predicted=0;
    var errors=0;
    var covered=0;
    var squaredError=0.0
    init {
        for(k in 0 until full.fit.rank)acceptedIndex[full.fit.accepted[k]]=k
    }
    fun fitted(selected: Int)=cache.getOrPut(selected) {
        Subfit(design,selected)
    }
}
private data class Drop(val term: Int,val degrees: Int,val ss: Double,val rss: Double,val f: Double,val p: Double)
private fun drops(a: Analysis,mask: Int): List<Drop> {
    val current=a.fitted(mask);
    val result=mutableListOf<Drop>();
    for(t in a.design.model.terms.indices)if(Formula.removable(a.design.model,mask,t)) {
        val removed=a.fitted(mask and (1 shl t).inv());
        val degrees=current.fit.rank-removed.fit.rank;
        val ss=removed.fit.rss-current.fit.rss;
        val f=if(degrees>0)(ss/degrees)/(current.fit.rss/current.stats.degrees) else Double.NaN;
        result+=Drop(t,degrees,ss,removed.fit.rss,f,if(degrees>0)Inference.pf(f,degrees,current.stats.degrees) else Double.NaN)
    };
    return result
}
private fun quantile(sorted: DoubleArray,probability: Double): Double {
    val position=(sorted.size-1)*probability;
    val index=floor(position).toInt();
    return if(index==sorted.size-1)sorted[index] else sorted[index]+(position-index)*(sorted[index+1]-sorted[index])
}
private fun dataSummary(): MutableList<String> {
    val frame=data.frame;
    val n=frame.rows.size;
    val output=mutableListOf("Data: $n rows, ${frame.columns.size} columns","","Numeric columns:");
    val numeric=mutableListOf<String>();
    var rows=mutableListOf<TableRow>();
    for(column in frame.columns)if(column !in data.categorical) {
        numeric+=column;
        val values=mutableListOf<Double>();
        var sum=0.0;
        for(row in frame.rows)if(row.values[column]!=null) {
            val value=row.numeric(column);
            values+=value;
            sum+=value
        };
        val mean=sum/values.size;
        var variance=0.0;
        var min=values[0];
        var max=min;
        for(value in values) {
            variance+=(value-mean)*(value-mean);
            min=minOf(min,value);
            max=maxOf(max,value)
        };
        rows+=plain(column,integer(values.size),integer(n-values.size),real(mean),real(sqrt(variance/(values.size-1))),real(min),real(max))
    };
    output+=table(listOf("column","n","missing","Mean","SD","Min","Max"),rows);
    output+="";
    output+="Categorical columns:";
    for(column in frame.columns)if(column in data.categorical) {
        val counts=sortedMapOf<String,Int>();
        var count=0;
        for(row in frame.rows) {
            val value=row.values[column];
            if(value!=null) {
                count++;
                counts[value]=counts.getOrDefault(value,0)+1
            }
        };
        val labels=counts.keys.map {
            "$it ${counts[it]}"
        };
        output+="$column: $count values, ${n-count} missing, ${counts.size} levels: ${labels.joinToString(", ")}"
    };
    output+="";
    output+="Correlations (pairwise complete observations):";
    rows=mutableListOf();
    for(left in numeric) {
        val fields=mutableListOf(left);
        for(right in numeric) {
            var sx=0.0;
            var sy=0.0;
            var count=0;
            for(row in frame.rows)if(row.values[left]!=null&&row.values[right]!=null) {
                count++;
                sx+=row.numeric(left);
                sy+=row.numeric(right)
            };
            val mx=sx/count;
            val my=sy/count;
            var xx=0.0;
            var yy=0.0;
            var xy=0.0;
            for(row in frame.rows)if(row.values[left]!=null&&row.values[right]!=null) {
                val x=row.numeric(left)-mx;
                val y=row.numeric(right)-my;
                xx+=x*x;
                yy+=y*y;
                xy+=x*y
            };
            fields+=real(xy/sqrt(xx*yy))
        };
        rows+=TableRow(fields,"")
    };
    output+=table(listOf("column")+numeric,rows);
    output+="";
    return output
}
private fun modelSummary(a: Analysis,number: Int): List<String> {
    val d=a.design;
    val fit=a.full.fit;
    val s=a.full.stats;
    val diag=a.diagnostics;
    val terms=d.model.terms.map {
        it.name
    };
    val aliases=d.columns.indices.filter {
        a.acceptedIndex[it]<0
    }.map {
        d.columns[it].name
    };
    val output=mutableListOf("Model $number: ${d.model.original}","Terms: ${terms.joinToString(", ")}",
        "Weights: ${d.model.weight?:"none"}","Observations: ${s.n} used, ${data.frame.rows.size-s.n} dropped",
        "Columns: ${d.columns.size}, rank ${fit.rank}, aliased: ${if(aliases.isEmpty())"none" else aliases.joinToString(", ")}",
        "");
    val sorted=fit.epsilon.sortedArray();
    output+="Residuals: Min ${real(sorted[0])}, 1Q ${real(quantile(sorted,0.25))}, Median ${real(quantile(sorted,0.5))}, 3Q ${real(quantile(sorted,0.75))}, Max ${real(sorted.last())}";
    output+="";
    output+="Coefficients:";
    var rows=mutableListOf<TableRow>();
    for(j in d.columns.indices) {
        val name=d.columns[j].name;
        val k=a.acceptedIndex[j];
        if(k<0)rows+=plain(name,"NA","NA","NA","NA") else {
            val se=s.sigma*sqrt(fit.variance[k]);
            val t=fit.beta[j]/se;
            val p=Inference.pt(t,s.degrees);
            rows+=marked(Inference.mark(p),name,real(fit.beta[j]),real(se),real(t),pvalue(p))
        }
    };
    output+=table(listOf("term","Estimate","Std. Error","t value","Pr(>|t|)"),rows);
    output+="---";
    output+="Signif. codes: 0 '***' 0.001 '**' 0.01 '*' 0.05 '.' 0.1 ' ' 1";
    output+="";
    output+="Residual standard error: ${real(s.sigma)} on ${s.degrees} degrees of freedom";
    output+="Multiple R-squared: ${real(s.r2)}, Adjusted R-squared: ${real(s.adjusted)}";
    output+="F-statistic: ${real(s.f)} on ${s.rank-1} and ${s.degrees} DF, p-value: ${pvalue(s.fp)}";
    output+="Log-likelihood: ${real(s.likelihood)}, AIC: ${real(s.aic)}, BIC: ${real(s.bic)}";
    output+="PRESS: ${real(s.press)}, Predicted R-squared: ${real(s.predicted)}";
    output+="";
    output+="Confidence intervals (level ${real(settings.number("CONFIDENCE"))}, t ${real(a.critical)}):";
    rows=mutableListOf();
    for(j in d.columns.indices) {
        val k=a.acceptedIndex[j];
        val half=if(k<0)Double.NaN else a.critical*(s.sigma*sqrt(fit.variance[k]));
        rows+=plain(d.columns[j].name,real(fit.beta[j]-half),real(fit.beta[j]+half))
    };
    output+=table(listOf("term","Lower","Upper"),rows);
    output+="";
    output+="Robust standard errors (HC3):";
    rows=mutableListOf();
    for(j in d.columns.indices) {
        val name=d.columns[j].name;
        val k=a.acceptedIndex[j];
        if(k<0)rows+=plain(name,"NA","NA","NA") else {
            var variance=0.0;
            for(i in 0 until s.n) {
                val omega=fit.epsilon[i]*fit.epsilon[i]/((1-fit.leverage[i])*(1-fit.leverage[i]));
                variance+=omega*fit.g[i][k]*fit.g[i][k]
            };
            val se=sqrt(variance);
            val t=fit.beta[j]/se;
            val p=Inference.pt(t,s.degrees);
            rows+=marked(Inference.mark(p),name,real(se),real(t),pvalue(p))
        }
    };
    output+=table(listOf("term","Std. Error","t value","Pr(>|t|)"),rows);
    output+="";
    output+="Analysis of variance (sequential):";
    rows=mutableListOf();
    for(t in d.model.terms.indices) {
        var degrees=0;
        var ss=0.0;
        for(k in 0 until fit.rank)if(d.columns[fit.accepted[k]].term==t) {
            degrees++;
            ss+=fit.effects[k]*fit.effects[k]
        };
        if(degrees>0) {
            val ms=ss/degrees;
            val f=ms/(fit.rss/s.degrees);
            val p=Inference.pf(f,degrees,s.degrees);
            rows+=marked(Inference.mark(p),d.model.terms[t].name,integer(degrees),real(ss),real(ms),real(f),pvalue(p))
        }
    };
    rows+=plain("Residuals",integer(s.degrees),real(fit.rss),real(fit.rss/s.degrees));
    output+=table(listOf("term","Df","Sum Sq","Mean Sq","F value","Pr(>F)"),rows);
    output+="";
    output+="Marginal F tests (drop one term):";
    rows=mutableListOf();
    for(drop in drops(a,a.mask))rows+=marked(Inference.mark(drop.p),d.model.terms[drop.term].name,
        integer(drop.degrees),real(drop.ss),real(drop.rss),real(drop.f),pvalue(drop.p));
    output+=table(listOf("term","Df","Sum Sq","RSS","F value","Pr(>F)"),rows);
    output+="";
    output+="Variance inflation factors:";
    rows=mutableListOf();
    for(k in 1 until fit.rank) {
        val x=Array(s.n) {
            DoubleArray(fit.rank-1)
        };
        val y=DoubleArray(s.n);
        var sum=0.0;
        for(i in 0 until s.n) {
            var next=0;
            for(m in 0 until fit.rank)if(m!=k)x[i][next++]=a.full.x[i][fit.accepted[m]];
            y[i]=a.full.x[i][fit.accepted[k]];
            sum+=d.w[i]*y[i]
        };
        val aux=QrSolver.fit(x,y,d.w,settings.number("RANK_TOL"));
        val mean=sum/s.sumWeights;
        var total=0.0;
        for(i in 0 until s.n)total+=d.w[i]*(y[i]-mean)*(y[i]-mean);
        val r2=1-aux.rss/total;
        val vif=1/(1-r2);
        rows+=marked(if(vif>settings.number("VIF"))"high" else "",d.columns[fit.accepted[k]].name,real(vif))
    };
    output+=table(listOf("column","VIF"),rows);
    output+="";
    output+="Diagnostics:";
    val dwLimit=settings.number("DURBIN_WATSON");
    output+="Durbin-Watson: ${real(diag.dw)} (${if(diag.dw<dwLimit)"positive autocorrelation" else if(diag.dw>4-dwLimit)"negative autocorrelation" else "no autocorrelation"})";
    output+="Breusch-Pagan: ${real(diag.bp)} on ${diag.bpDegrees} DF, p-value: ${pvalue(diag.bpP)} (${if(diag.bpP<settings.number("BREUSCH_PAGAN"))"heteroscedastic" else "homoscedastic"})";
    output+="Jarque-Bera: ${real(diag.jb)} on 2 DF, p-value: ${pvalue(diag.jbP)}, skewness ${real(diag.skewness)}, kurtosis ${real(diag.kurtosis)} (${if(diag.jbP<settings.number("NORMALITY"))"non-normal" else "normal"})";
    val resetX=Array(s.n) {
        DoubleArray(fit.rank+2)
    };
    for(i in 0 until s.n) {
        for(k in 0 until fit.rank)resetX[i][k]=a.full.x[i][fit.accepted[k]];
        resetX[i][fit.rank]=fit.fitted[i]*fit.fitted[i];
        resetX[i][fit.rank+1]=fit.fitted[i]*fit.fitted[i]*fit.fitted[i]
    };
    val reset=QrSolver.fit(resetX,d.y,d.w,settings.number("RANK_TOL"));
    val q=reset.rank-fit.rank;
    val resetDf=s.n-reset.rank;
    val resetF=((fit.rss-reset.rss)/q)/(reset.rss/resetDf);
    output+="RESET (powers 2 and 3): F ${real(resetF)} on $q and $resetDf DF, p-value: ${pvalue(Inference.pf(resetF,q,resetDf))}";
    var outlier=0;
    for(i in 1 until s.n)if(abs(diag.studentized[i])>abs(diag.studentized[outlier]))outlier=i;
    val pu=Inference.pt(diag.studentized[outlier],s.degrees-1);
    output+="Outlier test: row ${d.rows[outlier].number}, studentized ${real(diag.studentized[outlier])}, unadjusted p-value: ${pvalue(pu)}, Bonferroni p-value: ${pvalue(minOf(1.0,s.n*pu))}";
    val flags=IntArray(5);
    for(flag in diag.flags) {
        if('H' in flag)flags[0]++;
        if('O' in flag)flags[1]++;
        if('C' in flag)flags[2]++;
        if('F' in flag)flags[3]++;
        if(flag!="-")flags[4]++
    };
    output+="Flagged rows: leverage ${flags[0]}, outlier ${flags[1]}, cooks ${flags[2]}, dffits ${flags[3]}, any ${flags[4]}";
    output+="Largest Cook's distances:";
    val order=(0 until s.n).sortedWith(compareByDescending<Int> {
        diag.cooks[it]
    }.thenBy {
        it
    });
    for(position in 0 until minOf(3,s.n)) {
        val i=order[position];
        output+="row ${d.rows[i].number}: cooks_d ${real(diag.cooks[i])}, leverage ${real(fit.leverage[i])}, studentized ${real(diag.studentized[i])}, flags ${diag.flags[i]}"
    };
    output+="Largest absolute DFBETAS:";
    rows=mutableListOf();
    for(k in 0 until fit.rank) {
        var best=0;
        for(i in 1 until s.n)if(abs(diag.dfbetas[i][k])>abs(diag.dfbetas[best][k]))best=i;
        rows+=plain(d.columns[fit.accepted[k]].name,integer(d.rows[best].number),real(diag.dfbetas[best][k]))
    };
    output+=table(listOf("column","row","DFBETAS"),rows);
    return output
}
private fun predictions() {
    val output=mutableListOf("model,row,fit,se_fit,conf_lower,conf_upper,pred_lower,pred_upper,actual,error,covered");
    for(model in analyses.indices) {
        val a=analyses[model];
        val fit=a.full.fit;
        val sigma=a.full.stats.sigma;
        for(row in data.predictions.rows) {
            val prefix="${model+1},${row.number},";
            if(!a.design.predictable(row)) {
                output+=prefix+"NA,NA,NA,NA,NA,NA,NA,NA,NA";
                continue
            };
            a.predicted++;
            val x=a.design.vector(row);
            var f=0.0;
            var variance=0.0;
            for(k in 0 until fit.rank) {
                f+=x[fit.accepted[k]]*fit.beta[fit.accepted[k]];
                var u=0.0;
                for(m in 0 until fit.rank)u+=x[fit.accepted[m]]*fit.inverse[m][k];
                variance+=u*u
            };
            val se=sigma*sqrt(variance);
            val ci=a.critical*se;
            val pi=a.critical*sqrt(sigma*sigma+se*se);
            var actual="NA,NA,NA";
            if(row.values[a.design.model.response]!=null) {
                a.errors++;
                val y=row.numeric(a.design.model.response);
                val error=y-f;
                a.squaredError+=error*error;
                val covered=f-pi<=y&&y<=f+pi;
                if(covered)a.covered++;
                actual="${real(y)},${real(error)},${if(covered)"yes" else "no"}"
            };
            output+=prefix+"${real(f)},${real(se)},${real(f-ci)},${real(f+ci)},${real(f-pi)},${real(f+pi)},$actual"
        }
    };
    write("predictions.csv",output)
}
private fun summary() {
    val output=dataSummary();
    val comparison=mutableListOf<TableRow>();
    for(i in analyses.indices) {
        val a=analyses[i];
        if(i>0)output+="";
        output+=modelSummary(a,i+1);
        val s=a.full.stats;
        comparison+=plain(integer(i+1),integer(s.n),integer(s.rank),real(s.sigma),real(s.r2),real(s.adjusted),real(s.predicted),real(s.aic),real(s.bic))
    };
    output+="";
    output+="Model comparison:";
    output+=table(listOf("model","n","rank","sigma","R-squared","Adj. R-squared","Pred. R-squared","AIC","BIC"),comparison);
    output+="";
    output+="Prediction check:";
    for(i in analyses.indices) {
        val a=analyses[i];
        output+="model ${i+1}: ${a.predicted} predicted, ${a.errors} with actual values, RMSE ${real(if(a.errors==0)Double.NaN else sqrt(a.squaredError/a.errors))}, inside prediction interval ${a.covered}"
    };
    write("summary.txt",output)
}
private fun diagnosticReport() {
    val output=mutableListOf("model,row,fitted,residual,leverage,studentized,cooks_d,dffits,flags");
    for(model in analyses.indices) {
        val a=analyses[model];
        val f=a.full.fit;
        val d=a.diagnostics;
        for(i in a.design.rows.indices)output+="${model+1},${a.design.rows[i].number},${real(f.fitted[i])},${real(f.residual[i])},${real(f.leverage[i])},${real(d.studentized[i])},${real(d.cooks[i])},${real(d.dffits[i])},${d.flags[i]}"
    };
    write("diagnostics.csv",output)
}
private fun selection() {
    val a=analyses[0];
    val model=a.design.model;
    var mask=a.mask;
    var step=1;
    val n=a.design.rows.size;
    val alpha=settings.number("ALPHA_REMOVE");
    val output=mutableListOf("Backward elimination (model 1, alpha ${real(alpha)}, rows $n)");
    while(true) {
        val current=a.fitted(mask);
        output+="Step $step: ${Formula.display(model,mask)} (RSS ${real(current.fit.rss)}, df ${current.stats.degrees}, AIC ${real(current.stats.aic)})";
        if(mask==0) {
            output+="  stop: no removable terms";
            break
        };
        val candidates=drops(a,mask);
        var best=candidates[0];
        for(drop in candidates) {
            output+="  - ${model.terms[drop.term].name}: F ${real(drop.f)} on ${drop.degrees} and ${current.stats.degrees} DF, p-value ${pvalue(drop.p)}";
            if(drop.p>best.p)best=drop
        };
        if(best.p>alpha) {
            output+="  remove ${model.terms[best.term].name}";
            mask=mask and (1 shl best.term).inv();
            step++
        } else {
            output+="  stop: largest p-value ${pvalue(best.p)} is not above ${real(alpha)}";
            break
        }
    };
    output+="Final model: ${Formula.display(model,mask)}";
    output+="";
    output+="Forward selection by AIC (model 1, rows $n)";
    mask=0;
    step=1;
    while(true) {
        val current=a.fitted(mask);
        output+="Step $step: ${Formula.display(model,mask)} (AIC ${real(current.stats.aic)})";
        val candidates=mutableListOf<Int>();
        for(t in model.terms.indices)if(mask and (1 shl t)==0) {
            var valid=true;
            for(contained in model.terms.indices)if(Formula.contained(model.terms[contained],model.terms[t])&&mask and (1 shl contained)==0)valid=false;
            if(valid)candidates+=t
        };
        if(candidates.isEmpty()) {
            output+="  stop: no candidate terms remain";
            break
        };
        var best=candidates[0];
        var bestAic=a.fitted(mask or (1 shl best)).stats.aic;
        for(t in candidates) {
            val aic=a.fitted(mask or (1 shl t)).stats.aic;
            output+="  + ${model.terms[t].name}: AIC ${real(aic)}";
            if(aic<bestAic) {
                best=t;
                bestAic=aic
            }
        };
        if(bestAic<current.stats.aic) {
            output+="  add ${model.terms[best].name}";
            mask=mask or (1 shl best);
            step++
        } else {
            output+="  stop: no candidate lowers the AIC";
            break
        }
    };
    output+="Final model: ${Formula.display(model,mask)}";
    val subsets=(0..a.mask).filter {
        Formula.hierarchical(model,it)
    }.map {
        a.fitted(it)
    }.sortedWith(compareBy<Subfit> {
        it.stats.bic
    }.thenBy {
        it.mask
    });
    output+="";
    output+="Best subsets by BIC (model 1, rows $n, subsets ${subsets.size})";
    for(i in 0 until minOf(settings.integer("BEST_SUBSETS"),subsets.size)) {
        val sub=subsets[i];
        output+="${i+1}. BIC ${real(sub.stats.bic)}, AIC ${real(sub.stats.aic)}, rank ${sub.fit.rank}: ${Formula.display(model,sub.mask)}"
    };
    write("selection.txt",output)
}
private fun cells(x: DoubleArray,y: DoubleArray,lo: Double,hi: Double): Array<IntArray> {
    val w=settings.width();
    val h=settings.height();
    val limit=settings.limit();
    val counts=Array(h) {
        IntArray(w)
    };
    for(i in x.indices) {
        val col=minOf(floor((x[i]-lo)/(hi-lo)*w).toInt(),w-1);
        val row=maxOf(0,minOf(h-1,floor((limit-y[i])/(2*limit)*h).toInt()));
        counts[row][col]++
    };
    return counts
}
private fun frame(counts: Array<IntArray>): List<String> {
    val h=counts.size;
    val w=counts[0].size;
    val border="+"+"-".repeat(w)+"+";
    val output=mutableListOf(border);
    for(row in 0 until h) {
        var line="|";
        for(count in counts[row])line+=if(count>=10)"*" else if(count>0)integer(count) else if(row==h/2)"-" else ".";
        output+=line+"|"
    };
    output+=border;
    return output
}
private fun plots() {
    val output=mutableListOf<String>();
    for(model in analyses.indices) {
        val a=analyses[model];
        if(model>0)output+="";
        var min=a.full.fit.fitted[0];
        var max=min;
        var highest=0.0;
        for(value in a.full.fit.fitted) {
            min=minOf(min,value);
            max=maxOf(max,value)
        };
        for(value in a.full.fit.leverage)highest=maxOf(highest,value);
        val limit=settings.limit();
        val counts=cells(a.full.fit.fitted,a.diagnostics.studentized,min,max);
        output+="Model ${model+1}: studentized residuals vs fitted values";
        output+="fitted ${real(min)} to ${real(max)}, studentized ${real(-limit)} to ${real(limit)}";
        output+=frame(counts);
        var above=0;
        var below=0;
        var outside=0;
        for(value in a.diagnostics.studentized) {
            if(value>2)above++;
            if(value< -2)below++;
            if(abs(value)>limit)outside++
        };
        output+="points: ${a.design.rows.size}, above +2: $above, below -2: $below, outside range: $outside";
        output+="Histogram of studentized residuals:";
        val totals=IntArray(counts.size);
        var maximum=0;
        for(row in counts.indices) {
            for(count in counts[row])totals[row]+=count;
            maximum=maxOf(maximum,totals[row])
        };
        for(row in counts.indices) {
            val bar=(totals[row]*40+maximum-1)/maximum;
            output+="${real(limit-2*limit*(row+1)/counts.size)} to ${real(limit-2*limit*row/counts.size)}: ${totals[row]}"+if(bar==0)"" else " "+"#".repeat(bar)
        };
        output+="Model ${model+1}: studentized residuals vs leverage";
        output+="leverage 0.0000 to ${real(highest)}, studentized ${real(-limit)} to ${real(limit)}";
        output+=frame(cells(a.full.fit.leverage,a.diagnostics.studentized,0.0,highest))
    };
    write("residual_plot.txt",output)
}
fun main() {
    data=Dataframe.read();
    settings=data.settings;
    for(line in data.models)analyses+=Analysis(Formula.parse(line));
    predictions();
    summary();
    diagnosticReport();
    selection();
    plots()
}
