object Transient {
    data class Step(val field: DoubleArray,val intermediate: DoubleArray?)
    fun flow(s: Heat.Thermal,x: DoubleArray,p: Int,first: Int,last: Int): Double {
        var sum=0.0
        for(f in first..last) {
            val face=s.faces[p][f];
            if(face.neighbor>=0)sum+=face.g*(x[face.neighbor]-x[p]) else if(face.boundary)sum+=face.g*(face.theta-x[p])
        }
        return sum
    }
    fun thomas(lower: DoubleArray,diagonal: DoubleArray,upper: DoubleArray,rhs: DoubleArray): DoubleArray {
        val n=diagonal.size;
        val u=DoubleArray(n);
        val v=DoubleArray(n);
        val x=DoubleArray(n);
        u[0]=upper[0]/diagonal[0];
        v[0]=rhs[0]/diagonal[0]
        for(i in 1 until n) {
            val pivot=diagonal[i]-lower[i]*u[i-1];
            u[i]=upper[i]/pivot;
            v[i]=(rhs[i]-lower[i]*v[i-1])/pivot
        }
        x[n-1]=v[n-1];
        for(i in n-2 downTo 0)x[i]=v[i]-u[i]*x[i+1]
        return x
    }
    fun sweep(s: Heat.Thermal,tau: Double,rhs: DoubleArray,horizontal: Boolean): DoubleArray {
        val m=s.mesh;
        val lines=if(horizontal)m.height else m.width;
        val length=if(horizontal)m.width else m.height;
        val first=if(horizontal)0 else 2;
        val field=DoubleArray(m.count)
        for(line in 0 until lines) {
            val lower=DoubleArray(length);
            val diagonal=DoubleArray(length);
            val upper=DoubleArray(length);
            val right=DoubleArray(length);
            val cells=IntArray(length)
            for(i in 0 until length) {
                val p=if(horizontal)m.cell(line,i) else m.cell(i,line);
                cells[i]=p;
                val a=s.faces[p][first];
                val b=s.faces[p][first+1]
                lower[i]=if(a.neighbor>=0)-a.g else 0.0;
                upper[i]=if(b.neighbor>=0)-b.g else 0.0;
                diagonal[i]=s.capacity[p]/tau+a.g+b.g
                var value=rhs[p];
                if(a.boundary)value+=a.g*a.theta;
                if(b.boundary)value+=b.g*b.theta;
                right[i]=value
            }
            val solved=thomas(lower,diagonal,upper,right);
            for(i in 0 until length)field[cells[i]]=solved[i]
        }
        return field
    }
    fun advance(method: String,s: Heat.Thermal,field: DoubleArray,source: DoubleArray,dt: Double): Step {
        val n=s.mesh.count;
        val rhs=DoubleArray(n)
        if(method=="ftcs") {
            for(p in 0 until n)rhs[p]=field[p]+dt*(flow(s,field,p,0,3)+source[p])/s.capacity[p];
            return Step(rhs,null)
        }
        val backward=method=="backward_euler";
        val tau=if(backward)dt else dt/2;
        val vertical=DoubleArray(n)
        for(p in 0 until n) {
            vertical[p]=flow(s,field,p,2,3);
            rhs[p]=s.capacity[p]/tau*field[p]+vertical[p]+source[p]
        }
        val middle=sweep(s,tau,rhs,true)
        for(p in 0 until n)rhs[p]=if(backward)s.capacity[p]/dt*middle[p]-vertical[p] else s.capacity[p]/tau*middle[p]+flow(s,middle,p,0,1)+source[p]
        return Step(sweep(s,tau,rhs,false),middle)
    }
}
