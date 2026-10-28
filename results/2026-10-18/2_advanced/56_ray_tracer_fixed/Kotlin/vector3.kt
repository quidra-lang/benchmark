data class Vector3(val x: Long,val y: Long,val z: Long) {
    fun add(v: Vector3)=Vector3(x+v.x,y+v.y,z+v.z)
    fun subtract(v: Vector3)=Vector3(x-v.x,y-v.y,z-v.z)
    fun negate()=Vector3(-x,-y,-z)
    fun dot(v: Vector3)=FixedPoint.divide(x*v.x+y*v.y+z*v.z,FixedPoint.S)
    fun scale(k: Long)=Vector3(FixedPoint.multiply(x,k),FixedPoint.multiply(y,k),FixedPoint.multiply(z,k))
    fun length()=FixedPoint.isqrt(x*x+y*y+z*z)
    fun normalize(): Vector3 {
        val l=length();
        return Vector3(FixedPoint.divide(x*FixedPoint.S,l),FixedPoint.divide(y*FixedPoint.S,l),FixedPoint.divide(z*FixedPoint.S,l))
    }
    fun coordinate(axis: Int)=if(axis==0)x else if(axis==1)y else z
    override fun toString()="$x $y $z"
    companion object {
        fun axis(axis: Int,value: Long)=Vector3(if(axis==0)value else 0,if(axis==1)value else 0,if(axis==2)value else 0)
    }
}
