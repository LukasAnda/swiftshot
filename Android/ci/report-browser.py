#!/usr/bin/env python3
"""index.html in a real browser, from file://, on the golden fixtures. No network, no timed waits: Chrome's
--dump-dom returns the DOM after the load event, and the page renders synchronously.

Each report is checked twice:
- as written: rows, groups, images that exist, nothing injected by a hostile id (its CSP is in force);
- a copy with a test script added (only its script-src relaxed): keys, filters, ticks, the slider and the accept text,
  which goes through a real shell. (The accept recipe's reading of the comment is tested by bin/check-recipes.)

Android/ci/report-browser.py        CHROME=<path> names the browser; the default looks on PATH.
"""
import base64
import hashlib
import html.parser
import json
import os
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile
import urllib.parse

ROOT = pathlib.Path(__file__).resolve().parents[2] / "Shared/testdata/baseline"
GROUPS = [("error", "Errors"), ("changed", "Changed"), ("added", "Added"), ("removed", "Removed")]
failures = []


def check(ok, what):
    if not ok:
        failures.append(what)
        print("FAIL:", what)


def chrome():
    names = [os.environ.get("CHROME"), "google-chrome", "google-chrome-stable", "chromium", "chromium-browser",
             "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"]
    for name in names:
        path = name and shutil.which(name)
        if path:
            return path
    sys.exit("No Chrome found; set CHROME")


class Dom(html.parser.HTMLParser):
    """Every element as (tag, attrs, text directly inside it), plus each script's text."""

    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.elements, self.stack = [], []

    def handle_starttag(self, tag, attrs):
        e = {"tag": tag, "attrs": dict(attrs), "text": ""}
        self.elements.append(e)
        if tag not in ("meta", "img", "input", "br", "link", "hr"):
            self.stack.append(e)

    def handle_endtag(self, tag):
        while self.stack and self.stack.pop()["tag"] != tag:
            pass

    def handle_data(self, data):
        if self.stack:
            self.stack[-1]["text"] += data

    def all(self, tag=None, **attrs):
        return [e for e in self.elements if (tag is None or e["tag"] == tag) and all(e["attrs"].get(k) == v for k, v in attrs.items())]


def dump(browser, page, profile):
    out = subprocess.run([browser, "--headless=new", "--disable-gpu", "--no-sandbox", "--no-first-run", "--user-data-dir=" + profile,
                          "--dump-dom", page.as_uri()], capture_output=True, timeout=180, check=True)
    dom = Dom()
    dom.feed(out.stdout.decode("utf-8"))
    return dom


