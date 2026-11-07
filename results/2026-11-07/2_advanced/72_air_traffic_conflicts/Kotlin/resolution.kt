object Resolution {
    data class Manoeuvre(val name: String,val amount: Int)
    fun manoeuvres(maximum: Int)=listOf(Manoeuvre("level_up",10),Manoeuvre("level_down",-10),Manoeuvre("speed_down",
        0))+(60..maximum step 60).map {
        Manoeuvre("delay_$it",it)
    }
    fun priority(a: FlightPlans.Plan,b: FlightPlans.Plan): List<String> {
        var comparison=(a.departure+a.delay).compareTo(b.departure+b.delay);
        if(comparison==0)comparison=a.callsign.compareTo(b.callsign);
        return if(comparison>0)listOf(a.callsign,b.callsign) else listOf(b.callsign,a.callsign)
    }
    fun propose(plan: FlightPlans.Plan,manoeuvre: Manoeuvre,types: Map<String,FlightPlans.AircraftType>,
        settings: FlightPlans.Settings): FlightPlans.Plan? {
        val changed=plan.copy();
        when(manoeuvre.name) {
            "level_up","level_down"-> {
                changed.offset+=manoeuvre.amount;
                if(changed.levels().any {
                    it<settings.levelMin||it>settings.levelMax
                })return null
            };
            "speed_down"-> {
                changed.speed=changed.speed*9/10;
                if(changed.speed<types.getValue(changed.type).minimum)return null
            };
            else->changed.delay+=manoeuvre.amount
        };
        return changed
    }
}
