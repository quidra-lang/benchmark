import java.io.File

object Ratings {
    data class Rating(val user: Int,val item: Int,val rating: Int,val time: Long)
    data class Item(val title: String,val genreText: String,val genres: List<String>)
    class Settings(val values: Map<String,List<String>>) {
        fun integer(key: String)=values.getValue(key)[0].toInt();
        fun number(key: String)=decimal(key,0);
        fun decimal(key: String,index: Int)=values.getValue(key)[index].toDouble();
        fun list(key: String)=values.getValue(key).map(String::toInt).toIntArray()
    }
    class Data(val training: List<Rating>,val test: List<Rating>,val users: List<Int>,val items: List<Int>,
        val userIndex: Map<Int,Int>,val itemIndex: Map<Int,Int>,val catalog: Map<Int,Item>,
        val settings: Settings,val ratings: Array<IntArray>,val byUser: List<List<Int>>,val byItem: List<List<Int>>,
        val userCounts: IntArray,val itemCounts: IntArray,val userMeans: DoubleArray,val itemMeans: DoubleArray,
        val mean: Double)
    fun lines(name: String)=File("input/$name").readLines(Charsets.US_ASCII)
    fun rows(name: String,training: Boolean)=lines(name).drop(1).map {
        val w=it.split(',');
        Rating(w[0].toInt(),w[1].toInt(),w[2].toInt(),if(training)w[3].toLong() else 0L)
    }
    fun read(): Data {
        val raw=rows("ratings.csv",true);
        val users=raw.map {
            it.user
        }.toSortedSet().toList();
        val items=raw.map {
            it.item
        }.toSortedSet().toList();
        val userIndex=users.withIndex().associate {
            it.value to it.index
        };
        val itemIndex=items.withIndex().associate {
            it.value to it.index
        };
        val training=raw.map {
            Rating(userIndex.getValue(it.user),itemIndex.getValue(it.item),it.rating,it.time)
        };
        val test=rows("test.csv",false).map {
            Rating(userIndex.getValue(it.user),itemIndex.getValue(it.item),it.rating,0L)
        };
        val ratings=Array(users.size) {
            IntArray(items.size)
        };
        var sum=0L;
        for(row in training) {
            ratings[row.user][row.item]=row.rating;
            sum+=row.rating
        };
        val byUser=users.indices.map {
            u->items.indices.filter {
                ratings[u][it]>0
            }
        };
        val byItem=items.indices.map {
            i->users.indices.filter {
                ratings[it][i]>0
            }
        };
        val userCounts=IntArray(users.size) {
            byUser[it].size
        };
        val itemCounts=IntArray(items.size) {
            byItem[it].size
        };
        val userMeans=DoubleArray(users.size) {
            u->var total=0;
            for(i in byUser[u])total+=ratings[u][i];
            total.toDouble()/userCounts[u]
        };
        val itemMeans=DoubleArray(items.size) {
            i->var total=0;
            for(u in byItem[i])total+=ratings[u][i];
            total.toDouble()/itemCounts[i]
        };
        val catalog=lines("items.csv").drop(1).associate {
            val w=it.split(',');
            w[0].toInt() to Item(w[1],w[2],w[2].split('|'))
        };
        val settings=Settings(lines("params.txt").associate {
            val w=it.split(' ');
            w[0] to w.drop(1)
        });
        return Data(training,test,users,items,userIndex,itemIndex,catalog,settings,ratings,
            byUser,byItem,userCounts,itemCounts,userMeans,itemMeans,sum.toDouble()/training.size)
    }
}