def as_written(browser, name, profile):
    """Rows, groups, images, nothing injected."""
    case = ROOT / name / "expected"
    result_text = (case / "result.json").read_text(encoding="utf-8")
    result = json.loads(result_text)
    dom = dump(browser, case / "index.html", profile)
    entries = result["screenshots"]
    want = [(s, t) for s, t in GROUPS if any(e["status"] == s for e in entries)]
    titles = [e["text"] for e in dom.all("h2")]
    check(titles == ["%s (%d)" % (t, sum(1 for e in entries if e["status"] == s)) for s, t in want], "%s: groups %s" % (name, titles))
    for s, _ in want:
        rows = [e for e in dom.elements if e["attrs"].get("data-status") == s]
        check(len(rows) == sum(1 for e in entries if e["status"] == s), "%s: %s rows" % (name, s))
    check(not [e for e in dom.elements if e["attrs"].get("data-status") == "unchanged"], "%s: unchanged rows before the toggle" % name)
    ticks = sum(1 for e in entries if e["status"] in ("changed", "added", "removed") and "," not in e["id"])
    check(len(dom.all("input", type="checkbox")) == ticks + 1, "%s: checkboxes (one is the unchanged toggle)" % name)
    # Nothing injected: no handlers, no extra scripts or foreign elements, the data block intact.
    for e in dom.elements:
        check(not [k for k in e["attrs"] if k.startswith("on")], "%s: handler on %s" % (name, e))
        check(e["tag"] in ALLOWED, "%s: unexpected element <%s>" % (name, e["tag"]))
    scripts = dom.all("script")
    check(len(scripts) == 2, "%s: %d scripts" % (name, len(scripts)))
    check(dom.all("script", id="data")[0]["text"] == result_text.replace("<", "\\u003c"), "%s: the data block is not result.json" % name)
    # Every image exists and is one this entry may have.
    allowed = {e[k] for e in entries for k in ("baseline", "new", "diff") if k in e}
    for img in dom.all("img"):
        path = urllib.parse.unquote(img["attrs"]["src"])
        check(path in allowed, "%s: image %s is not in result.json" % (name, path))
        check((case / path).is_file(), "%s: image %s does not exist" % (name, path))
    check(bool(dom.all("h1", id="verdict")[0]["text"]), "%s: no verdict" % name)
    # The policy is exactly this, with the hashes of the page's own style and script, as the browser has it.
    source = (case / "index.html").read_text(encoding="utf-8")
    style = re.search(r"<style>(.*?)</style>", source, re.S).group(1)
    script = re.search(r"<script>(.*?)</script>", source, re.S).group(1)
    want_csp = ("default-src 'none'; img-src 'self' file:; style-src '%s'; script-src '%s'; base-uri 'none'; form-action 'none'"
                % (sha256(style), sha256(script)))
    metas = dom.all("meta", **{"http-equiv": "Content-Security-Policy"})
    check(len(metas) == 1 and metas[0]["attrs"].get("content") == want_csp, "%s: CSP %s, want %s" % (name, [m["attrs"].get("content") for m in metas], want_csp))
    # The Pixels the page shows are the ones summary.md shows.
    summary = case / "summary.md"
    if summary.is_file():
        cells = [m.group(1).replace("\\>", ">") for m in (re.match(r"\| changed \| `.*` \| (\S+) \|$", line) for line in summary.read_text(encoding="utf-8").splitlines()) if m]
        shown = [m.group(1) if m else None for m in (re.search(r"\(([^)]*)\)", text) for text in row_pixels(dom))]
        check(shown == cells, "%s: Pixels on the page %s, in summary.md %s" % (name, shown, cells))
    return dom, result


def sha256(text):
    return "sha256-" + base64.b64encode(hashlib.sha256(text.encode("utf-8")).digest()).decode("ascii")


def row_pixels(dom):
    """The .px text of each changed row of the list, in order."""
    out, status = [], None
    for e in dom.elements:
        if e["attrs"].get("id") == "stagewrap":
            break
        if e["attrs"].get("class") == "row":
            status = e["attrs"].get("data-status")
        elif e["attrs"].get("class") == "px" and status == "changed":
            out.append(e["text"])
    return out


ALLOWED = {"html", "head", "meta", "title", "style", "body", "div", "header", "h1", "h2", "h3", "span", "select", "option", "label", "input",
           "main", "nav", "button", "strong", "pre", "script", "img", "figure", "figcaption", "code", "a", "p"}

