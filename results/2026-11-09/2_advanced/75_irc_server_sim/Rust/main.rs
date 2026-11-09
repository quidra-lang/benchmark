mod protocol;
mod masks;
mod clients;
mod channels;
mod modes;
use std::collections::BTreeMap;
use std::fs;
use clients::Client;
use channels::{Ban,Channel};
use modes::Item;
struct Settings {
    values: BTreeMap<String,String>,
    motd: Vec<String>
}
impl Settings {
    fn read() -> Self {
        let mut values = BTreeMap::new();
        let mut motd = Vec::new();
        for line in fs::read_to_string("input/server.txt").unwrap().lines() {
            let (key,value) = line.split_once(' ').unwrap();
            if key == "MOTD" {
                motd.push(value.to_owned());
            } else {
                values.insert(key.to_owned(),value.to_owned());
            }
        }
        Self {
            values,
            motd
        }
    }
    fn text(&self, key: &str) -> &str {
        &self.values[key]
    }
    fn number(&self, key: &str) -> usize {
        self.text(key).parse().unwrap()
    }
}
struct Server {
    settings: Settings,
    clients: Vec<Option<Client>>,
    channels: Vec<Option<Channel>>,
    time: usize,
    sent: Vec<String>,
    numerics: BTreeMap<usize,usize>,
    commands: BTreeMap<String,usize>,
    line_counts: [usize;4],
    message_counts: [usize;5],
    pings: usize,
    errors: usize,
    peaks: [(usize,usize);2],
    disconnects: [usize;4],
    gone: Vec<String>
}
impl Server {
    fn new() -> Self {
        Self {
            settings: Settings::read(),
            clients: Vec::new(),
            channels: Vec::new(),
            time: 0,
            sent: Vec::new(),
            numerics: BTreeMap::new(),
            commands: BTreeMap::new(),
            line_counts: [0;4],
            message_counts: [0;5],
            pings: 0,
            errors: 0,
            peaks: [(0,0);2],
            disconnects: [0;4],
            gone: Vec::new()
        }
    }
    fn client(&self, i: usize) -> &Client {
        self.clients[i].as_ref().unwrap()
    }
    fn channel(&self, i: usize) -> &Channel {
        self.channels[i].as_ref().unwrap()
    }
    fn find_connection(&self, id: &str) -> Option<usize> {
        self.clients.iter().position(|c| c.as_ref().map_or(false,|c| c.id == id))
    }
    fn find_user(&self, nickname: &str) -> Option<usize> {
        let folded = protocol::fold(nickname);
        self.clients.iter().position(|c| c.as_ref().map_or(false,|c| c.registered && protocol::fold(c.addressee()) == folded))
    }
    fn find_channel(&self, name: &str) -> Option<usize> {
        let folded = protocol::fold(name);
        self.channels.iter().position(|c| c.as_ref().map_or(false,|c| protocol::fold(&c.name) == folded))
    }
    fn send(&mut self, i: usize, line: String) {
        let client = self.clients[i].as_mut().unwrap();
        client.sent += 1;
        self.sent.push(format!("{} {} {}",self.time,client.id,line));
    }
    fn numeric(&mut self, i: usize, number: usize, content: String) {
        *self.numerics.entry(number).or_insert(0) += 1;
        self.send(i,format!(":{} {:03} {} {}",self.settings.text("NAME"),number,self.client(i).addressee(),content));
    }
    fn error(&mut self, i: usize, number: usize, value: &str) {
        let content = match number {
            401 => format!("{} :No such nick/channel",value),403 => format!("{} :No such channel",value),404 => format!("{} :Cannot send to channel",value),405 => format!("{} :You have joined too many channels",value),409 => ":No origin specified".to_owned(),411 => format!(":No recipient given ({})",value),412 => ":No text to send".to_owned(),421 => format!("{} :Unknown command",value),431 => ":No nickname given".to_owned(),432 => format!("{} :Erroneous nickname",value),433 => format!("{} :Nickname is already in use",value),441 => format!("{} :They aren't on that channel",value),442 => format!("{} :You're not on that channel",value),443 => format!("{} :is already on channel",value),451 => ":You have not registered".to_owned(),461 => format!("{} :Not enough parameters",value),462 => ":You may not reregister".to_owned(),467 => format!("{} :Channel key already set",value),471 => format!("{} :Cannot join channel (+l)",value),473 => format!("{} :Cannot join channel (+i)",value),474 => format!("{} :Cannot join channel (+b)",value),475 => format!("{} :Cannot join channel (+k)",value),482 => format!("{} :You're not channel operator",value),501 => ":Unknown MODE flag".to_owned(),502 => ":Cannot change mode for other users".to_owned(),_ => unreachable!()
        };
        self.numeric(i,number,content);
    }
    fn broadcast(&mut self, channel: usize, line: String, skip: Option<usize>) {
        let recipients: Vec<_> = self.channel(channel).members.iter().map(|m| m.client).filter(|c| Some(*c) != skip).collect();
        for i in recipients {
            self.send(i,line.clone());
        }
    }
    fn peers(&self, i: usize) -> Vec<usize> {
        (0..self.clients.len()).filter(|&j| j != i && self.clients[j].is_some() && self.client(i).channels.iter().any(|&s| self.channel(s).member(j).is_some())).collect()
    }
    fn remove_member(&mut self, i: usize, channel: usize) {
        self.channels[channel].as_mut().unwrap().remove(i);
        self.clients[i].as_mut().unwrap().channels.retain(|&s| s != channel);
        if self.channel(channel).members.is_empty() {
            self.channels[channel] = None;
            for client in self.clients.iter_mut().flatten() {
                client.invites.retain(|&s| s != channel);
            }
        }
    }
    fn disconnect(&mut self, i: usize, reason: String, kind: usize) {
        if kind != 1 {
            self.errors += 1;
            self.send(i,format!("ERROR :Closing Link: {}[{}] ({})",self.client(i).addressee(),self.client(i).host,reason));
        }
        if self.client(i).registered {
            let line = format!(":{} QUIT :{}",self.client(i).prefix(),reason);
            for peer in self.peers(i) {
                self.send(peer,line.clone());
            }
        }
        let joined = self.client(i).channels.clone();
        for channel in joined {
            self.remove_member(i,channel);
        }
        self.message_counts[3] += self.client(i).queue.len();
        let client = self.clients[i].take().unwrap();
        self.gone.push(format!("GONE {} {} {} {}",self.time,client.id,client.addressee(),reason));
        self.disconnects[kind] += 1;
    }
    fn register(&mut self, i: usize) {
        if self.client(i).registered || self.client(i).nickname.is_none() || self.client(i).username.is_none() {
            return;
        }
        let client = self.clients[i].as_mut().unwrap();
        client.registered = true;
        client.signon = Some(self.time);
        client.last_speaking = self.time;
        let count = self.clients.iter().flatten().filter(|c| c.registered).count();
        if count > self.peaks[1].0 {
            self.peaks[1] = (count,self.time);
        }
        self.numeric(i,1,format!(":Welcome to the Internet Relay Network {}",self.client(i).prefix()));
        self.numeric(i,2,format!(":Your host is {}, running version {}",self.settings.text("NAME"),self.settings.text("VERSION")));
        self.numeric(i,3,format!(":This server was created {}",self.settings.text("CREATED")));
        self.numeric(i,4,format!("{} {} i biklmnotv",self.settings.text("NAME"),self.settings.text("VERSION")));
        self.numeric(i,5,format!("CASEMAPPING=rfc1459 CHANTYPES=# NICKLEN={} CHANNELLEN={} TOPICLEN={} CHANLIMIT=#:{} CHANMODES=b,k,l,imnt PREFIX=(ov)@+ :are supported by this server",self.settings.number("NICKLEN"),self.settings.number("CHANNELLEN"),self.settings.number("TOPICLEN"),self.settings.number("MAXCHANNELS")));
        self.numeric(i,375,format!(":- {} Message of the day -",self.settings.text("NAME")));
        for line in self.settings.motd.clone() {
            self.numeric(i,372,format!(":- {}",line));
        }
        self.numeric(i,376,":End of /MOTD command.".to_owned());
        if self.client(i).invisible {
            self.send(i,format!(":{} MODE {} :+i",self.client(i).addressee(),self.client(i).addressee()));
        }
    }
    fn names(&mut self, i: usize, channel: usize) {
        let member = self.channel(channel).member(i).is_some();
        let names: Vec<_> = self.channel(channel).members.iter().filter(|m| member || !self.client(m.client).invisible).map(|m| self.channel(channel).display(m.client,self.client(m.client).addressee())).collect();
        let name = self.channel(channel).name.clone();
        if !names.is_empty() {
            self.numeric(i,353,format!("= {} :{}",name,names.join(" ")));
        }
        self.numeric(i,366,format!("{} :End of /NAMES list.",name));
    }
    fn topic_replies(&mut self, i: usize, channel: usize) {
        let c = self.channel(channel);
        let first = format!("{} :{}",c.name,c.topic);
        let second = format!("{} {} {}",c.name,c.setter,c.topic_time);
        self.numeric(i,332,first);
        self.numeric(i,333,second);
    }
    fn joined_names(&self, i: usize, delimiter: &str) -> String {
        self.client(i).channels.iter().map(|&s| format!("{}{}",self.channel(s).privilege(i),self.channel(s).name)).collect::<Vec<_>>().join(delimiter)
    }
    fn need(&mut self, i: usize, command: &str, parameters: &[String], count: usize) -> bool {
        if parameters.len() < count {
            self.error(i,461,command);
            false
        } else {
            true
        }
    }
    fn process(&mut self, i: usize, raw: String) {
        self.message_counts[2] += 1;
        let Some((command,p)) = protocol::parse(&raw) else {
            self.message_counts[4] += 1;
            return;
        };
        *self.commands.entry(command.clone()).or_insert(0) += 1;
        if !self.client(i).registered && !["NICK","USER","PING","PONG","QUIT"].contains(&command.as_str()) {
            self.error(i,451,"");
            return;
        }
        match command.as_str() {
            "NICK" => {
                if p.first().map_or(true,|s| s.is_empty()) {
                    self.error(i,431,"");
                    return;
                }
                let n = p[0][..p[0].len().min(self.settings.number("NICKLEN"))].to_owned();
                if !protocol::nickname(&n) {
                    self.error(i,432,&n);
                    return;
                }
                if self.client(i).nickname.as_deref() == Some(n.as_str()) {
                    return;
                }
                if self.clients.iter().enumerate().any(|(j,c)| j != i && c.as_ref().and_then(|c| c.nickname.as_ref()).map_or(false,|nick| protocol::fold(nick) == protocol::fold(&n))) {
                    self.error(i,433,&n);
                    return;
                }
                if self.client(i).registered {
                    let line = format!(":{} NICK :{}",self.client(i).prefix(),n);
                    self.send(i,line.clone());
                    for peer in self.peers(i) {
                        self.send(peer,line.clone());
                    }
                }
                self.clients[i].as_mut().unwrap().nickname = Some(n);
                self.register(i);
            }
            "USER" => {
                if self.client(i).username.is_some() {
                    self.error(i,462,"");
                    return;
                }
                if !self.need(i,&command,&p,4) {
                    return;
                }
                let invisible = protocol::digits(&p[1]) && p[1].len() <= 3 && (p[1].parse::<usize>().unwrap()/8)%2 == 1;
                let c = self.clients[i].as_mut().unwrap();
                c.username = Some(p[0].clone());
                c.realname = p[3].clone();
                c.invisible = invisible;
                self.register(i);
            }
            "PING" => {
                if p.first().map_or(true,|s| s.is_empty()) {
                    self.error(i,409,"");
                } else {
                    self.send(i,format!(":{} PONG {} :{}",self.settings.text("NAME"),self.settings.text("NAME"),p[0]));
                }
            }
            "PONG" => (), "QUIT" => {
                let reason = p.first().filter(|s| !s.is_empty()).map_or_else(|| "Client Quit".to_owned(),|s| format!("Quit: {}",s));
                self.disconnect(i,reason,0);
            }
            "JOIN" => self.join(i,&p), "PART" => {
                if !self.need(i,&command,&p,1) {
                    return;
                }
                let suffix = p.get(1).filter(|s| !s.is_empty()).map_or_else(String::new,|s| format!(" :{}",s));
                for x in p[0].split(',') {
                    if let Some(s) = self.find_channel(x) {
                        let name = self.channel(s).name.clone();
                        if self.channel(s).member(i).is_none() {
                            self.error(i,442,&name);
                        } else {
                            self.broadcast(s,format!(":{} PART {}{}",self.client(i).prefix(),name,suffix),None);
                            self.remove_member(i,s);
                        }
                    } else {
                        self.error(i,403,x);
                    }
                }
            }
            "PRIVMSG" | "NOTICE" => self.message(i,&command,&p), "TOPIC" => {
                if !self.need(i,&command,&p,1) {
                    return;
                }
                let Some(s) = self.find_channel(&p[0]) else {
                    self.error(i,403,&p[0]);
                    return;
                };
                let name = self.channel(s).name.clone();
                let Some(member) = self.channel(s).member(i) else {
                    self.error(i,442,&name);
                    return;
                };
                if p.len() == 1 {
                    if self.channel(s).topic.is_empty() {
                        self.numeric(i,331,format!("{} :No topic is set",name));
                    } else {
                        self.topic_replies(i,s);
                    }
                    return;
                }
                if self.channel(s).flags.contains(&b't') && !member.operator {
                    self.error(i,482,&name);
                    return;
                }
                let topic = p[1][..p[1].len().min(self.settings.number("TOPICLEN"))].to_owned();
                let setter = self.client(i).addressee().to_owned();
                let channel = self.channels[s].as_mut().unwrap();
                channel.topic = topic.clone();
                channel.setter = setter;
                channel.topic_time = self.time;
                self.broadcast(s,format!(":{} TOPIC {} :{}",self.client(i).prefix(),name,topic),None);
            }
            "NAMES" => {
                if p.is_empty() {
                    self.numeric(i,366,"* :End of /NAMES list.".to_owned());
                } else {
                    for name in p[0].split(',') {
                        if let Some(s) = self.find_channel(name) {
                            self.names(i,s);
                        } else {
                            self.numeric(i,366,format!("{} :End of /NAMES list.",name));
                        }
                    }
                }
            }
            "WHOIS" => self.whois(i,&p), "AWAY" => {
                let away = p.first().cloned().unwrap_or_default();
                let number = if away.is_empty() {
                    305
                } else {
                    306
                };
                self.clients[i].as_mut().unwrap().away = away;
                self.numeric(i,number,if number == 305 {
                    ":You are no longer marked as being away"
                } else {
                    ":You have been marked as being away"
                }.to_owned());
            }
            "INVITE" => self.invite(i,&p), "KICK" => self.kick(i,&p), "MODE" => self.mode(i,&p), _ => self.error(i,421,&command)
        }
    }
    fn join(&mut self, i: usize, p: &[String]) {
        if !self.need(i,"JOIN",p,1) {
            return;
        }
        if p[0] == "0" {
            for s in self.client(i).channels.clone() {
                self.broadcast(s,format!(":{} PART {}",self.client(i).prefix(),self.channel(s).name),None);
                self.remove_member(i,s);
            }
            return;
        }
        let keys: Vec<_> = p.get(1).map_or_else(Vec::new,|s| s.split(',').collect());
        for (index,x) in p[0].split(',').enumerate() {
            if !protocol::channel(x,self.settings.number("CHANNELLEN")) {
                self.error(i,403,x);
                continue;
            }
            let found = self.find_channel(x);
            if found.map_or(false,|s| self.channel(s).member(i).is_some()) {
                continue;
            }
            if self.client(i).channels.len() >= self.settings.number("MAXCHANNELS") {
                self.error(i,405,x);
                continue;
            }
            let s = if let Some(s) = found {
                let c = self.channel(s);
                let invited = self.client(i).invites.contains(&s);
                let key = keys.get(index).copied().unwrap_or("");
                let error = if c.banned(&self.client(i).prefix()) && !invited {
                    474
                } else if c.flags.contains(&b'i') && !invited {
                    473
                } else if !c.key.is_empty() && c.key != key {
                    475
                } else if c.limit > 0 && c.members.len() >= c.limit {
                    471
                } else {
                    0
                };
                if error != 0 {
                    let name = c.name.clone();
                    self.error(i,error,&name);
                    continue;
                }
                s
            } else {
                self.channels.push(Some(Channel::new(x.to_owned(),self.time)));
                self.channels.len()-1
            };
            self.clients[i].as_mut().unwrap().invites.retain(|&c| c != s);
            self.channels[s].as_mut().unwrap().add(i);
            self.clients[i].as_mut().unwrap().channels.push(s);
            self.broadcast(s,format!(":{} JOIN {}",self.client(i).prefix(),self.channel(s).name),None);
            if !self.channel(s).topic.is_empty() {
                self.topic_replies(i,s);
            }
            self.names(i,s);
        }
    }
    fn message(&mut self, i: usize, command: &str, p: &[String]) {
        let notice = command == "NOTICE";
        if !notice {
            self.clients[i].as_mut().unwrap().last_speaking = self.time;
        }
        if p.first().map_or(true,|s| s.is_empty()) {
            if !notice {
                self.error(i,411,command);
            }
            return;
        }
        if p.get(1).map_or(true,|s| s.is_empty()) {
            if !notice {
                self.error(i,412,"");
            }
            return;
        }
        for target in p[0].split(',') {
            if target.starts_with('#') {
                if let Some(s) = self.find_channel(target) {
                    let name = self.channel(s).name.clone();
                    if !self.channel(s).can_speak(i,&self.client(i).prefix()) {
                        if !notice {
                            self.error(i,404,&name);
                        }
                    } else {
                        self.channels[s].as_mut().unwrap().messages += 1;
                        self.broadcast(s,format!(":{} {} {} :{}",self.client(i).prefix(),command,name,p[1]),Some(i));
                    }
                } else if !notice {
                    self.error(i,401,target);
                }
            } else if let Some(user) = self.find_user(target) {
                self.send(user,format!(":{} {} {} :{}",self.client(i).prefix(),command,self.client(user).addressee(),p[1]));
                if !notice && !self.client(user).away.is_empty() {
                    self.numeric(i,301,format!("{} :{}",self.client(user).addressee(),self.client(user).away));
                }
            } else if !notice {
                self.error(i,401,target);
            }
        }
    }
    fn whois(&mut self, i: usize, p: &[String]) {
        if p.is_empty() {
            self.error(i,431,"");
            return;
        }
        let Some(u) = self.find_user(&p[0]) else {
            self.error(i,401,&p[0]);
            self.numeric(i,318,format!("{} :End of /WHOIS list.",p[0]));
            return;
        };
        let nickname = self.client(u).addressee().to_owned();
        self.numeric(i,311,format!("{} {} {} * :{}",nickname,self.client(u).username.as_deref().unwrap(),self.client(u).host,self.client(u).realname));
        if !self.client(u).channels.is_empty() {
            self.numeric(i,319,format!("{} :{}",nickname,self.joined_names(u," ")));
        }
        self.numeric(i,312,format!("{} {} :{}",nickname,self.settings.text("NAME"),self.settings.text("DESCRIPTION")));
        if !self.client(u).away.is_empty() {
            self.numeric(i,301,format!("{} :{}",nickname,self.client(u).away));
        }
        self.numeric(i,317,format!("{} {} {} :seconds idle, signon time",nickname,self.time-self.client(u).last_speaking,self.client(u).signon.unwrap()));
        self.numeric(i,318,format!("{} :End of /WHOIS list.",nickname));
    }
    fn invite(&mut self, i: usize, p: &[String]) {
        if !self.need(i,"INVITE",p,2) {
            return;
        }
        let Some(u) = self.find_user(&p[0]) else {
            self.error(i,401,&p[0]);
            return;
        };
        let Some(s) = self.find_channel(&p[1]) else {
            self.error(i,403,&p[1]);
            return;
        };
        let name = self.channel(s).name.clone();
        let nickname = self.client(u).addressee().to_owned();
        let Some(member) = self.channel(s).member(i) else {
            self.error(i,442,&name);
            return;
        };
        if self.channel(s).member(u).is_some() {
            self.error(i,443,&format!("{} {}",nickname,name));
            return;
        }
        if self.channel(s).flags.contains(&b'i') && !member.operator {
            self.error(i,482,&name);
            return;
        }
        if !self.client(u).invites.contains(&s) {
            self.clients[u].as_mut().unwrap().invites.push(s);
        }
        self.numeric(i,341,format!("{} {}",nickname,name));
        if !self.client(u).away.is_empty() {
            self.numeric(i,301,format!("{} :{}",nickname,self.client(u).away));
        }
        self.send(u,format!(":{} INVITE {} :{}",self.client(i).prefix(),nickname,name));
    }
    fn kick(&mut self, i: usize, p: &[String]) {
        if !self.need(i,"KICK",p,2) {
            return;
        }
        let Some(s) = self.find_channel(&p[0]) else {
            self.error(i,403,&p[0]);
            return;
        };
        let name = self.channel(s).name.clone();
        let Some(member) = self.channel(s).member(i) else {
            self.error(i,442,&name);
            return;
        };
        if !member.operator {
            self.error(i,482,&name);
            return;
        }
        let Some(u) = self.find_user(&p[1]) else {
            self.error(i,401,&p[1]);
            return;
        };
        let nickname = self.client(u).addressee().to_owned();
        if self.channel(s).member(u).is_none() {
            self.error(i,441,&format!("{} {}",nickname,name));
            return;
        }
        let reason = p.get(2).filter(|s| !s.is_empty()).map_or(self.client(i).addressee(),String::as_str);
        self.broadcast(s,format!(":{} KICK {} {} :{}",self.client(i).prefix(),name,nickname,reason),None);
        self.remove_member(u,s);
    }
    fn mode(&mut self, i: usize, p: &[String]) {
        if !self.need(i,"MODE",p,1) {
            return;
        }
        if !p[0].starts_with('#') {
            let Some(u) = self.find_user(&p[0]) else {
                self.error(i,401,&p[0]);
                return;
            };
            if u != i {
                self.error(i,502,"");
                return;
            }
            if p.len() == 1 {
                self.numeric(i,221,self.client(i).mode().to_owned());
                return;
            }
            let mut plus = true;
            let mut changes = Vec::new();
            let mut unknown = false;
            for character in p[1].bytes() {
                if character == b'+' || character == b'-' {
                    plus = character == b'+';
                } else if character != b'i' {
                    unknown = true;
                } else if self.client(i).invisible != plus {
                    self.clients[i].as_mut().unwrap().invisible = plus;
                    changes.push(Item {
                        plus,
                        character,
                        argument: None
                    });
                }
            }
            if !changes.is_empty() {
                self.send(i,format!(":{} MODE {} :{}",self.client(i).addressee(),self.client(i).addressee(),modes::changes(&changes)));
            }
            if unknown {
                self.error(i,501,"");
            }
            return;
        }
        let Some(s) = self.find_channel(&p[0]) else {
            self.error(i,403,&p[0]);
            return;
        };
        let name = self.channel(s).name.clone();
        if p.len() == 1 {
            self.numeric(i,324,format!("{} {}",name,self.channel(s).mode(self.channel(s).member(i).is_some())));
            self.numeric(i,329,format!("{} {}",name,self.channel(s).created));
            return;
        }
        let operator = self.channel(s).member(i).map_or(false,|m| m.operator);
        let mut denied = false;
        let mut bans_sent = false;
        let mut changes = Vec::new();
        for item in modes::items(&p[1],&p[2..]) {
            let c = item.character;
            let plus = item.plus;
            if !b"biklmnotv".contains(&c) {
                self.numeric(i,472,format!("{} :is unknown mode char to me for {}",c as char,name));
                continue;
            }
            if c == b'b' && item.argument.is_none() {
                if plus && !bans_sent {
                    bans_sent = true;
                    let bans: Vec<_> = self.channel(s).bans.iter().map(|b| format!("{} {} {} {}",name,b.mask,b.setter,b.time)).collect();
                    for ban in bans {
                        self.numeric(i,367,ban);
                    }
                    self.numeric(i,368,format!("{} :End of channel ban list",name));
                }
                continue;
            }
            if ((c == b'o' || c == b'v') || (plus && (c == b'k' || c == b'l'))) && item.argument.is_none() {
                continue;
            }
            if !operator {
                if !denied {
                    self.error(i,482,&name);
                    denied = true;
                }
                continue;
            }
            let mut argument = None;
            let mut changed = false;
            match c {
                b'o' | b'v' => {
                    let target = item.argument.as_ref().unwrap();
                    let Some(u) = self.find_user(target) else {
                        self.error(i,401,target);
                        continue;
                    };
                    let nickname = self.client(u).addressee().to_owned();
                    if self.channel(s).member(u).is_none() {
                        self.error(i,441,&format!("{} {}",nickname,name));
                        continue;
                    }
                    let member = self.channels[s].as_mut().unwrap().member_mut(u).unwrap();
                    let privilege = if c == b'o' {
                        &mut member.operator
                    } else {
                        &mut member.voice
                    };
                    if *privilege != plus {
                        *privilege = plus;
                        changed = true;
                        argument = Some(nickname);
                    }
                }
                b'b' => {
                    let mask = masks::normalize(item.argument.as_ref().unwrap());
                    let existing = self.channel(s).bans.iter().position(|b| protocol::fold(&b.mask) == protocol::fold(&mask));
                    if plus && existing.is_none() {
                        let setter = self.client(i).addressee().to_owned();
                        self.channels[s].as_mut().unwrap().bans.push(Ban {
                            mask: mask.clone(),
                            setter,
                            time: self.time
                        });
                        changed = true;
                        argument = Some(mask);
                    } else if !plus {
                        if let Some(index) = existing {
                            let removed = self.channels[s].as_mut().unwrap().bans.remove(index);
                            argument = Some(removed.mask);
                            changed = true;
                        }
                    }
                }
                b'k' => {
                    if plus {
                        if !self.channel(s).key.is_empty() {
                            self.error(i,467,&name);
                        } else {
                            let key = item.argument.clone().unwrap();
                            self.channels[s].as_mut().unwrap().key = key.clone();
                            argument = Some(key);
                            changed = true;
                        }
                    } else if !self.channel(s).key.is_empty() {
                        self.channels[s].as_mut().unwrap().key.clear();
                        argument = Some("*".to_owned());
                        changed = true;
                    }
                }
                b'l' => {
                    let limit = if plus {
                        item.argument.as_ref().unwrap().parse().unwrap()
                    } else {
                        0
                    };
                    if self.channel(s).limit != limit {
                        self.channels[s].as_mut().unwrap().limit = limit;
                        changed = true;
                        if plus {
                            argument = Some(limit.to_string());
                        }
                    }
                }
                _ => {
                    if self.channel(s).flags.contains(&c) != plus {
                        if plus {
                            self.channels[s].as_mut().unwrap().flags.insert(c);
                        } else {
                            self.channels[s].as_mut().unwrap().flags.remove(&c);
                        }
                        changed = true;
                    }
                }
            }
            if changed {
                changes.push(Item {
                    plus,
                    character: c,
                    argument
                });
            }
        }
        if !changes.is_empty() {
            self.broadcast(s,format!(":{} MODE {} {}",self.client(i).prefix(),name,modes::changes(&changes)),None);
        }
    }
    fn arrive(&mut self, id: &str, body: &str) {
        self.line_counts[0] += 1;
        if let Some(host) = body.strip_prefix("CONNECT ") {
            self.line_counts[1] += 1;
            self.clients.push(Some(Client::new(id.to_owned(),host.to_owned(),self.time,self.settings.number("BUCKET"))));
            let count = self.clients.iter().flatten().count();
            if count > self.peaks[0].0 {
                self.peaks[0] = (count,self.time);
            }
        } else if body == "DISCONNECT" {
            self.line_counts[2] += 1;
            if let Some(i) = self.find_connection(id) {
                self.disconnect(i,"Remote host closed the connection".to_owned(),1);
            }
        } else {
            self.line_counts[3] += 1;
            let Some(i) = self.find_connection(id) else {
                self.message_counts[0] += 1;
                return;
            };
            let c = self.clients[i].as_mut().unwrap();
            c.received += 1;
            c.last_received = self.time;
            c.ping = None;
            if c.queue.is_empty() && c.tokens > 0 {
                c.use_token(self.time,self.settings.number("BUCKET"),self.settings.number("REFILL"));
                self.process(i,body.to_owned());
            } else if c.queue.len() >= self.settings.number("QUEUE") {
                self.message_counts[3] += 1;
                self.disconnect(i,"Excess Flood".to_owned(),2);
            } else {
                c.queue.push_back(body.to_owned());
                self.message_counts[1] += 1;
            }
        }
    }
    fn run(&mut self) -> usize {
        let traffic: Vec<_> = fs::read_to_string("input/traffic.txt").unwrap().lines().map(|line| {
            let mut w = line.splitn(3,' ');
            (w.next().unwrap().parse::<usize>().unwrap(),w.next().unwrap().to_owned(),w.next().unwrap().to_owned())
        }).collect();
        let end = traffic.last().unwrap().0;
        let mut next = 0;
        for time in 0..=end {
            self.time = time;
            let clients: Vec<_> = self.clients.iter().enumerate().filter(|(_,c)| c.is_some()).map(|(i,_)| i).collect();
            for i in clients {
                self.clients[i].as_mut().unwrap().refill(time,self.settings.number("BUCKET"),self.settings.number("REFILL"));
                loop {
                    let raw = if let Some(c) = self.clients[i].as_mut() {
                        if c.tokens > 0 && !c.queue.is_empty() {
                            c.use_token(time,self.settings.number("BUCKET"),self.settings.number("REFILL"));
                            c.queue.pop_front()
                        } else {
                            None
                        }
                    } else {
                        None
                    };
                    if let Some(raw) = raw {
                        self.process(i,raw);
                    } else {
                        break;
                    }
                }
            }
            while next < traffic.len() && traffic[next].0 == time {
                self.arrive(&traffic[next].1,&traffic[next].2);
                next += 1;
            }
            let clients: Vec<_> = self.clients.iter().enumerate().filter(|(_,c)| c.is_some()).map(|(i,_)| i).collect();
            for i in clients {
                if let Some(sent) = self.client(i).ping {
                    if time-sent >= self.settings.number("TIMEOUT") {
                        self.disconnect(i,format!("Ping timeout: {} seconds",time-self.client(i).last_received),3);
                    }
                } else if time-self.client(i).last_received >= self.settings.number("PINGFREQ") {
                    self.pings += 1;
                    self.send(i,format!("PING :{}",self.settings.text("NAME")));
                    self.clients[i].as_mut().unwrap().ping = Some(time);
                }
            }
        }
        end
    }
    fn reports(&self, end: usize) -> [(String,Vec<String>);4] {
        let mut channel_lines = Vec::new();
        let mut total_members = 0;
        let mut total_bans = 0;
        for channel in self.channels.iter().flatten() {
            total_members += channel.members.len();
            total_bans += channel.bans.len();
            channel_lines.push(format!("CHANNEL {} created {} members {} peak {} messages {} modes {}",channel.name,channel.created,channel.members.len(),channel.peak,channel.messages,channel.mode(true)));
            channel_lines.push(if channel.topic.is_empty() {
                "TOPIC none".to_owned()
            } else {
                format!("TOPIC {} {} {}",channel.setter,channel.topic_time,channel.topic)
            });
            for ban in &channel.bans {
                channel_lines.push(format!("BAN {} {} {}",ban.mask,ban.setter,ban.time));
            }
            channel_lines.push(format!("MEMBERS {}",channel.members.iter().map(|m| channel.display(m.client,self.client(m.client).addressee())).collect::<Vec<_>>().join(" ")));
        }
        channel_lines.push(format!("TOTAL channels {} members {} bans {}",self.channels.iter().flatten().count(),total_members,total_bans));
        let mut client_lines = Vec::new();
        for (i,client) in self.clients.iter().enumerate().filter_map(|(i,c)| c.as_ref().map(|c| (i,c))) {
            let joined = self.joined_names(i,",");
            let invites = client.invites.iter().map(|&s| self.channel(s).name.as_str()).collect::<Vec<_>>().join(",");
            client_lines.push(format!("CLIENT {} {} {} {} {} connected {} signon {} received {} sent {} tokens {} queue {} channels {} invites {}",client.id,client.addressee(),client.username.as_deref().unwrap_or("*"),client.host,client.mode(),client.connected,client.signon.map_or_else(|| "-".to_owned(),|t| t.to_string()),client.received,client.sent,client.tokens,client.queue.len(),if joined.is_empty() {
                "none"
            } else {
                &joined
            },if invites.is_empty() {
                "none"
            } else {
                &invites
            }));
            if !client.away.is_empty() {
                client_lines.push(format!("AWAY {} {}",client.id,client.away));
            }
        }
        client_lines.push(format!("TOTAL clients {} registered {} invisible {} away {}",self.clients.iter().flatten().count(),self.clients.iter().flatten().filter(|c| c.registered).count(),self.clients.iter().flatten().filter(|c| c.invisible).count(),self.clients.iter().flatten().filter(|c| !c.away.is_empty()).count()));
        let counts = self.line_counts;
        let messages = self.message_counts;
        let mut statistics = vec![format!("END {}",end),format!("LINES total {} connect {} disconnect {} messages {}",counts[0],counts[1],counts[2],counts[3]),format!("MESSAGES dropped {} queued {} processed {} discarded {} pending {} empty {}",messages[0],messages[1],messages[2],messages[3],self.clients.iter().flatten().map(|c| c.queue.len()).sum::<usize>(),messages[4]),format!("SENT lines {} numerics {} pings {} errors {}",self.sent.len(),self.numerics.values().sum::<usize>(),self.pings,self.errors)];
        for (command,count) in &self.commands {
            statistics.push(format!("COMMAND {} {}",command,count));
        }
        for (number,count) in &self.numerics {
            statistics.push(format!("NUMERIC {:03} {}",number,count));
        }
        statistics.push(format!("PEAK connections {} at {}",self.peaks[0].0,self.peaks[0].1));
        statistics.push(format!("PEAK registered {} at {}",self.peaks[1].0,self.peaks[1].1));
        statistics.push(format!("DISCONNECTS quit {} closed {} flood {} timeout {}",self.disconnects[0],self.disconnects[1],self.disconnects[2],self.disconnects[3]));
        statistics.extend(self.gone.clone());
        [("sent.txt".to_owned(),self.sent.clone()),("channels.txt".to_owned(),channel_lines),("clients.txt".to_owned(),client_lines),("stats.txt".to_owned(),statistics)]
    }
}
fn main() {
    let mut server = Server::new();
    let end = server.run();
    fs::create_dir_all("output").unwrap();
    for (name,lines) in server.reports(end) {
        let content = if lines.is_empty() {
            String::new()
        } else {
            lines.join("\n")+"\n"
        };
        fs::write(format!("output/{}",name),content).unwrap();
    }
}
