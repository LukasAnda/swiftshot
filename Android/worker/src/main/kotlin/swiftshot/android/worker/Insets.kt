package swiftshot.android.worker

import android.view.InsetsController
import android.view.InsetsState
import android.view.WindowRelayoutResult
import net.bytebuddy.ByteBuddy
import net.bytebuddy.agent.ByteBuddyAgent
import net.bytebuddy.asm.Advice
import net.bytebuddy.description.method.MethodDescription
import net.bytebuddy.dynamic.ClassFileLocator
import net.bytebuddy.matcher.ElementMatchers.named
import net.bytebuddy.pool.TypePool
import java.lang.instrument.ClassFileTransformer
import java.security.ProtectionDomain

/**
 * Window insets as a device reports them. Layoutlib registers its status and navigation bars as
 * inset sources when a session inflates, but its window session answers every `relayout` with an
 * empty InsetsState, and the real ViewRootImpl applies that state, wiping the bars again. Compose
 * then sees no insets: `safeDrawingPadding()` does nothing and bottom bars sit under the gesture
 * handle. This keeps the sources layoutlib set up and hands them back on every relayout.
 */
object Insets {
    @Volatile @JvmStatic var state: InsetsState? = null

    private val targets = mapOf(
        "com/android/layoutlib/bridge/util/InsetUtil" to ("setupSysUiInsets" to SetupAdvice::class.java),
        "com/android/layoutlib/bridge/impl/BridgeWindowSession" to ("relayout" to RelayoutAdvice::class.java),
    )
    private var installed = false

    /** Call after Paparazzi's setup(), before the first session: chains after its own patches. */
    fun install() {
        if (installed) return
        installed = true
        ByteBuddyAgent.install().addTransformer(object : ClassFileTransformer {
            override fun transform(loader: ClassLoader?, className: String?, redefined: Class<*>?, domain: ProtectionDomain?, buffer: ByteArray): ByteArray? {
                val (method, advice) = targets[className] ?: return null
                return try {
                    val name = className!!.replace('/', '.')
                    val locator = ClassFileLocator.Compound(
                        ClassFileLocator.Simple.of(name, buffer),
                        if (loader == null) ClassFileLocator.ForClassLoader.ofSystemLoader() else ClassFileLocator.ForClassLoader.of(loader),
                    )
                    val type = TypePool.Default.of(locator).describe(name).resolve()
                    ByteBuddy().redefine<Any>(type, locator)
                        .visit(Advice.to(advice).on(named<MethodDescription>(method)))
                        .make().bytes
                } catch (t: Throwable) {
                    System.err.println("swiftshot: could not patch $className: $t")
                    null
                }
            }
        }, false)
    }

    @JvmStatic fun remember(controller: InsetsController?) {
        val s = controller?.state ?: return
        state = InsetsState(s, true)
    }

    /** Insets of a device's system bars, for sessions rendered without layoutlib's decor. */
    @Volatile @JvmStatic var synthetic: IntArray? = null  // width, height, statusTop, navBottom

    @JvmStatic fun fill(result: WindowRelayoutResult?) {
        result ?: return
        val bars = synthetic
        if (bars != null) {
            val (w, h, top, bottom) = bars.toList()
            val s = InsetsState()
            s.setDisplayFrame(android.graphics.Rect(0, 0, w, h))
            s.getOrCreateSource(STATUS_ID, android.view.WindowInsets.Type.statusBars()).setFrame(0, 0, w, top)
            s.getOrCreateSource(NAV_ID, android.view.WindowInsets.Type.navigationBars()).setFrame(0, h - bottom, w, h)
            s.getOrCreateSource(GESTURE_ID, android.view.WindowInsets.Type.mandatorySystemGestures()).setFrame(0, h - bottom, w, h)
            result.insetsState.set(s, true)
            return
        }
        val s = state ?: return
        result.insetsState.set(s, true)
    }

    private const val STATUS_ID = 0x5357_0001
    private const val NAV_ID = 0x5357_0002
    private const val GESTURE_ID = 0x5357_0003

    object SetupAdvice {
        @JvmStatic
        @Advice.OnMethodExit
        fun exit(@Advice.Argument(1) controller: InsetsController?) = remember(controller)
    }

    object RelayoutAdvice {
        @JvmStatic
        @Advice.OnMethodExit
        fun exit(@Advice.Argument(8) result: WindowRelayoutResult?) = fill(result)
    }
}
