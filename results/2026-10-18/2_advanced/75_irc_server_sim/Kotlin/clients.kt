object Clients {
    class Client(val identifier: String,val hostname: String,val connectionTime: Int,capacity: Int) {
        var nickname: String?=null;
        var username: String?=null;
        var realname="";
        var away="";
        var invisible=false;
        var registered=false;
        var active=true;
        var registrationTime=-1;
        var lastReceived=connectionTime;
        var lastSpeaking=-1;
        var pingSent=-1;
        var tokens=capacity;
        var refillTime=-1;
        var received=0;
        var sent=0;
        val queue=ArrayDeque<String>();
        val channels=mutableListOf<Channels.Channel>();
        val invites=mutableListOf<Channels.Channel>()
        val addressee get()=nickname?:"*";
        val prefix get()="${nickname!!}!${username!!}@$hostname";
        val mode get()=if(invisible)"+i" else "+"
        fun useToken(time: Int,capacity: Int,interval: Int) {
            if(tokens==capacity)refillTime=time+interval;
            tokens--
        }
        fun refill(time: Int,capacity: Int,interval: Int) {
            if(refillTime==time) {
                tokens++;
                refillTime=if(tokens<capacity)time+interval else -1
            }
        }
    }
}
