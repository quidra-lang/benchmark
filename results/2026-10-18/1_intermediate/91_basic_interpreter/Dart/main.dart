import 'dart:io';
import 'dart:math' as math;

class SyntaxFault implements Exception {}
class BasicFault implements Exception {
  final String reason;
  BasicFault(this.reason);
}

const signatures=<String,List<String>>{
  'ABS':['I'],'SGN':['I'],'INT':['I'],'SQR':['I'],'RND':['I'],
  'LEN':['S'],'ASC':['S'],'VAL':['S'],'CHR$':['I'],'STR$':['I'],
  'LEFT$':['SI'],'RIGHT$':['SI'],'MID$':['SI','SII'],'INSTR':['SS']
};

const errorCodes=<String,int>{
  'NEXT WITHOUT FOR':1,'RETURN WITHOUT GOSUB':3,'OUT OF DATA':4,
  'ILLEGAL FUNCTION CALL':5,'OVERFLOW':6,'OUT OF MEMORY':7,
  'UNDEFINED LINE NUMBER':8,'SUBSCRIPT OUT OF RANGE':9,
  'DUPLICATE DEFINITION':10,'DIVISION BY ZERO':11,'TYPE MISMATCH':13,
  'STRING TOO LONG':15,'RESUME WITHOUT ERROR':20,'FOR WITHOUT NEXT':26,
  'WHILE WITHOUT WEND':29,'WEND WITHOUT WHILE':30,'INPUT PAST END':62
};

const operators=<List<String>>[
  ['OR'],['AND'],[],['=','<>','<','>','<=','>='],
  ['+','-'],['*','/','MOD'],[],['^']
];

Never syntax()=>throw SyntaxFault();
Never fault(String reason)=>throw BasicFault(reason);
bool variableName(String name)=>RegExp(r'^[A-Z][0-9]?\$?$').hasMatch(name);
String nameType(String name)=>name.endsWith('\$')?'S':'I';
String valueType(Object value)=>value is String?'S':'I';
bool digit(String s)=>s.isNotEmpty&&s.codeUnitAt(0)>=48&&s.codeUnitAt(0)<=57;
bool upper(String s)=>s.isNotEmpty&&s.codeUnitAt(0)>=65&&s.codeUnitAt(0)<=90;

class Token {
  final String kind,text;
  final Object value;
  const Token(this.kind,this.text,this.value);
}
class Expr {
  String kind;
  final String type;
  final Object value;
  final List<Expr> args;
  Expr(this.kind,this.type,this.value,[List<Expr>? args]):args=args??[];
}
class PrintItem {
  final String kind;
  final Expr? expr;
  const PrintItem(this.kind,this.expr);
}
class Clause {
  final int? line;
  final List<Statement> body;
  const Clause(this.line,this.body);
}
class Statement {
  String kind;
  int line=0;
  Statement? next;
  Expr? expr,target;
  final targets=<Expr>[],expressions=<Expr>[];
  final values=<Object>[];
  final numbers=<int>[];
  String name='',mode='';
  final clauses=<Clause>[];
  final items=<PrintItem>[];
  Statement(this.kind);
}

List<Token> tokenize(String text){
  final tokens=<Token>[];
  var p=0;
  while(p<text.length){
    final ch=text[p];
    if(ch==' '){p++;continue;}
    if(ch=='"'){
      final end=text.indexOf('"',p+1);
      if(end<0)syntax();
      tokens.add(Token('S',text.substring(p,end+1),text.substring(p+1,end)));
      p=end+1;
    }else if(digit(ch)){
      final start=p;
      while(p<text.length&&digit(text[p]))p++;
      final word=text.substring(start,p),value=int.tryParse(word);
      if(value==null||value>32767)syntax();
      tokens.add(Token('I',word,value));
    }else if(upper(ch)){
      if(text.startsWith('REM',p)){
        tokens.add(const Token('W','REM','REM'));
        break;
      }
      final start=p;
      while(p<text.length&&(upper(text[p])||digit(text[p])))p++;
      if(p<text.length&&text[p]=='\$')p++;
      final word=text.substring(start,p);
      tokens.add(Token('W',word,word));
    }else{
      if(!'+-*/^=<>() ,;:'.contains(ch))syntax();
      final pair=text.substring(p,math.min(p+2,text.length));
      final word=['<>','<=','>='].contains(pair)?pair:ch;
      tokens.add(Token('P',word,word));
      p+=word.length;
    }
  }
  tokens.add(const Token('E','',''));
  return tokens;
}

