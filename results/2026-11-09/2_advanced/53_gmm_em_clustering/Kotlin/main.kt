import kotlin.math.*

object Main {
    lateinit var points: List<Dataset.Point>;
    lateinit var params: Dataset.Params;
    lateinit var initial: Map<Int,Em.Model>;
    lateinit var ks: IntArray;
    lateinit var types: List<String>;
    val models=mutableListOf<Summary>();
    val kmeans=mutableMapOf<Int,Kmeans.Run>();
    lateinit var selected: Summary
    class Summary(val k: Int,val typeIndex: Int,val type: String,val run: Em.Run) {
        var p=0;
        var settled=0;
        var largest=1;
        val assignment=IntArray(run.step.density.size);
        val sizes=IntArray(k);
        var bic=0.0;
        var aic=0.0;
        var icl=0.0;
        var entropy=0.0;
        var increase=0.0;
        val violations=mutableListOf<Int>()
    }
    data class Metrics(val silhouette: Double,val ch: Double,val db: Double,val cluster: DoubleArray)
    data class Ari(val numerator: Long,val denominator: Long) {
        fun text()="$numerator/$denominator ${Report.f(numerator.toDouble()/denominator)}"
    }
    fun f(value: Double)=Report.f(value)
    fun ints(values: IntArray,oneBased: Boolean)=values.joinToString(" ") {
        (it+if(oneBased)1 else 0).toString()
    }
    fun decimals(values: DoubleArray)=values.joinToString(" ") {
        f(it)
    }
    fun entropy(row: DoubleArray): Double {
        var sum=0.0;
        for(value in row)if(value!=0.0)sum+=value*ln(value);
        return -sum
    }
    fun maximum(row: DoubleArray): Int {
        var best=0;
        for(j in 1 until row.size)if(row[j]>row[best])best=j;
        return best
    }
    fun summarize(k: Int,typeIndex: Int,run: Em.Run): Summary {
        val result=Summary(k,typeIndex,types[typeIndex],run);
        result.p=when(result.type) {
            "FULL"->6*k-1;
            "TIED"->3*k+2;
            "DIAG"->5*k-1;
            else->4*k-1
        };
        for(i in result.assignment.indices) {
            val row=run.step.responsibilities[i];
            result.assignment[i]=maximum(row);
            result.sizes[result.assignment[i]]++;
            result.entropy+=entropy(row)
        };
        val loglik=run.step.loglik;
        result.bic=-2*loglik+result.p*ln(result.assignment.size.toDouble());
        result.aic=-2*loglik+2*result.p;
        result.icl=result.bic+2*result.entropy;
        val trace=run.trace;
        val last=trace.last();
        for(t in trace.indices)if(abs(trace[t]-last)>params.get("SETTLE_TOLERANCE"))result.settled=t+1;
        result.increase=trace[1]-trace[0];
        for(t in 1 until trace.size) {
            val increase=trace[t]-trace[t-1];
            if(increase>result.increase) {
                result.increase=increase;
                result.largest=t
            };
            if(trace[t]<trace[t-1]-0.000001*abs(trace[t-1]))result.violations+=t
        };
        return result
    }
    fun fit(data: List<Dataset.Point>,source: Em.Model,type: String)=Em.fit(data,source,type,params.integer("ITERATIONS"),params.get("REGULARIZATION"))
    fun criterion(s: Summary,kind: Int)=if(kind==0)s.bic else if(kind==1)s.aic else s.icl
    fun compare(a: Summary,b: Summary,kind: Int): Int {
        var c=Report.rounded(criterion(a,kind)).compareTo(Report.rounded(criterion(b,kind)));
        if(c==0)c=a.p.compareTo(b.p);
        if(c==0)c=a.k.compareTo(b.k);
        if(c==0)c=a.typeIndex.compareTo(b.typeIndex);
        return c
    }
    fun ranking(kind: Int)=models.sortedWith(Comparator {
        a,b->compare(a,b,kind)
    })
    fun bestK(k: Int)=ranking(0).first {
        it.k==k
    }
    fun contingency(a: IntArray,ka: Int,b: IntArray,kb: Int): Array<IntArray> {
        val result=Array(ka) {
            IntArray(kb)
        };
        for(i in a.indices)result[a[i]][b[i]]++;
        return result
    }
    fun pairs(n: Long)=n*(n-1)/2
    fun gcd(a0: Long,b0: Long): Long {
        var a=a0;
        var b=b0;
        while(b!=0L) {
            val r=a%b;
            a=b;
            b=r
        };
        return a
    }
    fun ari(table: Array<IntArray>): Ari {
        var s=0L;
        var a=0L;
        var b=0L;
        var n=0L;
        val columns=LongArray(table[0].size);
        for(row in table) {
            var sum=0L;
            for(c in row.indices) {
                s+=pairs(row[c].toLong());
                sum+=row[c];
                columns[c]+=row[c]
            };
            a+=pairs(sum);
            n+=sum
        };
        for(value in columns)b+=pairs(value);
        val z=pairs(n);
        var numerator=2*(z*s-a*b);
        var denominator=z*(a+b)-2*a*b;
        if(denominator==0L)return Ari(1,1);
        val g=gcd(abs(numerator),abs(denominator));
        numerator/=g;
        denominator/=g;
        if(denominator<0) {
            numerator=-numerator;
            denominator=-denominator
        };
        return Ari(numerator,denominator)
    }
    fun metrics(assignment: IntArray,k: Int): Metrics {
        val n=points.size;
        val counts=IntArray(k);
        val centers=Array(k) {
            DoubleArray(2)
        };
        val center=DoubleArray(2);
        for(i in 0 until n) {
            val p=points[i];
            val j=assignment[i];
            counts[j]++;
            centers[j][0]+=p.x;
            centers[j][1]+=p.y;
            center[0]+=p.x;
            center[1]+=p.y
        };
        var groups=0;
        for(j in 0 until k)if(counts[j]>0) {
            groups++;
            centers[j][0]/=counts[j].toDouble();
            centers[j][1]/=counts[j].toDouble()
        };
        val cluster=DoubleArray(k) {
            Double.NaN
        };
        if(groups<2)return Metrics(Double.NaN,Double.NaN,Double.NaN,cluster);
        center[0]/=n.toDouble();
        center[1]/=n.toDouble();
        var silhouette=0.0;
        val sums=DoubleArray(k);
        for(i in 0 until n) {
            val j=assignment[i];
            var s=0.0;
            if(counts[j]>1) {
                var own=0.0;
                val others=DoubleArray(k);
                for(q in 0 until n)if(q!=i) {
                    val distance=Kmeans.distance(points[i],points[q]);
                    if(assignment[q]==j)own+=distance else others[assignment[q]]+=distance
                };
                val a=own/(counts[j]-1);
                var b=Double.POSITIVE_INFINITY;
                for(c in 0 until k)if(c!=j&&counts[c]>0)b=minOf(b,others[c]/counts[c]);
                s=(b-a)/maxOf(a,b)
            };
            silhouette+=s;
            sums[j]+=s
        };
        for(j in 0 until k)if(counts[j]>0)cluster[j]=sums[j]/counts[j];
        var between=0.0;
        var within=0.0;
        for(j in 0 until k)if(counts[j]>0)between+=counts[j]*Kmeans.squared(centers[j][0],centers[j][1],center);
        val scatters=DoubleArray(k);
        for(i in 0 until n) {
            val p=points[i];
            val j=assignment[i];
            val square=Kmeans.squared(p.x,p.y,centers[j]);
            within+=square;
            scatters[j]+=sqrt(square)
        };
        for(j in 0 until k)if(counts[j]>0)scatters[j]/=counts[j].toDouble();
        var db=0.0;
        for(j in 0 until k)if(counts[j]>0) {
            var maximum=Double.NEGATIVE_INFINITY;
            for(c in 0 until k)if(c!=j&&counts[c]>0)maximum=maxOf(maximum,(scatters[j]+scatters[c])/sqrt(Kmeans.squared(centers[j][0],
                centers[j][1],centers[c])));
            db+=maximum
        };
        return Metrics(silhouette/n,(between/(groups-1))/(within/(n-groups)),db/groups,cluster)
    }
    fun modelReport(): List<String> {
        val out=mutableListOf<String>();
        for(s in models) {
            if(out.isNotEmpty())out+="";
            val m=s.run.model;
            out+="model K=${s.k} type=${s.type}";
            out+="parameters ${s.p}";
            out+="loglik ${f(s.run.step.loglik)}";
            out+="bic ${f(s.bic)}";
            out+="aic ${f(s.aic)}";
            out+="icl ${f(s.icl)}";
            out+="mean_entropy ${f(s.entropy/points.size)}";
            out+="settled_at ${s.settled}";
            out+="largest_increase iteration ${s.largest} value ${f(s.increase)}";
            out+="violations ${s.violations.size}";
            out+="sizes ${ints(s.sizes,false)}";
            for(j in 0 until s.k) {
                val e=Gaussian.eigen(m.cov[j]);
                out+="component ${j+1} weight ${f(m.weights[j])} mean ${decimals(m.means[j])} cov ${decimals(m.cov[j])} axes ${f(e.major)} ${f(e.minor)} angle ${f(e.angle)}"
            }
        };
        return out
    }
    fun traceReport(): List<String> {
        val out=mutableListOf("K,type,iteration,loglik");
        for(s in models)for(t in s.run.trace.indices)out+="${s.k},${s.type},$t,${f(s.run.trace[t])}";
        return out
    }
    fun assignmentsReport(): List<String> {
        val out=mutableListOf("id,component,max_responsibility,log_density,kmeans_cluster");
        for(i in points.indices)out+="${points[i].id},${selected.assignment[i]+1},${f(selected.run.step.responsibilities[i][selected.assignment[i]])},${f(selected.run.step.density[i])},${kmeans.getValue(selected.k).assignment[i]+1}";
        return out
    }
    fun block(out: MutableList<String>,heading: String) {
        if(out.isNotEmpty())out+="";
        out+=heading
    }
    fun ranks(out: MutableList<String>) {
        val bic=ranking(0);
        val aic=ranking(1);
        val icl=ranking(2);
        out+="ranking by bic";
        out+="rank K type parameters loglik bic delta_bic aic aic_rank icl icl_rank";
        for(i in bic.indices) {
            val s=bic[i];
            val delta=(Report.rounded(s.bic)-Report.rounded(selected.bic)).toPlainString();
            out+="${i+1} ${s.k} ${s.type} ${s.p} ${f(s.run.step.loglik)} ${f(s.bic)} $delta ${f(s.aic)} ${aic.indexOf(s)+1} ${f(s.icl)} ${icl.indexOf(s)+1}"
        };
        out+="selected K=${selected.k} type=${selected.type}";
        out+="best_aic K=${aic.first().k} type=${aic.first().type}";
        out+="best_icl K=${icl.first().k} type=${icl.first().type}";
        block(out,"best K per type");
        for(type in types) {
            val best=IntArray(3);
            for(kind in 0..2)best[kind]=ranking(kind).first {
                it.type==type
            }.k;
            out+="$type bic ${best[0]} aic ${best[1]} icl ${best[2]}"
        }
    }
    fun compareK(out: MutableList<String>) {
        var previous: Summary?=null;
        for(k in ks) {
            val best=bestK(k);
            val km=kmeans.getValue(k);
            val g=metrics(best.assignment,k);
            val m=metrics(km.assignment,k);
            block(out,"K=$k type=${best.type} bic ${f(best.bic)}");
            out+="  kmeans iterations ${km.iterations} inertia ${f(km.inertia)}";
            out+="  ari ${ari(contingency(best.assignment,k,km.assignment,k)).text()}";
            out+="  silhouette gmm ${f(g.silhouette)} kmeans ${f(m.silhouette)}";
            out+="  calinski_harabasz gmm ${f(g.ch)} kmeans ${f(m.ch)}";
            out+="  davies_bouldin gmm ${f(g.db)} kmeans ${f(m.db)}";
            if(previous!=null) {
                val table=contingency(previous.assignment,previous.k,best.assignment,k);
                val parents=mutableListOf<String>();
                val shared=IntArray(k);
                for(j in 0 until k) {
                    var parent=-1;
                    for(a in 0 until previous.k)if(table[a][j]>shared[j]) {
                        shared[j]=table[a][j];
                        parent=a
                    };
                    parents+=if(parent<0)"-" else (parent+1).toString()
                };
                out+="  parents K=${previous.k} ${parents.joinToString(" ")} shared ${ints(shared,false)}"
            };
            previous=best
        }
    }
    fun violations(out: MutableList<String>) {
        block(out,"violations");
        var any=false;
        for(s in models)for(t in s.violations) {
            any=true;
            out+="K=${s.k} type=${s.type} iteration $t previous ${f(s.run.trace[t-1])} current ${f(s.run.trace[t])}"
        };
        if(!any)out+="none"
    }
    fun components(out: MutableList<String>) {
        block(out,"selected components");
        val model=selected.run.model;
        val r=selected.run.step.responsibilities;
        val metrics=metrics(selected.assignment,selected.k);
        val boundaries=params.row("GOF_EDGES");
        for(j in 0 until selected.k) {
            val e=Gaussian.eigen(model.cov[j]);
            var soft=0.0;
            var inside1=0;
            var inside2=0;
            val observed=IntArray(boundaries.size+1);
            for(i in points.indices) {
                soft+=r[i][j];
                if(selected.assignment[i]!=j)continue;
                val p=points[i];
                val q=Gaussian.q(p.x,p.y,model.means[j],model.cov[j]);
                if(q<=1)inside1++;
                if(q<=4)inside2++;
                val rho=sqrt(q);
                var bucket=0;
                while(bucket<boundaries.size&&rho>=boundaries[bucket])bucket++;
                observed[bucket]++
            };
            val expected=DoubleArray(observed.size);
            var chi=0.0;
            for(b in observed.indices) {
                val lo=if(b==0)0.0 else boundaries[b-1];
                val right=if(b==boundaries.size)0.0 else exp(-boundaries[b]*boundaries[b]/2);
                expected[b]=selected.sizes[j]*(exp(-lo*lo/2)-right);
                chi+=(observed[b]-expected[b])*(observed[b]-expected[b])/expected[b]
            };
            out+="component ${j+1} weight ${f(model.weights[j])} size ${selected.sizes[j]} soft_size ${f(soft)} mean ${decimals(model.means[j])}";
            out+="  cov ${decimals(model.cov[j])} corr ${f(e.correlation)}";
            out+="  eigen ${f(e.leading)} ${f(e.trailing)} direction ${f(e.ux)} ${f(e.uy)} angle ${f(e.angle)}";
            out+="  axes_1sigma ${f(e.major)} ${f(e.minor)} axes_2sigma ${f(2*e.major)} ${f(2*e.minor)}";
            out+="  inside_1sigma $inside1 inside_2sigma $inside2 area_1sigma ${f(e.area)}";
            out+="  silhouette ${f(metrics.cluster[j])}";
            out+="  gof observed ${ints(observed,false)} expected ${decimals(expected)} chi2 ${f(chi)}"
        };
        block(out,"overlap");
        if(selected.k==1)out+="none";
        for(a in 0 until selected.k)for(b in a+1 until selected.k) {
            val distance=Gaussian.bhattacharyya(model.means[a],model.cov[a],model.means[b],model.cov[b]);
            var shared=0.0;
            for(i in points.indices)shared+=r[i][a]*r[i][b];
            out+="${a+1}-${b+1} bhattacharyya ${f(distance)} coefficient ${f(exp(-distance))} shared ${f(shared)}"
        }
    }