# Runs right after the page's own script; every step is synchronous.
TEST_SCRIPT = r"""
<script>
(function(){
 const $=q=>document.querySelector(q),$$=q=>[...document.querySelectorAll(q)],out={};
 const rows=()=>$$(".row"),key=k=>document.body.dispatchEvent(new KeyboardEvent("keydown",{key:k,bubbles:true}));
 const current=()=>{const r=$('.row[aria-current="true"]');return r?r.querySelector(".name").textContent:null};
 const click=e=>e.click();
 out.first=current();
 out.side=$$("#stage img").map(i=>i.getAttribute("src"));
 out.mark=(()=>{const m=$("#stage .mark");return m?[m.style.left,m.style.top,m.style.width,m.style.height]:null})();
 key("3");out.diff=$$("#stage img").map(i=>i.getAttribute("src"));out.pressed=$('#modes [aria-pressed="true"]').textContent;
 key("2");out.slider=!!$("#stage input[type=range]");
 key("1");
 const before=rows();
 key("j");out.afterJ=current();key("k");out.afterK=current();
 out.sameRows=before.every((r,i)=>r===rows()[i]);
 const boxes=()=>$$("#list input[type=checkbox]");
 out.boxes=boxes().length;
 out.empty=$("#cmd").textContent;
 click(boxes()[0]);out.one=$("#cmd").textContent;out.count=$("#count").textContent;
 if(boxes()[1]){click(boxes()[1]);out.two=$("#cmd").textContent}
 const device=$("#fDevice");
 if(!device.hidden){device.value=device.options[device.options.length-1].value;device.dispatchEvent(new Event("change"));out.filtered=rows().length;out.filteredCmd=$("#cmd").textContent;device.value="";device.dispatchEvent(new Event("change"))}
 out.keptTicks=boxes().filter(b=>b.checked).length;
 click($("#tickall"));out.allButton=$("#cmd").textContent;out.allCount=$("#count").textContent;
 click($("#tickall"));
 const show=$("#showAll");
 if(!$("#showAllLabel").hidden){click(show);const u=$$('.row[data-status="unchanged"]');out.unchanged=u.length;out.unchangedImgs=u.reduce((n,r)=>n+r.querySelectorAll("img").length,0);click(u[0]);out.unchangedStage=$("#stage").textContent;click(show)}
 const err=$('.row[data-status="error"]');
 if(err){click(err);out.errorStage=$("#stage pre").textContent;out.errorBoxes=err.querySelectorAll("input").length}
 const added=$('.row[data-status="added"]');
 if(added){click(added);out.added=$$("#stage img").map(i=>i.getAttribute("src"));out.addedModes=$("#modes").style.visibility}
 const removed=$('.row[data-status="removed"]');
 if(removed){click(removed);out.removed=$$("#stage img").map(i=>i.getAttribute("src"))}
 if(boxes().length){
  click(boxes()[0]);
  Object.defineProperty(navigator,"clipboard",{value:undefined,configurable:true});
  click($("#copy"));out.fallback=getSelection().toString()===$("#cmd").textContent&&$("#copy").textContent.startsWith("Selected");
 }
 const first=$('.row[data-status="changed"]');
 if(first){click(first);out.stageImages=$$("#stage img")}
 const pre=document.createElement("pre");pre.id="test-result";
 addEventListener("load",()=>{const imgs=out.stageImages||[];out.stageImages=imgs.map(i=>i.naturalWidth);pre.textContent=JSON.stringify(out);document.body.append(pre)});
})();
</script>
"""


DATA = re.compile(r'(<script type="application/json" id="data">)(.*?)(</script>)', re.S)


def small_script(body):
    """A test script that has `$`, `$$`, `key`, `click` and `out`, and prints `out` as JSON in #test-result."""
    return ("<script>(function(){const $=q=>document.querySelector(q),$$=q=>[...document.querySelectorAll(q)],out={};"
            "const key=k=>document.body.dispatchEvent(new KeyboardEvent('keydown',{key:k,bubbles:true})),click=e=>e.click();"
            "const change=(e,v)=>{e.value=v;e.dispatchEvent(new Event('change'))},boxes=()=>$$('#list input[type=checkbox]');"
            + body +
            ";const pre=document.createElement('pre');pre.id='test-result';"
            "addEventListener('load',()=>{pre.textContent=JSON.stringify(out);document.body.append(pre)})})();</script>")


# The size-change stage: sizes as shares of the canvas, the slider's clip and handle, in every mode.
SLIDER_SCRIPT = small_script("""
 const imgs=()=>$$('#stage img').map(i=>[i.style.width,i.style.height]);
 out.ar=$('#stage .shot').style.getPropertyValue('--ar');out.side=imgs();out.sideShots=$$('#stage .shot').length;
 key('2');out.slider=imgs();out.range=!!$('#stage input[type=range]');out.at50=[$('#stage .clip').style.clipPath,$('#stage .handle').style.left];
 const r=$('#stage input[type=range]');r.value='25';r.dispatchEvent(new Event('input'));
 out.at25=[$('#stage .clip').style.clipPath,$('#stage .handle').style.left];
 key('3');key('2');out.kept=[$('#stage .clip').style.clipPath,$('#stage .handle').style.left,$('#stage input[type=range]').value];
 key('3');out.diff=$$('#stage img').length
""")

