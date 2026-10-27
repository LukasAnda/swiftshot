package swiftshot.android.worker

import android.view.View
import android.view.ViewGroup

/**
 * How far the preview's vertical scroll containers can still scroll, from Compose's semantics
 * (`verticalScroll`, LazyColumn and friends report a VerticalScrollAxisRange). Full-length
 * screenshots grow the screen by this much and render again until nothing scrolls. Reflection
 * keeps the worker independent of the app's Compose version.
 */
object Scroll {
    fun remaining(root: View): Int {
        var most = 0
        for (owner in composeViews(root)) {
            val semantics = runCatching { owner.javaClass.getMethod("getSemanticsOwner").invoke(owner) }.getOrNull() ?: continue
            val node = runCatching { semantics.javaClass.getMethod("getUnmergedRootSemanticsNode").invoke(semantics) }.getOrNull() ?: continue
            most = maxOf(most, walk(node))
        }
        return most
    }

    private val key: Any? by lazy {
        runCatching {
            val props = Class.forName("androidx.compose.ui.semantics.SemanticsProperties")
            val instance = props.getField("INSTANCE").get(null)
            props.getMethod("getVerticalScrollAxisRange").invoke(instance)
        }.getOrNull()
    }

    private fun walk(node: Any): Int {
        var most = 0
        runCatching {
            val config = node.javaClass.getMethod("getConfig").invoke(node)
            val k = key
            if (k != null && config.javaClass.methods.first { it.name == "contains" && it.parameterCount == 1 }.invoke(config, k) == true) {
                val range = config.javaClass.methods.first { it.name == "get" && it.parameterCount == 1 }.invoke(config, k)
                val value = (range.javaClass.getMethod("getValue").invoke(range) as Function0<*>).invoke() as Float
                val max = (range.javaClass.getMethod("getMaxValue").invoke(range) as Function0<*>).invoke() as Float
                if (max.isFinite() && max > value) most = (max - value).toInt()
            }
            @Suppress("UNCHECKED_CAST")
            val children = node.javaClass.methods.first { it.name == "getChildren" && it.parameterCount == 0 }.invoke(node) as List<Any>
            for (c in children) most = maxOf(most, walk(c))
        }
        return most
    }

    private fun composeViews(v: View): List<View> {
        val result = mutableListOf<View>()
        if (v.javaClass.name == "androidx.compose.ui.platform.AndroidComposeView") result += v
        if (v is ViewGroup) for (i in 0 until v.childCount) result += composeViews(v.getChildAt(i))
        return result
    }
}
