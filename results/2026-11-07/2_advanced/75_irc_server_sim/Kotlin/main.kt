import java.io.File
object Server {
    val settings=mutableMapOf<String,String>();
    val motd=mutableListOf<String>();
    val traffic=mutableListOf<Traffic>();
    val clients=linkedMapOf<String,Clients.Client>();
    val channels=linkedMapOf<String,Channels.Channel>();
    val sent=mutableListOf<String>();
    val commands=sortedMapOf<String,Int>();
    val numerics=sortedMapOf<Int,Int>();
    val lineCounts=mutableMapOf<String,Int>();
    val statistics=mutableMapOf<String,Int>();
    val disconnections=mutableMapOf<String,Int>();
    val gone=mutableListOf<Gone>();
    var time=0;
    var end=0;
    var peakConnections=0;
    var peakConnectionsTime=0;
    var peakRegistered=0;
    var peakRegisteredTime=0
    data class Traffic(val time: Int,val identifier: String,val kind: String,val body: String)
    data class Gone(val time: Int,val identifier: String,val addressee: String,val reason: String)
    fun setting(key: String)=settings.getValue(key).toInt()
    fun <K> add(counts: MutableMap<K,Int>,key: K,amount: Int) {
        counts[key]=counts.getOrDefault(key,0)+amount
    }
    fun stat(key: String)=statistics.getOrDefault(key,0)
    fun number(value: Int)=value.toString().padStart(3,'0')
    fun send(client: Clients.Client,line: String) {
        sent.add("$time ${client.identifier} $line");
        client.sent++
    }
    fun reply(client: Clients.Client,number: Int,content: String) {
        add(numerics,number,1);
        send(client,":${settings.getValue("NAME")} ${Server.number(number)} ${client.addressee} $content")
    }
    fun error(client: Clients.Client,number: Int,vararg a: String) {
        val x=a.firstOrNull()?:"";
        val content=when(number) {
            401->"$x :No such nick/channel";
            403->"$x :No such channel";
            404->"$x :Cannot send to channel";
            405->"$x :You have joined too many channels";
            409->":No origin specified";
            411->":No recipient given ($x)";
            412->":No text to send";
            421->"$x :Unknown command";
            431->":No nickname given";
            432->"$x :Erroneous nickname";
            433->"$x :Nickname is already in use";
            441->"$x ${a[1]} :They aren't on that channel";
            442->"$x :You're not on that channel";
            443->"$x ${a[1]} :is already on channel";
            451->":You have not registered";
            461->"$x :Not enough parameters";
            462->":You may not reregister";
            467->"$x :Channel key already set";
            471->"$x :Cannot join channel (+l)";
            472->"$x :is unknown mode char to me for ${a[1]}";
            473->"$x :Cannot join channel (+i)";
            474->"$x :Cannot join channel (+b)";
            475->"$x :Cannot join channel (+k)";
            482->"$x :You're not channel operator";
            501->":Unknown MODE flag";
            502->":Cannot change mode for other users";
            else->kotlin.error("Unknown numeric")
        };
        reply(client,number,content)
    }
    fun broadcast(channel: Channels.Channel,line: String,exclude: Clients.Client?=null) {
        for(member in channel.members)if(member.client!==exclude)send(member.client,line)
    }
    fun peers(client: Clients.Client,line: String) {
        val peers=client.channels.flatMap {
            it.members.map {
                member->member.client
            }
        }.toSet();
        for(other in clients.values)if(other!==client&&other in peers)send(other,line)
    }
    fun findUser(nickname: String): Clients.Client? {
        val name=Protocol.fold(nickname);
        return clients.values.firstOrNull {
            it.registered&&Protocol.fold(it.nickname!!)==name
        }
    }
    fun findChannel(name: String)=channels[Protocol.fold(name)]
    fun joined(client: Clients.Client,separator: String)=client.channels.joinToString(separator) {
        it.member(client)!!.status+it.name
    }
    fun removeMember(client: Clients.Client,channel: Channels.Channel) {
        channel.remove(client);
        if(channel.members.isEmpty()) {
            channels.remove(Protocol.fold(channel.name));
            for(other in clients.values)other.invites.remove(channel)
        }
    }
    fun disconnect(client: Clients.Client,reason: String,kind: String) {
        if(kind!="closed") {
            send(client,"ERROR :Closing Link: ${client.addressee}[${client.hostname}] ($reason)");
            add(statistics,"errors",1)
        };
        if(client.registered)peers(client,":${client.prefix} QUIT :$reason");
        for(channel in client.channels.toList())removeMember(client,channel);
        add(statistics,"discarded",client.queue.size);
        client.queue.clear();
        clients.remove(client.identifier);
        client.active=false;
        gone.add(Gone(time,client.identifier,client.addressee,reason));
        add(disconnections,kind,1)
    }
    fun completeRegistration(client: Clients.Client) {
        if(client.registered||client.nickname==null||client.username==null)return;
        client.registered=true;
        client.registrationTime=time;
        client.lastSpeaking=time;
        val registered=clients.values.count {
            it.registered
        };
        if(registered>peakRegistered) {
            peakRegistered=registered;
            peakRegisteredTime=time
        };
        val server=settings.getValue("NAME");
        val version=settings.getValue("VERSION");
        reply(client,1,":Welcome to the Internet Relay Network ${client.prefix}");
        reply(client,2,":Your host is $server, running version $version");
        reply(client,3,":This server was created ${settings.getValue("CREATED")}");
        reply(client,4,"$server $version i biklmnotv");
        reply(client,5,"CASEMAPPING=rfc1459 CHANTYPES=# NICKLEN=${setting("NICKLEN")} CHANNELLEN=${setting("CHANNELLEN")} TOPICLEN=${setting("TOPICLEN")} CHANLIMIT=#:${setting("MAXCHANNELS")} CHANMODES=b,k,l,imnt PREFIX=(ov)@+ :are supported by this server");
        reply(client,375,":- $server Message of the day -");
        for(line in motd)reply(client,372,":- $line");
        reply(client,376,":End of /MOTD command.");
        if(client.invisible)send(client,":${client.nickname} MODE ${client.nickname} :+i")
    }
    fun require(client: Clients.Client,parameters: List<String>,count: Int,command: String): Boolean {
        if(parameters.size>=count)return true;
        error(client,461,command);
        return false
    }
    fun nick(client: Clients.Client,p: List<String>) {
        if(p.isEmpty()||p.first().isEmpty()) {
            error(client,431);
            return
        };
        val nickname=p.first().take(setting("NICKLEN"));
        if(!Protocol.validNickname(nickname)) {
            error(client,432,nickname);
            return
        };
        if(nickname==client.nickname)return;
        val folded=Protocol.fold(nickname);
        if(clients.values.any {
            it!==client&&it.nickname?.let {
                old->Protocol.fold(old)==folded
            }
            ==true
        }) {
            error(client,433,nickname);
            return
        };
        if(client.registered) {
            val line=":${client.prefix} NICK :$nickname";
            send(client,line);
            peers(client,line)
        };
        client.nickname=nickname;
        completeRegistration(client)
    }
    fun user(client: Clients.Client,p: List<String>) {
        if(client.username!=null) {
            error(client,462);
            return
        };
        if(!require(client,p,4,"USER"))return;
        client.username=p[0];
        client.realname=p[3];
        val mode=p[1];
        client.invisible=Protocol.digits(mode)&&mode.length<=3&&(mode.toInt()/8)%2==1;
        completeRegistration(client)
    }
    fun ping(client: Clients.Client,p: List<String>) {
        if(p.isEmpty()||p.first().isEmpty()) {
            error(client,409);
            return
        };
        val server=settings.getValue("NAME");
        send(client,":$server PONG $server :${p.first()}")
    }
    fun namesReply(client: Clients.Client,channel: Channels.Channel) {
        val names=channel.nameList(client);
        if(names.isNotEmpty())reply(client,353,"= ${channel.name} :$names");
        reply(client,366,"${channel.name} :End of /NAMES list.")
    }
    fun topicReplies(client: Clients.Client,channel: Channels.Channel) {
        reply(client,332,"${channel.name} :${channel.topic}");
        reply(client,333,"${channel.name} ${channel.topicSetter} ${channel.topicTime}")
    }
    fun join(client: Clients.Client,p: List<String>) {
        if(!require(client,p,1,"JOIN"))return;
        if(p.first()=="0") {
            for(channel in client.channels.toList()) {
                broadcast(channel,":${client.prefix} PART ${channel.name}");
                removeMember(client,channel)
            };
            return
        };
        val keys=if(p.size>=2)p[1].split(',') else emptyList();
        for((i,name) in p.first().split(',').withIndex()) {
            val key=keys.getOrElse(i) {
                ""
            };
            if(!Protocol.validChannel(name,setting("CHANNELLEN"))) {
                error(client,403,name);
                continue
            };
            val found=findChannel(name);
            if(found?.member(client)!=null)continue;
            if(client.channels.size>=setting("MAXCHANNELS")) {
                error(client,405,name);
                continue
            };
            val channel=if(found==null)Channels.Channel(name,time).also {
                channels[Protocol.fold(name)]=it
            } else {
                val invited=found in client.invites;
                val failure=when {
                    found.banned(client)&&!invited->474;
                    'i' in found.flags&&!invited->473;
                    found.key.isNotEmpty()&&key!=found.key->475;
                    found.limit>0&&found.members.size>=found.limit->471;
                    else->0
                };
                if(failure!=0) {
                    error(client,failure,found.name);
                    continue
                };
                found
            };
            client.invites.remove(channel);
            channel.add(client,channel.members.isEmpty());
            broadcast(channel,":${client.prefix} JOIN ${channel.name}");
            if(channel.topic.isNotEmpty())topicReplies(client,channel);
            namesReply(client,channel)
        }
    }
    fun part(client: Clients.Client,p: List<String>) {
        if(!require(client,p,1,"PART"))return;
        val suffix=if(p.size>=2&&p[1].isNotEmpty())" :${p[1]}" else "";
        for(name in p.first().split(',')) {
            val channel=findChannel(name);
            if(channel==null)error(client,403,name) else if(channel.member(client)==null)error(client,
                442,channel.name) else {
                broadcast(channel,":${client.prefix} PART ${channel.name}$suffix");
                removeMember(client,channel)
            }
        }
    }
    fun message(client: Clients.Client,p: List<String>,command: String) {
        val replies=command=="PRIVMSG";
        if(replies)client.lastSpeaking=time;
        if(p.isEmpty()||p.first().isEmpty()) {
            if(replies)error(client,411,command);
            return
        };
        if(p.size<2||p[1].isEmpty()) {
            if(replies)error(client,412);
            return
        };
        val text=p[1];
        for(target in p.first().split(','))if(target.startsWith('#')) {
            val channel=findChannel(target);
            if(channel==null) {
                if(replies)error(client,401,target)
            } else if(!channel.canSpeak(client)) {
                if(replies)error(client,404,channel.name)
            } else {
                channel.messages++;
                broadcast(channel,":${client.prefix} $command ${channel.name} :$text",client)
            }
        } else {
            val user=findUser(target);
            if(user==null) {
                if(replies)error(client,401,target);
                continue
            };
            send(user,":${client.prefix} $command ${user.nickname} :$text");
            if(replies&&user.away.isNotEmpty())reply(client,301,"${user.nickname} :${user.away}")
        }
    }
    fun topic(client: Clients.Client,p: List<String>) {
        if(!require(client,p,1,"TOPIC"))return;
        val channel=findChannel(p.first());
        if(channel==null) {
            error(client,403,p.first());
            return
        };
        val member=channel.member(client);
        if(member==null) {
            error(client,442,channel.name);
            return
        };
        if(p.size==1) {
            if(channel.topic.isEmpty())reply(client,331,"${channel.name} :No topic is set") else topicReplies(client,
                channel);
            return
        };
        if('t' in channel.flags&&!member.op) {
            error(client,482,channel.name);
            return
        };
        channel.topic=p[1].take(setting("TOPICLEN"));
        channel.topicSetter=client.nickname!!;
        channel.topicTime=time;
        broadcast(channel,":${client.prefix} TOPIC ${channel.name} :${channel.topic}")
    }
    fun names(client: Clients.Client,p: List<String>) {
        if(p.isEmpty()) {
            reply(client,366,"* :End of /NAMES list.");
            return
        };
        for(name in p.first().split(',')) {
            val channel=findChannel(name);
            if(channel==null)reply(client,366,"$name :End of /NAMES list.") else namesReply(client,channel)
        }
    }
    fun whois(client: Clients.Client,p: List<String>) {
        if(p.isEmpty()) {
            error(client,431);
            return
        };
        val user=findUser(p.first());
        if(user==null) {
            error(client,401,p.first());
            reply(client,318,"${p.first()} :End of /WHOIS list.");
            return
        };
        reply(client,311,"${user.nickname} ${user.username} ${user.hostname} * :${user.realname}");
        if(user.channels.isNotEmpty())reply(client,319,"${user.nickname} :${joined(user," ")}");
        reply(client,312,"${user.nickname} ${settings.getValue("NAME")} :${settings.getValue("DESCRIPTION")}");
        if(user.away.isNotEmpty())reply(client,301,"${user.nickname} :${user.away}");
        reply(client,317,"${user.nickname} ${time-user.lastSpeaking} ${user.registrationTime} :seconds idle, signon time");
        reply(client,318,"${user.nickname} :End of /WHOIS list.")
    }
    fun away(client: Clients.Client,p: List<String>) {
        client.away=p.firstOrNull()?:"";
        reply(client,if(client.away.isEmpty())305 else 306,if(client.away.isEmpty())":You are no longer marked as being away" else ":You have been marked as being away")
    }
    fun invite(client: Clients.Client,p: List<String>) {
        if(!require(client,p,2,"INVITE"))return;
        val user=findUser(p.first());
        if(user==null) {
            error(client,401,p.first());
            return
        };
        val channel=findChannel(p[1]);
        if(channel==null) {
            error(client,403,p[1]);
            return
        };
        val member=channel.member(client);
        if(member==null) {
            error(client,442,channel.name);
            return
        };
        if(channel.member(user)!=null) {
            error(client,443,user.nickname!!,channel.name);
            return
        };
        if('i' in channel.flags&&!member.op) {
            error(client,482,channel.name);
            return
        };
        if(channel !in user.invites)user.invites.add(channel);
        reply(client,341,"${user.nickname} ${channel.name}");
        if(user.away.isNotEmpty())reply(client,301,"${user.nickname} :${user.away}");
        send(user,":${client.prefix} INVITE ${user.nickname} :${channel.name}")
    }
    fun kick(client: Clients.Client,p: List<String>) {
        if(!require(client,p,2,"KICK"))return;
        val channel=findChannel(p.first());
        if(channel==null) {
            error(client,403,p.first());
            return
        };
        val member=channel.member(client);
        if(member==null) {
            error(client,442,channel.name);
            return
        };
        if(!member.op) {
            error(client,482,channel.name);
            return
        };
        val user=findUser(p[1]);
        if(user==null) {
            error(client,401,p[1]);
            return
        };
        if(channel.member(user)==null) {
            error(client,441,user.nickname!!,channel.name);
            return
        };
        val reason=if(p.size>=3&&p[2].isNotEmpty())p[2] else client.nickname!!;
        broadcast(channel,":${client.prefix} KICK ${channel.name} ${user.nickname} :$reason");
        removeMember(user,channel)
    }
    fun userMode(client: Clients.Client,p: List<String>) {
        val user=findUser(p.first());
        if(user==null) {
            error(client,401,p.first());
            return
        };
        if(user!==client) {
            error(client,502);
            return
        };
        if(p.size==1) {
            reply(client,221,client.mode);
            return
        };
        var sign='+';
        var unknown=false;
        val changes=mutableListOf<Modes.Item>();
        for(c in p[1])if(c=='+'||c=='-')sign=c else if(c=='i') {
            val desired=sign=='+';
            if(client.invisible!=desired) {
                client.invisible=desired;
                changes.add(Modes.Item(sign,c,null))
            }
        } else unknown=true;
        if(changes.isNotEmpty())send(client,":${client.nickname} MODE ${client.nickname} :${Modes.changeString(changes)}");
        if(unknown)error(client,501)
    }
    fun applyMode(client: Clients.Client,channel: Channels.Channel,item: Modes.Item): Modes.Item? {
        val sign=item.sign;
        val c=item.character;
        val argument=item.argument;
        var changeArgument: String?=null;
        val adding=sign=='+';
        var changed=false;
        if(c=='o'||c=='v') {
            val user=findUser(argument!!);
            if(user==null) {
                error(client,401,argument);
                return null
            };
            val member=channel.member(user);
            if(member==null) {
                error(client,441,user.nickname!!,channel.name);
                return null
            };
            val old=if(c=='o')member.op else member.voice;
            if(old!=adding) {
                if(c=='o')member.op=adding else member.voice=adding;
                changed=true;
                changeArgument=user.nickname
            }
        } else if(c=='b') {
            val mask=Masks.normalize(argument!!);
            val folded=Protocol.fold(mask);
            val found=channel.bans.indexOfFirst {
                Protocol.fold(it.mask)==folded
            };
            if(adding&&found<0) {
                channel.bans.add(Channels.Ban(mask,client.nickname!!,time));
                changed=true;
                changeArgument=mask
            } else if(!adding&&found>=0) {
                changeArgument=channel.bans.removeAt(found).mask;
                changed=true
            }
        } else if(c=='k') {
            if(adding) {
                if(channel.key.isNotEmpty())error(client,467,channel.name) else {
                    channel.key=argument!!;
                    changed=true;
                    changeArgument=argument
                }
            } else if(channel.key.isNotEmpty()) {
                channel.key="";
                changed=true;
                changeArgument="*"
            }
        } else if(c=='l') {
            if(adding) {
                val limit=argument!!.toInt();
                if(channel.limit!=limit) {
                    channel.limit=limit;
                    changed=true;
                    changeArgument=limit.toString()
                }
            } else if(channel.limit!=0) {
                channel.limit=0;
                changed=true
            }
        } else changed=if(adding)channel.flags.add(c) else channel.flags.remove(c);
        return if(changed)Modes.Item(sign,c,changeArgument) else null
    }
    fun channelMode(client: Clients.Client,p: List<String>) {
        val channel=findChannel(p.first());
        if(channel==null) {
            error(client,403,p.first());
            return
        };
        if(p.size==1) {
            reply(client,324,"${channel.name} ${channel.modeDisplay(channel.member(client)!=null)}");
            reply(client,329,"${channel.name} ${channel.created}");
            return
        };
        val items=Modes.channelItems(p[1],p.drop(2));
        val changes=mutableListOf<Modes.Item>();
        val authorized=channel.member(client)?.op==true;
        var bansSent=false;
        var denialSent=false;
        for(item in items) {
            val sign=item.sign;
            val c=item.character;
            val argument=item.argument;
            if(c !in "biklmnotv") {
                error(client,472,c.toString(),channel.name);
                continue
            };
            if(c=='b'&&argument==null) {
                if(sign=='+'&&!bansSent) {
                    for(ban in channel.bans)reply(client,367,"${channel.name} ${ban.mask} ${ban.setter} ${ban.time}");
                    reply(client,368,"${channel.name} :End of channel ban list");
                    bansSent=true
                };
                continue
            };
            if(argument==null&&(c=='o'||c=='v'||sign=='+'&&(c=='k'||c=='l')))continue;
            if(!authorized) {
                if(!denialSent) {
                    error(client,482,channel.name);
                    denialSent=true
                };
                continue
            };
            val change=applyMode(client,channel,item);
            if(change!=null)changes.add(change)
        };
        if(changes.isNotEmpty())broadcast(channel,":${client.prefix} MODE ${channel.name} ${Modes.changeString(changes)}")
    }
    fun process(client: Clients.Client,raw: String) {
        add(statistics,"processed",1);
        val parsed=Protocol.parse(raw);
        val command=parsed.command;
        val p=parsed.parameters;
        if(command.isEmpty()) {
            add(statistics,"empty",1);
            return
        };
        add(commands,command,1);
        if(!client.registered&&command !in setOf("NICK","USER","PING","PONG","QUIT")) {
            error(client,451);
            return
        };
        when(command) {
            "NICK"->nick(client,p);
            "USER"->user(client,p);
            "PING"->ping(client,p);
            "PONG"->Unit;
            "QUIT"->disconnect(client,if(p.isNotEmpty()&&p.first().isNotEmpty())"Quit: ${p.first()}" else "Client Quit",
                "quit");
            "JOIN"->join(client,p);
            "PART"->part(client,p);
            "PRIVMSG","NOTICE"->message(client,p,command);
            "TOPIC"->topic(client,p);
            "NAMES"->names(client,p);
            "WHOIS"->whois(client,p);
            "AWAY"->away(client,p);
            "INVITE"->invite(client,p);
            "KICK"->kick(client,p);
            "MODE"->if(require(client,p,1,"MODE")) {
                if(p.first().startsWith('#'))channelMode(client,p) else userMode(client,p)
            };
            else->error(client,421,command)
        }
    }
    fun arrival(record: Traffic) {
        val kind=record.kind;
        if(kind=="connect") {
            val client=Clients.Client(record.identifier,record.body.substring(8),time,setting("BUCKET"));
            clients[client.identifier]=client;
            if(clients.size>peakConnections) {
                peakConnections=clients.size;
                peakConnectionsTime=time
            };
            return
        };
        val client=clients[record.identifier];
        if(kind=="disconnect") {
            if(client!=null)disconnect(client,"Remote host closed the connection","closed");
            return
        };
        if(client==null) {
            add(statistics,"dropped",1);
            return
        };
        client.received++;
        client.lastReceived=time;
        client.pingSent=-1;
        if(client.queue.isEmpty()&&client.tokens>=1) {
            client.useToken(time,setting("BUCKET"),setting("REFILL"));
            process(client,record.body)
        } else if(client.queue.size>=setting("QUEUE")) {
            add(statistics,"discarded",1);
            disconnect(client,"Excess Flood","flood")
        } else {
            client.queue.addLast(record.body);
            add(statistics,"queued",1)
        }
    }
    fun simulate() {
        var position=0;
        for(t in 0..end) {
            time=t;
            for(client in clients.values.toList()) {
                client.refill(time,setting("BUCKET"),setting("REFILL"));
                while(client.active&&client.queue.isNotEmpty()&&client.tokens>=1) {
                    client.useToken(time,setting("BUCKET"),setting("REFILL"));
                    process(client,client.queue.removeFirst())
                }
            };
            while(position<traffic.size&&traffic[position].time==time)arrival(traffic[position++]);
            for(client in clients.values.toList())if(client.pingSent>=0) {
                if(time-client.pingSent>=setting("TIMEOUT"))disconnect(client,"Ping timeout: ${time-client.lastReceived} seconds",
                    "timeout")
            } else if(time-client.lastReceived>=setting("PINGFREQ")) {
                send(client,"PING :${settings.getValue("NAME")}");
                add(statistics,"pings",1);
                client.pingSent=time
            }
        }
    }
    fun channelReport(): List<String> {
        val lines=mutableListOf<String>();
        var members=0;
        var bans=0;
        for(channel in channels.values) {
            members+=channel.members.size;
            bans+=channel.bans.size;
            lines.add("CHANNEL ${channel.name} created ${channel.created} members ${channel.members.size} peak ${channel.peak} messages ${channel.messages} modes ${channel.modeDisplay(true)}");
            lines.add(if(channel.topic.isEmpty())"TOPIC none" else "TOPIC ${channel.topicSetter} ${channel.topicTime} ${channel.topic}");
            for(ban in channel.bans)lines.add("BAN ${ban.mask} ${ban.setter} ${ban.time}");
            lines.add("MEMBERS "+channel.members.joinToString(" ") {
                it.display
            })
        };
        lines.add("TOTAL channels ${channels.size} members $members bans $bans");
        return lines
    }
    fun clientReport(): List<String> {
        val lines=mutableListOf<String>();
        for(client in clients.values) {
            val joined=joined(client,",").ifEmpty {
                "none"
            };
            val invites=client.invites.joinToString(",") {
                it.name
            }.ifEmpty {
                "none"
            };
            val signon=if(client.registered)client.registrationTime.toString() else "-";
            lines.add("CLIENT ${client.identifier} ${client.addressee} ${client.username?:"*"} ${client.hostname} ${client.mode} connected ${client.connectionTime} signon $signon received ${client.received} sent ${client.sent} tokens ${client.tokens} queue ${client.queue.size} channels $joined invites $invites");
            if(client.away.isNotEmpty())lines.add("AWAY ${client.identifier} ${client.away}")
        };
        lines.add("TOTAL clients ${clients.size} registered ${clients.values.count{it.registered}} invisible ${clients.values.count{it.invisible}} away ${clients.values.count{it.away.isNotEmpty()}}");
        return lines
    }
    fun statisticsReport(): List<String> {
        val pending=clients.values.sumOf {
            it.queue.size
        };
        val numericTotal=numerics.values.sum();
        val lines=mutableListOf("END $end","LINES total ${traffic.size} connect ${lineCounts.getOrDefault("connect",0)} disconnect ${lineCounts.getOrDefault("disconnect",0)} messages ${lineCounts.getOrDefault("messages",0)}",
            "MESSAGES dropped ${stat("dropped")} queued ${stat("queued")} processed ${stat("processed")} discarded ${stat("discarded")} pending $pending empty ${stat("empty")}",
            "SENT lines ${sent.size} numerics $numericTotal pings ${stat("pings")} errors ${stat("errors")}");
        for((command,count) in commands)lines.add("COMMAND $command $count");
        for((code,count) in numerics)lines.add("NUMERIC ${number(code)} $count");
        lines.add("PEAK connections $peakConnections at $peakConnectionsTime");
        lines.add("PEAK registered $peakRegistered at $peakRegisteredTime");
        lines.add("DISCONNECTS "+listOf("quit","closed","flood","timeout").joinToString(" ") {
            "$it ${disconnections.getOrDefault(it,0)}"
        });
        for(record in gone)lines.add("GONE ${record.time} ${record.identifier} ${record.addressee} ${record.reason}");
        return lines
    }
    fun write(name: String,lines: List<String>) {
        File("output",name).writeText(lines.joinToString("\n")+if(lines.isEmpty())"" else "\n")
    }
    fun run() {
        for(line in File("input/server.txt").readLines()) {
            val separator=line.indexOf(' ');
            val key=line.substring(0,separator);
            val value=line.substring(separator+1);
            if(key=="MOTD")motd.add(value) else settings[key]=value
        };
        for(line in File("input/traffic.txt").readLines()) {
            val fields=line.split(' ',limit=3);
            val body=fields[2];
            val kind=if(body.startsWith("CONNECT ")&&body.substring(8).matches(Regex("[A-Za-z0-9.-]{1,63}")))"connect" else if(body=="DISCONNECT")"disconnect" else "messages";
            traffic.add(Traffic(fields[0].toInt(),fields[1],kind,body));
            add(lineCounts,kind,1)
        };
        end=traffic.last().time;
        simulate();
        File("output").mkdirs();
        write("sent.txt",sent);
        write("channels.txt",channelReport());
        write("clients.txt",clientReport());
        write("stats.txt",statisticsReport())
    }
}
fun main()=Server.run()