# Tick all with a filter on: only what is shown.
FILTER_SCRIPT = small_script("""
 click(boxes()[0]);out.start=$('#count').textContent;out.startButton=$('#tickall').textContent;
 change($('#fStatus'),'added');
 out.shown=boxes().length;out.button=$('#tickall').textContent;out.kept=$('#count').textContent;
 click($('#tickall'));out.ticked=$('#count').textContent;out.checked=boxes().filter(b=>b.checked).length;out.buttonOn=$('#tickall').textContent;
 click($('#tickall'));out.unticked=$('#count').textContent;out.checkedOff=boxes().filter(b=>b.checked).length;out.buttonOff=$('#tickall').textContent;
 click($('#tickall'));change($('#fStatus'),'');
 out.all=boxes().filter(b=>b.checked).length;out.allButton=$('#tickall').textContent;out.allCount=$('#count').textContent
""")

# A very long selection: tick all, then read the tray.
LONG_SCRIPT = small_script("""
 out.button=$('#tickall').textContent;click($('#tickall'));out.cmd=$('#cmd').textContent;out.count=$('#count').textContent;
 out.px=$$('.row').map(r=>(r.querySelector('.px')||{textContent:''}).textContent).filter(t=>t.indexOf('>')>=0)
""")


def with_test_script(name, directory, ci=None, edit=None, script=None):
    """A copy of the report in `directory` with the test script; `ci`: result.json's ci in the copy (any value, also
    a dict with None in it); `edit(result)` may change the whole result first."""
    case = ROOT / name / "expected"
    target = pathlib.Path(directory)
    shutil.copytree(case, target)
    text = (target / "index.html").read_text(encoding="utf-8")
    text, n = re.subn(r"script-src '[^']*'", "script-src 'unsafe-inline'", text)
    assert n == 1
    if ci is not None or edit:
        result = json.loads(DATA.search(text).group(2))
        if ci is not None:
            assert result["ci"] is None
            result["ci"] = ci
        if edit:
            edit(result)
        data = json.dumps(result, ensure_ascii=False).replace("<", "\\u003c")
        text = DATA.sub(lambda m: m.group(1) + data + m.group(3), text, count=1)
    text = text.replace("</body>", (script or TEST_SCRIPT) + "</body>", 1)
    (target / "index.html").write_text(text, encoding="utf-8")
    return target / "index.html"


def result_of(dom):
    found = dom.all("pre", id="test-result")
    check(bool(found), "the test script did not finish")
    return json.loads(found[0]["text"]) if found else {}


def shell_args(command):
    """What a real shell passes for `command`, and proof that nothing in it ran."""
    with tempfile.TemporaryDirectory() as cwd:
        # On stdin: a long command is not one argument of bash, which Linux limits to 128 KiB.
        script = 'swiftshot() { printf "%s\\0" "$@"; }; ' + command
        out = subprocess.run(["bash", "-s"], input=script.encode("utf-8"), capture_output=True, cwd=cwd, check=True)
        check(os.listdir(cwd) == [], "the command ran something: %s" % command)
    return out.stdout.decode("utf-8").split("\0")[:-1]


