object Protocol {
    val dirty=setOf("M","O")
    data class Request(val transaction: String?,val state: String)
    data class Snoop(val state: String,val supply: Boolean,val flush: Boolean)
    fun requester(protocol: String,old: String,op: String,otherHasLine: Boolean): Request {
        if(protocol=="VI")return if(op=="R")Request(if(old=="I")"BusRd" else null,"V") else Request("BusWr",
            if(old=="I")"I" else "V");
        if(old=="I")return if(op=="W")Request("BusRdX","M") else Request("BusRd",if(protocol!="MSI"&&!otherHasLine)"E" else "S");
        if(op=="R")return Request(null,old);
        return if(old=="M"||old=="E")Request(null,"M") else Request("BusUpgr","M")
    }
    fun snoop(protocol: String,old: String,transaction: String): Snoop {
        if(protocol=="VI")return Snoop(if(transaction=="BusRd")"V" else "I",false,false);
        if(transaction=="BusRd") {
            if(old=="M")return if(protocol=="MOESI")Snoop("O",true,false) else Snoop("S",true,true);
            if(old=="O")return Snoop("O",true,false);
            return Snoop("S",false,false)
        };
        return Snoop("I",transaction=="BusRdX"&&old in dirty,false)
    }
}
