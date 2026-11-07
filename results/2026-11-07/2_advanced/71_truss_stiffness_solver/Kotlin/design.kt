import kotlin.math.*
object Design {
    const val PI=3.141592653589793
    fun buckling(p: Assembly.Properties,g: Assembly.Geometry,inertia: Double=p.inertia)=PI*PI*p.young*inertia/(g.length*g.length)
    fun utilization(force: Double,p: Assembly.Properties,g: Assembly.Geometry,section: ModelIo.Section?=null): Double {
        val area=section?.area?:p.area;
        val inertia=section?.inertia?:p.inertia;
        return maxOf(abs(force/area)/p.yieldStress,maxOf(0.0,-force)/buckling(p,g,inertia))
    }
    fun slenderness(p: Assembly.Properties,g: Assembly.Geometry,section: ModelIo.Section?=null): Double {
        val area=section?.area?:p.area;
        val inertia=section?.inertia?:p.inertia;
        return g.length/sqrt(inertia/area)
    }
    fun limit(member: Int,combinations: List<Postprocess.Result>,settings: ModelIo.Settings)=if(combinations.any {
        it.forces[member]<0
    })settings.compressionLimit else settings.tensionLimit
    fun select(members: List<Int>,sections: List<ModelIo.Section>,properties: List<Assembly.Properties>,
        geometry: List<Assembly.Geometry>,combinations: List<Postprocess.Result>,limits: DoubleArray): Int {
        for((s,section) in sections.withIndex()) {
            var acceptable=true;
            for(m in members) {
                if(slenderness(properties[m],geometry[m],section)>limits[m]) {
                    acceptable=false;
                    break
                };
                for(result in combinations)if(utilization(result.forces[m],properties[m],geometry[m],
                    section)>1) {
                    acceptable=false;
                    break
                };
                if(!acceptable)break
            };
            if(acceptable)return s
        };
        return sections.lastIndex
    }
}