def behaviour(browser, profile, tmp):
    case = ROOT / "hostile-ids/expected"
    result = json.loads((case / "result.json").read_text(encoding="utf-8"))
    entries = result["screenshots"]
    order = [e for s, _ in GROUPS for e in entries if e["status"] == s]
    ticks = [e["id"] for e in order if e["status"] in ("changed", "added", "removed") and "," not in e["id"]]

    # No CI: the command, in a directory that itself needs quoting.
    directory = pathlib.Path(tmp) / "a report's dir $x"
    page = with_test_script("hostile-ids", directory)
    r = result_of(dump(browser, page, profile))
    xss = next(e for e in entries if "onerror=alert(1)" in e["id"] and e["status"] == "changed")
    check(r["first"] == xss["preview"], "starts on the first changed row: %s" % r["first"])
    check(r["side"] == [urllib.parse.quote(xss["baseline"], safe="/()*!'~"), urllib.parse.quote(xss["new"], safe="/()*!'~")], "side by side: %s" % r["side"])
    check(r["mark"] == ["8.8%", "9.4%", "17.4%", "8.7%"], "corner marks: %s" % r["mark"])
    check(r["diff"] == [urllib.parse.quote(xss["diff"], safe="/()*!'~")] and r["pressed"] == "Differences", "key 3: %s" % r["diff"])
    check(r["slider"], "key 2 shows the slider")
    check(r["afterJ"] != r["first"] and r["afterK"] == r["first"], "j and k: %s, %s" % (r["afterJ"], r["afterK"]))
    check(r["sameRows"], "j and k rebuilt the rows")
    check(r["boxes"] == len(ticks), "checkboxes %d, want %d" % (r["boxes"], len(ticks)))
    check("command to run" in r["empty"], "tray prompt: %s" % r["empty"])
    args = shell_args(r["one"])
    check(args == ["accept", "--from", str(directory), "--only", ticks[0]], "one tick: %s" % args)
    args = shell_args(r["two"])
    check(args == ["accept", "--from", str(directory), "--only", ",".join(ticks[:2])], "two ticks: %s" % args)
    check(r["count"] == "Accept 1 of %d" % len(ticks), r["count"])
    check(r["keptTicks"] == 2, "a filter changed the ticks: %s" % r["keptTicks"])
    check(r["filteredCmd"] == r["two"], "a filter changed the tray")
    check(r["filtered"] < len(order), "the device filter hides rows")
    # Everything that can be ticked is ticked, but the row with a comma isn't: the ids are still named.
    args = shell_args(r["allButton"])
    check(args == ["accept", "--from", str(directory), "--only", ",".join(ticks)], "tick all with a row that can't be ticked: %s" % args)
    check(r["unchanged"] == 1 and r["unchangedImgs"] == 0 and "Same as the baseline" in r["unchangedStage"], "unchanged: %s" % r)
    check(r["errorStage"] == next(e["message"] for e in order if e["status"] == "error") and r["errorBoxes"] == 0, "error stage: %s" % r["errorStage"])
    check(len(r["added"]) == 1 and r["added"][0].startswith("images/new/") and r["addedModes"] == "hidden", "added: %s" % r["added"])
    check(len(r["removed"]) == 1 and r["removed"][0].startswith("images/baseline/"), "removed: %s" % r["removed"])
    check(r["fallback"], "without navigator.clipboard the text is selected")
    check(r["stageImages"] == [40, 40], "the stage's images loaded under the CSP: %s" % r["stageImages"])

    # GitHub on a pull request: the comment names the commit on its first line, then the ids one per line.
    commit = result["commit"]
    page = with_test_script("hostile-ids", pathlib.Path(tmp) / "github", ci={"buildUrl": "https://example.com/run/1", "provider": "github", "pullRequest": "7"})
    r = result_of(dump(browser, page, profile))
    check("comment to post" in r["empty"], "tray prompt: %s" % r["empty"])
    lines = [line.strip() for line in r["two"].split("\n")]
    check(lines == ["/swiftshot accept " + commit] + ticks[:2], "comment: %s" % lines)
    check(r["two"].startswith("/swiftshot accept"), "the recipe's trigger matches the comment")
    check([line.strip() for line in r["allButton"].split("\n")] == ["/swiftshot accept " + commit] + ticks, "comment, a row can't be ticked: %s" % r["allButton"])

    # GitHub without a pull request, or without a commit: nobody can comment, so the command is shown.
    for what, ci, edit in (("no pull request", {"buildUrl": None, "provider": "github", "pullRequest": None}, None),
                           ("no commit", {"buildUrl": None, "provider": "github", "pullRequest": "7"}, lambda x: x.update(commit=None)),
                           ("a commit that is not hex", {"buildUrl": None, "provider": "github", "pullRequest": "7"}, lambda x: x.update(commit="main; ls"))):
        page = with_test_script("hostile-ids", pathlib.Path(tmp) / ("gh " + what), ci=ci, edit=edit)
        r = result_of(dump(browser, page, profile))
        check("command to run" in r["empty"], "%s: tray prompt: %s" % (what, r["empty"]))
        check(shell_args(r["two"]) == ["accept", "--from", str(page.parent), "--only", ",".join(ticks[:2])], "%s: %s" % (what, r["two"]))

    # All rows can be ticked: the bare forms.
    page = with_test_script("added", pathlib.Path(tmp) / "bare")
    r = result_of(dump(browser, page, profile))
    check(shell_args(r["one"]) == ["accept", "--from", str(page.parent)], "all ticked needs no --only: %s" % r["one"])
    added = json.loads((ROOT / "added/expected/result.json").read_text(encoding="utf-8"))
    page = with_test_script("added", pathlib.Path(tmp) / "bare-github", ci={"buildUrl": None, "provider": "github", "pullRequest": "7"})
    r = result_of(dump(browser, page, profile))
    check(r["one"] == "/swiftshot accept " + added["commit"], "all ticked on GitHub: %s" % r["one"])

    # Tick all means the rows shown. One row is ticked first, outside the filter, and stays ticked.
    visible = sum(1 for e in entries if e["status"] == "added" and "," not in e["id"])
    check(0 < visible - 1 and visible < len(ticks) - 1, "the fixture can show the filter (%d of %d)" % (visible, len(ticks)))
    r = result_of(dump(browser, with_test_script("hostile-ids", pathlib.Path(tmp) / "filter", script=FILTER_SCRIPT), profile))
    check(r["start"] == "Accept 1 of %d" % len(ticks) and r["startButton"] == "Tick all %d" % len(ticks), "before the filter: %s, %s" % (r["start"], r["startButton"]))
    check(r["shown"] == visible and r["button"] == "Tick %d shown" % visible, "the button counts the shown rows: %s" % r["button"])
    check(r["kept"] == r["start"], "a filter changed what is ticked: %s" % r["kept"])
    check(r["ticked"] == "Accept %d of %d" % (visible + 1, len(ticks)) and r["checked"] == visible, "tick all with a filter: %s, %d boxes" % (r["ticked"], r["checked"]))
    check(r["buttonOn"] == "Untick %d shown" % visible, "button after: %s" % r["buttonOn"])
    check(r["unticked"] == r["start"] and r["checkedOff"] == 0 and r["buttonOff"] == r["button"], "untick the shown rows only: %s, %s" % (r["unticked"], r["buttonOff"]))
    check(r["all"] == visible + 1 and r["allCount"] == "Accept %d of %d" % (visible + 1, len(ticks)), "filter cleared: %d ticked" % r["all"])
    check(r["allButton"] == "Tick all %d" % len(ticks), "button without a filter: %s" % r["allButton"])

    # The size-change stage and the slider, against result.json.
    case = json.loads((ROOT / "changed-size/expected/result.json").read_text(encoding="utf-8"))
    e = next(x for x in case["screenshots"] if x["status"] == "changed")
    canvas, base, new = e["canvasSize"], e["baselineSize"], e["newSize"]
    check(base != new, "the fixture changes size")
    r = result_of(dump(browser, with_test_script("changed-size", pathlib.Path(tmp) / "slider", script=SLIDER_SCRIPT), profile))

    def share(size):
        return [size[0] / canvas[0] * 100, size[1] / canvas[1] * 100]

    def near(got, want):
        return len(got) == len(want) and all(abs(float(g.rstrip("%")) - w) < 1e-3 for g, w in zip(got, want))
    check(r["ar"].replace(" ", "") == "%d/%d" % tuple(canvas), "canvas aspect ratio: %s" % r["ar"])
    for mode in ("side", "slider"):
        sizes = r[mode]
        check(len(sizes) == 2 and near(sizes[0], share(base)) and near(sizes[1], share(new)), "%s: image sizes %s, want %s and %s" % (mode, sizes, share(base), share(new)))
    check(r["sideShots"] == 2, "two canvases side by side: %s" % r["sideShots"])
    check(r["range"] and "50%" in r["at50"][0] and r["at50"][1] == "50%", "slider at the middle: %s" % r["at50"])
    check("25%" in r["at25"][0] and r["at25"][1] == "25%", "slider moved: %s" % r["at25"])
    check("25%" in r["kept"][0] and r["kept"][1] == "25%" and float(r["kept"][2]) == 25, "slider position kept across modes: %s" % r["kept"])
    check(r["diff"] == 1, "one diff image: %s" % r["diff"])

    # A long selection: --only is split below the 128 KiB a Linux argument can hold; far too long warns.
    def synthetic(n):
        def edit(x):
            x["screenshots"] = [{"id": "en-US/Pixel 9-%s-%05d" % ("x" * 60, i), "status": "changed", "reason": "pixels", "pixels": 1 + i % 7, "canvasSize": [40, 80]} for i in range(n)]
            x["screenshots"] += [{"id": "has,comma", "status": "changed", "reason": "pixels", "pixels": 1, "canvasSize": [40, 80]},
                                 {"id": "en-US/Pixel 9-almost-all", "status": "changed", "reason": "pixels", "pixels": 1999, "canvasSize": [40, 50]}]
            x["counts"] = dict(x["counts"], changed=len(x["screenshots"]))
        return edit
    r = result_of(dump(browser, with_test_script("hostile-ids", pathlib.Path(tmp) / "long", edit=synthetic(3000), script=LONG_SCRIPT), profile))
    ids = ["en-US/Pixel 9-%s-%05d" % ("x" * 60, i) for i in range(3000)] + ["en-US/Pixel 9-almost-all"]
    args = shell_args(r["cmd"])
    only = [a for k, a in zip(args, args[1:]) if k == "--only"]
    check(args[:3] == ["accept", "--from", str(pathlib.Path(tmp) / "long")] and args.count("--only") == len(only) and len(args) == 3 + 2 * len(only), "long command shape: %s" % args[:6])
    check(len(only) >= 2 and all(len(a.encode("utf-8")) <= 100000 for a in only), "long list split into %d --only, sizes %s" % (len(only), [len(a) for a in only]))
    check(",".join(only).split(",") == ids, "the split lists name every id once, in order")
    check("too long" not in r["count"], "no warning for %d bytes: %s" % (len(r["cmd"]), r["count"]))
    check(any(">99.9%" in x for x in r["px"]), "1999 of 2000 pixels reads >99.9%%: %s" % r["px"])
    r = result_of(dump(browser, with_test_script("hostile-ids", pathlib.Path(tmp) / "huge", edit=synthetic(8000), script=LONG_SCRIPT), profile))
    check(len(r["cmd"].encode("utf-8")) > 400000 and "too long to run as one command" in r["count"], "the warning for %d bytes: %s" % (len(r["cmd"]), r["count"]))


