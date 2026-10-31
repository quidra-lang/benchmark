#include "dsp.h"
#include <stdarg.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

#define MAX_ARGS 67
#define MAX_SIGNALS 310

typedef enum {NAME_ARG,SIGNAL_ARG,INTEGER_ARG,METRIC_ARG,SET_OP_ARG,EXPECT_OP_ARG} ArgKind;
typedef enum {C_SET,C_IMPULSE,C_STEP,C_NOISE,C_GAIN,C_MIX,C_DELAY,C_ECHO,C_RESAMPLE,C_FADE,C_TRIM,C_CONCAT,C_FIR,C_BIQUAD,C_MOVAVG,C_DCBLOCK,C_NORMALIZE,C_GATE,C_ENVELOPE,C_COMPRESS,C_ANALYZE,C_COMPARE,C_EXPECT,C_SEGMENTS,C_ONSETS,C_PITCHTRACK,C_EXCERPT,C_PLOT,C_METER,C_HISTOGRAM,C_TRACE,C_SAVE} CommandId;
typedef struct {const char *name;ArgKind kind;int64_t low,high;} ArgSpec;
typedef struct {const char *name;CommandId id;int count;ArgSpec args[7];int repeat_count;ArgSpec repeated[5];int minimum,maximum;} Command;
typedef struct {ArgSpec spec;const char *token;int64_t integer;Signal *signal;} Argument;
typedef struct {Argument values[MAX_ARGS];int count;} Arguments;
typedef struct {char name[17];int64_t value;} Variable;
typedef struct {Signal *signals[MAX_SIGNALS],*owned[MAX_SIGNALS];int signal_count,owned_count;Variable variables[300];int variable_count;Lines log,analysis,excerpts,waveforms,saved;int steps,errors,passed,failed;} Pipeline;
#define N(name) {name,NAME_ARG,0,0}
#define S {"src",SIGNAL_ARG,0,0}
#define I(name,low,high) {name,INTEGER_ARG,low,high}
static const Command commands[]={
 {"SET",C_SET,4,{N("var"),I("value",-10000000,10000000),{"op",SET_OP_ARG,0,0},I("operand",-10000000,10000000)}},
 {"IMPULSE",C_IMPULSE,5,{N("dst"),I("rate",1000,48000),I("count",1,20000),I("pos",0,20000),I("amp",-32768,32767)}},
 {"STEP",C_STEP,5,{N("dst"),I("rate",1000,48000),I("count",1,20000),I("pos",0,20000),I("amp",-32768,32767)}},
 {"NOISE",C_NOISE,4,{N("dst"),I("rate",1000,48000),I("count",1,20000),I("seed",1,2147483646)}},
 {"GAIN",C_GAIN,4,{N("dst"),S,I("num",-65536,65536),I("den",1,65536)}},
 {"MIX",C_MIX,2,{N("dst"),I("den",1,65536)},2,{S,I("weight",-65536,65536)},1,8},
 {"DELAY",C_DELAY,3,{N("dst"),S,I("samples",0,20000)}},
 {"ECHO",C_ECHO,6,{N("dst"),S,I("delay",1,20000),I("num",-65536,65536),I("den",1,65536),I("tail",0,20000)}},
 {"RESAMPLE",C_RESAMPLE,3,{N("dst"),S,I("new_rate",1000,48000)}},
 {"FADE",C_FADE,4,{N("dst"),S,I("in",0,20000),I("out",0,20000)}},
 {"TRIM",C_TRIM,4,{N("dst"),S,I("start",0,20000),I("count",1,20000)}},
 {"CONCAT",C_CONCAT,1,{N("dst")},1,{S},2,8},
 {"FIR",C_FIR,3,{N("dst"),S,I("divisor",1,1000000)},1,{I("tap",-32768,32767)},1,64},
 {"BIQUAD",C_BIQUAD,2,{N("dst"),S},5,{I("b0",-65536,65536),I("b1",-65536,65536),I("b2",-65536,65536),I("a1",-65536,65536),I("a2",-65536,65536)},1,4},
 {"MOVAVG",C_MOVAVG,3,{N("dst"),S,I("width",1,1000)}},
 {"DCBLOCK",C_DCBLOCK,4,{N("dst"),S,I("num",0,65535),I("den",1,65536)}},
 {"NORMALIZE",C_NORMALIZE,3,{N("dst"),S,I("target",1,32767)}},
 {"GATE",C_GATE,4,{N("dst"),S,I("threshold",1,32768),I("hold",0,20000)}},
 {"ENVELOPE",C_ENVELOPE,4,{N("dst"),S,I("attack",1,32768),I("release",1,32768)}},
 {"COMPRESS",C_COMPRESS,7,{N("dst"),S,I("threshold",1,32767),I("ratio_num",1,100),I("ratio_den",1,100),I("attack",1,32768),I("release",1,32768)}},
 {"ANALYZE",C_ANALYZE,3,{S,I("min_hz",1,48000),I("max_hz",1,48000)}},
 {"COMPARE",C_COMPARE,2,{S,S}},
 {"EXPECT",C_EXPECT,4,{S,{"metric",METRIC_ARG,0,0},{"op",EXPECT_OP_ARG,0,0},I("value",-1000000000,1000000000)}},
 {"SEGMENTS",C_SEGMENTS,4,{S,I("threshold",1,32768),I("gap",1,20000),I("min_length",1,20000)}},
 {"ONSETS",C_ONSETS,5,{S,I("attack",1,32768),I("release",1,32768),I("threshold",1,32767),I("min_gap",1,20000)}},
 {"PITCHTRACK",C_PITCHTRACK,6,{S,I("frame",16,20000),I("hop",1,20000),I("min_hz",1,48000),I("max_hz",1,48000),I("threshold",0,32767)}},
 {"EXCERPT",C_EXCERPT,3,{S,I("start",0,20000),I("count",1,1000)}},
 {"PLOT",C_PLOT,7,{S,I("start",0,20000),I("count",1,20000),I("columns",8,120),I("half",2,20),I("attack",1,32768),I("release",1,32768)}},
 {"METER",C_METER,2,{S,I("block",1,20000)}},
 {"HISTOGRAM",C_HISTOGRAM,2,{S,I("bins",2,64)}},
 {"TRACE",C_TRACE,1,{S}},{"SAVE",C_SAVE,1,{S}}
};
static const char *text(const char *format,...){static char buffers[64][1024];static unsigned next;char *result=buffers[next++%64];va_list args;va_start(args,format);vsnprintf(result,1024,format,args);va_end(args);return result;}
void add_line(Lines *lines,const char *format,...){if(lines->count==lines->capacity){lines->capacity=lines->capacity?lines->capacity*2:64;char **grown=realloc(lines->values,(size_t)lines->capacity*sizeof *grown);if(!grown)exit(1);lines->values=grown;}va_list args,copy;va_start(args,format);va_copy(copy,args);int length=vsnprintf(NULL,0,format,copy);va_end(copy);char *line=malloc((size_t)length+1);if(!line)exit(1);vsnprintf(line,(size_t)length+1,format,args);va_end(args);lines->values[lines->count++]=line;}
void append_lines(Lines *to,const Lines *from){for(int j=0;j<from->count;j++)add_line(to,"%s",from->values[j]);}
static void clear_lines(Lines *lines){for(int j=0;j<lines->count;j++)free(lines->values[j]);free(lines->values);*lines=(Lines){0};}
static Signal *find_signal(const Pipeline *p,const char *name){for(int j=0;j<p->signal_count;j++)if(!strcmp(p->signals[j]->name,name))return p->signals[j];return NULL;}
static void register_signal(Pipeline *p,Signal *signal){int index=0;while(index<p->signal_count&&strcmp(p->signals[index]->name,signal->name))index++;if(index==p->signal_count)p->signal_count++;p->signals[index]=signal;p->owned[p->owned_count++]=signal;}
static int variable_index(const Pipeline *p,const char *name){for(int j=0;j<p->variable_count;j++)if(!strcmp(p->variables[j].name,name))return j;return -1;}
static bool argument_specs(const Command *c,int count,ArgSpec *specs){if(c->id==C_SET){if(count!=2&&count!=4)return false;memcpy(specs,c->args,(size_t)count*sizeof *specs);return true;}if(!c->repeat_count){if(count!=c->count)return false;memcpy(specs,c->args,(size_t)count*sizeof *specs);return true;}int remaining=count-c->count;if(remaining<0||remaining%c->repeat_count)return false;int groups=remaining/c->repeat_count;if(groups<c->minimum||groups>c->maximum)return false;memcpy(specs,c->args,(size_t)c->count*sizeof *specs);for(int j=0;j<remaining;j++)specs[c->count+j]=c->repeated[j%c->repeat_count];return true;}
static bool valid_name(const char *token){size_t length=strlen(token);if(length<1||length>16||token[0]<'a'||token[0]>'z')return false;for(size_t j=1;j<length;j++)if(!((token[j]>='a'&&token[j]<='z')||(token[j]>='0'&&token[j]<='9')||token[j]=='_'))return false;return true;}
static bool valid_integer(const char *token){const char *digits=token[0]=='-'?token+1:token;size_t length=strlen(digits);if(length<1||length>10||(length>1&&digits[0]=='0')||!strcmp(token,"-0"))return false;for(size_t j=0;j<length;j++)if(digits[j]<'0'||digits[j]>'9')return false;return true;}
static int64_t value_of(const Arguments *args,const char *name){for(int j=0;j<args->count;j++)if(!strcmp(args->values[j].spec.name,name))return args->values[j].integer;return 0;}
static Signal *first_signal(const Arguments *args){for(int j=0;j<args->count;j++)if(args->values[j].signal)return args->values[j].signal;return NULL;}
static void argument_bounds(CommandId command,ArgSpec spec,const Arguments *args,int64_t *low,int64_t *high){*low=spec.low;*high=spec.high;Signal *s=first_signal(args);const char *name=spec.name;if(!strcmp(name,"pos"))*high=value_of(args,"count")-1;else if(!strcmp(name,"in")||!strcmp(name,"out"))*high=s->samples.count;else if(!strcmp(name,"start"))*high=s->samples.count-1;else if(!strcmp(name,"count")){if(command==C_TRIM||command==C_PLOT)*high=s->samples.count-value_of(args,"start");}else if(!strcmp(name,"den")){if(command==C_DCBLOCK)*low=value_of(args,"num")+1;}else if(!strcmp(name,"ratio_den"))*high=value_of(args,"ratio_num");else if(!strcmp(name,"frame"))*high=s->samples.count;else if(!strcmp(name,"hop"))*high=value_of(args,"frame");else if(!strcmp(name,"min_hz"))*high=s->rate/2-1;else if(!strcmp(name,"max_hz")){*low=value_of(args,"min_hz")+1;*high=s->rate/2;}else if(!strcmp(name,"columns")){int64_t count=value_of(args,"count");*high=count<120?count:120;}}
static bool member(const char *token,const char *const *choices,int count){for(int j=0;j<count;j++)if(!strcmp(token,choices[j]))return true;return false;}
static const char *parse_arguments(const Pipeline *p,const Command *command,const ArgSpec *specs,char *const *tokens,int count,Arguments *args){
 static const char *const metrics[]={"samples","peak","rms","sum","zero_crossings","clipped"},*const set_ops[]={"+","-","*","/"},*const expect_ops[]={"eq","ne","lt","le","gt","ge"};
 for(int j=0;j<count;j++){ArgSpec spec=specs[j];const char *token=tokens[j];Argument arg={.spec=spec,.token=token};
  if(spec.kind==NAME_ARG){if(!valid_name(token))return text("bad name %s",token);}
  else if(spec.kind==SIGNAL_ARG){arg.signal=find_signal(p,token);if(!arg.signal)return text("unknown signal %s",token);}
  else if(spec.kind==METRIC_ARG){if(!member(token,metrics,6))return text("unknown metric %s",token);}
  else if(spec.kind==SET_OP_ARG){if(!member(token,set_ops,4))return text("unknown operator %s",token);}
  else if(spec.kind==EXPECT_OP_ARG){if(!member(token,expect_ops,6))return text("unknown operator %s",token);}
  else{if(token[0]=='$'){int index=variable_index(p,token+1);if(index<0)return text("undefined variable %s",token);arg.integer=p->variables[index].value;}else{if(!valid_integer(token))return text("bad integer %s",token);arg.integer=strtoll(token,NULL,10);}int64_t low,high;argument_bounds(command->id,spec,args,&low,&high);if(arg.integer<low||arg.integer>high)return text("%s out of range",spec.name);}args->values[args->count++]=arg;
 }
 return NULL;
}
static void lag_range(const Arguments *args,int *low,int *high){Signal *s=first_signal(args);int64_t min_hz=value_of(args,"min_hz"),max_hz=value_of(args,"max_hz");*low=(int)((s->rate+max_hz-1)/max_hz);*high=(int)(s->rate/min_hz);}
static int64_t set_result(const Arguments *args){int64_t value=args->values[1].integer;if(args->count==2)return value;int64_t operand=args->values[3].integer;const char *op=args->values[2].token;if(!strcmp(op,"+"))return value+operand;if(!strcmp(op,"-"))return value-operand;if(!strcmp(op,"*"))return value*operand;return floor_div(value,operand);}
static const char *checks(const Command *c,const Arguments *args){Signal *s=first_signal(args);switch(c->id){case C_SET:if(args->count==4&&!strcmp(args->values[2].token,"/")&&!args->values[3].integer)return "division by zero";if(sample_abs(set_result(args))>10000000)return "value out of range";break;
 case C_MIX:case C_CONCAT:case C_COMPARE:{int64_t total=0;for(int j=0;j<args->count;j++)if(args->values[j].signal){Signal *next=args->values[j].signal;if(next->rate!=s->rate)return "rate mismatch";total+=next->samples.count;}if(c->id==C_CONCAT&&total>20000)return "result too long";break;}
 case C_DELAY:if(s->samples.count+value_of(args,"samples")>20000)return "result too long";break;
 case C_ECHO:if(sample_abs(value_of(args,"num"))>=value_of(args,"den"))return "unstable feedback";if(s->samples.count+value_of(args,"tail")>20000)return "result too long";break;
 case C_RESAMPLE:if((int64_t)(s->samples.count-1)*value_of(args,"new_rate")/s->rate+1>20000)return "result too long";break;
 case C_ANALYZE:case C_PITCHTRACK:{int low,high;lag_range(args,&low,&high);if(low>high)return "empty lag range";if(c->id==C_ANALYZE&&high>=s->samples.count)return "signal too short";if(c->id==C_PITCHTRACK&&high>=value_of(args,"frame"))return "frame too short";break;}
 default:break;}return NULL;}
