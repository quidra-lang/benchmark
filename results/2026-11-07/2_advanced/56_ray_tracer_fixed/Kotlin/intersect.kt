object Intersect {
    data class Bounds(val lo: Vector3,val hi: Vector3)
    data class Slab(val near: Long,val nearAxis: Int,val far: Long,val farAxis: Int)
    data class Candidate(val distance: Long,val entering: Boolean,val axis: Int)
    fun bounds(obj: Scene.Obj,pad: Long): Bounds {
        val margin=Vector3(pad,pad,pad);
        if(obj.kind=="sphere") {
            val radius=obj.radius+pad;
            val extent=Vector3(radius,radius,radius);
            return Bounds(obj.center.subtract(extent),obj.center.add(extent))
        };
        return Bounds(obj.lo.subtract(margin),obj.hi.add(margin))
    }
    fun slab(box: Bounds,origin: Vector3,direction: Vector3): Slab? {
        var near=Long.MIN_VALUE;
        var far=Long.MAX_VALUE;
        var nearAxis=-1;
        var farAxis=-1;
        for(a in 0..2) {
            val d=direction.coordinate(a);
            val o=origin.coordinate(a);
            val lo=box.lo.coordinate(a);
            val hi=box.hi.coordinate(a);
            if(d==0L) {
                if(o<lo||o>hi)return null;
                continue
            };
            val t1=FixedPoint.divide((lo-o)*FixedPoint.S,d);
            val t2=FixedPoint.divide((hi-o)*FixedPoint.S,d);
            val entry=minOf(t1,t2);
            val exit=maxOf(t1,t2);
            if(entry>near) {
                near=entry;
                nearAxis=a
            };
            if(exit<far) {
                far=exit;
                farAxis=a
            }
        };
        return if(near>far)null else Slab(near,nearAxis,far,farAxis)
    }
    fun test(obj: Scene.Obj,origin: Vector3,direction: Vector3,epsilon: Long): Candidate? {
        if(obj.kind=="sphere") {
            val oc=origin.subtract(obj.center);
            val b=oc.dot(direction);
            val tc=FixedPoint.divide(-b*FixedPoint.S,direction.dot(direction));
            val h=oc.add(direction.scale(tc));
            val q=FixedPoint.divide(obj.radius*obj.radius,FixedPoint.S)-h.dot(h);
            if(q<0)return null;
            val w=FixedPoint.divide(FixedPoint.isqrt(q*FixedPoint.S)*FixedPoint.S,direction.length());
            val t1=tc-w;
            val t2=tc+w;
            if(t1>epsilon)return Candidate(t1,true,-1);
            if(t2>epsilon)return Candidate(t2,false,-1);
            return null
        };
        if(obj.kind=="plane") {
            val den=direction.dot(obj.normal);
            if(den==0L)return null;
            val t=FixedPoint.divide(obj.point.subtract(origin).dot(obj.normal)*FixedPoint.S,den);
            return if(t>epsilon)Candidate(t,true,-1) else null
        };
        val slab=slab(Bounds(obj.lo,obj.hi),origin,direction)?:return null;
        if(slab.near>epsilon)return Candidate(slab.near,true,slab.nearAxis);
        if(slab.far>epsilon)return Candidate(slab.far,false,slab.farAxis);
        return null
    }
    fun outward(obj: Scene.Obj,hit: Candidate,point: Vector3,direction: Vector3): Vector3 {
        if(obj.kind=="sphere")return point.subtract(obj.center).normalize();
        if(obj.kind=="plane")return obj.normal;
        var sign=if(direction.coordinate(hit.axis)>0)1L else -1L;
        if(hit.entering)sign=-sign;
        return Vector3.axis(hit.axis,sign*FixedPoint.S)
    }
}
