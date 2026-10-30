import java.io.File
class Interlocking(val layout: Layout) {
    data class Requirement(val point: String,val position: String)
    data class PointLock(val route: String,val position: String)
    companion object {
        fun names(text: String)=if(text=="-")emptyList() else text.split(',');
        fun requirements(text: String)=names(text).map {
            val f=it.split(':');
            Requirement(f[0],f[1])
        }
    }
    class Route(f: List<String>,layout: Layout) {
        val name=f[1];
        val start=f[2];
        val finish=f[3];
        val points=Interlocking.requirements(f[4]);
        val sections=names(f[5]);
        val overlap=names(f[6]);
        val flank=Interlocking.requirements(f[7]);
        val conflicts=names(f[8]);
        val approachTime=f[9].toInt();
        val direction=layout.signals.getValue(start).direction;
        val requirements=points+flank;
        var state: String?=null;
        var overlapCounter=0;
        var requests=0;
        var grants=0;
        var uses=0;
        var cancels=0;
        var wait=0;
        var maxwait=0;
        var lockedSeconds=0;
        var releaseTime: Int?=null;
        val passed=mutableSetOf<String>();
        var overlapLocked=false
    }
    val routes=linkedMapOf<String,Route>();
    init {
        for(line in File("input/routes.txt").readLines(Charsets.US_ASCII)) {
            val route=Route(line.split(' '),layout);
            routes[route.name]=route
        }
    }
    fun lock(route: Route) {
        route.state="LOCKED";
        route.releaseTime=null;
        route.passed.clear();
        route.overlapLocked=true;
        route.overlapCounter=0;
        for(name in route.sections)layout.sections.getValue(name).routeLock=route.name;
        for(name in route.overlap)layout.sections.getValue(name).overlapLocks.add(route.name);
        for(requirement in route.requirements)layout.points.getValue(requirement.point).locks.add(PointLock(route.name,
            requirement.position))
    }
    fun unlockPoints(route: Route,sections: Set<String>?) {
        for(point in layout.points.values)if(sections==null||point.common in sections)point.locks.removeAll {
            it.route==route.name
        }
    }
    fun unlockSection(route: Route,name: String) {
        val section=layout.sections.getValue(name);
        if(section.routeLock==route.name)section.routeLock=null;
        unlockPoints(route,setOf(name))
    }
    fun unlockOverlap(route: Route) {
        for(name in route.overlap)layout.sections.getValue(name).overlapLocks.remove(route.name);
        unlockPoints(route,route.overlap.toSet());
        route.overlapLocked=false
    }
    fun release(route: Route) {
        for(name in route.sections)if(layout.sections.getValue(name).routeLock==route.name)layout.sections.getValue(name).routeLock=null;
        if(route.overlapLocked)unlockOverlap(route);
        unlockPoints(route,null);
        route.state=null;
        route.releaseTime=null
    }
}
