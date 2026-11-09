object Shading {
    data class Phong(val diffuse: Long,val specular: Long)
    data class Refraction(val reflected: Long,val transmitted: Long,val direction: Vector3?,val totalInternal: Boolean)
    fun base(material: Scene.Material,point: Vector3): Scene.Color {
        val checker=material.checker;
        if(checker!=null) {
            val k=FixedPoint.divide(point.x,material.checkerSize)+FixedPoint.divide(point.y,
                material.checkerSize)+FixedPoint.divide(point.z,material.checkerSize);
            if(k%2!=0L)return checker
        };
        return material.color
    }
    fun phong(material: Scene.Material,normal: Vector3,light: Vector3,view: Vector3,ndl: Long,intensity: Long,factor: Long): Phong {
        val effective=FixedPoint.multiply(intensity,factor);
        val diffuse=FixedPoint.multiply(FixedPoint.multiply(material.kd,ndl),effective);
        val rv=normal.scale(2*ndl).subtract(light).dot(view);
        var specular=0L;
        if(rv>0) {
            var power=FixedPoint.S;
            for(n in 0 until material.exponent)power=FixedPoint.multiply(power,rv);
            specular=FixedPoint.multiply(FixedPoint.multiply(material.ks,power),effective)
        };
        return Phong(diffuse,specular)
    }
    fun reflected(direction: Vector3,normal: Vector3)=direction.subtract(normal.scale(2*direction.dot(normal))).normalize()
    fun refracted(material: Scene.Material,direction: Vector3,normal: Vector3,front: Boolean): Refraction {
        val wr=material.kr;
        val wt=material.kt;
        if(wt==0L)return Refraction(wr,wt,null,false);
        val eta=if(front)FixedPoint.divide(FixedPoint.S*FixedPoint.S,material.ior) else material.ior;
        val cn=-direction.dot(normal);
        val disc=FixedPoint.S*FixedPoint.S-FixedPoint.divide(FixedPoint.multiply(eta,eta)*(FixedPoint.S*FixedPoint.S-cn*cn),FixedPoint.S);
        if(disc<0)return Refraction(wr+wt,0,null,true);
        val transmitted=direction.scale(eta).add(normal.scale(FixedPoint.multiply(eta,cn)-FixedPoint.isqrt(disc))).normalize();
        val r0=FixedPoint.divide((material.ior-FixedPoint.S)*FixedPoint.S,material.ior+FixedPoint.S);
        val reflectance=FixedPoint.multiply(r0,r0);
        val x=FixedPoint.S-minOf(cn,FixedPoint.S);
        var power=FixedPoint.S;
        for(n in 0 until 5)power=FixedPoint.multiply(power,x);
        val fresnel=reflectance+FixedPoint.multiply(FixedPoint.S-reflectance,power);
        val transfer=FixedPoint.multiply(material.kt,fresnel);
        return Refraction(wr+transfer,wt-transfer,transmitted,false)
    }
    fun mix(colors: List<Scene.Color>,weights: LongArray): Scene.Color {
        val values=LongArray(3);
        for(c in 0..2)for(i in colors.indices)values[c]+=FixedPoint.divide(colors[i].component(c)*weights[i],FixedPoint.S);
        return Scene.Color.of(values)
    }
}