static bool generate(Pipeline *p,const Command *c,const Arguments *args,int line,const char **details){Signal *s=first_signal(args);Samples x=s?s->samples:(Samples){0},y={0};int rate=s?s->rate:(int)value_of(args,"rate");int64_t count=0;char extra[128]="";
 switch(c->id){
 case C_IMPULSE:case C_STEP:case C_NOISE:y=test_signal(c->name,(int)value_of(args,"count"),(int)value_of(args,"pos"),value_of(args,"amp"),value_of(args,"seed"));break;
 case C_GAIN:y=gain(x,value_of(args,"num"),value_of(args,"den"),&count);snprintf(extra,sizeof extra," clipped=%lld",(long long)count);break;
 case C_MIX:{Signal *tracks[8];int64_t weights[8];int n=0;for(int j=2;j<args->count;j+=2){tracks[n]=args->values[j].signal;weights[n++]=args->values[j+1].integer;}y=mix(tracks,weights,n,value_of(args,"den"),&count);snprintf(extra,sizeof extra," clipped=%lld",(long long)count);break;}
 case C_DELAY:y=delay(x,(int)value_of(args,"samples"));break;
 case C_ECHO:y=echo(x,(int)value_of(args,"delay"),value_of(args,"num"),value_of(args,"den"),(int)value_of(args,"tail"),&count);snprintf(extra,sizeof extra," clipped=%lld",(long long)count);break;
 case C_RESAMPLE:rate=(int)value_of(args,"new_rate");y=resample(x,s->rate,rate);break;
 case C_FADE:y=fade(x,(int)value_of(args,"in"),(int)value_of(args,"out"));break;
 case C_TRIM:{int start=(int)value_of(args,"start"),length=(int)value_of(args,"count");y=new_samples(length);memcpy(y.values,x.values+start,(size_t)length*sizeof *y.values);break;}
 case C_CONCAT:{int length=0;for(int j=0;j<args->count;j++)if(args->values[j].signal)length+=args->values[j].signal->samples.count;y=new_samples(length);int position=0;for(int j=0;j<args->count;j++)if(args->values[j].signal){Samples part=args->values[j].signal->samples;memcpy(y.values+position,part.values,(size_t)part.count*sizeof *part.values);position+=part.count;}break;}
 case C_FIR:{int64_t taps[64];for(int j=3;j<args->count;j++)taps[j-3]=args->values[j].integer;y=fir(x,value_of(args,"divisor"),taps,args->count-3,&count);snprintf(extra,sizeof extra," clipped=%lld",(long long)count);break;}
 case C_BIQUAD:{int64_t coefficients[20];for(int j=2;j<args->count;j++)coefficients[j-2]=args->values[j].integer;y=biquad(x,coefficients,args->count-2,&count);snprintf(extra,sizeof extra," sections=%d clipped=%lld",(args->count-2)/5,(long long)count);break;}
 case C_MOVAVG:y=moving_average(x,(int)value_of(args,"width"));break;
 case C_DCBLOCK:y=dc_block(x,value_of(args,"num"),value_of(args,"den"),&count);snprintf(extra,sizeof extra," clipped=%lld",(long long)count);break;
 case C_NORMALIZE:y=normalize(x,value_of(args,"target"),&count);snprintf(extra,sizeof extra," source_peak=%lld",(long long)count);break;
 case C_GATE:y=gate(x,value_of(args,"threshold"),(int)value_of(args,"hold"),&count);snprintf(extra,sizeof extra," muted=%lld",(long long)count);break;
 case C_ENVELOPE:y=envelope(x,value_of(args,"attack"),value_of(args,"release"));break;
 case C_COMPRESS:{int64_t reduced=0;y=compress_signal(x,value_of(args,"threshold"),value_of(args,"ratio_num"),value_of(args,"ratio_den"),value_of(args,"attack"),value_of(args,"release"),&count,&reduced);snprintf(extra,sizeof extra," min_gain=%lld reduced=%lld",(long long)count,(long long)reduced);break;}
 default:return false;
 }
 Signal *result=calloc(1,sizeof *result);if(!result)exit(1);strcpy(result->name,args->values[0].token);result->rate=rate;result->samples=y;snprintf(result->origin,sizeof result->origin,"line %d %s",line,c->name);for(int j=0;j<args->count;j++)if(args->values[j].signal)result->ingredients[result->ingredient_count++]=args->values[j].signal;register_signal(p,result);*details=text("%s rate=%d samples=%d peak=%lld sum=%lld%s",result->name,rate,y.count,(long long)peak(y),(long long)sample_sum(y),extra);return true;
}
static int64_t metric(const Signal *s,const char *name){Samples x=s->samples;if(!strcmp(name,"samples"))return x.count;if(!strcmp(name,"peak"))return peak(x);if(!strcmp(name,"rms"))return rms(x);if(!strcmp(name,"sum"))return sample_sum(x);if(!strcmp(name,"zero_crossings"))return zero_crossings(x);return clipped(x);}
static bool comparison(int64_t a,int64_t b,const char *op){if(!strcmp(op,"eq"))return a==b;if(!strcmp(op,"ne"))return a!=b;if(!strcmp(op,"lt"))return a<b;if(!strcmp(op,"le"))return a<=b;if(!strcmp(op,"gt"))return a>b;return a>=b;}
static void trace_lines(const Signal *s,int depth,Lines *lines){add_line(lines,"%*s%s <- %s",2*depth,"",s->name,s->origin);for(int j=0;j<s->ingredient_count;j++)trace_lines(s->ingredients[j],depth+1,lines);}
static int minimum(int a,int b){return a<b?a:b;}
static int64_t maximum64(int64_t a,int64_t b){return a>b?a:b;}
static Lines segment_lines(const Signal *s,int64_t threshold,int gap,int minimum_length){typedef struct{int first,last;} Segment;Segment *segments=malloc((size_t)s->samples.count*sizeof *segments);if(!segments)exit(1);int count=0;for(int n=0;n<s->samples.count;n++)if(sample_abs(s->samples.values[n])>=threshold){if(!count||n-segments[count-1].last>gap)segments[count++]=(Segment){n,n};else segments[count-1].last=n;}Lines lines={0};for(int j=0;j<count;j++){Segment segment=segments[j];if(segment.last-segment.first+1<minimum_length)continue;Samples x={s->samples.values+segment.first,segment.last-segment.first+1};add_line(&lines,"  segment %d start=%d end=%d start_ms=%lld end_ms=%lld peak=%lld rms=%lld crossings=%lld",lines.count+1,segment.first,segment.last,(long long)((int64_t)segment.first*1000/s->rate),(long long)((int64_t)segment.last*1000/s->rate),(long long)peak(x),(long long)rms(x),(long long)zero_crossings(x));}free(segments);return lines;}
static int compare_ints(const void *left,const void *right){int a=*(const int *)left,b=*(const int *)right;return (a>b)-(a<b);}
static Lines onset_lines(const Signal *s,int64_t attack,int64_t release,int64_t threshold,int minimum_gap,const char **tempo){Samples env=envelope(s->samples,attack,release);int *onsets=malloc((size_t)env.count*sizeof *onsets);if(!onsets)exit(1);int count=0;for(int n=0;n<env.count;n++)if(env.values[n]>=threshold&&(!n||env.values[n-1]<threshold)&&(!count||n-onsets[count-1]>=minimum_gap))onsets[count++]=n;*tempo="none";if(count>=2){int *differences=malloc((size_t)(count-1)*sizeof *differences);if(!differences)exit(1);for(int j=1;j<count;j++)differences[j-1]=onsets[j]-onsets[j-1];if(count>2)qsort(differences,(size_t)(count-1),sizeof *differences,compare_ints);*tempo=decimal_two(rdiv((int64_t)6000*s->rate,differences[(count-2)/2]));free(differences);}Lines lines={0};for(int j=0;j<count;j++)add_line(&lines,"  onset %d sample=%d ms=%lld interval=%s",j+1,onsets[j],(long long)((int64_t)onsets[j]*1000/s->rate),j?text("%d",onsets[j]-onsets[j-1]):"none");free(onsets);free(env.values);return lines;}
static int waveform_row(int64_t scale,int64_t value,int rows){return (int)rdiv((scale-value)*(rows-1),2*scale);}
static Lines waveform(const Signal *s,int start,int count,int columns,int half,int64_t attack,int64_t release){Samples x={s->samples.values+start,count},env=envelope(s->samples,attack,release);int64_t scale=maximum64(1,peak(x)),top[120],bottom[120],ec[120]={0};int rows=2*half+1;for(int c=0;c<columns;c++){int first=c*count/columns,last=(c+1)*count/columns;top[c]=bottom[c]=x.values[first];for(int j=first;j<last;j++){if(x.values[j]>top[c])top[c]=x.values[j];if(x.values[j]<bottom[c])bottom[c]=x.values[j];if(env.values[start+j]>ec[c])ec[c]=env.values[start+j];}if(ec[c]>scale)ec[c]=scale;}Lines lines={0};add_line(&lines,"PLOT %s rate=%d start=%d count=%d columns=%d rows=%d scale=%lld attack=%lld release=%lld",s->name,s->rate,start,count,columns,rows,(long long)scale,(long long)attack,(long long)release);
 for(int r=0;r<rows;r++){char band[121];for(int c=0;c<columns;c++){char symbol=' ';if(r==waveform_row(scale,ec[c],rows)||r==waveform_row(scale,-ec[c],rows))symbol='*';else if(waveform_row(scale,top[c],rows)<=r&&r<=waveform_row(scale,bottom[c],rows))symbol='#';else if(r==half)symbol='-';band[c]=symbol;}band[columns]='\0';const char *label=r==0?text("%lld",(long long)scale):r==half?"0":r==rows-1?text("%lld",(long long)-scale):"";add_line(&lines,"%6s |%s|",label,band);}
 char axis[256],time[256];memset(axis,'-',(size_t)columns);for(int c=0;c<columns;c+=10)axis[c]='+';axis[columns]='\0';add_line(&lines,"       +%s+",axis);memset(time,' ',sizeof time);memcpy(time,"    ms",6);int used=6;for(int c=0;c<columns;c+=10){const char *value=text("%lld",(long long)(((int64_t)start+(int64_t)c*count/columns)*1000/s->rate));int position=8+c,length=(int)strlen(value);memcpy(time+position,value,(size_t)length);used=position+length;}time[used]='\0';add_line(&lines,"%s",time);free(env.values);return lines;
}
static Lines meter(const Signal *s,int block){int blocks=(s->samples.count+block-1)/block;Lines lines={0};add_line(&lines,"METER %s rate=%d samples=%d block=%d blocks=%d",s->name,s->rate,s->samples.count,block,blocks);for(int b=0;b<blocks;b++){int first=b*block,last=minimum((b+1)*block,s->samples.count);Samples x={s->samples.values+first,last-first};int64_t p=peak(x),q=rms(x),k=clipped(x),np=rdiv(p*40,32768),nq=rdiv(q*40,32768);char bar[41];for(int j=0;j<40;j++)bar[j]=j<nq?'#':j<np?'-':' ';bar[40]='\0';add_line(&lines,"%6lld |%s| peak=%lld rms=%lld clipped=%lld",(long long)((int64_t)first*1000/s->rate),bar,(long long)p,(long long)q,(long long)k);}return lines;}
static Lines histogram(const Signal *s,int bins){int64_t counts[64]={0},largest=0;for(int j=0;j<s->samples.count;j++){int b=(int)((s->samples.values[j]+32768)*bins/65536);counts[b]++;if(counts[b]>largest)largest=counts[b];}Lines lines={0};add_line(&lines,"HISTOGRAM %s rate=%d samples=%d bins=%d max=%lld",s->name,s->rate,s->samples.count,bins,(long long)largest);for(int b=0;b<bins;b++){int low=(b*65536+bins-1)/bins-32768,high=((b+1)*65536+bins-1)/bins-32768-1,length=(int)rdiv(counts[b]*50,largest);char bar[51];memset(bar,'#',(size_t)length);bar[length]='\0';add_line(&lines,"%6d %6d %5lld |%s",low,high,(long long)counts[b],bar);}return lines;}
static Lines pitch_track(const Signal *s,int frame,int hop,int low,int high,int64_t threshold,int *voiced){int frames=(s->samples.count-frame)/hop+1;int64_t *levels=calloc((size_t)frames,sizeof *levels);int *lags=calloc((size_t)frames,sizeof *lags);if(!levels||!lags)exit(1);*voiced=0;for(int t=0;t<frames;t++){Samples x={s->samples.values+t*hop,frame};levels[t]=rms(x);if(levels[t]>=threshold){lags[t]=pitch_lag(x,low,high);*voiced+=lags[t]>0;}}Lines lines={0};add_line(&lines,"PITCHTRACK %s rate=%d frame=%d hop=%d lags=%d-%d threshold=%lld frames=%d voiced=%d",s->name,s->rate,frame,hop,low,high,(long long)threshold,frames,*voiced);for(int t=0;t<frames;t++){char bar[42];memset(bar,' ',41);bar[41]='\0';int lag=lags[t];if(lag){int position=high>low?(int)rdiv((int64_t)(high-lag)*40,high-low):0;bar[position]='o';add_line(&lines,"%6lld |%s| lag=%d hz=%s rms=%lld",(long long)((int64_t)t*hop*1000/s->rate),bar,lag,frequency(s->rate,lag),(long long)levels[t]);}else add_line(&lines,"%6lld |%s| unvoiced rms=%lld",(long long)((int64_t)t*hop*1000/s->rate),bar,(long long)levels[t]);}free(levels);free(lags);return lines;}
static const char *execute(Pipeline *p,const Command *c,const Arguments *args,int line,Lines *extra){const char *generated;if(generate(p,c,args,line,&generated))return generated;Signal *s=first_signal(args);switch(c->id){
 case C_SET:{int64_t result=set_result(args);int index=variable_index(p,args->values[0].token);if(index<0){index=p->variable_count++;strcpy(p->variables[index].name,args->values[0].token);}p->variables[index].value=result;return text("%s=%lld",args->values[0].token,(long long)result);}
 case C_ANALYZE:{int low,high;lag_range(args,&low,&high);int lag=pitch_lag(s->samples,low,high);add_line(&p->analysis,"%s,%lld,%lld,%lld,%lld,%s,%s,%s",s->name,(long long)peak(s->samples),(long long)rms(s->samples),(long long)zero_crossings(s->samples),(long long)clipped(s->samples),crest_fraction(s->samples),lag?text("%d",lag):"none",lag?frequency(s->rate,lag):"none");return text("%s lags=%d-%d",args->values[0].token,low,high);}
 case C_COMPARE:{Samples a=args->values[0].signal->samples,b=args->values[1].signal->samples;int first=-1,differing=0,length=a.count>b.count?a.count:b.count;int64_t maximum=0,error_energy=0;for(int n=0;n<length;n++){int64_t difference=(n<a.count?a.values[n]:0)-(n<b.count?b.values[n]:0);if(difference){differing++;if(first<0)first=n;}if(sample_abs(difference)>maximum)maximum=sample_abs(difference);error_energy+=difference*difference;}return text("%s %s differing=%d max_diff=%lld first=%s error_energy=%lld",args->values[0].token,args->values[1].token,differing,(long long)maximum,first<0?"none":text("%d",first),(long long)error_energy);}
 case C_EXPECT:{int64_t measured=metric(s,args->values[1].token);bool passed=comparison(measured,args->values[3].integer,args->values[2].token);if(passed)p->passed++;else p->failed++;return text("%s %s=%lld %s %lld %s",args->values[0].token,args->values[1].token,(long long)measured,args->values[2].token,(long long)args->values[3].integer,passed?"pass":"fail");}
 case C_SEGMENTS:*extra=segment_lines(s,value_of(args,"threshold"),(int)value_of(args,"gap"),(int)value_of(args,"min_length"));return text("%s segments=%d",args->values[0].token,extra->count);
 case C_ONSETS:{const char *tempo;*extra=onset_lines(s,value_of(args,"attack"),value_of(args,"release"),value_of(args,"threshold"),(int)value_of(args,"min_gap"),&tempo);return text("%s onsets=%d tempo=%s",args->values[0].token,extra->count,tempo);}
 case C_PITCHTRACK:{int low,high,voiced;lag_range(args,&low,&high);int frame=(int)value_of(args,"frame"),hop=(int)value_of(args,"hop");Lines plot=pitch_track(s,frame,hop,low,high,value_of(args,"threshold"),&voiced);append_lines(&p->waveforms,&plot);clear_lines(&plot);return text("%s frames=%d voiced=%d",args->values[0].token,(s->samples.count-frame)/hop+1,voiced);}
 case C_EXCERPT:{int start=(int)value_of(args,"start"),count=minimum((int)value_of(args,"count"),s->samples.count-start);add_line(&p->excerpts,"EXCERPT %s rate=%d samples=%d start=%d count=%d",s->name,s->rate,s->samples.count,start,count);for(int first=0;first<count;first+=8){char row[128];snprintf(row,sizeof row,"%5d:",start+first);for(int j=first;j<minimum(first+8,count);j++)snprintf(row+strlen(row),sizeof row-strlen(row)," %6lld",(long long)s->samples.values[start+j]);add_line(&p->excerpts,"%s",row);}return text("%s start=%d count=%d",args->values[0].token,start,count);}
 case C_PLOT:{int start=(int)value_of(args,"start"),count=(int)value_of(args,"count"),columns=(int)value_of(args,"columns"),half=(int)value_of(args,"half");Lines plot=waveform(s,start,count,columns,half,value_of(args,"attack"),value_of(args,"release"));append_lines(&p->waveforms,&plot);clear_lines(&plot);return text("%s start=%d count=%d columns=%d rows=%d",args->values[0].token,start,count,columns,2*half+1);}
 case C_METER:{int block=(int)value_of(args,"block");Lines plot=meter(s,block);append_lines(&p->waveforms,&plot);clear_lines(&plot);return text("%s block=%d",args->values[0].token,block);}
 case C_HISTOGRAM:{int bins=(int)value_of(args,"bins");Lines plot=histogram(s,bins);append_lines(&p->waveforms,&plot);clear_lines(&plot);return text("%s bins=%d",args->values[0].token,bins);}
 case C_TRACE:trace_lines(s,1,extra);return args->values[0].token;
 case C_SAVE:format_signal(s,&p->saved);return text("%s samples=%d",args->values[0].token,s->samples.count);
 default:exit(1);
 }}