def main():
    browser = chrome()
    with tempfile.TemporaryDirectory() as tmp:
        tmp = os.path.realpath(tmp)
        profile = os.path.join(tmp, "profile")
        names = sorted(p.parents[1].name for p in ROOT.glob("*/expected/index.html"))
        check(len(names) == 28, "%d reports" % len(names))
        for name in names:
            if name != "summary-truncation":  # 300 rows of the same; covered by the others
                as_written(browser, name, profile)
        dom, _ = as_written(browser, "hostile-run-error", profile)
        check(any("onerror=alert(8)" in e["text"] for e in dom.all("div") if e["attrs"].get("class") == "note bad"), "the error without id is shown as text")
        dom, _ = as_written(browser, "unchanged", profile)
        check("match the baseline" in dom.all("h1", id="verdict")[0]["text"], "a passing run says so")
        check(not dom.all("div", id="tray") or "hidden" in dom.all("div", id="tray")[0]["attrs"], "a passing run has no tray")
        dom, _ = as_written(browser, "ci-github", profile)
        check(any(e["attrs"].get("href") == "https://github.com/acme/app/actions/runs/9876543210" for e in dom.all("a")), "the build link")
        behaviour(browser, profile, tmp)
    print("index.html in a browser: %s" % ("FAILED" if failures else "ok"))
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
