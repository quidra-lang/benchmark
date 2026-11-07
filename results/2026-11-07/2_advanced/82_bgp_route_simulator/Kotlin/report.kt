import java.io.File
object Report {
    fun path(path:List<Int>)=path.joinToString(",")
    fun attribute(attribute:Decision.Attribute)="path ${path(attribute.path)} origin ${attribute.origin} med ${attribute.med} comm ${Policy.communityText(attribute.communities)}"
    fun route(route:Decision.Route?):String {
        if(route==null)return "NONE";
        val comm=Policy.communityText(route.communities);
        if(route.local)return "LOCAL origin ${route.origin} comm $comm";
        return "next ${route.neighbor} path ${path(route.path)} link ${route.link!!.name} lp ${route.localPref} med ${route.med} origin ${route.origin} comm $comm"
    }
    fun write(name:String,lines:List<String>) {
        File("output").mkdirs();
        File("output",name).writeText(lines.joinToString("\n")+(if(lines.isEmpty())"" else "\n"),Charsets.US_ASCII)
    }
}
