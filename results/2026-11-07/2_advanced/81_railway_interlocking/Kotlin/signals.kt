object Signals {
    data class Aspect(val signal: Layout.Signal,val aspect: String)
    fun aspects(interlocking: Interlocking,occupied: (String)->Boolean): List<Aspect> {
        val layout=interlocking.layout;
        val cleared=mutableMapOf<String,Interlocking.Route>();
        for(signal in layout.signals.values)for(route in interlocking.routes.values) {
            if(route.start!=signal.name||route.state!="LOCKED")continue;
            val pointsReady=route.requirements.all {
                val point=layout.points.getValue(it.point);
                point.detected()&&point.position==it.position
            };
            if(pointsReady&&(route.sections+route.overlap).none {
                occupied(it)
            }) {
                cleared[signal.name]=route;
                break
            }
        };
        return layout.signals.values.map {
            signal->val route=cleared[signal.name];
            val aspect=when {
                route==null->"RED";
                route.finish in layout.signals->if(route.finish in cleared)"GREEN" else "YELLOW";
                route.finish in layout.buffers->"YELLOW";
                else->"GREEN"
            };
            Aspect(signal,aspect)
        }
    }
}
