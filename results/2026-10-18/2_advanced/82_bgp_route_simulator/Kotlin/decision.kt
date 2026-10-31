object Decision {
    data class Attribute(val path:List<Int>,val origin:String,val med:Int,val communities:List<Policy.Community>)
    data class Route(val path:List<Int>,val origin:String,val med:Int,val communities:List<Policy.Community>,
        val localPref:Int?,val link:Topology.Link?) {
        val local get()=link==null;
        val neighbor get()=path.first()
        companion object {
            fun originated(origin:String,communities:List<Policy.Community>)=Route(emptyList(),origin,
                0,communities,null,null)
        }
    }
    data class Selection(val route:Route,val reason:String)
    fun best(candidates:List<Route>,routerIds:Map<Int,Long>):Selection {
        var remaining=candidates.toList();
        if(remaining.size==1)return Selection(remaining.first(),"ONLY");
        for(reason in listOf("LOCALPREF","ASPATH","ORIGIN","MED","ROUTERID","LINK")) {
            if(reason=="MED") {
                val minima=remaining.groupBy {
                    it.neighbor
                }.mapValues {
                    (_,routes)->routes.minOf {
                        it.med
                    }
                };
                remaining=remaining.filter {
                    it.med==minima.getValue(it.neighbor)
                }
            }else {
                val key:(Route)->Long=when(reason) {
                    "LOCALPREF"-> {
                        route->-route.localPref!!.toLong()
                    };
                    "ASPATH"-> {
                        route->route.path.size.toLong()
                    };
                    "ORIGIN"-> {
                        route->when(route.origin) {
                            "IGP"->0L;
                            "EGP"->1L;
                            else->2L
                        }
                    };
                    "ROUTERID"-> {
                        route->routerIds.getValue(route.neighbor)
                    };
                    else-> {
                        route->route.link!!.number.toLong()
                    }
                };
                val minimum=remaining.minOf(key);
                remaining=remaining.filter {
                    key(it)==minimum
                }
            }
            if(remaining.size==1)return Selection(remaining.first(),reason)
        }
        error("No best route")
    }
}
