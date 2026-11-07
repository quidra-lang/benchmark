class Safety {
    companion object {
        val properties=listOf("OCCUPANCY","POINT_MOTION","CONFLICT","SIGNAL_PASSING")
    }
    val checks=mutableMapOf<String,Int>();
    val violations=mutableMapOf<String,Int>();
    val records=mutableListOf<String>()
    fun check(time: Int,kind: String,details: String?) {
        checks[kind]=checks.getOrDefault(kind,0)+1;
        if(details!=null) {
            violations[kind]=violations.getOrDefault(kind,0)+1;
            records.add("VIOLATION $time $kind $details")
        }
    }
    fun inspect(time: Int,layout: Layout,routes: Map<String,Interlocking.Route>) {
        for(section in layout.sections.values)check(time,"OCCUPANCY",if(section.occupants.size>=2)section.name+" "+section.occupants.joinToString(",") else null);
        for(point in layout.points.values)if(point.moving) {
            val details=when {
                layout.sections.getValue(point.common).occupants.isNotEmpty()->"${point.name} occupied";
                point.locks.any {
                    routes.getValue(it.route).state in listOf("USED","APPROACH")
                }
                ->"${point.name} locked";
                else->null
            };
            check(time,"POINT_MOTION",details)
        };
        val locked=routes.values.filter {
            it.state in listOf("LOCKED","APPROACH")
        };
        for(a in locked.indices)for(b in a+1 until locked.size) {
            val first=locked[a];
            val second=locked[b];
            check(time,"CONFLICT",if(second.name in first.conflicts||first.name in second.conflicts)"${first.name} ${second.name}" else null)
        }
    }
    fun report(): List<String> {
        val lines=mutableListOf<String>();
        for(kind in properties) {
            val count=violations.getOrDefault(kind,0);
            val verdict=if(count>0)"FAIL" else "OK";
            lines.add("$kind $verdict checks ${checks.getOrDefault(kind,0)} violations $count")
        };
        lines.addAll(records);
        lines.add("RESULT "+if(records.isEmpty())"SAFE" else "UNSAFE");
        return lines
    }
}
