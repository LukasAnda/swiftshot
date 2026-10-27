package swiftshot.android

import java.io.File
import java.util.Locale

/** screenshots.html: the shots by language and device, each linking to its PNG. */
object Gallery {
    fun write(output: File, shots: List<Map<String, Any?>>, seconds: Double) {
        fun esc(s: String) = s.replace("&", "&amp;").replace("<", "&lt;").replace("\"", "&quot;")
        val body = StringBuilder()
        for ((lang, group) in shots.groupBy { it["language"] as String }.toSortedMap()) {
            body.append("<h2>${esc(lang)}</h2>\n")
            for ((device, row) in group.groupBy { it["device"] as String }.toSortedMap()) {
                body.append("<h3>${esc(device)}</h3><div class=row>\n")
                for (s in row) {
                    val src = (s["file"] as String).split('/').joinToString("/") { java.net.URLEncoder.encode(it, "UTF-8").replace("+", "%20") }
                    body.append("<figure><a href=\"$src\"><img loading=lazy src=\"$src\"></a><figcaption>${esc(s["preview"] as String)} · ${s["appearance"]} · ${s["width"]}×${s["height"]}</figcaption></figure>\n")
                }
                body.append("</div>\n")
            }
        }
        File(output, "screenshots.html").writeText(
            """
            <!doctype html><meta charset=utf-8><title>Screenshots</title>
            <style>body{font:14px system-ui,sans-serif;margin:24px;background:#f5f5f7;color:#1d1d1f}
            .row{display:flex;flex-wrap:wrap;gap:16px}figure{margin:0;width:220px}img{width:100%;border-radius:12px;box-shadow:0 2px 8px #0002;background:#fff}
            figcaption{font-size:12px;color:#555;margin-top:6px}h3{font-weight:500;color:#444}
            @media (prefers-color-scheme:dark){body{background:#111;color:#eee}figcaption,h3{color:#aaa}}</style>
            <h1>${shots.size} screenshots · ${"%.1f".format(Locale.ROOT, seconds)}s</h1>
            """.trimIndent() + "\n" + body
        )
    }
}
