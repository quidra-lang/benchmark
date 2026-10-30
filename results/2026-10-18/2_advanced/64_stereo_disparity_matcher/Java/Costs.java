final class Costs {
    static int clamp(int v,int size) {
        return Math.min(Math.max(v,0),size-1);
    }
    static int at(int[] image,int w,int h,int x,int y) {
        return image[clamp(y,h)*w+clamp(x,w)];
    }
    static long[] box(long[] image,int w,int h,int window) {
        int radius=window/2,pw=w+2*radius,ph=h+2*radius;
        long[][] integral=new long[ph+1][pw+1];
        for(int y=0; y<ph; y++) {
            long row=0;
            for(int x=0; x<pw; x++) {
                row+=image[clamp(y-radius,h)*w+clamp(x-radius,w)];
                integral[y+1][x+1]=integral[y][x+1]+row;
            }
        }
        long[] result=new long[w*h];
        for(int y=0; y<h; y++)for(int x=0; x<w; x++)result[y*w+x]=integral[y+window][x+window]-integral[y][x+window]-integral[y+window][x]+integral[y][x];
        return result;
    }
    static int[] census(int[] image,int w,int h) {
        int[] result=new int[image.length];
        for(int y=0; y<h; y++)for(int x=0; x<w; x++) {
            int code=0;
            for(int dy=-2; dy<=2; dy++)for(int dx=-2; dx<=2; dx++)if(dx!=0||dy!=0)code=(code<<1)|(at(image,w,h,x+dx,y+dy)<image[y*w+x]?1:0);
            result[y*w+x]=code;
        }
        return result;
    }
    static long[] texture(int[] image,int w,int h,int window) {
        long[] gradient=new long[image.length];
        for(int y=0; y<h; y++)for(int x=0; x<w; x++)gradient[y*w+x]=Math.abs(at(image,w,h,x+1,y)-at(image,w,h,x-1,y));
        return box(gradient,w,h,window);
    }
    static long[][] volume(int[] left,int[] right,int[] cl,int[] cr,int w,int h,String kind,int window,int min,int max) {
        long[][] volume=new long[left.length][max-min+1];
        for(int d=min; d<=max; d++) {
            long[] pixels=new long[left.length];
            for(int y=0; y<h; y++)for(int x=0; x<w; x++) {
                int p=y*w+x,q=y*w+Math.max(x-d,0),difference=left[p]-right[q];
                pixels[p]=kind.equals("census")?Integer.bitCount(cl[p]^cr[q]):kind.equals("sad")?Math.abs(difference):difference*difference;
            }
            long[] totals=box(pixels,w,h,window);
            for(int p=0; p<left.length; p++)volume[p][d-min]=totals[p];
        }
        return volume;
    }
}