static int compare_signals(const void *left,const void *right){const Signal *a=*(Signal *const *)left,*b=*(Signal *const *)right;return strcmp(a->name,b->name);}
static void write_report(const char *name,const Lines *lines){char path[128];snprintf(path,sizeof path,"output/%s",name);FILE *file=fopen(path,"w");if(!file)exit(1);for(int j=0;j<lines->count;j++)fprintf(file,"%s\n",lines->values[j]);if(fclose(file))exit(1);}
int main(void){
 Pipeline *p=calloc(1,sizeof *p);if(!p)return 1;add_line(&p->analysis,"signal,peak,rms,zero_crossings,clipped,crest,pitch_lag,pitch_hz");Signal *loaded[10];int count=read_signals(loaded);for(int j=0;j<count;j++){Signal *s=loaded[j];register_signal(p,s);add_line(&p->log,"load %s rate=%d samples=%d peak=%lld",s->name,s->rate,s->samples.count,(long long)peak(s->samples));}
 FILE *file=fopen("input/pipeline.txt","r");if(!file)return 1;char line[256];int number=0;while(fgets(line,sizeof line,file)){number++;size_t length=strlen(line);if(length&&line[length-1]=='\n')line[length-1]='\0';if(!line[0]||line[0]=='#')continue;char *tokens[201];int token_count=0;for(char *token=strtok(line," ");token;token=strtok(NULL," "))tokens[token_count++]=token;const char *name=tokens[0];const Command *command=NULL;for(size_t j=0;j<sizeof commands/sizeof *commands;j++)if(!strcmp(name,commands[j].name)){command=&commands[j];break;}const char *reason=NULL;Arguments args={0};
  if(!command)reason=text("unknown command %s",name);else{ArgSpec specs[MAX_ARGS];if(!argument_specs(command,token_count-1,specs))reason="wrong number of arguments";else{reason=parse_arguments(p,command,specs,tokens+1,token_count-1,&args);if(!reason)reason=checks(command,&args);}}
  if(reason){p->errors++;add_line(&p->log,"line %d: error: %s",number,reason);continue;}Lines extra={0};const char *details=execute(p,command,&args,number,&extra);p->steps++;add_line(&p->log,"line %d: %s %s",number,name,details);append_lines(&p->log,&extra);clear_lines(&extra);
 }
 fclose(file);if(p->signal_count>1)qsort(p->signals,(size_t)p->signal_count,sizeof *p->signals,compare_signals);for(int j=0;j<p->signal_count;j++){Signal *s=p->signals[j];add_line(&p->log,"signal %s rate=%d samples=%d peak=%lld rms=%lld",s->name,s->rate,s->samples.count,(long long)peak(s->samples),(long long)rms(s->samples));}add_line(&p->log,"summary steps=%d errors=%d signals=%d passed=%d failed=%d",p->steps,p->errors,p->signal_count,p->passed,p->failed);mkdir("output",0755);const char *names[5]={"log.txt","analysis.csv","excerpts.txt","waveforms.txt","signals_out.txt"};Lines *reports[5]={&p->log,&p->analysis,&p->excerpts,&p->waveforms,&p->saved};for(int j=0;j<5;j++){write_report(names[j],reports[j]);clear_lines(reports[j]);}for(int j=0;j<p->owned_count;j++){free(p->owned[j]->samples.values);free(p->owned[j]);}free(p);return 0;
}
