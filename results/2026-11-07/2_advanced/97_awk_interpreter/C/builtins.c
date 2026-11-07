#include "awk.h"
void runtime_error(Runtime *r,Position p,const char *message) {
    if(!r->message) {
        r->error=p;
        r->message=str_copy(message);
    }
}
static void padding(Buffer *out,int n,char c) {
    while(n-->0)buffer_add(out,&c,1);
}
char *format_values(Runtime *r,Position pos,Value *args,int count) {
    if(!count) {
        runtime_error(r,pos,"not enough arguments");
        return str_copy("");
    }
    char *format=textual(args[0]);
    Buffer output= {
        0
    };
    int arg=1;
    for(int i=0;format[i]&&!r->message;) {
        if(format[i]!='%') {
            buffer_add(&output,format+i++,1);
            continue;
        }
        ++i;
        if(format[i]=='%') {
            buffer_add(&output,"%",1);
            ++i;
            continue;
        }
        int left=0,zero=0,width=0,precision=-1;
        while(format[i]=='-'||format[i]=='0') {
            if(format[i]=='-')left=1;
            else zero=1;
            ++i;
        }
        while(isdigit((unsigned char)format[i]))width=width*10+format[i++]-'0';
        if(format[i]=='.') {
            ++i;
            precision=0;
            while(isdigit((unsigned char)format[i]))precision=precision*10+format[i++]-'0';
        }
        char conversion=format[i];
        if(!conversion||!strchr("discxo",conversion)) {
            runtime_error(r,pos,"invalid format");
            break;
        }
        ++i;
        if(arg>=count) {
            runtime_error(r,pos,"not enough arguments");
            break;
        }
        Value v=args[arg++];
        Buffer body= {
            0
        };
        int negative=0,numeric_conversion=strchr("dixo",conversion)!=NULL;
        if(numeric_conversion) {
            long long n=numeric(v);
            negative=n<0;
            unsigned long long magnitude=(unsigned long long)(negative?-n:n);
            unsigned base=conversion=='x'?16:conversion=='o'?8:10;
            char reversed[80];
            int nd=0;
            do {
                reversed[nd++]="0123456789abcdef"[magnitude%base];
                magnitude/=base;
            }
            while(magnitude);
            if(!n&&!precision)nd=0;
            padding(&body,precision>nd?precision-nd:0,'0');
            while(nd)buffer_add(&body,&reversed[--nd],1);
        }
        else if(conversion=='s') {
            char *s=textual(v);
            size_t length=strlen(s);
            if(precision>=0&&(size_t)precision<length)length=(size_t)precision;
            buffer_add(&body,s,length);
            free(s);
        }
        else {
            char c=0;
            if(v.kind==1||v.kind==3) {
                long long code=numeric(v);
                if(code!=10&&(code<32||code>126)) {
                    runtime_error(r,pos,"invalid character code");
                    free(body.data);
                    break;
                }
                c=(char)code;
            }
            else {
                char *s=textual(v);
                c=*s;
                free(s);
            }
            if(c)buffer_add(&body,&c,1);
        }
        int length=(int)body.length+negative,pad=width>length?width-length:0;
        if(!left&&!(numeric_conversion&&zero&&precision<0))padding(&output,pad,' ');
        if(negative)buffer_add(&output,"-",1);
        if(!left&&numeric_conversion&&zero&&precision<0)padding(&output,pad,'0');
        if(body.length)buffer_add(&output,body.data,body.length);
        if(left)padding(&output,pad,' ');
        free(body.data);
    }
    free(format);
    if(r->message) {
        free(output.data);
        return str_copy("");
    }
    return output.data?output.data:str_copy("");
}
Value simple_builtin(Runtime *r,Expr *e,Value *args) {
    const char *name=e->token.text;
    char *s=NULL;
    Value result= {
        0
    };
    if(!strcmp(name,"int"))return number(numeric(args[0]));
    if(!strcmp(name,"sprintf")) {
        s=format_values(r,e->token.pos,args,e->count);
        result=string(s);
        free(s);
        return result;
    }
    s=textual(args[0]);
    if(!strcmp(name,"substr")) {
        long long start=numeric(args[1]),end=e->count==3?start+numeric(args[2]):(long long)strlen(s)+1;
        if(start<1)start=1;
        if(end>(long long)strlen(s)+1)end=(long long)strlen(s)+1;
        if(end>start) {
            char *piece=mem_new((size_t)(end-start)+1);
            memcpy(piece,s+start-1,(size_t)(end-start));
            result=string(piece);
            free(piece);
        }
        else result=string("");
    }
    else if(!strcmp(name,"index")) {
        char *t=textual(args[1]);
        char *found=*t?strstr(s,t):NULL;
        result=number(found?found-s+1:0);
        free(t);
    }
    else if(!strcmp(name,"toupper")||!strcmp(name,"tolower")) {
        for(char *p=s;*p;++p) {
            if(!strcmp(name,"toupper")&&*p>='a'&&*p<='z')*p=(char)(*p-'a'+'A');
            if(!strcmp(name,"tolower")&&*p>='A'&&*p<='Z')*p=(char)(*p-'A'+'a');
        }
        result=string(s);
    }
    free(s);
    return result;
}
