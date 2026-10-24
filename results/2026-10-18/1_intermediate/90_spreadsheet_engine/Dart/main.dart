import 'dart:io';

class Expr {
  final String kind, text;
  final int n, row, flags;
  final Expr? a, b;
  final List<Expr> args;
  const Expr(this.kind, [this.n=0, this.row=0, this.flags=0, this.text='', this.a, this.b, this.args=const []]);
}
Expr num(int n)=>Expr('N',n);
Expr text(String s)=>Expr('S',0,0,0,s);
Expr error(String s)=>Expr('E',0,0,0,s);
Expr ref(int c,int r,[int f=0])=>Expr('R',c,r,f);
const invalid=Expr('X');
int id(Expr r)=>r.row*26+r.n;
String label(int i)=>String.fromCharCode(65+i%26)+(i~/26+1).toString();
bool inside(Expr r)=>r.n>=0&&r.n<26&&r.row>=0&&r.row<99;
Never fail(String s)=>throw FormatException(s);
Expr range(Expr a,Expr b){
  int c=a.n,d=b.n,r=a.row,t=b.row,ac=a.flags&1,bc=b.flags&1,ar=a.flags&2,br=b.flags&2;
  if(c>d){int z=c;c=d;d=z;z=ac;ac=bc;bc=z;}if(r>t){int z=r;r=t;t=z;z=ar;ar=br;br=z;}
  return Expr('G',0,0,0,'',ref(c,r,ac|ar),ref(d,t,bc|br));
}
Expr address(String s){if(!RegExp(r'^[A-Z][1-9][0-9]?$').hasMatch(s))fail('bad address');return ref(s.codeUnitAt(0)-65,int.parse(s.substring(1))-1);}
Expr area(String s){final p=s.split(':');if(p.length>2)fail('bad address');final a=address(p[0]),b=p.length==1?a:address(p[1]);return range(a,b);}
List<int> cells(Expr g)=>[for(int r=g.a!.row;r<=g.b!.row;r++)for(int c=g.a!.n;c<=g.b!.n;c++)r*26+c];
bool contains(Expr g,Expr r)=>r.n>=g.a!.n&&r.n<=g.b!.n&&r.row>=g.a!.row&&r.row<=g.b!.row;
const levels=[['=','<>','<','<=','>','>='],['&'],['+','-'],['*','/']];
int precedence(String s)=>levels.indexWhere((xs)=>xs.contains(s));
class Token{final Expr value;final int position;Token(this.value,this.position);}
class Parser{
  final List<Token> tokens=[];int at=0;
  Never syntax(int p)=>fail('syntax error at $p');
  Parser(String s){
    int i=1;while(i<s.length){final p=i+1,ch=s[i];if(ch==' '){i++;continue;}late Expr x;
      if(RegExp(r'[0-9]').hasMatch(ch)){int j=i;while(j<s.length&&RegExp(r'[0-9]').hasMatch(s[j]))j++;if(j-i>=10)syntax(p);x=num(int.parse(s.substring(i,j)));i=j;}
      else if(ch=='"'){final j=s.indexOf('"',i+1);if(j<0)syntax(p);x=text(s.substring(i+1,j));i=j+1;}
      else if(RegExp(r'[A-Za-z$]').hasMatch(ch)){
        int j=i;while(j<s.length&&RegExp(r'[A-Za-z0-9$]').hasMatch(s[j]))j++;final w=s.substring(i,j).toUpperCase();i=j;
        final m=RegExp(r'^(\$?)([A-Z])(\$?)([1-9][0-9]?)$').firstMatch(w);
        if(m!=null)x=ref(m[2]!.codeUnitAt(0)-65,int.parse(m[4]!)-1,(m[1]!.isEmpty?0:1)|(m[3]!.isEmpty?0:2));
        else if(RegExp(r'^[A-Z][A-Z0-9]*$').hasMatch(w))x=Expr(s.substring(j).trimLeft().startsWith('(')?'C':'W',0,0,0,w);
        else syntax(p);
      }else{
        String op=s.substring(i,i+2>s.length?s.length:i+2);if(!['<>','<=','>='].contains(op))op=ch;
        if(!'+-*/&(),:=<>'.contains(ch))syntax(p);x=Expr('T',0,0,0,op);i+=op.length;
      }tokens.add(Token(x,p));
    }tokens.add(Token(const Expr('Z'),s.length+1));
  }
  bool take(String op){final x=tokens[at].value;if(x.kind=='T'&&x.text==op){at++;return true;}return false;}
  void expect(String op){if(!take(op))syntax(tokens[at].position);}
  Expr expression([int level=0]){
    if(level==4)return primary();Expr a=expression(level+1);
    while(tokens[at].value.kind=='T'&&levels[level].contains(tokens[at].value.text)){final op=tokens[at++].value.text;a=Expr('B',0,0,0,op,a,expression(level+1));}return a;
  }
  Expr primary(){
    if(take('-'))return Expr('U',0,0,0,'',primary());final t=tokens[at++],x=t.value;
    if(['N','S','W'].contains(x.kind))return x;
    if(x.kind=='R'){if(!take(':'))return x;if(tokens[at].value.kind!='R')syntax(tokens[at].position);return range(x,tokens[at++].value);}
    if(x.kind=='C'){expect('(');final args=<Expr>[];if(!take(')')){args.add(expression());while(take(','))args.add(expression());expect(')');}return Expr('F',0,0,0,x.text,null,null,args);}
    if(x.kind=='T'&&x.text=='('){final a=expression();expect(')');return a;}syntax(t.position);
  }
  Expr parse(){final x=expression();if(tokens[at].value.kind!='Z')syntax(tokens[at].position);return x;}
}
String canonical(Expr x){
  switch(x.kind){
    case 'N':return x.n.toString();case 'S':return '"${x.text}"';case 'W':return x.text;case 'X':return '#REF!';
    case 'R':return (x.flags&1!=0?r'$':'')+String.fromCharCode(65+x.n)+(x.flags&2!=0?r'$':'')+(x.row+1).toString();
    case 'G':return '${canonical(x.a!)}:${canonical(x.b!)}';
    case 'F':return '${x.text}(${x.args.map(canonical).join(',')})';
    case 'U':return '-'+(x.a!.kind=='B'?'(${canonical(x.a!)})':canonical(x.a!));
    default:
      String a=canonical(x.a!),b=canonical(x.b!);
      if(x.a!.kind=='B'&&precedence(x.a!.text)<precedence(x.text))a='($a)';
      if(x.b!.kind=='B'&&precedence(x.b!.text)<=precedence(x.text))b='($b)';return a+x.text+b;
  }
}
String display(Expr? x)=>x==null?'':x.kind=='N'?x.n.toString():x.text;
String notation(Expr? x)=>x==null?'(empty)':x.kind=='='?'=${canonical(x.a!)}':x.kind=='S'?'"${x.text}"':display(x);
Expr number(Expr? x)=>x==null?num(0):['S','G'].contains(x.kind)?error('#VALUE!'):x;
Expr string(Expr? x)=>x==null?text(''):x.kind=='N'?text(x.n.toString()):x.kind=='G'?error('#VALUE!'):x;
Expr? rewrite(Expr? x,Expr Function(Expr) f){
  if(x==null)return null;if(x.kind=='R'||x.kind=='G')return f(x);
  final a=rewrite(x.a,f),b=rewrite(x.b,f),args=x.args.map((v)=>rewrite(v,f)!).toList();
  return Expr(x.kind,x.n,x.row,x.flags,x.text,a,b,args);
}
Set<int> dependencies(Expr? x,[Set<int>? output]){
  final out=output??<int>{};if(x==null)return out;
  if(x.kind=='R')out.add(id(x));else if(x.kind=='G')out.addAll(cells(x));
  else{dependencies(x.a,out);dependencies(x.b,out);for(final a in x.args)dependencies(a,out);}return out;
}
class Sheet{
  List<Expr?> contents=List.filled(2574,null),values=List.filled(2574,null);
  List<Set<int>> deps=List.generate(2574,(_)=><int>{});final history=<(String,List<Expr?>)>[];
  Expr? evaluate(Expr x){
    if(['N','S','G'].contains(x.kind))return x;if(x.kind=='R')return values[id(x)];if(x.kind=='W')return error('#NAME?');if(x.kind=='X')return error('#REF!');
    if(x.kind=='U'){final a=number(evaluate(x.a!));return a.kind=='E'?a:num(-a.n);}
    if(x.kind=='B'){
      Expr? a=evaluate(x.a!),b=evaluate(x.b!);if(a?.kind=='E')return a;if(b?.kind=='E')return b;final op=x.text;
      if(precedence(op)==0){
        if(a?.kind=='G'||b?.kind=='G')return error('#VALUE!');final blank=a?.kind=='S'||b?.kind=='S'?text(''):num(0);a??=blank;b??=blank;
        final c=a.kind!=b.kind?(a.kind=='N'?-1:1):a.kind=='N'?a.n.compareTo(b.n):a.text.compareTo(b.text);
        return num((op=='='?c==0:op=='<>'?c!=0:op=='<'?c<0:op=='<='?c<=0:op=='>'?c>0:c>=0)?1:0);
      }
      final u=op=='&'?string(a):number(a),v=op=='&'?string(b):number(b);if(u.kind=='E')return u;if(v.kind=='E')return v;
      switch(op){case '&':return text(u.text+v.text);case '+':return num(u.n+v.n);case '-':return num(u.n-v.n);case '*':return num(u.n*v.n);default:return v.n==0?error('#DIV/0!'):num(u.n~/v.n);}
    }
    final name=x.text,args=x.args;
    if(['SUM','MIN','MAX','COUNT','AVERAGE','AND','OR','CONCAT'].contains(name)){
      if(args.isEmpty)return error('#VALUE!');final items=<Expr?>[];
      for(final a in args){final v=evaluate(a);if(v?.kind=='G')items.addAll(cells(v!).map((i)=>values[i]));else items.add(v);}
      final ns=[for(final a in items)if(a?.kind=='N')a!.n];if(name=='COUNT')return num(ns.length);for(final a in items)if(a?.kind=='E')return a;
      if(name=='CONCAT')return text(items.map((a)=>string(a).text).join());int sum=0;for(final n in ns)sum+=n;
      if(name=='SUM')return num(sum);if(name=='MIN')return num(ns.isEmpty?0:ns.reduce((a,b)=>a<b?a:b));if(name=='MAX')return num(ns.isEmpty?0:ns.reduce((a,b)=>a>b?a:b));
      if(ns.isEmpty)return error(name=='AVERAGE'?'#DIV/0!':'#VALUE!');if(name=='AVERAGE')return num(sum~/ns.length);return num((name=='AND'?ns.every((n)=>n!=0):ns.any((n)=>n!=0))?1:0);
    }
    if(name=='IF'){if(args.length!=2&&args.length!=3)return error('#VALUE!');final c=number(evaluate(args[0]));if(c.kind=='E')return c;return c.n!=0?evaluate(args[1]):args.length==3?evaluate(args[2]):num(0);}
    if(!['ABS','NOT','LEN'].contains(name))return error('#NAME?');if(args.length!=1)return error('#VALUE!');final v=name=='LEN'?string(evaluate(args[0])):number(evaluate(args[0]));return v.kind=='E'?v:num(name=='LEN'?v.text.length:name=='ABS'?v.n.abs():v.n==0?1:0);
  }
  void recalculate(){
    deps=contents.map((x)=>x?.kind=='='?dependencies(x!.a):<int>{}).toList();values=contents.map((x)=>x?.kind=='='?null:x).toList();
    final indices=List.filled(2574,-1),low=List.filled(2574,0),on=<int>{},cyclic=<int>{},stack=<int>[];int serial=0;
    void visit(int i){
      indices[i]=low[i]=serial++;stack.add(i);on.add(i);
      for(final j in deps[i])if(contents[j]?.kind=='='){if(indices[j]<0){visit(j);if(low[j]<low[i])low[i]=low[j];}else if(on.contains(j)&&indices[j]<low[i])low[i]=indices[j];}
      if(low[i]==indices[i]){final part=<int>[];int j;do{j=stack.removeLast();on.remove(j);part.add(j);}while(j!=i);if(part.length>1||deps[i].contains(i))cyclic.addAll(part);}
    }
    for(int i=0;i<2574;i++)if(contents[i]?.kind=='='&&indices[i]<0)visit(i);
    final done=<int>{};void calculate(int i){
      if(contents[i]?.kind!='='||done.contains(i))return;done.add(i);if(cyclic.contains(i)){values[i]=error('#CYCLE!');return;}
      for(final j in deps[i])calculate(j);final v=evaluate(contents[i]!.a!);values[i]=v==null?num(0):v.kind=='G'?error('#VALUE!'):v;
    }
    for(int i=0;i<2574;i++)calculate(i);
  }
  int replace(List<Expr?> next){final old=values;contents=next;recalculate();int changed=0;for(int i=0;i<2574;i++)if(notation(old[i])!=notation(values[i]))changed++;return changed;}
  String describe(int i)=>'${label(i)}: ${notation(contents[i])} -> ${notation(values[i])}';
  String formatted(Iterable<int> xs){final ids=xs.toList()..sort();return ids.isEmpty?'none':ids.map(label).join(',');}
  List<String> execute(String line){
    final p=line.indexOf(' '),name=p<0?line:line.substring(0,p),rest=p<0?'':line.substring(p+1);
    if(name=='SHOW')return [describe(id(address(rest)))];if(name=='LIST'){final out=[for(int i=0;i<2574;i++)if(contents[i]!=null)describe(i)];return out.isEmpty?['(no cells)']:out;}
    if(name=='DEPS'){final i=id(address(rest));return ['$rest: precedents=${formatted(deps[i])} dependents=${formatted([for(int j=0;j<2574;j++)if(deps[j].contains(i))j])}'];}
    if(name=='PRINT'){
      final g=area(rest),rw=(g.b!.row+1).toString().length,ws=<int>[];String sep='+${'-'*rw}+',head='|${' '*rw}|';
      for(int c=g.a!.n;c<=g.b!.n;c++){int w=1;for(int r=g.a!.row;r<=g.b!.row;r++){final n=display(values[r*26+c]).length;if(n>w)w=n;}ws.add(w);sep+='${'-'*w}+';head+='${String.fromCharCode(65+c).padRight(w)}|';}
      final out=[sep,head,sep];for(int r=g.a!.row;r<=g.b!.row;r++){String s='|${(r+1).toString().padLeft(rw)}|';for(int j=0;j<ws.length;j++){final v=values[r*26+g.a!.n+j];s+=(v?.kind=='N'?display(v).padLeft(ws[j]):display(v).padRight(ws[j]))+'|';}out.add(s);}out.add(sep);return out;
    }
    if(name=='UNDO'){if(history.isEmpty)fail('nothing to undo');final e=history.removeLast();return ['UNDO ${e.$1} changed=${replace(e.$2)}'];}
    List<Expr?> next=List.of(contents);int target=-1;
    if(name=='SET'){
      final p=rest.indexOf(' '),a=rest.substring(0,p),s=rest.substring(p+1);target=id(address(a));
      if(s.startsWith('='))next[target]=Expr('=',0,0,0,'',Parser(s).parse());else if(RegExp(r'^"[^"]*"$').hasMatch(s))next[target]=text(s.substring(1,s.length-1));else if(RegExp(r'^(0|-?[1-9][0-9]{0,8})$').hasMatch(s))next[target]=num(int.parse(s));else fail('bad value');
    }else if(name=='CLEAR'){for(final i in cells(area(rest)))next[i]=null;}
    else if(name=='COPY'||name=='MOVE'){
      final p=rest.indexOf(' '),source=area(rest.substring(0,p)),dest=address(rest.substring(p+1)),dc=dest.n-source.a!.n,dr=dest.row-source.a!.row;
      Expr shift(Expr r,bool relative)=>ref(r.n+(relative&&r.flags&1!=0?0:dc),r.row+(relative&&r.flags&2!=0?0:dr),r.flags);
      final destination=range(shift(source.a!,false),shift(source.b!,false));if(!inside(destination.a!)||!inside(destination.b!))fail('out of grid');
      Expr transform(Expr x){
        if(x.kind=='R'){if(name=='COPY'){final a=shift(x,true);return inside(a)?a:invalid;}return contains(source,x)?shift(x,false):contains(destination,x)?invalid:x;}
        if(name=='MOVE'&&!(contains(source,x.a!)&&contains(source,x.b!)))return x;final a=shift(x.a!,name=='COPY'),b=shift(x.b!,name=='COPY');return inside(a)&&inside(b)?range(a,b):invalid;
      }
      if(name=='MOVE')next=next.map((x)=>rewrite(x,transform)).toList();final ids=cells(source),moving=[for(final i in cells(source))name=='COPY'?rewrite(contents[i],transform):next[i]];if(name=='MOVE')for(final i in ids)next[i]=null;for(int j=0;j<ids.length;j++)next[ids[j]+dr*26+dc]=moving[j];
    }else if(['INSERTROW','DELETEROW','INSERTCOL','DELETECOL'].contains(name)){
      final row=name.endsWith('ROW'),insert=name.startsWith('INSERT');if(!(row?RegExp(r'^[1-9][0-9]?$'):RegExp(r'^[A-Z]$')).hasMatch(rest))fail('bad address');final at=row?int.parse(rest)-1:rest.codeUnitAt(0)-65,limit=row?99:26;
      int axis(Expr x)=>row?x.row:x.n;Expr change(Expr x,int v)=>ref(row?x.n:v,row?v:x.row,x.flags);
      if(insert)for(int i=0;i<2574;i++)if(contents[i]!=null&&(row?i~/26:i%26)==limit-1)fail('last ${row?'row':'column'} not empty');
      Expr transform(Expr x){
        if(x.kind=='R'){final v=axis(x);if(!insert&&v==at)return invalid;final n=v+(insert?(v>=at?1:0):(v>at?-1:0));return n>=limit?invalid:change(x,n);}
        final a=axis(x.a!),b=axis(x.b!);if(!insert&&a==at&&b==at)return invalid;final u=a+(insert?(a>=at?1:0):(a>at?-1:0)),v=b+(insert?(b>=at?1:0):(b>=at?-1:0));return v>=limit?invalid:range(change(x.a!,u),change(x.b!,v));
      }
      next=List.filled(2574,null);for(int i=0;i<2574;i++)if(contents[i]!=null){final r=ref(i%26,i~/26),v=axis(r);if(!insert&&v==at)continue;final t=change(r,v+(insert?(v>=at?1:0):(v>at?-1:0)));next[id(t)]=rewrite(contents[i],transform);}
    }else fail('unknown command');
    history.add((name,contents));final changed=replace(next);return [name+(name=='SET'?' ${label(target)}=${notation(values[target])}':'')+' changed=$changed'];
  }
}
void main(){final n=int.parse(stdin.readLineSync()!),sheet=Sheet();for(int i=0;i<n;i++){final line=stdin.readLineSync()!;try{for(final s in sheet.execute(line))stdout.writeln(s);}on FormatException catch(e){stdout.writeln('ERROR ${e.message}');}}}
