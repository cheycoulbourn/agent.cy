import os, re, sys, json, collections

SC = "/private/tmp/claude-501/-Users-cheycoulbourn-Documents-Agent-cy-App/f4f952ec-713d-4fbe-a094-33299db34639/scratchpad/L4"
decls = json.load(open(SC + "/decls.json"))

ROOT = "/Users/cheycoulbourn/Documents/Agent.cy App"
# All source we consider "references": swift + project.yml + xcassets json + entitlements etc
srcfiles = []
for base in ["ios/AgentCy", "ios/AgentCyShared", "ios/AgentCyWidgets", "ios/AgentCyInspirationShare", "ios/AgentCyTests", "ios/AgentCyMac"]:
    for dp, dn, fn in os.walk(os.path.join(ROOT, base)):
        p = dp.split(os.sep)
        if "build" in p or "build-device" in p: continue
        for f in fn:
            if f.endswith((".swift", ".plist", ".entitlements", ".json", ".intentdefinition", ".strings")):
                srcfiles.append(os.path.join(dp, f))
srcfiles.append(os.path.join(ROOT, "ios/project.yml"))

# token index: name -> list of (file, line)
occ = collections.defaultdict(list)
tok = re.compile(r'[A-Za-z_][A-Za-z0-9_]*')
for f in srcfiles:
    try: text = open(f, encoding="utf-8", errors="replace").read()
    except Exception: continue
    for i, line in enumerate(text.split("\n"), 1):
        for m in set(tok.findall(line)):
            occ[m].append((f, i))

results = []
for d in decls:
    name = d["name"]
    hits = occ.get(name, [])
    others = [(f, l) for (f, l) in hits if not (f == d["file"] and l == d["line"])]
    d2 = dict(d); d2["refs"] = len(others)
    d2["refsites"] = others[:6]
    results.append(d2)

json.dump(results, open(SC + "/refs.json", "w"))
zero = [r for r in results if r["refs"] == 0]
print("total decls:", len(results), "zero-ref:", len(zero))
bykind = collections.Counter(r["kind"] for r in zero)
print(bykind)
