import kotlin.math.*

object Smo {
    data class Pass(val full: Boolean,val examined: Int,val changed: Int,val alpha: DoubleArray?)
    class Model(val points: List<Kernels.Point>,val labels: IntArray,val kernel: Kernels.Kernel,
        val matrix: Array<DoubleArray>,val c: Double,settings: Dataset.Settings) {
        val tolerance=settings.tolerance;
        val eps=settings.eps;
        val maximum=settings.maximum;
        var b=0.0
        val alpha=DoubleArray(points.size);
        val errors=DoubleArray(points.size) {
            -labels[it].toDouble()
        }
        var fullPasses=0;
        var nonboundPasses=0;
        var examined=0;
        var steps=0;
        val choices=IntArray(3);
        val clipping=IntArray(3);
        val records=mutableListOf<Pass>();
        var converged=false
        fun passes()=fullPasses+nonboundPasses
        fun nonbound(i: Int)=alpha[i]>0&&alpha[i]<c
        fun snap(a: Double)=if(a<0.00000001)0.0 else if(a>c-0.00000001)c else a
        fun take(first: Int,second: Int): Boolean {
            if(first==second)return false
            val alpha1=alpha[first];
            val alpha2=alpha[second];
            val e1=errors[first];
            val e2=errors[second];
            val y1=labels[first];
            val y2=labels[second]
            val lo=if(y1!=y2)maxOf(0.0,alpha2-alpha1) else maxOf(0.0,alpha2+alpha1-c)
            val hi=if(y1!=y2)minOf(c,c+alpha2-alpha1) else minOf(c,alpha2+alpha1)
            if(lo==hi)return false
            val k11=matrix[first][first];
            val k12=matrix[first][second];
            val k22=matrix[second][second];
            val eta=k11+k22-2*k12
            if(eta<=0)return false
            var a2=alpha2+y2*(e1-e2)/eta;
            var clip=0
            if(a2<lo) {
                a2=lo;
                clip=1
            } else if(a2>hi) {
                a2=hi;
                clip=2
            }
            a2=snap(a2);
            if(abs(a2-alpha2)<eps*(a2+alpha2+eps))return false
            val a1=snap(alpha1+y1*y2*(alpha2-a2));
            val t1=y1*(a1-alpha1);
            val t2=y2*(a2-alpha2)
            val b1=e1+t1*k11+t2*k12+b;
            val b2=e2+t1*k12+t2*k22+b
            val threshold=if(a1>0&&a1<c)b1 else if(a2>0&&a2<c)b2 else (b1+b2)/2;
            val delta=threshold-b
            for(i in errors.indices)errors[i]=errors[i]+(t1*matrix[first][i]+t2*matrix[second][i]-delta)
            if(a1>0&&a1<c)errors[first]=0.0;
            if(a2>0&&a2<c)errors[second]=0.0
            alpha[first]=a1;
            alpha[second]=a2;
            b=threshold;
            steps++;
            clipping[clip]++
            return true
        }
        fun examine(second: Int): Int {
            examined++;
            val r=errors[second]*labels[second]
            if(!(r< -tolerance&&alpha[second]<c||r>tolerance&&alpha[second]>0))return 0
            var partner=-1;
            var largest=-1.0
            for(i in alpha.indices)if(i!=second&&nonbound(i)) {
                val difference=abs(errors[i]-errors[second]);
                if(difference>largest) {
                    largest=difference;
                    partner=i
                }
            }
            if(partner>=0&&take(partner,second)) {
                choices[0]++;
                return 1
            }
            for(i in alpha.indices)if(nonbound(i)&&take(i,second)) {
                choices[1]++;
                return 1
            }
            for(i in alpha.indices)if(take(i,second)) {
                choices[2]++;
                return 1
            }
            return 0
        }
        fun fit(): Model {
            var all=true
            while(true) {
                val before=examined;
                var changed=0;
                for(i in alpha.indices)if(all||nonbound(i))changed+=examine(i)
                if(all)fullPasses++ else nonboundPasses++;
                records.add(Pass(all,examined-before,changed,if(all)alpha.copyOf() else null))
                if(all&&changed==0) {
                    converged=true;
                    break
                };
                if(passes()==maximum)break;
                if(all)all=false else if(changed==0)all=true
            }
            return this
        }
        fun decision(point: Kernels.Point): Double {
            var sum=0.0;
            for(i in alpha.indices)if(alpha[i]>0)sum+=alpha[i]*labels[i]*kernel.value(points[i],point);
            return sum-b
        }
        fun raw(coefficients: DoubleArray): DoubleArray {
            val values=DoubleArray(alpha.size);
            for(i in values.indices)for(j in alpha.indices)if(coefficients[j]>0)values[i]+=coefficients[j]*labels[j]*matrix[i][j];
            return values
        }
        fun training(): DoubleArray {
            val values=raw(alpha);
            for(i in values.indices)values[i]-=b;
            return values
        }
        fun decisions(examples: List<Dataset.Example>)=DoubleArray(examples.size) {
            decision(examples[it].point)
        }
    }
    fun train(points: List<Kernels.Point>,labels: IntArray,kernel: Kernels.Kernel,matrix: Array<DoubleArray>,
        c: Double,settings: Dataset.Settings)=Model(points,labels,kernel,matrix,c,settings).fit()
}
