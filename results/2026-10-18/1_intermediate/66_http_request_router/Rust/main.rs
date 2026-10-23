use std::collections::{BTreeMap, BTreeSet};
use std::io::{self, Read};

fn name(s: &str) -> bool { (1..=20).contains(&s.len()) && s.as_bytes()[0].is_ascii_lowercase() && s.bytes().all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c==b'_') }
fn role(s: &str) -> bool { (1..=16).contains(&s.len()) && s.bytes().all(|c| c.is_ascii_lowercase()) }
fn unreserved(c: u8) -> bool { c.is_ascii_alphanumeric() || b"-._~".contains(&c) }
fn segment(s: &str) -> bool { !s.is_empty() && s!="." && s!=".." && s.bytes().all(unreserved) }
fn canonical(s: &str) -> bool { s=="/" || (s.starts_with('/') && s[1..].split('/').all(segment)) }
fn media_part(s: &str) -> bool { !s.is_empty() && s.bytes().all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || b".+-".contains(&c)) }
fn media(s: &str) -> bool { s.split_once('/').is_some_and(|(a,b)| media_part(a) && media_part(b)) }
fn int_parameter(s: &str) -> bool { (1..=9).contains(&s.len()) && s.bytes().all(|c| c.is_ascii_digit()) }
fn slug(s: &str) -> bool { !s.is_empty() && s.bytes().all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c==b'-') }
fn decimal(s: &str, max: i64) -> Option<i64> { if s.is_empty() || (s.len()>1 && s.starts_with('0')) || !s.bytes().all(|c| c.is_ascii_digit()) { None } else { s.parse::<i64>().ok().filter(|&n| n>=1 && n<=max) } }
fn hex(c: u8) -> Option<u8> { match c { b'0'..=b'9' => Some(c-b'0'), b'a'..=b'f' => Some(c-b'a'+10), b'A'..=b'F' => Some(c-b'A'+10), _ => None } }
fn decode(s: &str) -> String {
    let b=s.as_bytes(); let mut at=0; let mut out=String::new();
    while at<b.len() { if b[at]==b'%' { out.push((hex(b[at+1]).unwrap()*16+hex(b[at+2]).unwrap()) as char); at+=3; } else { out.push(b[at] as char); at+=1; } }
    out
}
fn encode(s: &str) -> String { s.bytes().map(|c| if unreserved(c) { (c as char).to_string() } else { format!("%{c:02X}") }).collect() }
fn valid_escapes(s: &str) -> bool {
    let b=s.as_bytes(); let mut at=0;
    while at<b.len() {
        if b[at]==b'%' {
            if at+2>=b.len() { return false; }
            let (Some(a),Some(c))=(hex(b[at+1]),hex(b[at+2])) else { return false; };
            if !(32..=126).contains(&(a*16+c)) { return false; } at+=3;
        } else { at+=1; }
    }
    true
}
fn normalize(path: &str) -> String {
    let b=path.as_bytes(); let mut text=String::new(); let mut at=0;
    while at<b.len() {
        if b[at]==b'%' { let c=hex(b[at+1]).unwrap()*16+hex(b[at+2]).unwrap(); if unreserved(c) { text.push(c as char); } else { text+=&format!("%{c:02X}"); } at+=3; }
        else { text.push(b[at] as char); at+=1; }
    }
    let mut parts=Vec::new();
    for part in text[1..].split('/') { match part { ""|"." => {}, ".." => { parts.pop(); }, _ => parts.push(part) } }
    format!("/{}",parts.join("/"))
}
#[derive(Clone)]
struct Piece { kind: char, value: String }
fn pattern(s: &str) -> Option<Vec<Piece>> {
    if s=="/" { return Some(Vec::new()); }
    if !s.starts_with('/') { return None; }
    let parts:Vec<_>=s[1..].split('/').collect(); let mut result=Vec::new(); let mut names=BTreeSet::new();
    for (i,p) in parts.iter().enumerate() {
        let piece=if segment(p) { Piece { kind:'l',value:(*p).into() } }
        else if p.starts_with('{') && p.ends_with('}') {
            let inner=&p[1..p.len()-1];
            let (kind,value)=if let Some(value)=inner.strip_prefix('*') { if i+1!=parts.len() { return None; } ('w',value) }
            else if let Some((value,t))=inner.split_once(':') { (match t { "int"=>'i',"slug"=>'s',_=>return None },value) }
            else { ('p',inner) };
            if !name(value) || !names.insert(value.to_string()) { return None; }
            Piece { kind,value:value.into() }
        } else { return None; };
        result.push(piece);
    }
    Some(result)
}
#[derive(Clone)]
struct Route { name:String, methods:BTreeSet<String>, pattern:String, pieces:Vec<Piece>, role:String, types:Option<Vec<String>>, count:usize }
impl Route {
    fn matches(&self, parts:&[&str]) -> bool {
        let wildcard=self.pieces.last().is_some_and(|p| p.kind=='w'); let m=self.pieces.len()-usize::from(wildcard);
        (if wildcard { parts.len()>=m } else { parts.len()==m }) && self.pieces[..m].iter().zip(parts).all(|(p,x)| match p.kind { 'l'=>p.value==*x,'i'=>int_parameter(x),'s'=>slug(x),_=>true })
    }
    fn parameters(&self, parts:&[&str]) -> Vec<(String,String)> {
        let mut result=Vec::new();
        for (i,p) in self.pieces.iter().enumerate() {
            let value=match p.kind { 'l'=>continue,'w'=>parts[i..].iter().map(|s| decode(s)).collect::<Vec<_>>().join("/"),'i'=>parts[i].parse::<u32>().unwrap().to_string(),'s'=>parts[i].to_string(),_=>decode(parts[i]) };
            result.push((p.value.clone(),value));
        }
        result.sort_by(|a,b| a.0.cmp(&b.0)); result
    }
}
struct Redirect { from:String,to:String,prefix:bool,code:u16 }
struct Client { level:i64,last:i64,allowed:usize,limited:usize }
struct Response { status:u16,headers:BTreeMap<String,String>,body:String,head:bool,content_type:String }
impl Response {
    fn new(status:u16,body:impl Into<String>) -> Self { Self { status,headers:BTreeMap::new(),body:body.into(),head:false,content_type:"text/plain".into() } }
    fn header(mut self,name:&str,value:impl Into<String>) -> Self { self.headers.insert(name.into(),value.into()); self }
}
struct Router {
    routes:Vec<Route>,priority:Vec<usize>,tokens:BTreeMap<String,String>,redirects:Vec<Redirect>,origins:BTreeSet<String>,limit:Option<(i64,i64)>,clients:BTreeMap<String,Client>,statuses:BTreeMap<u16,usize>,config_errors:usize,
}
impl Router {
    fn new() -> Self { Self { routes:Vec::new(),priority:Vec::new(),tokens:BTreeMap::new(),redirects:Vec::new(),origins:BTreeSet::new(),limit:None,clients:BTreeMap::new(),statuses:BTreeMap::new(),config_errors:0 } }
    fn config(&mut self,w:&[&str]) -> Result<(),String> {
        let command=w[0]; let args=w.len()-1;
        if !["ROUTE","TOKEN","REDIRECT","ORIGIN","LIMIT","TYPES"].contains(&command) { return Err(format!("unknown command {command}")); }
        let valid=match command { "ROUTE"=>args==3 || args==5,"TOKEN"|"LIMIT"=>args==2,"REDIRECT"=>args==3,"ORIGIN"=>args==1,_=>args>=2 };
        if !valid { return Err("wrong number of arguments".into()); }
        match command {
            "ROUTE" => {
                if !name(w[1]) { return Err(format!("bad route name {}",w[1])); }
                if self.routes.iter().any(|r| r.name==w[1]) { return Err(format!("duplicate route {}",w[1])); }
                let methods:Vec<_>=w[2].split(',').collect(); let set:BTreeSet<_>=methods.iter().map(|m| m.to_string()).collect();
                if methods.iter().any(|m| !["GET","POST","PUT","PATCH","DELETE"].contains(m)) || methods.len()!=set.len() { return Err(format!("bad methods {}",w[2])); }
                let pieces=pattern(w[3]).ok_or_else(|| format!("bad pattern {}",w[3]))?;
                if args==5 && w[4]!="ROLE" { return Err(format!("unknown option {}",w[4])); }
                if args==5 && !role(w[5]) { return Err(format!("bad role {}",w[5])); }
                self.routes.push(Route { name:w[1].into(),methods:set,pattern:w[3].into(),pieces,role:if args==5 { w[5].into() } else { "none".into() },types:None,count:0 });
            }
            "TOKEN" => {
                if !(1..=32).contains(&w[1].len()) || !w[1].bytes().all(|c| c.is_ascii_alphanumeric() || b"._-".contains(&c)) { return Err(format!("bad token {}",w[1])); }
                if self.tokens.contains_key(w[1]) { return Err(format!("duplicate token {}",w[1])); }
                if !role(w[2]) { return Err(format!("bad role {}",w[2])); }
                self.tokens.insert(w[1].into(),w[2].into());
            }
            "REDIRECT" => {
                let rule=|s:&str| canonical(s) || s.strip_suffix("/*").is_some_and(|base| base!="/" && canonical(base));
                if !rule(w[1]) { return Err(format!("bad path {}",w[1])); } if !rule(w[2]) { return Err(format!("bad path {}",w[2])); }
                let p=w[1].ends_with("/*"); if p!=w[2].ends_with("/*") { return Err("wildcard mismatch".into()); }
                if !["301","302","307","308"].contains(&w[3]) { return Err(format!("bad redirect code {}",w[3])); }
                if self.redirects.iter().any(|r| r.prefix==p && r.from==w[1].strip_suffix("/*").unwrap_or(w[1])) { return Err(format!("duplicate redirect {}",w[1])); }
                self.redirects.push(Redirect { from:w[1].strip_suffix("/*").unwrap_or(w[1]).into(),to:w[2].strip_suffix("/*").unwrap_or(w[2]).into(),prefix:p,code:w[3].parse().unwrap() });
            }
            "ORIGIN" => {
                let suffix=w[1].strip_prefix("http://").or_else(||w[1].strip_prefix("https://"));
                if !suffix.is_some_and(|s| !s.is_empty() && s.bytes().all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || b".-:".contains(&c))) { return Err(format!("bad origin {}",w[1])); }
                if self.origins.contains(w[1]) { return Err(format!("duplicate origin {}",w[1])); } self.origins.insert(w[1].into());
            }
            "LIMIT" => {
                let (Some(n),Some(s))=(decimal(w[1],100),decimal(w[2],3600)) else { return Err("bad limit".into()); };
                if self.limit.is_some() { return Err("duplicate limit".into()); } self.limit=Some((n,s));
            }
            _ => {
                let i=self.routes.iter().position(|r|r.name==w[1]).ok_or_else(||format!("unknown route {}",w[1]))?;
                if self.routes[i].types.is_some() { return Err(format!("duplicate types {}",w[1])); }
                let mut types=BTreeSet::new();
                for t in &w[2..] { if !media(t) { return Err(format!("bad media type {t}")); } if !types.insert(*t) { return Err(format!("duplicate media type {t}")); } }
                self.routes[i].types=Some(w[2..].iter().map(|s|s.to_string()).collect());
            }
        }
        Ok(())
    }
    fn table(&mut self) {
        println!("CONFIG routes={} tokens={} redirects={} origins={} limit={} errors={}",self.routes.len(),self.tokens.len(),self.redirects.len(),self.origins.len(),self.limit.map_or("none".into(),|(n,s)|format!("{n}/{s}")),self.config_errors);
        for route in &mut self.routes { route.types.get_or_insert_with(||vec!["application/json".into()]); }
        self.priority=(0..self.routes.len()).collect();
        let routes = &self.routes;
        self.priority.sort_by_key(|&i| { let r=&routes[i]; (std::cmp::Reverse(r.pieces.iter().filter(|p|p.kind=='l').count()),std::cmp::Reverse(r.pieces.iter().filter(|p|p.kind=='i'||p.kind=='s').count()),r.pieces.iter().any(|p|p.kind=='w'),i) });
        for (rank,&i) in self.priority.iter().enumerate() { let r=&self.routes[i]; let mut methods=r.methods.clone(); if methods.contains("GET") { methods.insert("HEAD".into()); } println!("TABLE {} {} {} {} role={} types={}",rank+1,r.name,methods.into_iter().collect::<Vec<_>>().join(","),r.pattern,if r.role=="none" { "-" } else { &r.role },r.types.as_ref().unwrap().join(",")); }
    }
    fn request(&mut self,line:&str,raw:&[&str]) -> Response {
        let w:Vec<_>=line.split(' ').collect();
        if w.len()!=3 || !(1..=16).contains(&w[0].len()) || !w[0].bytes().all(|c|c.is_ascii_uppercase()) || !w[1].starts_with('/') || w[1].contains('#') || w[2]!="HTTP/1.1" { return Response::new(400,"bad request: request line"); }
        let head=w[0]=="HEAD";
        if !valid_escapes(w[1]) { let mut r=Response::new(400,"bad request: percent escape"); r.head=head; return r; }
        let mut headers=BTreeMap::new();
        for (i,row) in raw.iter().enumerate() {
            let Some((name,value))=row.split_once(':') else { let mut r=Response::new(400,format!("bad request: header line {}",i+1)); r.head=head; return r; };
            if name.is_empty() || !name.bytes().all(|c|c.is_ascii_alphanumeric() || c==b'-') { let mut r=Response::new(400,format!("bad request: header line {}",i+1)); r.head=head; return r; }
            let name=name.to_ascii_lowercase();
            if headers.contains_key(&name) { let mut r=Response::new(400,format!("bad request: duplicate header {name}")); r.head=head; return r; }
            headers.insert(name,value.trim_matches(' ').to_string());
        }
        let mut response=self.valid_request(w[0],w[1],&headers); response.head=head;
        if let Some(origin)=headers.get("origin").filter(|s|self.origins.contains(*s)) {
            response.headers.insert("Access-Control-Allow-Origin".into(),origin.clone());
            if response.status==204 && headers.contains_key("access-control-request-method") { response.headers.insert("Access-Control-Allow-Methods".into(),response.headers["Allow"].clone()); }
        }
        response
    }
    fn valid_request(&mut self,method:&str,target:&str,h:&BTreeMap<String,String>) -> Response {
        if !["GET","HEAD","POST","PUT","PATCH","DELETE","OPTIONS"].contains(&method) { return Response::new(501,format!("not implemented: {method}")); }
        if h.get("host").is_none_or(|s|s.is_empty()) { return Response::new(400,"bad request: missing host"); }
        let mut effective=method;
        if let Some(value)=h.get("x-http-method-override") { if method=="POST" && ["PUT","PATCH","DELETE"].contains(&value.as_str()) { effective=value; } else { return Response::new(400,"bad request: method override"); } }
        if let Some(client)=h.get("x-client").filter(|s|!s.is_empty()) {
            let time=h["x-time"].parse::<i64>().unwrap(); let (n,s)=self.limit.unwrap_or((0,0));
            let c=self.clients.entry(client.clone()).or_insert(Client { level:n*s,last:time,allowed:0,limited:0 });
            if self.limit.is_some() {
                c.level=(n*s).min(c.level+(time-c.last)*n); c.last=time;
                if c.level<s { c.limited+=1; return Response::new(429,format!("too many requests: client {client}")).header("Retry-After",((s-c.level+n-1)/n).to_string()); }
                c.level-=s;
            }
            c.allowed+=1;
        }
        let (path,query)=target.split_once('?').map_or((target,None),|(p,q)|(p,Some(q)));
        let suffix=query.map_or(String::new(),|q|format!("?{q}")); let normalized=normalize(path);
        if normalized!=path { let dest=normalized+&suffix; return Response::new(308,format!("redirect to {dest}")).header("Location",dest); }
        for rule in &self.redirects {
            if path==rule.from || (rule.prefix && path.starts_with(&(rule.from.clone()+"/"))) { let dest=rule.to.clone()+&path[rule.from.len()..]+&suffix; return Response::new(rule.code,format!("redirect to {dest}")).header("Location",dest); }
        }
        let parts:Vec<_>=if path=="/" { Vec::new() } else { path[1..].split('/').collect() };
        let matching:Vec<_>=self.priority.iter().copied().filter(|&i|self.routes[i].matches(&parts)).collect();
        if matching.is_empty() { return Response::new(404,format!("not found: {path}")); }
        let mut allow=BTreeSet::from(["OPTIONS".to_string()]); for &i in &matching { allow.extend(self.routes[i].methods.iter().cloned()); } if allow.contains("GET") { allow.insert("HEAD".into()); }
        let allow=allow.into_iter().collect::<Vec<_>>().join(", ");
        if effective=="OPTIONS" { return Response::new(204,"").header("Allow",allow); }
        let lookup=if effective=="HEAD" { "GET" } else { effective };
        let Some(i)=matching.into_iter().find(|&i|self.routes[i].methods.contains(lookup)) else { return Response::new(405,format!("method not allowed: {effective}")).header("Allow",allow); };
        self.routes[i].count+=1; let route=self.routes[i].clone();
        if route.role!="none" {
            let Some(auth)=h.get("authorization") else { return Response::new(401,"unauthorized: missing token").header("WWW-Authenticate","Bearer realm=\"api\""); };
            let (scheme,token)=auth.split_once(' ').unwrap_or((auth,""));
            let token_role=self.tokens.get(token);
            if !scheme.eq_ignore_ascii_case("bearer") || token_role.is_none() { return Response::new(401,"unauthorized: invalid token").header("WWW-Authenticate","Bearer realm=\"api\", error=\"invalid_token\""); }
            if token_role.unwrap()!=&route.role && token_role.unwrap()!="admin" { return Response::new(403,format!("forbidden: requires role {}",route.role)); }
        }
        let types=route.types.as_ref().unwrap();
        let vary=|mut r:Response| { if types.len()>=2 { r.headers.insert("Vary".into(),"Accept".into()); } r };
        let selected=if let Some(accept)=h.get("accept") { negotiate(types,accept) } else { Some(types[0].clone()) };
        let Some(selected)=selected else { return vary(Response::new(406,format!("not acceptable: {}",types.join(", ")))); };
        let params=route.parameters(&parts); let queries=query.map_or(Vec::new(),|q| q.split('&').filter(|s|!s.is_empty()).map(|s|{ let (a,b)=s.split_once('=').unwrap_or((s,"")); (decode(&a.replace('+'," ")),decode(&b.replace('+'," "))) }).collect());
        let mut cookies=BTreeMap::new();
        if let Some(cookie)=h.get("cookie") { for p in cookie.split(';').map(|s|s.trim_matches(' ')) { if let Some((a,b))=p.split_once('=') { if !a.is_empty() { cookies.entry(a.to_string()).or_insert(b.to_string()); } } } }
        let cookies=cookies.into_iter().collect::<Vec<_>>();
        let body=body(&route.name,&selected,&params,&queries,&cookies); let etag=etag(&body);
        if h.get("if-none-match").is_some_and(|s|s.split(',').any(|p| { let p=p.trim_matches(' '); let p=p.strip_prefix("W/").unwrap_or(p); p=="*" || p==etag })) {
            return if lookup=="GET" { vary(Response::new(304,"").header("ETag",etag)) } else { vary(Response::new(412,format!("precondition failed: {etag}"))) };
        }
        let mut response=vary(Response::new(200,body).header("ETag",etag)); response.content_type=selected; response
    }
    fn urlfor(&self,w:&[&str]) -> Result<String,String> {
        let route=self.routes.iter().find(|r|r.name==w[1]).ok_or_else(||format!("unknown route {}",w[1]))?;
        let names:BTreeSet<_>=route.pieces.iter().filter(|p|p.kind!='l').map(|p|p.value.as_str()).collect();
        let mut args=Vec::new(); let mut params=BTreeMap::new();
        for arg in &w[2..] {
            let Some((name,value))=arg.split_once('=') else { return Err(format!("bad argument {arg}")); };
            if name.is_empty() { return Err(format!("bad argument {arg}")); }
            if names.contains(name) && params.insert(name,value).is_some() { return Err(format!("duplicate parameter {name}")); }
            args.push((name,value));
        }
        for p in route.pieces.iter().filter(|p|p.kind!='l') {
            let value=params.get(p.value.as_str()).copied();
            if p.kind!='w' && value.is_none() { return Err(format!("missing parameter {}",p.value)); }
            let valid=match p.kind { 'p'=>value.is_some_and(|v|!v.is_empty() && v!="." && v!=".."),'i'=>value.is_some_and(int_parameter),'s'=>value.is_some_and(slug),_=>value.is_none_or(|v| v.is_empty() || v.split('/').all(|p|!p.is_empty() && p!="." && p!="..")) };
            if !valid { return Err(format!("bad value for {}",p.value)); }
        }
        let mut pieces=Vec::new();
        for p in &route.pieces { if p.kind=='l' { pieces.push(p.value.clone()); } else { let v=params.get(p.value.as_str()).copied().unwrap_or(""); if p.kind=='w' { if !v.is_empty() { pieces.extend(v.split('/').map(encode)); } } else { pieces.push(encode(v)); } } }
        let mut url=format!("/{}",pieces.join("/")); let queries:Vec<_>=args.into_iter().filter(|(n,_)|!names.contains(n)).map(|(n,v)|format!("{}={}",encode(n),encode(v))).collect();
        if !queries.is_empty() { url.push('?'); url+=&queries.join("&"); }
        Ok(format!("URLFOR {} {url}",route.name))
    }
}
fn negotiate(types:&[String],accept:&str) -> Option<String> {
    let mut elements=Vec::new();
    for element in accept.split(',') {
        let parts:Vec<_>=element.split(';').map(|s|s.trim_matches(' ')).collect(); let range=parts[0].to_ascii_lowercase();
        let specificity=if range=="*/*" { 1 } else if range.strip_suffix("/*").is_some_and(media_part) { 2 } else if media(&range) { 3 } else { continue; };
        let q=parts[1..].iter().find_map(|p|p.split_once('=').filter(|(n,_)|n.trim_matches(' ').eq_ignore_ascii_case("q")).map(|(_,v)|v.trim_matches(' ')));
        let weight=if let Some(q)=q {
            let (whole,fraction)=q.split_once('.').map_or((q,None),|(w,f)|(w,Some(f)));
            if !["0","1"].contains(&whole) || fraction.is_some_and(|f|f.len()>3 || !f.bytes().all(|c|c.is_ascii_digit()) || (whole=="1" && f.bytes().any(|c|c!=b'0'))) { continue; }
            if whole=="1" { 1000 } else { fraction.map_or(0,|f|format!("{f:0<3}").parse::<i32>().unwrap()) }
        } else { 1000 };
        elements.push((range,specificity,weight));
    }
    let mut best=0; let mut selected=None;
    for t in types {
        let mut specificity=0; let mut weight=0;
        for (range,s,w) in &elements { if *s>specificity && (range=="*/*" || range==t || range.strip_suffix("/*").is_some_and(|main|t.split_once('/').unwrap().0==main)) { specificity=*s; weight=*w; } }
        if weight>best { best=weight; selected=Some(t.clone()); }
    }
    selected
}
fn json(s:&str) -> String { format!("\"{}\"",s.replace('\\',"\\\\").replace('"',"\\\"")) }
fn html(s:&str) -> String { s.chars().map(|c|match c { '&'=>"&amp;".into(),'<'=>"&lt;".into(),'>'=>"&gt;".into(),'"'=>"&quot;".into(),_=>c.to_string() }).collect() }
fn body(route:&str,t:&str,params:&[(String,String)],query:&[(String,String)],cookies:&[(String,String)]) -> String {
    if t=="application/json" {
        let object=|pairs:&[(String,String)]| pairs.iter().map(|(a,b)|format!("{}:{}",json(a),json(b))).collect::<Vec<_>>().join(",");
        format!("{{\"route\":{},\"params\":{{{}}},\"query\":[{}],\"cookies\":{{{}}}}}",json(route),object(params),query.iter().map(|(a,b)|format!("[{},{}]",json(a),json(b))).collect::<Vec<_>>().join(","),object(cookies))
    } else if t=="text/html" {
        let mut text=format!("<dl><dt>route</dt><dd>{}</dd>",html(route));
        for (kind,list) in [("param",params),("query",query),("cookie",cookies)] { for (a,b) in list { text+=&format!("<dt>{kind} {}</dt><dd>{}</dd>",html(a),html(b)); } } text+"</dl>"
    } else {
        let list=|pairs:&[(String,String)]|if pairs.is_empty() { "-".into() } else { pairs.iter().map(|(a,b)|format!("{}={}",encode(a),encode(b))).collect::<Vec<_>>().join("&") };
        format!("route={route} params={} query={} cookies={}",list(params),list(query),list(cookies))
    }
}
fn etag(body:&str) -> String { let mut a=1u32; let mut b=0u32; for c in body.bytes() { a=(a+c as u32)%65521; b=(b+a)%65521; } format!("\"{b:04x}{a:04x}\"") }
fn reason(status:u16) -> &'static str { match status { 200=>"OK",204=>"No Content",301=>"Moved Permanently",302=>"Found",304=>"Not Modified",307=>"Temporary Redirect",308=>"Permanent Redirect",400=>"Bad Request",401=>"Unauthorized",403=>"Forbidden",404=>"Not Found",405=>"Method Not Allowed",406=>"Not Acceptable",412=>"Precondition Failed",429=>"Too Many Requests",_=>"Not Implemented" } }
fn output(number:usize,mut r:Response) {
    println!("REQUEST {number}\nHTTP/1.1 {} {}",r.status,reason(r.status));
    if r.status!=204 && r.status!=304 { r.headers.insert("Content-Type".into(),r.content_type); r.headers.insert("Content-Length".into(),r.body.len().to_string()); }
    for name in ["Location","Allow","Retry-After","WWW-Authenticate","Access-Control-Allow-Origin","Access-Control-Allow-Methods","Vary","ETag","Content-Type","Content-Length"] { if let Some(value)=r.headers.get(name) { println!("{name}: {value}"); } }
    if r.status!=204 && r.status!=304 && !r.head { println!("{}",r.body); }
}
fn main() {
    let mut input=String::new(); io::stdin().read_to_string(&mut input).unwrap(); let lines:Vec<_>=input.lines().collect(); let mut at=0; let mut router=Router::new();
    while lines[at]!="REQUESTS" { if let Err(error)=router.config(&lines[at].split(' ').collect::<Vec<_>>()) { router.config_errors+=1; println!("CONFIG ERROR {}: {error}",at+1); } at+=1; }
    at+=1; router.table(); let mut requests=0; let mut url_ok=0; let mut url_error=0;
    while lines[at]!="END" {
        let line=lines[at]; at+=1;
        if line.starts_with("URLFOR ") { match router.urlfor(&line.split(' ').collect::<Vec<_>>()) { Ok(text)=>{ url_ok+=1; println!("{text}"); },Err(error)=>{ url_error+=1; println!("URLFOR ERROR {error}"); } } }
        else { requests+=1; let mut headers=Vec::new(); while !lines[at].is_empty() { headers.push(lines[at]); at+=1; } at+=1; let response=router.request(line,&headers); *router.statuses.entry(response.status).or_default()+=1; output(requests,response); }
    }
    println!("SUMMARY requests={requests} urlfor_ok={url_ok} urlfor_error={url_error}");
    for (status,count) in router.statuses { println!("STATUS {status} {count}"); }
    for route in router.routes { println!("ROUTE {} {}",route.name,route.count); }
    for (name,c) in router.clients { println!("CLIENT {name} allowed={} limited={}",c.allowed,c.limited); }
}
