import java.util.*;
public final class Main {
    static final String[] NAMES= {
        "sad","ssd","census","sgm","fusion","wta_final","sgm_final"
    },SOURCES= {
        "kept","median","background","interpolated","none"
    };
    static final int[] REASONS= {
        50,100,150,200,255
    };
    static final String[] REASON_NAMES= {
        "textureless","nonunique","outside","mismatch","occluded"
    };
    static int w,h,size,min,max;
    static long focal,baseline;
    static int[] left,right,truth;
    static long[] strengths;
    static PgmIo.Parameters params;
    static Evaluation.Regions regions;
    static final Method[] methods=new Method[7];
    static long[][] summed;
    static final List<String> sweeps=new ArrayList<>();
    static final class Method {
        int[] image,reasons,lr,sources,votes;
        long[] margins;
        int window,bounds,speckles,specklePixels,medianChanged;
        Method(int[] image) {
            this.image=image;
        }
    }
    static final class ObjectInfo {
        int count,x0,y0,x1,y1,min,max,median,layer,hits,union,first;
        long total;
    }
    static int p(String name) {
        return params.integer(name);
    }
    static String two(long a,long b) {
        return Refinement.two(a,b);
    }
    static String ratio(long a,long b) {
        return Evaluation.ratio(a,b);
    }
    static int median(List<Integer> values) {
        values.sort(Integer::compare);
        return values.get((values.size()-1)/2);
    }
    static int valid(int[] image) {
        int count=0;
        for(int d:image)if(d!=0)count++;
        return count;
    }
    static boolean consistent(int pixel,int d,int[] rightDisparity) {
        return pixel%w>=d&&Math.abs(d-rightDisparity[pixel-d])<=p("lr_max_diff");
    }
    static Method select(long[][] volume) {
        int[] rightDisparity=new int[size];
        for(int y=0; y<h; y++)for(int x=0; x<w; x++) {
            int pixel=y*w+x;
            long best=Long.MAX_VALUE;
            for(int d=min; d<=max&&x+d<w; d++)if(volume[pixel+d][d-min]<best) {
                best=volume[pixel+d][d-min];
                rightDisparity[pixel]=d;
            }
        }
        Method result=new Method(new int[size]);
        result.reasons=new int[size];
        result.margins=new long[size];
        result.lr=new int[4];
        for(int pixel=0; pixel<size; pixel++) {
            long[] row=volume[pixel];
            int d1=min;
            for(int d=min+1; d<=max; d++)if(row[d-min]<row[d1-min])d1=d;
            long first=row[d1-min],second=Long.MAX_VALUE;
            for(int d=min; d<=max; d++)if(Math.abs(d-d1)>=2)second=Math.min(second,row[d-min]);
            if(d1==min||d1==max)result.bounds++;
            int reason=0;
            if(strengths[pixel]<p("texture_threshold"))reason=50;
            else if(100*second<=(100L+p("uniqueness"))*first)reason=100;
            else if(pixel%w<d1)reason=150;
            else if(!consistent(pixel,d1,rightDisparity)) {
                boolean found=false;
                for(int d=min; d<=max; d++)if(consistent(pixel,d,rightDisparity))found=true;
                reason=found?200:255;
            }else {
                result.image[pixel]=d1;
                result.margins[pixel]=second-first;
            }
            result.reasons[pixel]=reason;
            if(reason==0||reason==200||reason==255)result.lr[Math.min(3,Math.abs(d1-rightDisparity[pixel-d1]))]++;
        }
        return result;
    }
    static long[][] costs(int[] cl,int[] cr,String kind,int window) {
        return Costs.volume(left,right,cl,cr,w,h,kind,window,min,max);
    }
    static void estimate() {
        int[] cl=Costs.census(left,w,h),cr=Costs.census(right,w,h);
        for(int k=0; k<3; k++) {
            Evaluation.Metrics best=null;
            for(int window:params.integers(NAMES[k]+"_windows")) {
                Method method=select(costs(cl,cr,NAMES[k],window));
                method.window=window;
                Evaluation.Metrics score=Evaluation.evaluate(method.image,truth,regions.nonocc());
                sweeps.add("sweep "+NAMES[k]+" window "+window+" valid "+valid(method.image)+" bad1 "+ratio(score.bad1(),score.pixels())+" bad2 "+ratio(score.bad2(),score.pixels()));
                if(best==null||score.bad1()<best.bad1()||(score.bad1()==best.bad1()&&score.bad2()<best.bad2())) {
                    best=score;
                    methods[k]=method;
                }
            }
        }
        long[][] base=costs(cl,cr,params.text("sgm_cost"),p("sgm_window"));
        summed=new long[size][max-min+1];
        for(int i=0; i<p("sgm_paths"); i++) {
            Aggregation.accumulate(summed,Aggregation.path(base,left,w,h,i,p("p1"),p("p2"),p("p2_gamma")));
            methods[3]=select(summed);
            Evaluation.Metrics score=Evaluation.evaluate(methods[3].image,truth,regions.nonocc());
            sweeps.add("paths "+(i+1)+" valid "+valid(methods[3].image)+" bad1 "+ratio(score.bad1(),score.pixels())+" bad2 "+ratio(score.bad2(),score.pixels()));
        }
        methods[3].window=p("sgm_window");
    }
    static List<List<Integer>> components(int[] image,int range) {
        boolean[] visited=new boolean[size];
        List<List<Integer>> result=new ArrayList<>();
        for(int start=0; start<size; start++)if(image[start]!=0&&!visited[start]) {
            List<Integer> part=new ArrayList<>();
            ArrayDeque<Integer> stack=new ArrayDeque<>();
            stack.push(start);
            visited[start]=true;
            while(!stack.isEmpty()) {
                int pixel=stack.pop(),x=pixel%w,y=pixel/w;
                part.add(pixel);
                for(int k=0; k<4; k++) {
                    int xx=x+Aggregation.DIRECTIONS[k][0],yy=y+Aggregation.DIRECTIONS[k][1];
                    if(xx>=0&&xx<w&&yy>=0&&yy<h) {
                        int q=yy*w+xx;
                        if(!visited[q]&&image[q]!=0&&Math.abs(image[q]-image[pixel])<=range) {
                            visited[q]=true;
                            stack.push(q);
                        }
                    }
                }
            }
            result.add(part);
        }
        return result;
    }
    static List<Integer> rays(int[] image,int pixel,boolean background) {
        int x=pixel%w,y=pixel/w;
        List<Integer> result=new ArrayList<>();
        int count=background?2:8;
        for(int k=0; k<count; k++) {
            int dx=Aggregation.DIRECTIONS[k][0],dy=Aggregation.DIRECTIONS[k][1],xx=x+dx,yy=y+dy;
            while(xx>=0&&xx<w&&yy>=0&&yy<h) {
                int value=image[yy*w+xx];
                if(value!=0) {
                    result.add(value);
                    break;
                }
                xx+=dx;
                yy+=dy;
            }
        }
        return result;
    }
    static Method postprocess(Method source) {
        int[] original=source.image,filtered=original.clone();
        Method result=new Method(new int[size]);
        for(List<Integer> part:components(original,p("speckle_range")))if(part.size()<p("speckle_size")) {
            result.speckles++;
            result.specklePixels+=part.size();
            for(int pixel:part)filtered[pixel]=0;
        }
        int[] medians=new int[size];
        for(int pixel=0; pixel<size; pixel++)if(filtered[pixel]!=0) {
            int x=pixel%w,y=pixel/w;
            List<Integer> values=new ArrayList<>();
            for(int yy=Math.max(0,y-1); yy<=Math.min(h-1,y+1); yy++)for(int xx=Math.max(0,x-1); xx<=Math.min(w-1,x+1); xx++)if(filtered[yy*w+xx]!=0)values.add(filtered[yy*w+xx]);
            medians[pixel]=median(values);
            if(medians[pixel]!=filtered[pixel])result.medianChanged++;
        }
        result.image=medians.clone();
        result.sources=new int[size];
        Arrays.fill(result.sources,4);
        for(int pixel=0; pixel<size; pixel++) {
            if(medians[pixel]!=0)result.sources[pixel]=medians[pixel]==original[pixel]?0:1;
            else {
                boolean background=source.reasons[pixel]==150||source.reasons[pixel]==255;
                List<Integer> values=rays(medians,pixel,background);
                if(!values.isEmpty()) {
                    result.image[pixel]=background?Collections.min(values):median(values);
                    result.sources[pixel]=background?2:3;
                }
            }
        }
        return result;
    }
    static void fuse() {
        Method result=new Method(new int[size]);
        result.votes=new int[5];
        for(int pixel=0; pixel<size; pixel++) {
            List<Integer> values=new ArrayList<>();
            for(int k=0; k<4; k++)if(methods[k].image[pixel]!=0)values.add(methods[k].image[pixel]);
            result.votes[values.size()]++;
            if(!values.isEmpty()) {
                int median=median(values),agree=0;
                for(int value:values)if(Math.abs(value-median)<=1)agree++;
                if(agree>=p("fusion_min_votes"))result.image[pixel]=median;
            }
        }
        methods[4]=result;
        int selected=Arrays.asList(NAMES).indexOf(params.text("wta_cost"));
        methods[5]=postprocess(methods[selected]);
        methods[6]=postprocess(methods[3]);
    }
    static List<String> objects() {
        List<ObjectInfo> objects=new ArrayList<>();
        int small=0,totalPixels=0;
        int[] trueCounts=new int[max+1];
        for(int d:truth)if(d!=0)trueCounts[d]++;
        for(List<Integer> part:components(methods[6].image,p("object_range"))) {
            if(part.size()<p("object_min_size")) {
                small++;
                continue;
            }
            ObjectInfo object=new ObjectInfo();
            object.count=part.size();
            object.x0=w;
            object.y0=h;
            object.first=size;
            List<Integer> disparities=new ArrayList<>();
            int[] counts=new int[max+1];
            for(int pixel:part) {
                object.x0=Math.min(object.x0,pixel%w);
                object.x1=Math.max(object.x1,pixel%w);
                object.y0=Math.min(object.y0,pixel/w);
                object.y1=Math.max(object.y1,pixel/w);
                object.first=Math.min(object.first,pixel);
                int d=methods[6].image[pixel];
                disparities.add(d);
                object.total+=d;
                if(truth[pixel]!=0)counts[truth[pixel]]++;
            }
            object.median=median(disparities);
            object.min=disparities.getFirst();
            object.max=disparities.getLast();
            for(int g=min; g<=max; g++)if(counts[g]>object.hits) {
                object.layer=g;
                object.hits=counts[g];
            }
            if(object.layer!=0)object.union=object.count+trueCounts[object.layer]-object.hits;
            objects.add(object);
            totalPixels+=object.count;
        }
        objects.sort(Comparator.comparingInt((ObjectInfo o)->o.median).reversed().thenComparing(Comparator.comparingInt((ObjectInfo o)->o.count).reversed()).thenComparingInt(o->o.first));
        List<String> lines=new ArrayList<>();
        lines.add("objects "+objects.size()+" small "+small+" pixels "+totalPixels);
        boolean[] detected=new boolean[max+1];
        for(int i=0; i<objects.size(); i++) {
            ObjectInfo o=objects.get(i);
            String line="object "+(i+1)+" pixels "+o.count+" box "+o.x0+" "+o.y0+" "+o.x1+" "+o.y1+" disparity "+o.min+" "+o.max+" median "+o.median+" mean "+two(o.total,o.count)+" depth "+two(focal*baseline*o.count,o.total)+" size "+two((o.x1-o.x0+1)*baseline,o.median)+" "+two((o.y1-o.y0+1)*baseline,o.median);
            if(o.layer==0)line+=" truth - iou -";
            else {
                line+=" truth "+o.layer+" iou "+ratio(o.hits,o.union);
                if(2*o.hits>o.union)detected[o.layer]=true;
            }
            lines.add(line);
        }
        int layerCount=0,detectedCount=0;
        List<String> missed=new ArrayList<>();
        for(int g=min; g<=max; g++)if(trueCounts[g]!=0) {
            layerCount++;
            if(detected[g])detectedCount++;
            else missed.add(Integer.toString(g));
        }
        lines.add("layers "+layerCount+" detected "+detectedCount+" missed "+(missed.isEmpty()?"-":String.join(" ",missed)));
        return lines;
    }
    static List<String> samples() {
        List<String> lines=new ArrayList<>();
        lines.add("x,y,sad,ssd,census,sgm,disparity,source,subpixel,depth,truth,truth_depth");
        for(int[] point:params.samples) {
            int pixel=point[1]*w+point[0];
            String line=point[0]+","+point[1];
            for(int k=0; k<4; k++)line+=","+(methods[k].image[pixel]==0?"-":Integer.toString(methods[k].image[pixel]));
            int d=methods[6].image[pixel];
            if(d==0)line+=",-,none,-,-";
            else {
                String[] refined=Refinement.subpixel(d,summed[pixel],min,max,focal,baseline);
                line+=","+d+","+SOURCES[methods[6].sources[pixel]]+","+refined[0]+","+refined[1];
            }
            line+=truth[pixel]==0?",-,-":","+truth[pixel]+","+two(focal*baseline,truth[pixel]);
            lines.add(line);
        }
        return lines;
    }
    static String imageSummary(String name,int[] image) {
        long total=0;
        int low=255,high=0;
        for(int value:image) {
            total+=value;
            low=Math.min(low,value);
            high=Math.max(high,value);
        }
        return name+" mean "+two(total,size)+" min "+low+" max "+high;
    }
    static String regionLine(String name,Evaluation.Metrics m) {
        return "region "+name+" pixels "+m.pixels()+" valid "+m.valid()+" bad1 "+ratio(m.bad1(),m.pixels())+" bad2 "+ratio(m.bad2(),m.pixels())+" mae "+m.mae()+" exact "+m.exact();
    }
    static List<String> methodLines(int k,Evaluation.Metrics[] metrics) {
        Method method=methods[k];
        int[] image=method.image;
        List<Integer> values=new ArrayList<>();
        Set<Integer> distinct=new HashSet<>();
        int horizontal=0,vertical=0;
        for(int pixel=0; pixel<size; pixel++)if(image[pixel]!=0) {
            values.add(image[pixel]);
            distinct.add(image[pixel]);
            if(pixel%w+1<w&&image[pixel+1]!=0&&Math.abs(image[pixel]-image[pixel+1])>=2)horizontal++;
            if(pixel/w+1<h&&image[pixel+w]!=0&&Math.abs(image[pixel]-image[pixel+w])>=2)vertical++;
        }
        List<String> lines=new ArrayList<>();
        lines.add("method "+NAMES[k]+" valid "+values.size()+" invalid "+(size-values.size()));
        if(values.isEmpty())lines.add("disparity min - max - median - distinct 0");
        else {
            int median=median(values);
            lines.add("disparity min "+values.getFirst()+" max "+values.getLast()+" median "+median+" distinct "+distinct.size());
        }
        lines.add("jumps horizontal "+horizontal+" vertical "+vertical);
        if(k<4) {
            lines.add("window "+method.window+" bounds "+method.bounds);
            String reasons="reasons";
            for(int i=0; i<5; i++) {
                int reasonCount=0;
                for(int reason:method.reasons)if(reason==REASONS[i])reasonCount++;
                reasons+=" "+REASON_NAMES[i]+" "+reasonCount;
            }
            lines.add(reasons);
            lines.add("lr 0 "+method.lr[0]+" 1 "+method.lr[1]+" 2 "+method.lr[2]+" 3+ "+method.lr[3]);
        }else if(k==4) {
            String votes="votes";
            for(int i=0; i<5; i++)votes+=" "+i+" "+method.votes[i];
            lines.add(votes);
        }else {
            int[] counts=new int[5];
            for(int source:method.sources)counts[source]++;
            lines.add("postprocess speckles "+method.speckles+" "+method.specklePixels+" median "+method.medianChanged+" background "+counts[2]+" interpolated "+counts[3]+" unfilled "+counts[4]);
            for(int source=0; source<5; source++) {
                List<Integer> region=new ArrayList<>();
                for(int pixel:regions.all())if(method.sources[pixel]==source)region.add(pixel);
                Evaluation.Metrics m=Evaluation.evaluate(image,truth,region);
                lines.add("source "+SOURCES[source]+" pixels "+m.pixels()+" bad1 "+ratio(m.bad1(),m.pixels()));
            }
        }
        for(int i=0; i<3; i++)lines.add(regionLine(Evaluation.REGIONS[i],metrics[i]));
        int count=0;
        long total=0,maximum=0;
        for(int pixel:regions.nonocc())if(image[pixel]!=0) {
            long error=Math.abs(Refinement.depthHundredths(image[pixel],focal,baseline)-Refinement.depthHundredths(truth[pixel],focal,baseline));
            count++;
            total+=error;
            maximum=Math.max(maximum,error);
        }
        lines.add(count==0?"depth_error pixels 0 mean - max -":"depth_error pixels "+count+" mean "+two(total,100L*count)+" max "+two(maximum,100));
        int[] errors=new int[6];
        for(int pixel:regions.all())errors[image[pixel]==0?5:Math.min(4,Math.abs(image[pixel]-truth[pixel]))]++;
        lines.add("errors 0 "+errors[0]+" 1 "+errors[1]+" 2 "+errors[2]+" 3 "+errors[3]+" 4+ "+errors[4]+" invalid "+errors[5]);
        return lines;
    }
    static int compareMetrics(Evaluation.Metrics a,Evaluation.Metrics b) {
        int c=Integer.compare(a.bad1(),b.bad1());
        if(c!=0)return c;
        c=Integer.compare(a.bad2(),b.bad2());
        if(c!=0)return c;
        if(a.valid()==0||b.valid()==0)return a.valid()==b.valid()?0:a.valid()==0?1:-1;
        return Long.compare(a.error()*b.valid(),b.error()*a.valid());
    }
    static List<String> evaluation() {
        List<String> lines=new ArrayList<>();
        lines.add("image "+w+" "+h);
        lines.add("disparities "+min+" "+max);
        lines.add(imageSummary("left",left));
        lines.add(imageSummary("right",right));
        long textureTotal=0;
        int textureless=0;
        for(long value:strengths) {
            textureTotal+=value;
            if(value<p("texture_threshold"))textureless++;
        }
        lines.add("texture mean "+two(textureTotal,size)+" textureless "+textureless);
        lines.add("ground_truth known "+regions.all().size()+" nonocc "+regions.nonocc().size()+" occluded "+regions.occluded().size()+" disc "+regions.disc().size()+" unknown "+(size-regions.all().size()));
        long absolute=0,biasSum=0;
        for(int pixel:regions.nonocc()) {
            int delta=right[pixel-truth[pixel]]-left[pixel];
            absolute+=Math.abs(delta);
            biasSum+=delta;
        }
        String bias=two(Math.abs(biasSum),regions.nonocc().size());
        if(biasSum<0&&!bias.equals("0.00"))bias="-"+bias;
        lines.add("photometric pixels "+regions.nonocc().size()+" mean_abs "+two(absolute,regions.nonocc().size())+" bias "+bias);
        lines.addAll(sweeps);
        Evaluation.Metrics[][] metrics=new Evaluation.Metrics[7][3];
        for(int k=0; k<7; k++) {
            for(int i=0; i<3; i++)metrics[k][i]=Evaluation.evaluate(methods[k].image,truth,regions.at(i));
            lines.addAll(methodLines(k,metrics[k]));
        }
        for(int i=0; i<3; i++) {
            final int region=i;
            List<Integer> order=new ArrayList<>();
            for(int k=0; k<7; k++)order.add(k);
            order.sort((a,b)-> {
                int c=compareMetrics(metrics[a][region],metrics[b][region]);
                return c!=0?c:Integer.compare(a,b);
            });
            String ranking="ranking "+Evaluation.REGIONS[i];
            for(int k:order)ranking+=" "+NAMES[k];
            lines.add(ranking);
        }
        for(int k=0; k<4; k++) {
            int tp=0,fp=0;
            for(int pixel:regions.occluded())if(methods[k].reasons[pixel]==150||methods[k].reasons[pixel]==255)tp++;
            for(int pixel:regions.nonocc())if(methods[k].reasons[pixel]==150||methods[k].reasons[pixel]==255)fp++;
            int fn=regions.occluded().size()-tp;
            lines.add("occlusion "+NAMES[k]+" tp "+tp+" fp "+fp+" fn "+fn+" precision "+ratio(tp,tp+fp)+" recall "+ratio(tp,tp+fn));
        }
        for(int k=0; k<4; k++) {
            Method method=methods[k];
            List<Integer> pixels=new ArrayList<>();
            for(int pixel:regions.nonocc())if(method.image[pixel]!=0)pixels.add(pixel);
            pixels.sort((a,b)-> {
                int c=Long.compare(method.margins[b],method.margins[a]);
                return c!=0?c:Integer.compare(a,b);
            });
            for(int percentage:new int[] {
                25,50,75,100
            }) {
                int count=(pixels.size()*percentage+99)/100,bad=0;
                for(int i=0; i<count; i++) {
                    int pixel=pixels.get(i);
                    if(Math.abs(method.image[pixel]-truth[pixel])>1)bad++;
                }
                lines.add("confidence "+NAMES[k]+" "+percentage+" pixels "+count+" margin "+(count==0?"-":Long.toString(method.margins[pixels.get(count-1)]))+" bad1 "+ratio(bad,count));
            }
        }
        for(int g=min; g<=max; g++) {
            int count=0;
            List<Integer> region=new ArrayList<>();
            for(int pixel:regions.all())if(truth[pixel]==g)count++;
            if(count==0)continue;
            for(int pixel:regions.nonocc())if(truth[pixel]==g)region.add(pixel);
            String line="layer "+g+" pixels "+count+" nonocc "+region.size()+" bad1";
            for(Method method:methods)line+=" "+Evaluation.evaluate(method.image,truth,region).bad1();
            lines.add(line);
        }
        for(int d=min; d<=max; d++) {
            int count=0;
            for(int value:methods[6].image)if(value==d)count++;
            lines.add("histogram "+d+" "+count);
        }
        return lines;
    }
    public static void main(String[] args)throws Exception {
        PgmIo.Image image=PgmIo.read("left.pgm");
        w=image.width();
        h=image.height();
        size=w*h;
        left=image.pixels();
        right=PgmIo.read("right.pgm").pixels();
        truth=PgmIo.read("ground_truth.pgm").pixels();
        params=PgmIo.parameters();
        min=p("disparity_min");
        max=p("disparity_max");
        focal=p("focal_length");
        baseline=p("baseline");
        regions=Evaluation.regions(truth,w,h);
        strengths=Costs.texture(left,w,h,p("texture_window"));
        estimate();
        fuse();
        int[] wta=new int[size],sgm=new int[size],errors=new int[size];
        for(int pixel=0; pixel<size; pixel++) {
            wta[pixel]=8*methods[5].image[pixel];
            sgm[pixel]=8*methods[6].image[pixel];
            errors[pixel]=truth[pixel]==0?0:methods[6].image[pixel]==0?255:50*(Math.min(3,Math.abs(methods[6].image[pixel]-truth[pixel]))+1);
        }
        PgmIo.write("disparity_wta.pgm",w,h,wta);
        PgmIo.write("disparity_sgm.pgm",w,h,sgm);
        PgmIo.write("occlusion.pgm",w,h,methods[3].reasons);
        PgmIo.write("error_sgm.pgm",w,h,errors);
        PgmIo.text("depth.csv",samples());
        PgmIo.text("evaluation.txt",evaluation());
        PgmIo.text("objects.txt",objects());
    }
}