    fun merge(clusters: List<List<Int>>,a: Int,b: Int): List<List<Int>> {
        val result=clusters.toMutableList();
        result[a]=(clusters[a]+clusters[b]).sorted();
        result.removeAt(b);
        return result
    }
    fun collapsed(clusters: List<List<Int>>): Array<DoubleArray> {
        val result=Array(points.size) {
            DoubleArray(clusters.size)
        };
        for(i in points.indices)for(c in clusters.indices)for(j in clusters[c])result[i][c]+=selected.run.step.responsibilities[i][j];
        return result
    }
    fun mergedEntropy(clusters: List<List<Int>>): Double {
        var sum=0.0;
        for(row in collapsed(clusters))sum+=entropy(row);
        return sum
    }
    fun clusterName(cluster: List<Int>)=cluster.joinToString("+") {
        (it+1).toString()
    }
    fun merging(out: MutableList<String>) {
        block(out,"merging");
        var clusters: List<List<Int>> = List(selected.k) {
            listOf(it)
        };
        out+="start entropy ${f(mergedEntropy(clusters))}";
        var step=1;
        while(clusters.size>1) {
            var ba=0;
            var bb=1;
            var best=Double.POSITIVE_INFINITY;
            for(a in clusters.indices)for(b in a+1 until clusters.size) {
                val value=mergedEntropy(merge(clusters,a,b));
                if(best.isInfinite()||Report.rounded(value)<Report.rounded(best)) {
                    best=value;
                    ba=a;
                    bb=b
                }
            };
            val a=clusterName(clusters[ba]);
            val b=clusterName(clusters[bb]);
            clusters=merge(clusters,ba,bb);
            val r=collapsed(clusters);
            val sizes=IntArray(clusters.size);
            for(row in r)sizes[maximum(row)]++;
            out+="step $step merge $a $b entropy ${f(best)} sizes ${ints(sizes,false)}";
            step++
        }
    }
    data class Matching(val permutation: IntArray,val agreement: Int)
    fun permutations(table: Array<IntArray>,depth: Int,current: IntArray,used: BooleanArray,best: IntArray,largest: IntArray) {
        if(depth==current.size) {
            var agreement=0;
            for(j in current.indices)agreement+=table[current[j]][j];
            if(agreement>largest[0]) {
                largest[0]=agreement;
                current.copyInto(best)
            };
            return
        };
        for(j in current.indices)if(!used[j]) {
            used[j]=true;
            current[depth]=j;
            permutations(table,depth+1,current,used,best,largest);
            used[j]=false
        }
    }
    fun matching(table: Array<IntArray>): Matching {
        val k=table.size;
        val best=IntArray(k);
        val largest=intArrayOf(-1);
        permutations(table,0,IntArray(k),BooleanArray(k),best,largest);
        return Matching(best,largest[0])
    }
    fun compareKmeans(out: MutableList<String>) {
        val km=kmeans.getValue(selected.k);
        block(out,"kmeans K=${selected.k}");
        out+="iterations ${km.iterations}";
        out+="inertia ${f(km.inertia)}";
        val sizes=IntArray(selected.k);
        for(value in km.assignment)sizes[value]++;
        out+="sizes ${ints(sizes,false)}";
        for(j in 0 until selected.k)out+="center ${j+1} ${decimals(km.centers[j])}";
        val table=contingency(selected.assignment,selected.k,km.assignment,selected.k);
        out+="contingency";
        for(row in table)out+=ints(row,false);
        out+="ari ${ari(table).text()}";
        val match=matching(table);
        out+="matching ${ints(match.permutation,true)}";
        out+="agreement ${match.agreement}/${points.size} ${f(match.agreement.toDouble()/points.size)}";
        var disagreements=0;
        for(i in points.indices)if(match.permutation[km.assignment[i]]!=selected.assignment[i]) {
            disagreements++;
            out+="disagree ${points[i].id} gmm ${selected.assignment[i]+1} kmeans ${km.assignment[i]+1} max ${f(selected.run.step.responsibilities[i][selected.assignment[i]])}"
        };
        out+="disagreements $disagreements"
    }
    fun refit(out: MutableList<String>) {
        val km=kmeans.getValue(selected.k);
        val source=Em.Model(selected.k);
        val counts=IntArray(selected.k);
        for(value in km.assignment)counts[value]++;
        val eps=params.get("REGULARIZATION");
        for(j in 0 until selected.k) {
            source.weights[j]=counts[j].toDouble()/points.size;
            source.means[j]=km.centers[j].copyOf();
            for(i in points.indices)if(km.assignment[i]==j) {
                val dx=points[i].x-source.means[j][0];
                val dy=points[i].y-source.means[j][1];
                source.cov[j][0]+=dx*dx;
                source.cov[j][1]+=dx*dy;
                source.cov[j][2]+=dy*dy
            };
            source.cov[j][0]=source.cov[j][0]/counts[j]+eps;
            source.cov[j][1]/=counts[j].toDouble();
            source.cov[j][2]=source.cov[j][2]/counts[j]+eps
        };
        val result=summarize(selected.k,selected.typeIndex,fit(points,source,selected.type));
        block(out,"refit_from_kmeans K=${selected.k} type=${selected.type}");
        out+="loglik ${f(result.run.step.loglik)} bic ${f(result.bic)} settled_at ${result.settled}";
        out+="sizes ${ints(result.sizes,false)}";
        out+="ari_vs_selected ${ari(contingency(selected.assignment,selected.k,result.assignment,selected.k)).text()}"
    }
    fun crossValidation(out: MutableList<String>) {
        val folds=params.integer("CV_FOLDS");
        block(out,"cross_validation K=${selected.k} type=${selected.type} folds $folds");
        var sum=0.0;
        for(fold in 0 until folds) {
            val train=mutableListOf<Dataset.Point>();
            val test=mutableListOf<Dataset.Point>();
            for(i in points.indices)if(i%folds==fold)test+=points[i] else train+=points[i];
            val run=fit(train,initial.getValue(selected.k),selected.type);
            val score=Em.expectation(test,run.model).loglik/test.size;
            sum+=score;
            out+="fold ${fold+1} train ${train.size} test ${test.size} train_loglik ${f(run.step.loglik/train.size)} test_loglik ${f(score)}"
        };
        out+="mean_test_loglik ${f(sum/folds)}"
    }
    fun unusual(out: MutableList<String>) {
        val uncertain=mutableListOf<Int>();
        val outliers=mutableListOf<Int>();
        val r=selected.run.step.responsibilities;
        val lp=selected.run.step.density;
        val threshold=params.get("UNCERTAIN_THRESHOLD");
        val low=params.get("LOW_DENSITY_THRESHOLD");
        for(i in points.indices) {
            if(r[i][selected.assignment[i]]<threshold)uncertain+=i;
            if(lp[i]<low)outliers+=i
        };
        uncertain.sortWith(Comparator {
            a,b->val c=Report.rounded(r[a][selected.assignment[a]]).compareTo(Report.rounded(r[b][selected.assignment[b]]));
            if(c!=0)c else a.compareTo(b)
        });
        outliers.sortWith(Comparator {
            a,b->val c=Report.rounded(lp[a]).compareTo(Report.rounded(lp[b]));
            if(c!=0)c else a.compareTo(b)
        });
        block(out,"uncertain threshold ${f(threshold)}");
        for(i in uncertain)out+="${points[i].id} component ${selected.assignment[i]+1} max ${f(r[i][selected.assignment[i]])} responsibilities ${decimals(r[i])}";
        out+="count ${uncertain.size}";
        block(out,"outliers threshold ${f(low)}");
        val model=selected.run.model;
        for(i in outliers) {
            val p=points[i];
            val j=selected.assignment[i];
            out+="${p.id} component ${j+1} log_density ${f(lp[i])} q ${f(Gaussian.q(p.x,p.y,model.means[j],model.cov[j]))}"
        };
        out+="count ${outliers.size}"
    }
    fun selectionReport(): List<String> {
        val out=mutableListOf<String>();
        ranks(out);
        compareK(out);
        violations(out);
        components(out);
        merging(out);
        compareKmeans(out);
        refit(out);
        crossValidation(out);
        unusual(out);
        return out
    }
    fun cell(x: Double,y: Double,rx: DoubleArray,ry: DoubleArray,sx: Double,sy: Double,width: Int,height: Int): IntArray? {
        val col=floor((x-rx[0])/sx).toInt();
        val row=floor((ry[1]-y)/sy).toInt();
        return if(col<0||col>=width||row<0||row>=height)null else intArrayOf(col,row)
    }
    fun maps(): List<String> {
        val rx=params.row("MAP_X");
        val ry=params.row("MAP_Y");
        val size=params.row("MAP_SIZE");
        val width=size[0].toInt();
        val height=size[1].toInt();
        val sx=(rx[1]-rx[0])/width;
        val sy=(ry[1]-ry[0])/height;
        val characters=" .:-=+*#%@";
        val density=Array(height) {
            CharArray(width)
        };
        val regions=Array(height) {
            CharArray(width)
        };
        val uncertainty=Array(height) {
            CharArray(width)
        };
        val pointMap=Array(height) {
            CharArray(width) {
                ' '
            }
        };
        val values=Array(height) {
            DoubleArray(width)
        };
        var peakDensity=0.0;
        var sum=0.0;
        val model=selected.run.model;
        for(y in 0 until height)for(x in 0 until width) {
            val cx=rx[0]+(x+0.5)*sx;
            val cy=ry[1]-(y+0.5)*sy;
            val step=Em.expectation(listOf(Dataset.Point("",cx,cy)),model);
            var value=0.0;
            for(score in step.scores[0])value+=exp(score);
            values[y][x]=value;
            peakDensity=maxOf(peakDensity,value);
            sum+=value;
            regions[y][x]=('1'.code+maximum(step.scores[0])).toChar();
            var level=if(selected.k==1)0 else floor(10*entropy(step.responsibilities[0])/ln(selected.k.toDouble())).toInt();
            level=level.coerceIn(0,9);
            uncertainty[y][x]=characters[level];
            for(j in 0 until selected.k)if(Gaussian.q(cx,cy,model.means[j],model.cov[j])<=4) {
                for(d in listOf(intArrayOf(-1,0),intArrayOf(1,0),intArrayOf(0,-1),intArrayOf(0,1))) {
                    val xx=x+d[0];
                    val yy=y+d[1];
                    if(xx>=0&&xx<width&&yy>=0&&yy<height&&Gaussian.q(rx[0]+(xx+0.5)*sx,ry[1]-(yy+0.5)*sy,model.means[j],model.cov[j])>4)pointMap[y][x]='.'
                }
            }
        };
        val counts=IntArray(10);
        for(y in 0 until height)for(x in 0 until width) {
            val level=minOf(9,floor(10*values[y][x]/peakDensity).toInt());
            counts[level]++;
            density[y][x]=characters[level]
        };
        for(j in 0 until selected.k) {
            val cell=cell(model.means[j][0],model.means[j][1],rx,ry,sx,sy,width,height);
            if(cell!=null)density[cell[1]][cell[0]]=('1'.code+j).toChar()
        };
        var outside=0;
        for(i in points.indices) {
            val p=points[i];
            val cell=cell(p.x,p.y,rx,ry,sx,sy,width,height);
            if(cell==null) {
                outside++;
                continue
            };
            val old=pointMap[cell[1]][cell[0]];
            val symbol=('1'.code+selected.assignment[i]).toChar();
            pointMap[cell[1]][cell[0]]=if(old==' '||old=='.'||old==symbol)symbol else '*'
        };
        val out=mutableListOf("density K=${selected.k} type=${selected.type}","x ${f(rx[0])} ${f(rx[1])} y ${f(ry[0])} ${f(ry[1])} grid ${width}x$height",
            "max_density ${Report.decimal(peakDensity,6)} mass_in_map ${f(sum*sx*sy)}");
        out.addAll(Report.frame(density));
        for(level in 0..9)out+="level $level \"${characters[level]}\" from ${Report.decimal(level*peakDensity/10,6)} cells ${counts[level]}";
        block(out,"regions");
        out.addAll(Report.frame(regions));
        block(out,"uncertainty");
        out.addAll(Report.frame(uncertainty));
        block(out,"points");
        out.addAll(Report.frame(pointMap));
        out+="outside $outside";
        return out
    }
    @JvmStatic fun main(args: Array<String>) {
        val data=Dataset.read();
        points=data.points;
        initial=data.initial;
        params=data.params;
        types=params.words("TYPES");
        ks=params.words("K").map(String::toInt).toIntArray();
        for(k in ks) {
            for(t in types.indices)models+=summarize(k,t,fit(points,initial.getValue(k),types[t]));
            kmeans[k]=Kmeans.fit(points,initial.getValue(k).means,params.integer("KMEANS_MAX_ITERATIONS"))
        };
        selected=ranking(0).first();
        Report.write("models.txt",modelReport());
        Report.write("loglik_trace.csv",traceReport());
        Report.write("assignments.csv",assignmentsReport());
        Report.write("selection.txt",selectionReport());
        Report.write("density_map.txt",maps())
    }
}
