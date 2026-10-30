object Channels {
    class Member(val client: Clients.Client,var op: Boolean) {
        var voice=false;
        val status get()=if(op)"@" else if(voice)"+" else "";
        val display get()=status+client.nickname!!
    }
    data class Ban(val mask: String,val setter: String,val time: Int)
    class Channel(val name: String,val created: Int) {
        var topic="";
        var topicSetter="";
        var topicTime=-1;
        var key="";
        var limit=0;
        var peak=0;
        var messages=0;
        val members=mutableListOf<Member>();
        val bans=mutableListOf<Ban>();
        val flags=mutableSetOf('n','t')
        fun member(client: Clients.Client)=members.firstOrNull {
            it.client===client
        }
        fun add(client: Clients.Client,op: Boolean): Member {
            val member=Member(client,op);
            members.add(member);
            client.channels.add(this);
            peak=maxOf(peak,members.size);
            return member
        }
        fun remove(client: Clients.Client) {
            members.remove(member(client)!!);
            client.channels.remove(this)
        }
        fun nameList(viewer: Clients.Client): String {
            val inside=member(viewer)!=null;
            return members.filter {
                inside||!it.client.invisible
            }.joinToString(" ") {
                it.display
            }
        }
        fun banned(client: Clients.Client)=bans.any {
            Masks.matches(it.mask,client.prefix)
        }
        fun canSpeak(client: Clients.Client): Boolean {
            val member=member(client);
            val privileged=member!=null&&(member.op||member.voice);
            return (member!=null||'n' !in flags)&&('m' !in flags||privileged)&&(privileged||!banned(client))
        }
        fun modeDisplay(includeKey: Boolean): String {
            val mode=StringBuilder("+");
            for(c in "iklmnt")if(when(c) {
                'k'->key.isNotEmpty();
                'l'->limit!=0;
                else->c in flags
            })mode.append(c);
            if(includeKey&&key.isNotEmpty())mode.append(' ').append(key);
            if(limit!=0)mode.append(' ').append(limit);
            return mode.toString()
        }
    }
}