class Parser {
  final List<Token> tokens;
  int pos=0;
  Parser(this.tokens);
  Token get current=>tokens[pos];
  bool at(String s)=>(current.kind=='P'||current.kind=='W')&&current.text==s;
  bool take(String s){if(!at(s))return false;pos++;return true;}
  void expect(String s){if(!take(s))syntax();}
  int number(){if(current.kind!='I')syntax();return tokens[pos++].value as int;}
  Expr integer([int level=0]){
    final e=expression(level);
    if(e.type!='I')syntax();
    return e;
  }
  Expr target(){
    final token=current;
    if(token.kind!='W'||!variableName(token.text))syntax();
    pos++;
    final result=Expr('variable',nameType(token.text),token.text);
    if(take('(')){
      result.kind='array';
      result.args.add(integer());
      if(take(','))result.args.add(integer());
      expect(')');
    }
    return result;
  }
  Expr primary(){
    final token=current;
    if(token.kind=='I'||token.kind=='S'){
      pos++;
      return Expr('constant',token.kind,token.value);
    }
    if(take('(')){final e=expression();expect(')');return e;}
    if(token.kind=='W'&&variableName(token.text))return target();
    if(take('ERR'))return Expr('builtin','I','ERR');
    if(take('ERL'))return Expr('builtin','I','ERL');
    if(token.kind=='W'&&signatures.containsKey(token.text)){
      pos++;expect('(');
      final args=<Expr>[expression()];
      while(take(','))args.add(expression());
      expect(')');
      if(!signatures[token.text]!.contains(args.map((e)=>e.type).join()))syntax();
      return Expr('call',nameType(token.text),token.text,args);
    }
    syntax();
  }
  Expr expression([int level=0]){
    if(level==2&&take('NOT'))return Expr('unary','I','NOT',[integer(2)]);
    if(level==6&&take('-'))return Expr('unary','I','-',[integer(6)]);
    if(level==8)return primary();
    var left=expression(level+1);
    while(operators[level].contains(current.text)){
      final op=current.text;pos++;
      final right=expression(level==7?6:level+1);
      if(left.type!=right.type||(left.type=='S'&&level!=3&&op!='+'))syntax();
      left=Expr('binary',level==3?'I':left.type,op,[left,right]);
      if(level==7)break;
    }
    return left;
  }
  Clause clause()=>current.kind=='I'?Clause(number(),[]):Clause(null,listing(true));
  List<Statement> listing([bool inside=false]){
    final body=<Statement>[statement(inside)];
    while(take(':'))body.add(statement(inside));
    return body;
  }
  Statement statement(bool inside){
    final word=current.text;
    if(inside&&['IF','FOR','NEXT','WHILE','WEND','DATA'].contains(word))syntax();
    final s=Statement(word);
    for(final kind in ['REM','RETURN','WEND','END','STOP']){
      if(take(kind))return s;
    }
    if(take('PRINT')){
      var expressionLast=false;
      while(current.kind!='E'&&!at(':')&&!at('ELSE')){
        if(take(';')){
          s.items.add(const PrintItem(';',null));expressionLast=false;
        }else if(take(',')){
          s.items.add(const PrintItem(',',null));expressionLast=false;
        }else{
          final kind=at('TAB')?'TAB':at('SPC')?'SPC':'value';
          if(kind=='value'&&expressionLast)syntax();
          late Expr e;
          if(kind=='value'){e=expression();}
          else{pos++;expect('(');e=integer();expect(')');}
          s.items.add(PrintItem(kind,e));expressionLast=kind=='value';
        }
      }
      return s;
    }
    if(take('INPUT')||take('READ')||take('DIM')){
      do{
        final t=target();
        if(word=='DIM'&&t.kind!='array')syntax();
        s.targets.add(t);
      }while(take(','));
      return s;
    }
    if(take('DATA')){
      do{
        final negative=take('-');
        final t=current;
        if(t.kind!='I'&&(t.kind!='S'||negative))syntax();
        pos++;s.values.add(negative?-(t.value as int):t.value);
      }while(take(','));
      return s;
    }
    if(take('IF')){
      s.expr=integer();expect('THEN');s.clauses.add(clause());
      if(take('ELSE'))s.clauses.add(clause());
      if(current.kind!='E')syntax();
      return s;
    }
    if(take('GOTO')||take('GOSUB')){s.numbers.add(number());return s;}
    if(take('ON')){
      if(take('ERROR')){
        s.kind='handler';expect('GOTO');s.numbers.add(number());
      }else{
        s.expr=integer();
        if(take('GOTO'))s.mode='GOTO';
        else{expect('GOSUB');s.mode='GOSUB';}
        s.numbers.add(number());
        while(take(','))s.numbers.add(number());
      }
      return s;
    }
    if(take('RESUME')){
      if(take('NEXT'))s.mode='NEXT';
      else if(current.kind=='I'){s.mode='line';s.numbers.add(number());}
      return s;
    }
    if(take('FOR')){
      final t=current;
      if(t.kind!='W'||!variableName(t.text)||nameType(t.text)!='I')syntax();
      s.name=t.text;pos++;expect('=');
      s.expressions.add(integer());expect('TO');s.expressions.add(integer());
      s.expressions.add(take('STEP')?integer():Expr('constant','I',1));
      return s;
    }
    if(take('NEXT')){
      final t=current;
      if(t.kind=='W'&&variableName(t.text)&&nameType(t.text)=='I'){
        s.name=t.text;pos++;
      }
      return s;
    }
    if(take('WHILE')||take('RANDOMIZE')){s.expr=integer();return s;}
    if(take('RESTORE')){
      if(current.kind=='I')s.numbers.add(number());
      return s;
    }
    take('LET');s.kind='assign';s.target=target();expect('=');s.expr=expression();
    if(s.expr!.type!=s.target!.type)syntax();
    return s;
  }
  List<Statement> parse(){
    final result=listing();
    if(current.kind!='E')syntax();
    return result;
  }
}

