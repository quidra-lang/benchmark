import java.io.File
import java.util.Locale
import kotlin.math.*

private lateinit var subjects: List<Dataset.Subject>
private lateinit var settings: Dataset.Settings
private val groups=mutableListOf<List<Dataset.Subject>>()
private val collections=mutableListOf<CollectionSummary>()
private fun real(value: Double): String {
    if(value.isNaN())return "NA";
    val s=String.format(Locale.ROOT,"%.4f",value);
    return if(s=="-0.0000")"0.0000" else s
}
private fun one(value: Double)=String.format(Locale.ROOT,"%.1f",value)
private fun day(value: Int)=if(value<0)"NA" else value.toString()
private fun pad(s: String,width: Int)=" ".repeat(maxOf(0,width-s.length))+s
private fun reals(values: DoubleArray)=values.joinToString(" ") {
    real(it)
}
private fun section(output: MutableList<String>,part: List<String>) {
    if(output.isNotEmpty())output+="";
    output+=part
}
private fun write(name: String,lines: List<String>) {
    File("output/$name").writeText(lines.joinToString("\n",postfix="\n"),Charsets.US_ASCII)
}
private fun events(rows: List<Dataset.Subject>)=rows.sumOf {
    it.event
}
private fun level(s: Dataset.Subject,variable: String)=if(variable=="sex")s.sex else s.stage.toString()
private fun subset(rows: List<Dataset.Subject>,variable: String,value: String)=rows.filter {
    level(it,variable)==value
}
private fun levels(variable: String)=subjects.map {
    level(it,variable)
}.toSortedSet().toList()
private class CollectionSummary(val name: String,val subjects: List<Dataset.Subject>) {
    val rows=Estimators.km(subjects,false);
    val life=Estimators.life(subjects,settings.lifeWidth,settings.lifeCount);
    var events=0;
    var personDays=0;
    var maximum=0;
    var followup=-1;
    var rate=0.0;
    var rateLo=0.0;
    var rateHi=0.0;
    var lifeMedian=Double.NaN;
    var rmst=0.0;
    var se=0.0
}
private fun summarize(name: String,rows: List<Dataset.Subject>): CollectionSummary {
    val c=CollectionSummary(name,rows);
    c.events=events(rows);
    for(s in rows) {
        c.personDays+=s.time;
        c.maximum=maxOf(c.maximum,s.time)
    };
    c.rate=(1000*c.events).toDouble()/c.personDays;
    val eta=Numerics.Z/sqrt(c.events.toDouble());
    c.rateLo=exp(ln(c.rate)-eta);
    c.rateHi=exp(ln(c.rate)+eta);
    for(r in Estimators.km(rows,true))if(r.survival<=0.5) {
        c.followup=r.time;
        break
    };
    var previous=1.0;
    for(r in c.life) {
        if(r.survival<=0.5) {
            c.lifeMedian=r.start+settings.lifeWidth*(previous-0.5)/(previous-r.survival);
            break
        };
        previous=r.survival
    };
    val kept=c.rows.filter {
        it.time<=settings.tau
    };
    val tails=DoubleArray(kept.size+1);
    for(i in kept.size downTo 0) {
        val start=if(i==0)0 else kept[i-1].time;
        val end=if(i==kept.size)settings.tau else kept[i].time;
        val survival=if(i==0)1.0 else kept[i-1].survival;
        tails[i]=survival*(end-start)+(if(i==kept.size)0.0 else tails[i+1])
    };
    c.rmst=tails[0];
    var variance=0.0;
    for(i in 1 until tails.size) {
        val r=kept[i-1];
        variance+=tails[i]*tails[i]*(r.events.toDouble()/(r.risk*(r.risk-r.events)))
    };
    c.se=sqrt(variance);
    return c
}
private fun percentile(c: CollectionSummary,q: Double,field: Int): Int {
    for(r in c.rows) {
        val value=if(field==0)r.survival else if(r.survival==0.0)0.0 else if(field==1)r.lower else r.upper;
        if(value<=q)return r.time
    };
    return -1
}
private fun kmReport() {
    val output=mutableListOf<String>();
    val life=mutableListOf("group,interval,at_risk,events,withdrawn,exposed,q,survival,std_err,hazard");
    for(c in collections) {
        val block=mutableListOf("group ${c.name} subjects ${c.subjects.size} events ${c.events} censored ${c.subjects.size-c.events} max_time ${c.maximum}",
            "person_days ${c.personDays} rate ${real(c.rate)} lower ${real(c.rateLo)} upper ${real(c.rateHi)}",
            "followup_median ${day(c.followup)}","life_table_median ${real(c.lifeMedian)}");
        for(p in listOf(25,50,75)) {
            val q=1-p/100.0;
            block+="percentile $p time ${day(percentile(c,q,0))} lower ${day(percentile(c,q,1))} upper ${day(percentile(c,q,2))}"
        };
        block+="rmst tau ${settings.tau} estimate ${real(c.rmst)} se ${real(c.se)} lower ${real(c.rmst-Numerics.Z*c.se)} upper ${real(c.rmst+Numerics.Z*c.se)}";
        for(time in settings.report) {
            val r=Estimators.at(c.rows,time);
            val events=c.subjects.filter {
                it.time<=time
            }.sumOf {
                it.event
            };
            block+="at $time at_risk ${Estimators.risk(c.subjects,time)} events $events survival ${real(r.survival)} std_err ${real(r.se)} lower ${real(r.lower)} upper ${real(r.upper)} cum_hazard ${real(r.hazard)} hazard_se ${real(r.hazardSe)}"
        };
        block+=listOf("time","at_risk","events","censored","survival","std_err","lower","upper","cum_haz","haz_se").joinToString("") {
            pad(it,9)
        };
        for(r in c.rows)block+=listOf(r.time.toString(),r.risk.toString(),r.events.toString(),
            r.censored.toString(),real(r.survival),real(r.se),real(r.lower),real(r.upper),real(r.hazard),
            real(r.hazardSe)).joinToString("") {
            pad(it,9)
        };
        section(output,block);
        for(r in c.life)life+="${c.name},${r.start}-${r.end},${r.risk},${r.events},${r.withdrawn},${one(r.exposed2/2.0)},${real(r.q)},${real(r.survival)},${real(r.se)},${real(r.hazard)}"
    };
    write("km_tables.txt",output);
    write("life_table.csv",life)
}
private fun baseline(): MutableList<String> {
    val output=mutableListOf("baseline");
    for(c in collections) {
        val n=c.subjects.size;
        var sum=0;
        var male=0;
        val stage=IntArray(4);
        val ages=mutableListOf<Int>();
        for(s in c.subjects) {
            sum+=s.age;
            if(s.sex=="M")male++;
            stage[s.stage-1]++;
            ages+=s.age
        };
        val mean=sum.toDouble()/n;
        var variance=0.0;
        for(s in c.subjects)variance+=(s.age-mean)*(s.age-mean);
        ages.sort();
        val median=(ages[(n-1)/2]+ages[n/2])/2.0;
        output+="  group ${c.name} subjects $n age_mean ${real(mean)} age_sd ${real(sqrt(variance/(n-1)))} age_median ${one(median)} male $male stage ${stage.joinToString(" ")}"
    };
    val sorted=subjects.sortedWith(compareBy<Dataset.Subject> {
        it.age
    }.thenBy {
        it.id
    });
    val ranks=mutableMapOf<Int,Double>();
    var position=0;
    var ties=0;
    while(position<sorted.size) {
        var end=position+1;
        while(end<sorted.size&&sorted[end].age==sorted[position].age)end++;
        val t=end-position;
        ties+=t*t*t-t;
        val rank=(position+1+end)/2.0;
        for(i in position until end)ranks[sorted[i].id]=rank;
        position=end
    };
    val rankSum=DoubleArray(groups.size);
    for(s in subjects)rankSum[settings.groups.indexOf(s.group)]+=ranks.getValue(s.id);
    var sum=0.0;
    for(g in groups.indices)sum+=rankSum[g]*rankSum[g]/groups[g].size;
    val n=subjects.size;
    val w0=12*sum/(n*(n+1))-3*(n+1);
    val w=w0/(1-ties.toDouble()/(n*n*n-n));
    output+="  age kruskal_wallis chisq ${real(w)} df ${groups.size-1} p ${real(Numerics.pvalue(w,groups.size-1))}";
    for(variable in listOf("sex","stage")) {
        val levels=levels(variable);
        var chi2=0.0;
        for(g in groups.indices)for(value in levels) {
            val observed=subset(groups[g],variable,value).size;
            val column=subset(subjects,variable,value).size;
            val expected=(groups[g].size*column).toDouble()/n;
            chi2+=(observed-expected)*(observed-expected)/expected
        };
        val df=(groups.size-1)*(levels.size-1);
        output+="  $variable chisq ${real(chi2)} df $df p ${real(Numerics.pvalue(chi2,df))}"
    };
    return output
}
private fun testLine(prefix: String,r: GroupTests.Result)="$prefix chisq ${real(r.chi2)} df ${r.degrees} p ${real(r.pvalue)}"
private fun groupLines(output: MutableList<String>,r: GroupTests.Result) {
    for(g in r.groups.indices)output+="  group ${r.groups[g]} events ${r.events[g]} observed ${real(r.observed[g])} expected ${real(r.expected[g])} o_minus_e ${real(r.observed[g]-r.expected[g])} variance ${real(r.covariance[g][g])}"
}
private class Pair(val test: GroupTests.Result,val a: Int,val b: Int) {
    var hr=0.0;
    var phi=0.0;
    var lower=0.0;
    var upper=0.0;
    var adjusted=0.0
}
private fun pair(rows: List<Dataset.Subject>,a: Int,b: Int): Pair {
    val result=Pair(GroupTests.weighted(rows,listOf(settings.groups[a],settings.groups[b]),0,subjects.size),a,b);
    val o=result.test.observed;
    val x=result.test.expected;
    result.hr=(o[1]/x[1])/(o[0]/x[0]);
    result.phi=1/x[0]+1/x[1];
    val log=ln(result.hr);
    val se=sqrt(result.phi);
    result.lower=exp(log-Numerics.Z*se);
    result.upper=exp(log+Numerics.Z*se);
    return result
}
private fun pairRows(rows: List<Dataset.Subject>,a: Int,b: Int)=rows.filter {
    it.group==settings.groups[a]||it.group==settings.groups[b]
}
private fun difference(delta: Double,se: Double): String {
    val z=delta/se;
    return "difference ${real(delta)} se ${real(se)} lower ${real(delta-Numerics.Z*se)} upper ${real(delta+Numerics.Z*se)} z ${real(z)} p ${real(Numerics.pvalue(z*z,1))}"
}
private fun testsReport() {
    val output=baseline();
    var part=mutableListOf<String>();
    var logrank: GroupTests.Result?=null;
    for(weight in 0..2) {
        val r=GroupTests.weighted(subjects,settings.groups,weight,subjects.size);
        part+=testLine("test ${GroupTests.WEIGHTS[weight]}",r);
        groupLines(part,r);
        if(weight==0)logrank=r
    };
    val lr=logrank!!;
    var u=0.0;
    var variance=0.0;
    for(g in groups.indices) {
        u+=(g+1)*(lr.observed[g]-lr.expected[g]);
        var inner=0.0;
        for(h in groups.indices)inner+=(g+1)*(h+1)*lr.covariance[g][h];
        variance+=inner
    };
    val trend=u*u/variance;
    part+="test logrank_trend chisq ${real(trend)} df 1 p ${real(Numerics.pvalue(trend,1))}";
    section(output,part);
    part=mutableListOf();
    val strata=levels(settings.strata);
    for(weight in 0..2) {
        val results=mutableListOf<GroupTests.Result>();
        val rows=mutableListOf<List<Dataset.Subject>>();
        for(level in strata) {
            val stratum=subset(subjects,settings.strata,level);
            rows+=stratum;
            results+=GroupTests.weighted(stratum,settings.groups,weight,subjects.size)
        };
        val combined=GroupTests.combined(results,settings.groups);
        part+=testLine("stratified ${GroupTests.WEIGHTS[weight]} by ${settings.strata}",combined);
        for(i in strata.indices) {
            val r=results[i];
            part+="  stratum ${strata[i]} subjects ${rows[i].size} events ${events(rows[i])} chisq ${real(r.chi2)} p ${real(r.pvalue)}"
        };
        groupLines(part,combined)
    };
    section(output,part);
    val landmark=subjects.filter {
        it.time>settings.landmark
    };
    val lm=GroupTests.weighted(landmark,settings.groups,0,subjects.size);
    part=mutableListOf(testLine("landmark ${settings.landmark} subjects ${landmark.size}",lm));
    groupLines(part,lm);
    section(output,part);
    val pairs=mutableListOf<Pair>();
    for(a in groups.indices)for(b in a+1 until groups.size)pairs+=pair(pairRows(subjects,a,b),a,b);
    val order=pairs.indices.sortedWith(compareBy<Int> {
        pairs[it].test.pvalue
    }.thenBy {
        it
    });
    var previous=0.0;
    for(r in order.indices) {
        val p=pairs[order[r]];
        p.adjusted=maxOf(previous,minOf(1.0,(pairs.size-r)*p.test.pvalue));
        previous=p.adjusted
    };
    part=mutableListOf("pairwise logrank adjust holm");
    for(p in pairs)part+="  ${settings.groups[p.a]} ${settings.groups[p.b]} chisq ${real(p.test.chi2)} p ${real(p.test.pvalue)} p_holm ${real(p.adjusted)} hr ${real(p.hr)} lower ${real(p.lower)} upper ${real(p.upper)}";
    section(output,part);
    part=mutableListOf("subgroups reference ${settings.groups[0]}");
    for(variable in settings.subgroups)for(b in 1 until groups.size) {
        val levels=levels(variable);
        val estimates=mutableListOf<Pair>();
        for(level in levels) {
            val rows=pairRows(subset(subjects,variable,level),0,b);
            val p=pair(rows,0,b);
            estimates+=p;
            part+="  $variable $level ${settings.groups[b]} subjects ${rows.size} events ${events(rows)} hr ${real(p.hr)} lower ${real(p.lower)} upper ${real(p.upper)} p ${real(p.test.pvalue)}"
        };
        var numerator=0.0;
        var denominator=0.0;
        for(p in estimates) {
            numerator+=(1/p.phi)*ln(p.hr);
            denominator+=1/p.phi
        };
        val mean=numerator/denominator;
        var q=0.0;
        for(p in estimates) {
            val delta=ln(p.hr)-mean;
            q+=(1/p.phi)*delta*delta
        };
        val df=levels.size-1;
        part+="  $variable ${settings.groups[b]} heterogeneity chisq ${real(q)} df $df p ${real(Numerics.pvalue(q,df))}"
    };
    section(output,part);
    val control=collections[0];
    part=mutableListOf("rmst_difference tau ${settings.tau} reference ${control.name}");
    for(g in 1 until groups.size) {
        val c=collections[g];
        part+="  ${c.name} ${difference(c.rmst-control.rmst,sqrt(c.se*c.se+control.se*control.se))}"
    };
    section(output,part);
    part=mutableListOf("rate_ratio reference ${control.name}");
    for(g in 1 until groups.size) {
        val c=collections[g];
        val ratio=c.rate/control.rate;
        val se=sqrt(1.0/c.events+1.0/control.events);
        val log=ln(ratio);
        val z=log/se;
        part+="  ${c.name} ratio ${real(ratio)} lower ${real(exp(log-Numerics.Z*se))} upper ${real(exp(log+Numerics.Z*se))} z ${real(z)} p ${real(Numerics.pvalue(z*z,1))}"
    };
    section(output,part);
    part=mutableListOf("survival_difference reference ${control.name}");
    for(time in settings.report)for(g in 1 until groups.size) {
        val a=Estimators.at(control.rows,time);
        val b=Estimators.at(collections[g].rows,time);
        part+="  at $time ${settings.groups[g]} ${difference(b.survival-a.survival,sqrt(b.se*b.se+a.se*a.se))}"
    };
    section(output,part);
    write("tests.txt",output)
}
private fun covariate(s: Dataset.Subject,name: String): Double = when(name) {
    "age"->s.age.toDouble();
    "male"->if(s.sex=="M")1.0 else 0.0;
    "stage"->s.stage.toDouble();
    else->if(s.group==name)1.0 else 0.0
}
private fun coefficient(beta: Double,se: Double): String {
    val z=beta/se;
    return "coef ${real(beta)} se ${real(se)} z ${real(z)} p ${real(Numerics.pvalue(z*z,1))} hr ${real(exp(beta))} lower ${real(exp(beta-Numerics.Z*se))} upper ${real(exp(beta+Numerics.Z*se))}"
}
private fun hazard(hazards: Map<Int,Double>,time: Int): Double {
    var value=0.0;
    for((t,h) in hazards) {
        if(t>time)break;
        value=h
    };
    return value
}
private data class Residual(val index: Int,val martingale: Double,val deviance: Double)
private fun coxReport() {
    val n=subjects.size;
    val p=settings.covariates.size;
    val x=Array(n) {
        j->DoubleArray(p) {
            c->covariate(subjects[j],settings.covariates[c])
        }
    };
    val fit=Cox.fit(subjects,x);
    val end=fit.finalEvaluation;
    val start=fit.initial;
    val covariance=Numerics.inverse(end.information);
    val output=mutableListOf("cox covariates ${settings.covariates.joinToString(" ")} subjects $n events ${events(subjects)} event_times ${end.times.size}");
    for(i in fit.iterations)output+="iter ${i.number} loglik ${real(i.likelihood)} beta ${reals(i.beta)}";
    output+="final loglik ${real(end.likelihood)} null_loglik ${real(start.likelihood)}";
    for(c in 0 until p)output+="term ${settings.covariates[c]} ${coefficient(fit.beta[c],sqrt(covariance[c][c]))}";
    for(a in 0 until p)if(settings.covariates[a] in settings.groups)for(b in a+1 until p)if(settings.covariates[b] in settings.groups)output+="contrast ${settings.covariates[b]} vs ${settings.covariates[a]} ${coefficient(fit.beta[b]-fit.beta[a],sqrt(covariance[b][b]+covariance[a][a]-2*covariance[a][b]))}";
    val likelihoodRatio=2*(end.likelihood-start.likelihood);
    var wald=0.0;
    var score=0.0;
    for(c in 0 until p) {
        var inner=0.0;
        for(d in 0 until p)inner+=end.information[c][d]*fit.beta[d];
        wald+=fit.beta[c]*inner
    };
    val solved=Numerics.solve(start.information,start.score);
    for(c in 0 until p)score+=start.score[c]*solved[c];
    for(name in listOf("likelihood_ratio","wald","score")) {
        val chi2=if(name=="likelihood_ratio")likelihoodRatio else if(name=="wald")wald else score;
        output+="$name chisq ${real(chi2)} df $p p ${real(Numerics.pvalue(chi2,p))}"
    };
    for(c in 0 until p) {
        var ll=start.likelihood;
        if(p>1) {
            val reduced=Array(n) {
                j->x[j].indices.filter {
                    it!=c
                }.map {
                    x[j][it]
                }.toDoubleArray()
            };
            ll=Cox.fit(subjects,reduced).finalEvaluation.likelihood
        };
        val chi2=2*(end.likelihood-ll);
        output+="drop ${settings.covariates[c]} loglik ${real(ll)} chisq ${real(chi2)} df 1 p ${real(Numerics.pvalue(chi2,1))}"
    };
    var comparable=0;
    var concordant=0;
    var tied=0;
    for(i in 0 until n)if(subjects[i].event==1)for(j in 0 until n)if(i!=j&&(subjects[i].time<subjects[j].time||(subjects[i].time==subjects[j].time&&subjects[j].event==0))) {
        comparable++;
        if(x[i].contentEquals(x[j]))tied++ else if(end.theta[i]>end.theta[j])concordant++
    };
    output+="concordance ${real((2*concordant+tied).toDouble()/(2*comparable))} comparable $comparable concordant $concordant tied $tied";
    val eventOrder=subjects.indices.filter {
        subjects[it].event==1
    }.sortedWith(compareBy<Int> {
        subjects[it].time
    }.thenBy {
        subjects[it].id
    });
    var timeSum=0;
    for(i in eventOrder)timeSum+=subjects[i].time;
    val timeMean=timeSum.toDouble()/eventOrder.size;
    for(c in 0 until p) {
        val residual=DoubleArray(eventOrder.size);
        var sum=0.0;
        for(j in eventOrder.indices) {
            val i=eventOrder[j];
            val r=end.times.getValue(subjects[i].time);
            residual[j]=x[i][c]-r.s1[c]/r.s0;
            sum+=residual[j]
        };
        val mean=sum/eventOrder.size;
        var sxy=0.0;
        var sxx=0.0;
        var syy=0.0;
        for(j in eventOrder.indices) {
            val dx=residual[j]-mean;
            val dy=subjects[eventOrder[j]].time-timeMean;
            sxy+=dx*dy;
            sxx+=dx*dx;
            syy+=dy*dy
        };
        val rho=sxy/sqrt(sxx*syy);
        val z=0.5*ln((1+rho)/(1-rho))*sqrt((eventOrder.size-3).toDouble());
        output+="ph_check ${settings.covariates[c]} rho ${real(rho)} z ${real(z)} p ${real(Numerics.pvalue(z*z,1))}"
    };
    val cumulative=sortedMapOf<Int,Double>();
    var lambda=0.0;
    for((time,r) in end.times) {
        lambda+=r.events/r.s0;
        cumulative[time]=lambda
    };
    val residuals=mutableListOf<Residual>();
    for(i in 0 until n) {
        val s=subjects[i];
        val m=s.event-hazard(cumulative,s.time)*exp(end.theta[i]);
        var deviance=sqrt(if(s.event==1)-2*(m+ln(1-m)) else -2*m);
        if(!(m>0))deviance=-deviance;
        residuals+=Residual(i,m,deviance)
    };
    residuals.sortWith(compareByDescending<Residual> {
        abs(it.deviance)
    }.thenBy {
        subjects[it.index].id
    });
    output+="residuals top ${settings.residuals}";
    for(j in 0 until settings.residuals) {
        val r=residuals[j];
        val s=subjects[r.index];
        output+="  id ${s.id} group ${s.group} time ${s.time} event ${s.event} martingale ${real(r.martingale)} deviance ${real(r.deviance)}"
    };
    val means=DoubleArray(p);
    var meanLine="adjusted_survival mean";
    var standard=0;
    for(c in 0 until p)if(settings.covariates[c] in listOf("age","male","stage")) {
        var sum=0;
        for(i in 0 until n)sum+=x[i][c].toInt();
        means[c]=sum.toDouble()/n;
        meanLine+=" ${settings.covariates[c]} ${real(means[c])}";
        standard++
    };
    output+=meanLine+if(standard==0)" none" else "";
    val risks=DoubleArray(groups.size);
    for(g in groups.indices) {
        var theta=0.0;
        for(c in 0 until p) {
            val name=settings.covariates[c];
            val value=if(name in settings.groups) {
                if(name==settings.groups[g])1.0 else 0.0
            }else means[c];
            theta+=fit.beta[c]*value
        };
        risks[g]=exp(theta)
    };
    for(time in settings.report) {
        var line="  at $time";
        for(g in groups.indices)line+=" ${settings.groups[g]} ${real(exp(-hazard(cumulative,time)*risks[g]))}";
        output+=line
    };
    var line="  median";
    for(g in groups.indices) {
        var median=-1;
        for((time,h) in cumulative)if(exp(-h*risks[g])<=0.5) {
            median=time;
            break
        };
        line+=" ${settings.groups[g]} ${day(median)}"
    };
    output+=line;
    write("cox.txt",output)
}
private fun plotReport() {
    val tables=groups.indices.map {
        collections[it].rows
    };
    val output=mutableListOf("km_plot width ${settings.width} height ${settings.height} time ${settings.horizon}");
    var legend="legend";
    for(g in groups.indices)legend+=" ${('A'.code+g).toChar()} ${settings.groups[g]}";
    output+=legend;
    output+=Plot.draw(groups,tables,settings.width,settings.height,settings.horizon);
    output+="time 0 to ${settings.horizon} days, ${settings.horizon/settings.width} days per column";
    var line="at_risk";
    for(i in 0..settings.divisions)line+=" ${i*(settings.horizon/settings.divisions)}";
    output+=line;
    for(g in groups.indices) {
        line=settings.groups[g];
        for(i in 0..settings.divisions)line+=" ${Estimators.risk(groups[g],i*(settings.horizon/settings.divisions))}";
        output+=line
    };
    write("km_plot.txt",output)
}
fun main() {
    val data=Dataset.read();
    subjects=data.subjects;
    settings=data.settings;
    for(group in settings.groups) {
        val rows=subjects.filter {
            it.group==group
        };
        groups+=rows;
        collections+=summarize(group,rows)
    };
    collections+=summarize("all",subjects);
    File("output").mkdirs();
    kmReport();
    testsReport();
    coxReport();
    plotReport()
}
