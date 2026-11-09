object Color {
    fun clamp(v: Int)=minOf(maxOf(v,0),255)
    fun toYcbcr(r: Int,g: Int,b: Int)=intArrayOf((19595*r+38470*g+7471*b+32768).floorDiv(65536),
        (-11059*r-21709*g+32768*b+8421375).floorDiv(65536),(32768*r-27439*g-5329*b+8421375).floorDiv(65536))
    fun toRgb(y: Int,cb: Int,cr: Int)=intArrayOf(clamp(y+(91881*(cr-128)+32768).floorDiv(65536)),
        clamp(y+(-22554*(cb-128)-46802*(cr-128)+32768).floorDiv(65536)),clamp(y+(116130*(cb-128)+32768).floorDiv(65536)))
    fun split(image: ImageIo.Image): Array<ImageIo.Plane> {
        val w=image.width;
        val h=image.height;
        val planes=Array(3) {
            ImageIo.Plane(w,h,IntArray(w*h))
        };
        for(p in 0 until w*h) {
            val pixel=toYcbcr(image.pixels[3*p],image.pixels[3*p+1],image.pixels[3*p+2]);
            for(k in 0..2)planes[k].pixels[p]=pixel[k]
        };
        return planes
    }
    fun components(planes: Array<ImageIo.Plane>,factors: Array<IntArray>,mx: Int,my: Int): Array<ImageIo.Plane> {
        var hmax=1;
        var vmax=1;
        for(f in factors) {
            hmax=maxOf(hmax,f[0]);
            vmax=maxOf(vmax,f[1])
        };
        return Array(3) {
            k->val source=planes[k];
            val fx=hmax/factors[k][0];
            val fy=vmax/factors[k][1];
            val w=8*factors[k][0]*mx;
            val h=8*factors[k][1]*my;
            val data=IntArray(w*h);
            for(y in 0 until h)for(x in 0 until w) {
                var sum=0;
                for(j in 0 until fy)for(i in 0 until fx)sum+=source.pixels[minOf(fy*y+j,source.height-1)*source.width+minOf(fx*x+i,source.width-1)];
                data[y*w+x]=sum/(fx*fy)
            };
            ImageIo.Plane(w,h,data)
        }
    }
    fun upsample(planes: Array<ImageIo.Plane>,factors: Array<IntArray>,w: Int,h: Int): Array<ImageIo.Plane> {
        var hmax=1;
        var vmax=1;
        for(f in factors) {
            hmax=maxOf(hmax,f[0]);
            vmax=maxOf(vmax,f[1])
        };
        return Array(3) {
            k->val pixels=IntArray(w*h);
            for(y in 0 until h)for(x in 0 until w)pixels[y*w+x]=planes[k].pixels[(y*factors[k][1]/vmax)*planes[k].width+x*factors[k][0]/hmax];
            ImageIo.Plane(w,h,pixels)
        }
    }
    fun combine(planes: Array<ImageIo.Plane>): ImageIo.Image {
        val w=planes[0].width;
        val h=planes[0].height;
        val image=IntArray(3*w*h);
        for(p in 0 until w*h)toRgb(planes[0].pixels[p],planes[1].pixels[p],planes[2].pixels[p]).copyInto(image,3*p);
        return ImageIo.Image(w,h,image)
    }
}
