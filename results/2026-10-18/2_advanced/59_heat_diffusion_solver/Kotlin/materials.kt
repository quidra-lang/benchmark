import java.io.File

object Materials {
    data class Material(val code: Char,val name: String,val k: Double,val rho: Double,val cp: Double)
    fun read()=File("input/materials.txt").readLines().map {
        line->val w=line.split(' ');
        Material(w[0][0],w[1],w[2].toDouble(),w[3].toDouble(),w[4].toDouble())
    }
    fun capacity(m: Material,dx: Double,d: Double)=m.rho*m.cp*dx*dx*d
    fun interior(k1: Double,k2: Double,d: Double)=2*k1*k2/(k1+k2)*d
    fun fixedFace(k: Double,d: Double)=2*k*d
    fun convective(k: Double,h: Double,dx: Double,d: Double)=1/(1/(h*dx*d)+1/(2*k*d))
}
