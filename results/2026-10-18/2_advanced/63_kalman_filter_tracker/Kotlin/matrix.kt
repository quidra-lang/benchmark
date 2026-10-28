object Matrix {
    fun total(values: DoubleArray): Double {
        var result=0.0;
        for(value in values)result+=value;
        return result
    }
    fun diagonal(values: DoubleArray)=Array(values.size) {
        i->DoubleArray(values.size) {
            j->if(i==j)values[i] else 0.0
        }
    }
    fun identity(n: Int)=diagonal(DoubleArray(n) {
        1.0
    })
    fun transpose(a: Array<DoubleArray>)=Array(a[0].size) {
        j->DoubleArray(a.size) {
            i->a[i][j]
        }
    }
    fun add(a: Array<DoubleArray>,b: Array<DoubleArray>)=Array(a.size) {
        i->DoubleArray(a[0].size) {
            j->a[i][j]+b[i][j]
        }
    }
    fun subtract(a: Array<DoubleArray>,b: Array<DoubleArray>)=Array(a.size) {
        i->DoubleArray(a[0].size) {
            j->a[i][j]-b[i][j]
        }
    }
    fun add(a: DoubleArray,b: DoubleArray)=DoubleArray(a.size) {
        a[it]+b[it]
    }
    fun subtract(a: DoubleArray,b: DoubleArray)=DoubleArray(a.size) {
        a[it]-b[it]
    }
    fun product(a: Array<DoubleArray>,b: Array<DoubleArray>): Array<DoubleArray> {
        val c=Array(a.size) {
            DoubleArray(b[0].size)
        };
        for(i in a.indices)for(j in b[0].indices)for(k in b.indices)c[i][j]+=a[i][k]*b[k][j];
        return c
    }
    fun product(a: Array<DoubleArray>,b: DoubleArray): DoubleArray {
        val c=DoubleArray(a.size);
        for(i in a.indices)for(k in b.indices)c[i]+=a[i][k]*b[k];
        return c
    }
    fun inverse(a: Array<DoubleArray>): Array<DoubleArray> {
        val n=a.size;
        val x=Array(n) {
            DoubleArray(2*n)
        };
        for(i in 0 until n) {
            a[i].copyInto(x[i]);
            x[i][n+i]=1.0
        };
        for(c in 0 until n) {
            val p=x[c][c];
            for(j in 0 until 2*n)x[c][j]/=p;
            for(i in 0 until n)if(i!=c) {
                val f=x[i][c];
                for(j in 0 until 2*n)x[i][j]-=f*x[c][j]
            }
        };
        return Array(n) {
            x[it].copyOfRange(n,2*n)
        }
    }
    fun determinant2(a: Array<DoubleArray>)=a[0][0]*a[1][1]-a[0][1]*a[1][0]
    fun quadratic2(u: DoubleArray,a: Array<DoubleArray>)=u[0]*(a[0][0]*u[0]+a[0][1]*u[1])+u[1]*(a[1][0]*u[0]+a[1][1]*u[1])
}
