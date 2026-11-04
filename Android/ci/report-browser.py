#!/usr/bin/env python3
"""index.html in a real browser, from file://, on the golden fixtures. No network, no timed waits: Chrome's
--dump-dom returns the DOM after the load event, and the page renders synchronously.

Each report is checked twice:
- as written: rows, groups, images that exist, nothing injected by a hostile id (its CSP is in force);
- a copy with a test script added (only its script-src relaxed): keys, filters, ticks and the accept text, which
  goes through a real shell or the accept recipe's parsing.

Android/ci/report-browser.py        CHROME=<path> names the browser; the default looks on PATH.
"""
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
    return dom, result


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


def with_test_script(name, directory, ci=None):
    """A copy of the report in `directory` with the test script; `ci`: result.json's ci in the copy."""
    case = ROOT / name / "expected"
    target = pathlib.Path(directory)
    shutil.copytree(case, target)
    text = (target / "index.html").read_text(encoding="utf-8")
    text, n = re.subn(r"script-src '[^']*'", "script-src 'unsafe-inline'", text)
    assert n == 1
    if ci:
        assert '"ci": null' in text
        text = text.replace('"ci": null', '"ci": ' + json.dumps(ci), 1)
    text = text.replace("</body>", TEST_SCRIPT + "</body>", 1)
    (target / "index.html").write_text(text, encoding="utf-8")
    return target / "index.html"


def result_of(dom):
    found = dom.all("pre", id="test-result")
    check(bool(found), "the test script did not finish")
    return json.loads(found[0]["text"]) if found else {}


def shell_args(command):
    """What a real shell passes for `command`, and proof that nothing in it ran."""
    with tempfile.TemporaryDirectory() as cwd:
        out = subprocess.run(["bash", "-c", 'swiftshot() { printf "%s\\0" "$@"; }; ' + command], capture_output=True, cwd=cwd, check=True)
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

    # GitHub: the comment, read as the accept recipe reads it (first line, then one id per line, trimmed).
    page = with_test_script("hostile-ids", pathlib.Path(tmp) / "github", ci={"buildUrl": "https://example.com/run/1", "provider": "github", "pullRequest": "7"})
    r = result_of(dump(browser, page, profile))
    check("comment to post" in r["empty"], "tray prompt: %s" % r["empty"])
    lines = [line.strip() for line in r["two"].split("\n")]
    check(lines == ["/swiftshot accept"] + ticks[:2], "comment: %s" % lines)
    check([line.strip() for line in r["allButton"].split("\n")] == ["/swiftshot accept"] + ticks, "comment, a row can't be ticked: %s" % r["allButton"])

    # All rows can be ticked: the bare forms.
    page = with_test_script("added", pathlib.Path(tmp) / "bare")
    r = result_of(dump(browser, page, profile))
    check(shell_args(r["one"]) == ["accept", "--from", str(page.parent)], "all ticked needs no --only: %s" % r["one"])
    page = with_test_script("added", pathlib.Path(tmp) / "bare-github", ci={"buildUrl": None, "provider": "github", "pullRequest": "7"})
    r = result_of(dump(browser, page, profile))
    check(r["one"] == "/swiftshot accept", "all ticked on GitHub: %s" % r["one"])


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
