import java.io.File
import java.util.Locale
import kotlin.math.*

private lateinit var data: Dataset.Data
private lateinit var settings: Dataset.Settings
private lateinit var names: List<String>
private var p=0
private var n=0
private var k=0
private var top=0
private lateinit var observedMeans: DoubleArray
private lateinit var msa: DoubleArray
private lateinit var parallel: DoubleArray
private lateinit var ratio: DoubleArray
private lateinit var cumulative: DoubleArray
private lateinit var broken: DoubleArray
private lateinit var se: DoubleArray
private lateinit var communalities: DoubleArray
private lateinit var observed: IntArray
private lateinit var retention: IntArray
private lateinit var summary: Array<DoubleArray>
private lateinit var loadings: Array<DoubleArray>
private lateinit var circle: Array<DoubleArray>
private lateinit var rotated: Array<DoubleArray>
private lateinit var rotationSquares: DoubleArray
private lateinit var congruences: DoubleArray
private lateinit var criteria: DoubleArray
private lateinit var closest: IntArray
private lateinit var fit: Fit
private val observations=mutableListOf<Observation>()
private val projections=mutableListOf<Observation>()
private var total=0.0
private var average=0.0
private var kmo=0.0
private var determinant=0.0
private var bartlett=0.0
private fun real(value: Double)=format(value,4)
private fun format(value: Double,digits: Int): String {
    val text=String.format(Locale.ROOT,"%.${digits}f",value);
    return if(text.toDouble()==0.0&&text.startsWith('-'))text.substring(1) else text
}
private fun reals(values: DoubleArray)=values.joinToString(" ") {
    real(it)
}
private fun write(name: String,lines: List<String>) {
    File("output/$name").writeText(lines.joinToString("\n",postfix="\n"),Charsets.US_ASCII)
}
private fun components(prefix: String,count: Int)=(1..count).map {
    "$prefix$it"
}
private fun section(output: MutableList<String>,part: List<String>) {
    if(output.isNotEmpty())output+="";
    output+=part
}
private fun missing(row: DoubleArray)=row.any {
    it.isNaN()
}
private fun maximum(values: DoubleArray): Int {
    var best=0;
    for(i in 1 until values.size)if(values[i]>values[best])best=i;
    return best
}
private fun minimum(values: DoubleArray): Int {
    var best=0;
    for(i in 1 until values.size)if(values[i]<values[best])best=i;
    return best
}
private fun top(values: DoubleArray,count: Int)=values.indices.sortedWith(compareByDescending<Int> {
    values[it]
}.thenBy {
    it
}).take(count)
private fun congruence(first: DoubleArray,second: DoubleArray)=Matrix.dot(first,second)/sqrt(Matrix.dot(first,first)*Matrix.dot(second,second))
private class Fit(strategy: String,scaling: String) {
    val ids=mutableListOf<String>();
    val values: Array<DoubleArray>;
    val means: DoubleArray;
    val scales: DoubleArray;
    val covariance: Array<DoubleArray>;
    val correlation: Array<DoubleArray>;
    val matrix: Array<DoubleArray>;
    val eigen: Eigen.Result
    init {
        val rows=mutableListOf<DoubleArray>();
        for(row in data.data.rows) {
            if(strategy=="listwise"&&missing(row.values))continue;
            ids+=row.id;
            val values=row.values.copyOf();
            for(j in 0 until p)if(values[j].isNaN())values[j]=observedMeans[j];
            rows+=values
        };
        values=rows.toTypedArray();
        means=Pca.means(values);
        covariance=Pca.covariance(values,means);
        val sd=Pca.deviations(covariance);
        correlation=Pca.correlation(covariance,sd);
        matrix=if(scaling=="covariance")covariance else correlation;
        scales=DoubleArray(p) {
            if(scaling=="covariance")1.0 else sd[it]
        };
        eigen=Eigen.jacobi(matrix)
    }
}
private class Observation(val id: String,values: DoubleArray) {
    val z=Pca.standardize(values,fit.means,fit.scales);
    val scores=Pca.scores(z,fit.eigen.vectors);
    val t2=Pca.t2(scores,fit.eigen.values,k);
    val residuals=Pca.residuals(z,scores,fit.eigen.vectors,k);
    val spe=Matrix.dot(residuals,residuals);
    val quality: Double;
    val flag: String;
    val tContributions=DoubleArray(p);
    val qContributions=DoubleArray(p)
    init {
        var squares=0.0;
        for(h in 0 until k)squares+=scores[h]*scores[h];
        quality=squares/Matrix.dot(z,z);
        flag=((if(t2>settings.number("T2_LIMIT"))"T" else "")+(if(spe>settings.number("SPE_LIMIT"))"Q" else "")).ifEmpty {
            "-"
        };
        for(j in 0 until p) {
            var weight=0.0;
            for(h in 0 until k)weight+=(scores[h]/fit.eigen.values[h])*fit.eigen.vectors[h][j];
            tContributions[j]=z[j]*weight;
            qContributions[j]=residuals[j]*residuals[j]
        }
    }
}
private fun summarize() {
    observed=IntArray(p);
    observedMeans=DoubleArray(p);
    summary=Array(p) {
        DoubleArray(4)
    };
    for(j in 0 until p) {
        var sum=0.0;
        var min=Double.POSITIVE_INFINITY;
        var max=Double.NEGATIVE_INFINITY;
        for(row in data.data.rows)if(!row.values[j].isNaN()) {
            val value=row.values[j];
            observed[j]++;
            sum+=value;
            min=minOf(min,value);
            max=maxOf(max,value)
        };
        val mean=sum/observed[j];
        var variance=0.0;
        observedMeans[j]=mean;
        for(row in data.data.rows)if(!row.values[j].isNaN())variance+=(row.values[j]-mean)*(row.values[j]-mean);
        summary[j]=doubleArrayOf(mean,sqrt(variance/(observed[j]-1)),min,max)
    }
}
private fun adequacy() {
    val result=Matrix.inverse(fit.correlation);
    determinant=result.determinant;
    msa=DoubleArray(p);
    var rrTotal=0.0;
    var ppTotal=0.0;
    for(j in 0 until p) {
        var rr=0.0;
        var pp=0.0;
        for(h in 0 until p)if(j!=h) {
            val partial=-result.matrix[j][h]/sqrt(result.matrix[j][j]*result.matrix[h][h]);
            rr+=fit.correlation[j][h]*fit.correlation[j][h];
            pp+=partial*partial
        };
        msa[j]=rr/(rr+pp);
        rrTotal+=rr;
        ppTotal+=pp
    };
    kmo=rrTotal/(rrTotal+ppTotal);
    bartlett=-(n-1-(2*p+5)/6.0)*ln(determinant)
}
private fun variances() {
    parallel=DoubleArray(p);
    var state=settings.second("PARALLEL").toLong();
    val iterations=settings.integer("PARALLEL");
    for(iteration in 0 until iterations) {
        val values=Array(n) {
            DoubleArray(p)
        };
        for(i in 0 until n)for(j in 0 until p) {
            state=48271*state%2147483647;
            values[i][j]=state.toDouble()/2147483647
        };
        val covariance=Pca.covariance(values,Pca.means(values));
        val eigen=Eigen.jacobi(Pca.correlation(covariance,Pca.deviations(covariance))).values;
        val sum=Matrix.sum(eigen);
        for(h in 0 until p)parallel[h]+=eigen[h]/sum
    };
    for(h in 0 until p)parallel[h]/=iterations;
    total=Matrix.sum(fit.eigen.values);
    average=total/p;
    ratio=DoubleArray(p);
    cumulative=DoubleArray(p);
    broken=DoubleArray(p);
    se=DoubleArray(p);
    retention=intArrayOf(0,p,p,p);
    var running=0.0;
    for(h in 0 until p) {
        val value=fit.eigen.values[h];
        ratio[h]=value/total;
        running+=ratio[h];
        cumulative[h]=running;
        var sum=0.0;
        for(i in h+1..p)sum+=1.0/i;
        broken[h]=sum/p;
        se[h]=value*sqrt(2.0/n);
        if(value>average)retention[0]++
    };
    for(h in 0 until p)if(ratio[h]<=broken[h]) {
        retention[1]=h;
        break
    };
    for(h in 0 until p)if(ratio[h]<=parallel[h]) {
        retention[2]=h;
        break
    };
    for(h in 0 until p)if(cumulative[h]>=settings.number("CUMULATIVE_TARGET")) {
        retention[3]=h+1;
        break
    };
    val rule=settings.text("COMPONENTS");
    val rules=listOf("kaiser","broken_stick","parallel","cumulative");
    k=if(rule in rules)maxOf(1,retention[rules.indexOf(rule)]) else rule.toInt()
}
private fun criterion(g: Array<DoubleArray>): Double {
    var value=0.0;
    for(h in 0 until k) {
        var q4=0.0;
        var q2=0.0;
        for(j in 0 until p) {
            q4+=(g[j][h]*g[j][h])*(g[j][h]*g[j][h]);
            q2+=g[j][h]*g[j][h]
        };
        value+=q4/p-(q2/p)*(q2/p)
    };
    return value
}
private fun rotate(g: Array<DoubleArray>,a: Int,b: Int) {
    var sa=0.0;
    var sb=0.0;
    var sc=0.0;
    var sd=0.0;
    for(j in 0 until p) {
        val phi=g[j][a]*g[j][a]-g[j][b]*g[j][b];
        val psi=2*g[j][a]*g[j][b];
        sa+=phi;
        sb+=psi;
        sc+=phi*phi-psi*psi;
        sd+=2*phi*psi
    };
    val num=sd-2*sa*sb/p;
    val den=sc-(sa*sa-sb*sb)/p;
    val omega=sqrt(num*num+den*den);
    if(omega==0.0)return;
    val cos4=den/omega;
    val sin4=num/omega;
    val cos2=sqrt((1+cos4)/2);
    val sin2=if(cos2==0.0)1.0 else sin4/(2*cos2);
    val cos1=sqrt((1+cos2)/2);
    val sin1=sin2/(2*cos1);
    for(j in 0 until p) {
        val first=g[j][a];
        val second=g[j][b];
        g[j][a]=cos1*first+sin1*second;
        g[j][b]=-sin1*first+cos1*second
    }
}
private fun loadings() {
    loadings=Array(p) {
        DoubleArray(p)
    };
    circle=Array(p) {
        DoubleArray(2)
    };
    communalities=DoubleArray(p);
    val etas=DoubleArray(p);
    val g=Array(p) {
        DoubleArray(k)
    };
    for(j in 0 until p) {
        for(h in 0 until p)loadings[j][h]=fit.eigen.vectors[h][j]*sqrt(fit.eigen.values[h]);
        var sum=0.0;
        for(h in 0 until k)sum+=loadings[j][h]*loadings[j][h];
        communalities[j]=sum/fit.matrix[j][j];
        etas[j]=sqrt(sum);
        for(h in 0 until k)g[j][h]=loadings[j][h]/etas[j];
        for(h in 0 until 2)circle[j][h]=loadings[j][h]/sqrt(fit.matrix[j][j])
    };
    val cycles=settings.integer("VARIMAX_CYCLES");
    criteria=DoubleArray(cycles+1);
    criteria[0]=criterion(g);
    for(cycle in 1..cycles) {
        for(a in 0 until k-1)for(b in a+1 until k)rotate(g,a,b);
        criteria[cycle]=criterion(g)
    };
    val columns=Array(k) {
        DoubleArray(p)
    };
    val squares=DoubleArray(k);
    for(h in 0 until k) {
        for(j in 0 until p)columns[h][j]=g[j][h]*etas[j];
        Matrix.orient(columns[h]);
        squares[h]=Matrix.dot(columns[h],columns[h])
    };
    val order=top(squares,k);
    rotated=Array(k) {
        columns[order[it]]
    };
    rotationSquares=DoubleArray(k) {
        squares[order[it]]
    };
    closest=IntArray(k);
    congruences=DoubleArray(k);
    for(h in 0 until k) {
        val values=DoubleArray(k) {
            q->abs(congruence(rotated[h],Matrix.column(loadings,q)))
        };
        closest[h]=maximum(values);
        congruences[h]=values[closest[h]]
    }
}
private fun eigenReport(): List<String> {
    val output=mutableListOf<String>();
    val incomplete=data.data.rows.filter {
        missing(it.values)
    }.map {
        it.id
    };
    section(output,listOf("pca rows ${data.data.rows.size} used $n variables $p missing ${settings.text("MISSING")} scaling ${settings.text("SCALING")}",
        "incomplete ${incomplete.size} ${if(incomplete.isEmpty())"-" else incomplete.joinToString(" ")}"));
    var part=mutableListOf("variable observed missing mean sd min max msa");
    for(j in 0 until p)part+="${names[j]} ${observed[j]} ${data.data.rows.size-observed[j]} ${reals(summary[j])} ${real(msa[j])}";
    part+="adequacy kmo ${real(kmo)} determinant ${format(determinant,6)} bartlett ${real(bartlett)} df ${p*(p-1)/2}";
    section(output,part);
    part=mutableListOf("matrix ${settings.text("SCALING")}");
    for(j in 0 until p)part+=names[j]+" "+reals(fit.matrix[j]);
    val pairs=mutableListOf<Pair<Int,Int>>();
    val strengths=mutableListOf<Double>();
    for(j in 0 until p)for(h in j+1 until p) {
        pairs+=j to h;
        strengths+=abs(fit.correlation[j][h])
    };
    var strongest="strongest";
    for(index in top(strengths.toDoubleArray(),top)) {
        val (j,h)=pairs[index];
        strongest+=" ${names[j]}:${names[h]}:${real(fit.correlation[j][h])}"
    };
    part+=strongest;
    section(output,part);
    part=mutableListOf("jacobi sweeps ${fit.eigen.sweeps}","eigenvalues total ${real(total)} average ${real(average)}",
        "k eigenvalue ratio cumulative broken_stick parallel se separated");
    for(h in 0 until p) {
        var separated=true;
        if(h>0&&abs(fit.eigen.values[h]-fit.eigen.values[h-1])<=se[h])separated=false;
        if(h+1<p&&abs(fit.eigen.values[h]-fit.eigen.values[h+1])<=se[h])separated=false;
        part+="${h+1} ${reals(doubleArrayOf(fit.eigen.values[h],ratio[h],cumulative[h],broken[h],parallel[h],se[h]))} ${if(separated)"yes" else "no"}"
    };
    part+="retention kaiser ${retention[0]} broken_stick ${retention[1]} parallel ${retention[2]} cumulative ${retention[3]} target ${real(settings.number("CUMULATIVE_TARGET"))}";
    part+="components $k rule ${settings.text("COMPONENTS")}";
    section(output,part);
    part=mutableListOf("eigenvectors","variable "+components("pc",p).joinToString(" "));
    for(j in 0 until p)part+=names[j]+" "+reals(Matrix.column(fit.eigen.vectors,j));
    section(output,part);
    part=mutableListOf("power_iteration iterations 1000","k jacobi power agree_at match");
    val powers=Eigen.power(fit.matrix,fit.eigen.vectors);
    var matches=0;
    for(h in 0 until p) {
        val power=powers[h];
        val match=abs(power.value-fit.eigen.values[h])<=1e-8*fit.eigen.values[0]&&Matrix.difference(power.vector,fit.eigen.vectors[h])<=0.000001;
        if(match)matches++;
        part+="${h+1} ${real(fit.eigen.values[h])} ${real(power.value)} ${if(power.agreement==0)"-" else power.agreement.toString()} ${if(match)"yes" else "no"}"
    };
    part+="cross_check $matches/$p";
    section(output,part);
    part=mutableListOf("scores","component sd min min_id max max_id contributors");
    for(h in 0 until k) {
        val scores=DoubleArray(n);
        val contributions=DoubleArray(n);
        var sum=0.0;
        for(i in 0 until n) {
            scores[i]=observations[i].scores[h];
            sum+=scores[i]*scores[i];
            contributions[i]=scores[i]*scores[i]/((n-1)*fit.eigen.values[h])
        };
        val low=minimum(scores);
        val high=maximum(scores);
        var line="pc${h+1} ${real(sqrt(sum/(n-1)))} ${real(scores[low])} ${fit.ids[low]} ${real(scores[high])} ${fit.ids[high]}";
        for(i in top(contributions,top))line+=" ${fit.ids[i]}:${real(contributions[i])}";
        part+=line
    };
    section(output,part);
    part=mutableListOf("varimax components $k cycles ${settings.integer("VARIMAX_CYCLES")}");
    for(c in criteria.indices)part+="cycle $c criterion ${format(criteria[c],6)}";
    for(h in 0 until k)part+="rc${h+1} ss ${real(rotationSquares[h])} ratio ${real(rotationSquares[h]/total)} closest pc${closest[h]+1} congruence ${real(congruences[h])}";
    section(output,part);
    part=mutableListOf("sensitivity","missing scaling rows sweeps eigenvalues cumulative congruence");
    for(strategy in listOf("listwise","mean"))for(scaling in listOf("covariance","correlation")) {
        val alternative=Fit(strategy,scaling);
        val values=alternative.eigen.values;
        val sum=Matrix.sum(values);
        var cum=0.0;
        var line="$strategy $scaling ${alternative.ids.size} ${alternative.eigen.sweeps}";
        for(h in 0 until k) {
            line+=" "+real(values[h]);
            cum+=values[h]/sum
        };
        line+=" "+real(cum);
        for(h in 0 until k)line+=" "+real(abs(Matrix.dot(alternative.eigen.vectors[h],fit.eigen.vectors[h])));
        part+=line
    };
    section(output,part);
    return output
}
private fun loadingsReport(): List<String> {
    val header=listOf("variable")+components("pc",k)+"communality"+components("rc",k);
    val output=mutableListOf(header.joinToString(","));
    for(j in 0 until p) {
        var line=names[j];
        for(h in 0 until k)line+=","+real(loadings[j][h]);
        line+=","+real(communalities[j]);
        for(h in 0 until k)line+=","+real(rotated[h][j]);
        output+=line
    };
    return output
}
private fun scoresReport(): List<String> {
    val output=mutableListOf("id,set,"+components("pc",k).joinToString(","));
    for(set in 0 until 2)for(observation in if(set==0)observations else projections) {
        var line=observation.id+","+if(set==0)"data" else "supplementary";
        for(h in 0 until k)line+=","+real(observation.scores[h]);
        output+=line
    };
    return output
}
private fun outliersReport(): List<String> {
    val output=mutableListOf("diagnostics components $k t2_limit ${real(settings.number("T2_LIMIT"))} spe_limit ${real(settings.number("SPE_LIMIT"))}",
        "id t2 spe quality flag");
    var tCount=0;
    var qCount=0;
    var both=0;
    var any=0;
    for(row in observations) {
        output+=row.id+" "+reals(doubleArrayOf(row.t2,row.spe,row.quality))+" "+row.flag;
        if('T' in row.flag)tCount++;
        if('Q' in row.flag)qCount++;
        if(row.flag=="TQ")both++;
        if(row.flag!="-")any++
    };
    output+="flagged t2 $tCount spe $qCount both $both any $any";
    for(kind in 0 until 2) {
        val label=if(kind==0)"t2" else "spe";
        val part=mutableListOf("top $label","rank id $label variable contribution");
        val values=DoubleArray(n) {
            if(kind==0)observations[it].t2 else observations[it].spe
        };
        val order=top(values,top);
        for(position in order.indices) {
            val i=order[position];
            val row=observations[i];
            val contributions=if(kind==0)row.tContributions else row.qContributions;
            val variable=maximum(contributions);
            part+="${position+1} ${row.id} ${real(values[i])} ${names[variable]} ${real(contributions[variable])}"
        };
        section(output,part)
    };
    var part=mutableListOf("reconstruction","k mean_spe max_spe max_id");
    for(count in 1 until p) {
        val errors=DoubleArray(n);
        for(i in 0 until n) {
            val row=observations[i];
            val residuals=Pca.residuals(row.z,row.scores,fit.eigen.vectors,count);
            errors[i]=Matrix.dot(residuals,residuals)
        };
        val worst=maximum(errors);
        part+="$count ${real(Matrix.sum(errors)/n)} ${real(errors[worst])} ${fit.ids[worst]}"
    };
    section(output,part);
    part=mutableListOf("supplementary","id "+components("pc",k).joinToString(" ")+" t2 spe flag nearest distance");
    for(row in projections) {
        val distances=DoubleArray(n);
        for(i in 0 until n)for(h in 0 until k) {
            val delta=row.scores[h]-observations[i].scores[h];
            distances[i]+=delta*delta
        };
        val nearest=minimum(distances);
        var line=row.id;
        for(h in 0 until k)line+=" "+real(row.scores[h]);
        part+=line+" ${real(row.t2)} ${real(row.spe)} ${row.flag} ${fit.ids[nearest]} ${real(sqrt(distances[nearest]))}"
    };
    section(output,part);
    return output
}
private fun axes(grid: Array<CharArray>,origin: Plot.Cell) {
    grid[origin.row].fill('-');
    for(row in grid)row[origin.col]='|';
    grid[origin.row][origin.col]='+'
}
private fun points(grid: Array<CharArray>,cells: List<Plot.Cell>) {
    val counts=Array(grid.size) {
        IntArray(grid[0].size)
    };
    for(cell in cells)counts[cell.row][cell.col]++;
    for(row in grid.indices)for(col in grid[0].indices) {
        val count=counts[row][col];
        if(count>0)grid[row][col]=if(count==1)'.' else if(count<=3)'o' else '@'
    }
}
private fun mark(grid: Array<CharArray>,cell: Plot.Cell,value: Char) {
    grid[cell.row][cell.col]=value
}
private fun inside(row: Int,col: Int,rc: Int,cc: Int,radius: Int): Boolean {
    val x=col-cc;
    val y=2*(row-rc);
    return x*x+y*y<=radius*radius
}
private fun plots(): List<String> {
    var width=settings.integer("SCREE_WIDTH");
    val kaiser=Plot.rounded(average/fit.eigen.values[0],width);
    val output=mutableListOf("scree width $width kaiser_column $kaiser");
    for(h in 0 until p)output+=Plot.scree(Plot.rounded(fit.eigen.values[h]/fit.eigen.values[0],
        width),kaiser,Plot.rounded(broken[h]*total/fit.eigen.values[0],width),width)+" pc${h+1} ${real(fit.eigen.values[h])}";
    var mx=0.0;
    var my=0.0;
    var lx=0.0;
    var ly=0.0;
    for(row in observations+projections) {
        mx=maxOf(mx,abs(row.scores[0]));
        my=maxOf(my,abs(row.scores[1]))
    };
    for(j in 0 until p) {
        lx=maxOf(lx,abs(loadings[j][0]));
        ly=maxOf(ly,abs(loadings[j][1]))
    };
    val scale=0.9*minOf(mx/lx,my/ly);
    width=settings.integer("BIPLOT_SIZE");
    var height=settings.second("BIPLOT_SIZE");
    var grid=Plot.grid(height,width);
    val origin=Plot.biplot(0.0,0.0,mx,my,width,height);
    axes(grid,origin);
    val tips=mutableListOf<Plot.Cell>();
    var cells=mutableListOf<Plot.Cell>();
    for(j in 0 until p) {
        val tip=Plot.biplot(scale*loadings[j][0],scale*loadings[j][1],mx,my,width,height);
        tips+=tip;
        for(cell in Plot.shaft(origin,tip))mark(grid,cell,Plot.shaftCharacter(origin,tip))
    };
    for(row in observations)cells+=Plot.biplot(row.scores[0],row.scores[1],mx,my,width,height);
    points(grid,cells);
    for(i in 0 until n)if(observations[i].flag!="-")mark(grid,cells[i],'X');
    for(row in projections)mark(grid,Plot.biplot(row.scores[0],row.scores[1],mx,my,width,height),'*');
    for(j in 0 until p)mark(grid,tips[j],('A'.code+j).toChar());
    var part=mutableListOf("biplot pc1 pc2 width $width height $height","x ${real(-mx)} ${real(mx)} y ${real(-my)} ${real(my)} arrow_scale ${real(scale)}");
    part+=Plot.framed(grid);
    for(j in 0 until p)part+="${('A'.code+j).toChar()} ${names[j]} ${reals(doubleArrayOf(loadings[j][0],loadings[j][1]))}";
    section(output,part);
    val radius=settings.integer("CIRCLE_RADIUS");
    val rc=radius/2+1;
    val cc=radius+1;
    grid=Plot.grid(radius+3,2*radius+3);
    axes(grid,Plot.Cell(rc,cc));
    for(row in grid.indices)for(col in grid[0].indices)if(inside(row,col,rc,cc,radius)&&(!inside(row-1,
        col,rc,cc,radius)||!inside(row+1,col,rc,cc,radius)||!inside(row,col-1,rc,cc,radius)||!inside(row,
        col+1,rc,cc,radius)))grid[row][col]='.';
    for(j in 0 until p)mark(grid,Plot.circle(circle[j][0],circle[j][1],radius),('A'.code+j).toChar());
    part=mutableListOf("circle radius $radius");
    part+=Plot.framed(grid);
    for(j in 0 until p)part+="${('A'.code+j).toChar()} ${names[j]} ${reals(circle[j])} ${real(circle[j][0]*circle[j][0]+circle[j][1]*circle[j][1])}";
    section(output,part);
    width=settings.integer("DIAGNOSTIC_SIZE");
    height=settings.second("DIAGNOSTIC_SIZE");
    val xmax=2*settings.number("T2_LIMIT");
    val ymax=2*settings.number("SPE_LIMIT");
    grid=Plot.grid(height,width);
    axes(grid,Plot.diagnostic(settings.number("T2_LIMIT"),settings.number("SPE_LIMIT"),xmax,ymax,width,height));
    cells=mutableListOf();
    for(row in observations)cells+=Plot.diagnostic(row.t2,row.spe,xmax,ymax,width,height);
    points(grid,cells);
    for(row in projections)mark(grid,Plot.diagnostic(row.t2,row.spe,xmax,ymax,width,height),'*');
    part=mutableListOf("diagnostic width $width height $height t2_max ${real(xmax)} spe_max ${real(ymax)}");
    part+=Plot.framed(grid);
    section(output,part);
    return output
}
fun main() {
    data=Dataset.read();
    settings=data.settings;
    names=data.data.names;
    p=names.size;
    top=settings.integer("TOP_ROWS");
    summarize();
    fit=Fit(settings.text("MISSING"),settings.text("SCALING"));
    n=fit.ids.size;
    adequacy();
    variances();
    loadings();
    for(i in 0 until n)observations+=Observation(fit.ids[i],fit.values[i]);
    for(row in data.supplementary.rows)projections+=Observation(row.id,row.values);
    write("eigen.txt",eigenReport());
    write("loadings.csv",loadingsReport());
    write("scores.csv",scoresReport());
    write("outliers.txt",outliersReport());
    write("plots.txt",plots())
}
