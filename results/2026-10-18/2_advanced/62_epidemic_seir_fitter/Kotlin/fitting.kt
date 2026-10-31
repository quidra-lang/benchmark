object Fitting {
    const val PHI=0.6180339887498949
    data class GoldenRecord(val a: Double,val b: Double,val c: Double,val d: Double,val fc: Double,val fd: Double)
    data class Golden(val point: Double,val value: Double,val records: List<GoldenRecord>)
    fun golden(function: (Double)->Double,first: Double,last: Double,iterations: Int): Golden {
        var a=first;
        var b=last;
        var c=b-PHI*(b-a);
        var d=a+PHI*(b-a);
        var fc=function(c);
        var fd=function(d)
        val records=mutableListOf(GoldenRecord(a,b,c,d,fc,fd))
        repeat(iterations) {
            if(fc<fd) {
                b=d;
                d=c;
                fd=fc;
                c=b-PHI*(b-a);
                fc=function(c)
            } else {
                a=c;
                c=d;
                fc=fd;
                d=a+PHI*(b-a);
                fd=function(d)
            };
            records.add(GoldenRecord(a,b,c,d,fc,fd))
        }
        return if(fc<fd)Golden(c,fc,records) else Golden(d,fd,records)
    }
    data class Point(val beta: Double,val gamma: Double)
    data class Vertex(val serial: Int,val beta: Double,val gamma: Double,val value: Double)
    data class Operation(val name: String,val best: Vertex)
    data class Simplex(val initial: List<Vertex>,val operations: List<Operation>,val vertices: List<Vertex>)
    val ordering=compareBy<Vertex> {
        it.value
    }.thenBy {
        it.serial
    }
    fun toward(origin: Point,target: Point,factor: Double)=Point(origin.beta+factor*(target.beta-origin.beta),origin.gamma+factor*(target.gamma-origin.gamma))
    fun nelder(objective: (Double,Double)->Double,beta: Double,gamma: Double,db: Double,dg: Double,
        alpha: Double,chi: Double,psi: Double,omega: Double,iterations: Int): Simplex {
        var vertices=mutableListOf(Vertex(0,beta,gamma,objective(beta,gamma)),Vertex(1,beta+db,
            gamma,objective(beta+db,gamma)),Vertex(2,beta,gamma+dg,objective(beta,gamma+dg)))
        val initial=vertices.toList();
        val operations=mutableListOf<Operation>();
        var serial=3
        repeat(iterations) {
            vertices.sortWith(ordering);
            val first=vertices[0];
            val second=vertices[1];
            val third=vertices[2]
            val origin=Point((first.beta+second.beta)/2,(first.gamma+second.gamma)/2);
            val reflected=Point(origin.beta+alpha*(origin.beta-third.beta),origin.gamma+alpha*(origin.gamma-third.gamma))
            val fr=objective(reflected.beta,reflected.gamma);
            var value=0.0;
            var accepted: Point?=null;
            var operation="shrink"
            if(fr<first.value) {
                val expanded=toward(origin,reflected,chi);
                val fe=objective(expanded.beta,expanded.gamma);
                if(fe<fr) {
                    accepted=expanded;
                    value=fe;
                    operation="expand"
                } else {
                    accepted=reflected;
                    value=fr;
                    operation="reflect"
                }
            }
            else if(fr<second.value) {
                accepted=reflected;
                value=fr;
                operation="reflect"
            }
            else if(fr<third.value) {
                val contracted=toward(origin,reflected,psi);
                val fc=objective(contracted.beta,contracted.gamma);
                if(fc<=fr) {
                    accepted=contracted;
                    value=fc;
                    operation="contract_out"
                }
            }
            else {
                val contracted=toward(origin,Point(third.beta,third.gamma),psi);
                val fc=objective(contracted.beta,contracted.gamma);
                if(fc<third.value) {
                    accepted=contracted;
                    value=fc;
                    operation="contract_in"
                }
            }
            vertices=mutableListOf(first);
            val chosen=accepted
            if(chosen==null)for(vertex in listOf(second,third)) {
                val point=toward(Point(first.beta,first.gamma),Point(vertex.beta,vertex.gamma),omega);
                vertices.add(Vertex(serial++,point.beta,point.gamma,objective(point.beta,point.gamma)))
            }
            else {
                vertices.add(second);
                vertices.add(Vertex(serial++,chosen.beta,chosen.gamma,value))
            }
            vertices.sortWith(ordering);
            operations.add(Operation(operation,vertices[0]))
        }
        return Simplex(initial,operations,vertices)
    }
}