class BasicArray {
  final List<int> bounds;
  final List<Object> values;
  BasicArray(this.bounds,this.values);
}
class Address {
  final String name;
  final int? index;
  Address(this.name,this.index);
}
class Frame {
  final String kind;
  final Statement? position;
  final String name;
  final int limit,step;
  Frame(this.kind,this.position,[this.name='',this.limit=0,this.step=0]);
}
class Entry {
  final int line;
  final Object value;
  Entry(this.line,this.value);
}
class ProgramLine {
  final int number;
  final List<Statement> body;
  ProgramLine(this.number,this.body);
}

class Machine {
  final List<String> inputs;
  final variables=<String,Object>{};
  final arrays=<String,BasicArray>{};
  final stack=<Frame>[];
  final entries=<int,Statement>{};
  final sequence=<Statement>[];
  final data=<Entry>[];
  int dataPos=0,inputPos=0,random=1,handler=0,err=0,erl=0;
  bool handling=false;
  Statement? remembered;
  String buffer='';
  final output=<String>[];
  Machine(this.inputs);

  void endLine(){output.add(buffer.replaceFirst(RegExp(r' +$'),''));buffer='';}
  void message(String s){if(buffer.isNotEmpty)endLine();output.add(s);}
  int checked(num n){if(n< -32768||n>32767)fault('OVERFLOW');return n.toInt();}
  Object valueOf(String s)=>variables[s]??(nameType(s)=='S'?'':0);
  void declare(String name,List<int> bounds){
    var length=1;
    for(final b in bounds)length*=b+1;
    arrays[name]=BasicArray(bounds,List<Object>.filled(length,nameType(name)=='S'?'':0));
  }
  Address address(Expr target){
    final name=target.value as String;
    if(target.kind=='variable')return Address(name,null);
    final indices=target.args.map((e)=>evaluate(e) as int).toList();
    if(!arrays.containsKey(name))declare(name,List<int>.filled(indices.length,10));
    final arr=arrays[name]!;
    if(indices.length!=arr.bounds.length)fault('SUBSCRIPT OUT OF RANGE');
    var index=0;
    for(var i=0;i<indices.length;i++){
      final n=indices[i];
      if(n<0||n>arr.bounds[i])fault('SUBSCRIPT OUT OF RANGE');
      index=index*(arr.bounds[i]+1)+n;
    }
    return Address(name,index);
  }
  Object load(Address address)=>address.index==null?
    valueOf(address.name):arrays[address.name]!.values[address.index!];
  void store(Address a,Object value){
    if(a.index==null)variables[a.name]=value;
    else arrays[a.name]!.values[a.index!]=value;
  }
  Object evaluate(Expr e){
    final op=e.value;
    if(e.kind=='constant')return op;
    if(e.kind=='variable'||e.kind=='array')return load(address(e));
    if(e.kind=='builtin')return op=='ERR'?err:erl;
    if(e.kind=='unary'){
      final a=evaluate(e.args[0]) as int;
      return op=='NOT'?~a:checked(-a);
    }
    final args=e.args.map(evaluate).toList();
    if(e.kind=='call')return call(op as String,args);
    final a=args[0];
    final b=args[1];
    if(operators[3].contains(op)){
      final cmp=a is String?a.compareTo(b as String):
                    (a as int).compareTo(b as int);
      final success=switch(op){
        '='=>cmp==0,'<>'=>cmp!=0,'<'=>cmp<0,'>'=>cmp>0,
        '<='=>cmp<=0,'>='=>cmp>=0,_=>false
      };
      return success?-1:0;
    }
    if(e.type=='S'){
      final result=(a as String)+(b as String);
      if(result.length>255)fault('STRING TOO LONG');
      return result;
    }
    final x=a as int,y=b as int;
    switch(op){
      case '+':return checked(x+y);
      case '-':return checked(x-y);
      case '*':return checked(x*y);
      case '/':
        if(y==0)fault('DIVISION BY ZERO');
        return checked(x~/y);
      case 'MOD':
        if(y==0)fault('DIVISION BY ZERO');
        return x-y*(x~/y);
      case '^':
        if(y<0)fault('ILLEGAL FUNCTION CALL');
        if(x.abs()>1&&y>15)fault('OVERFLOW');
        var result=1;
        for(var i=0;i<y;i++)result=checked(result*x);
        return result;
      case 'AND':return x&y;
      case 'OR':return x|y;
    }
    fault('ILLEGAL FUNCTION CALL');
  }
  Object call(String name,List<Object> args){
    final a=args[0];
    final b=args.length>1?args[1]:null;
    final c=args.length>2?args[2]:null;
    switch(name){
      case 'ABS':return checked((a as int).abs());
      case 'SGN':
        final n=a as int;
        return n<0?-1:n>0?1:0;
      case 'INT':return a;
      case 'SQR':
        final n=a as int;
        if(n<0)fault('ILLEGAL FUNCTION CALL');
        return math.sqrt(n).floor();
      case 'RND':
        final n=a as int;
        if(n<1)fault('ILLEGAL FUNCTION CALL');
        random=(48271*random)%2147483647;
        return random%n+1;
      case 'LEN':return (a as String).length;
      case 'ASC':
        final s=a as String;
        if(s.isEmpty)fault('ILLEGAL FUNCTION CALL');
        return s.codeUnitAt(0);
      case 'VAL':
        final match=RegExp(r'^ *([+-]?[0-9]+)').firstMatch(a as String);
        return checked(match==null?0:(int.tryParse(match[1]!)??32768));
      case 'CHR$':
        final n=a as int;
        if(n<32||n>126)fault('ILLEGAL FUNCTION CALL');
        return String.fromCharCode(n);
      case 'STR$':return a.toString();
      case 'LEFT$':
        final s=a as String,n=b as int;
        if(n<0)fault('ILLEGAL FUNCTION CALL');
        return s.substring(0,math.min(n,s.length));
      case 'RIGHT$':
        final s=a as String,n=b as int;
        if(n<0)fault('ILLEGAL FUNCTION CALL');
        return s.substring(s.length-math.min(n,s.length));
      case 'MID$':
        final s=a as String,start=b as int,len=c as int?;
        if(start<1||(len!=null&&len<0))fault('ILLEGAL FUNCTION CALL');
        final from=math.min(start-1,s.length);
        return s.substring(from,len==null?s.length:math.min(from+len,s.length));
      case 'INSTR':return (a as String).indexOf(b as String)+1;
    }
    fault('ILLEGAL FUNCTION CALL');
  }
  Statement line(int n){
    final s=entries[n];
    if(s==null)fault('UNDEFINED LINE NUMBER');
    return s;
  }
  void push(Frame f){if(stack.length==100)fault('OUT OF MEMORY');stack.add(f);}
  int search(String kind,[String name='']){
    for(var i=stack.length-1;i>=0;i--){
      final f=stack[i];
      if(f.kind=='GOSUB')break;
      if(f.kind==kind&&(name.isEmpty||f.name==name))return i;
    }
    return -1;
  }
  Statement? matching(Statement s,String opening,String closing){
    final start=sequence.indexOf(s);
    var depth=0;
    for(var i=start+1;i<sequence.length;i++){
      final t=sequence[i];
      if(t.kind==opening)depth++;
      else if(t.kind==closing){
        if(depth==0)return t.next;
        depth--;
      }
    }
    fault(opening+' WITHOUT '+closing);
  }
  Statement subroutine(int number,Statement? after){
    final target=line(number);
    push(Frame('GOSUB',after));
    return target;
  }
  Statement? execute(Statement s){
    Statement? following=s.next;
    switch(s.kind){
      case 'assign':
        final place=address(s.target!);
        store(place,evaluate(s.expr!));
        break;
      case 'PRINT':
        for(final item in s.items){
          if(item.kind==','){
            buffer+=''.padRight(10-buffer.length%10);
          }else if(item.kind!=';'){
            final value=evaluate(item.expr!);
            if(item.kind=='value'){
              buffer+=value.toString();
            }else{
              final n=value as int;
              if(n<0)fault('ILLEGAL FUNCTION CALL');
              buffer+=''.padRight(item.kind=='SPC'?n:math.max(0,n-buffer.length));
            }
          }
        }
        if(s.items.isEmpty||![';',','].contains(s.items.last.kind))endLine();
        break;
      case 'INPUT':
      case 'READ':
        for(final target in s.targets){
          final place=address(target);
          late Object value;
          if(s.kind=='READ'){
            if(dataPos==data.length)fault('OUT OF DATA');
            value=data[dataPos++].value;
            if(valueType(value)!=target.type)fault('TYPE MISMATCH');
          }else{
            while(true){
              if(inputPos==inputs.length)fault('INPUT PAST END');
              final text=inputs[inputPos++];
              if(target.type=='S'){value=text;break;}
              final n=int.tryParse(text);
              if(RegExp(r'^-?[0-9]+$').hasMatch(text)&&
                 n!=null&&n>=-32768&&n<=32767){value=n;break;}
              message('?REDO FROM START');
            }
          }
          store(place,value);
        }
        break;
      case 'RESTORE':
        if(s.numbers.isEmpty)dataPos=0;
        else{
          final number=s.numbers[0];
          line(number);
          dataPos=data.indexWhere((entry)=>entry.line>=number);
          if(dataPos<0)dataPos=data.length;
        }
        break;
      case 'IF':
        final ix=(evaluate(s.expr!) as int)==0?1:0;
        if(ix<s.clauses.length){
          final selected=s.clauses[ix];
          following=selected.line==null?selected.body[0]:line(selected.line!);
        }
        break;
      case 'GOTO':following=line(s.numbers[0]);break;
      case 'GOSUB':following=subroutine(s.numbers[0],following);break;
      case 'ON':
        final n=evaluate(s.expr!) as int;
        if(n<0)fault('ILLEGAL FUNCTION CALL');
        if(n>=1&&n<=s.numbers.length){
          following=s.mode=='GOTO'?line(s.numbers[n-1]):
                    subroutine(s.numbers[n-1],following);
        }
        break;
      case 'RETURN':
        final ix=stack.lastIndexWhere((f)=>f.kind=='GOSUB');
        if(ix<0)fault('RETURN WITHOUT GOSUB');
        following=stack[ix].position;
        stack.removeRange(ix,stack.length);
        break;
      case 'FOR':
        final values=s.expressions.map((e)=>evaluate(e) as int).toList();
        final start=values[0],limit=values[1],step=values[2];
        if(step==0)fault('ILLEGAL FUNCTION CALL');
        final ix=search('FOR',s.name);
        if(ix>=0)stack.removeRange(ix,stack.length);
        variables[s.name]=start;
        if((step>0&&start>limit)||(step<0&&start<limit)){
          following=matching(s,'FOR','NEXT');
        }else push(Frame('FOR',following,s.name,limit,step));
        break;
      case 'NEXT':
        final ix=search('FOR',s.name);
        if(ix<0)fault('NEXT WITHOUT FOR');
        stack.removeRange(ix+1,stack.length);
        final frame=stack[ix];
        final value=checked((valueOf(frame.name) as int)+frame.step);
        variables[frame.name]=value;
        if((frame.step>0&&value>frame.limit)||
           (frame.step<0&&value<frame.limit))stack.removeLast();
        else following=frame.position;
        break;
      case 'WHILE':
        if((evaluate(s.expr!) as int)==0)following=matching(s,'WHILE','WEND');
        else push(Frame('WHILE',s));
        break;
      case 'WEND':
        final ix=search('WHILE');
        if(ix<0)fault('WEND WITHOUT WHILE');
        following=stack[ix].position;
        stack.removeRange(ix,stack.length);
        break;
      case 'DIM':
        for(final t in s.targets){
          final name=t.value as String;
          final bounds=t.args.map((e)=>evaluate(e) as int).toList();
          if(arrays.containsKey(name))fault('DUPLICATE DEFINITION');
          if(bounds.any((n)=>n<0))fault('ILLEGAL FUNCTION CALL');
          var size=1;
          for(final n in bounds)size*=n+1;
          if(size>10000)fault('OUT OF MEMORY');
          declare(name,bounds);
        }
        break;
      case 'RANDOMIZE':
        final n=evaluate(s.expr!) as int;
        if(n<1)fault('ILLEGAL FUNCTION CALL');
        random=n;
        break;
      case 'handler':
        if(s.numbers[0]!=0)line(s.numbers[0]);
        handler=s.numbers[0];
        break;
      case 'RESUME':
        if(!handling)fault('RESUME WITHOUT ERROR');
        following=s.mode=='line'?line(s.numbers[0]):
                  s.mode=='NEXT'?remembered!.next:remembered;
        handling=false;
        break;
      case 'STOP':message('BREAK IN LINE '+s.line.toString());return null;
      case 'END':return null;
    }
    return following;
  }
  void connect(List<Statement> body,Statement? after,int lineNumber){
    Statement? following=after;
    for(final s in body.reversed){
      s.line=lineNumber;s.next=following;
      for(final c in s.clauses)connect(c.body,following,lineNumber);
      following=s;
    }
  }
  List<String> finish(){
    if(buffer.isNotEmpty)endLine();
    output.add('READY');
    return output;
  }
  List<String> run(Map<int,String> source){
    final parsed=<ProgramLine>[];
    final numbers=source.keys.toList()..sort();
    for(final n in numbers){
      try{parsed.add(ProgramLine(n,Parser(tokenize(source[n]!)).parse()));}
      on SyntaxFault{
        message('ERROR IN LINE '+n.toString()+': SYNTAX ERROR');
        return finish();
      }
    }
    Statement? after;
    for(final e in parsed.reversed){
      connect(e.body,after,e.number);
      entries[e.number]=e.body[0];after=e.body[0];
    }
    for(final e in parsed){
      for(final s in e.body){
        sequence.add(s);
        if(s.kind=='DATA')for(final v in s.values)data.add(Entry(s.line,v));
      }
    }
    var pos=after;
    while(pos!=null){
      final current=pos;
      try{pos=execute(current);}
      on BasicFault catch(failure){
        if(handler!=0&&!handling){
          err=errorCodes[failure.reason]??0;
          erl=current.line;remembered=current;handling=true;
          try{pos=line(handler);}
          on BasicFault catch(secondary){
            message('ERROR IN LINE '+current.line.toString()+': '+secondary.reason);
            pos=null;
          }
        }else{
          message('ERROR IN LINE '+current.line.toString()+': '+failure.reason);
          pos=null;
        }
      }
    }
    return finish();
  }
}

void main(){
  final count=int.parse(stdin.readLineSync()!);
  for(var i=0;i<count;i++){
    final source=<int,String>{};
    while(true){
      final line=stdin.readLineSync()!;
      if(line=='RUN')break;
      final match=RegExp(r'^([0-9]+)(?: +(.*))?$').firstMatch(line)!;
      final number=int.parse(match[1]!);
      final body=match[2];
      if(body==null)source.remove(number);
      else source[number]=body;
    }
    final inputs=<String>[];
    while(true){
      final line=stdin.readLineSync()!;
      if(line=='END')break;
      inputs.add(line);
    }
    for(final line in Machine(inputs).run(source))stdout.writeln(line);
  }
}
