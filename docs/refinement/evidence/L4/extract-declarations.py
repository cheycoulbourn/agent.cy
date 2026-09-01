import os, re, sys, json

ROOT = "/Users/cheycoulbourn/Documents/Agent.cy App/ios"
TARGET_DIRS = ["AgentCy", "AgentCyShared", "AgentCyWidgets", "AgentCyInspirationShare", "AgentCyTests"]

files = []
for d in TARGET_DIRS:
    for dirpath, dirnames, filenames in os.walk(os.path.join(ROOT, d)):
        parts = dirpath.split(os.sep)
        if "build" in parts or "build-device" in parts:
            continue
        for f in filenames:
            if f.endswith(".swift"):
                files.append(os.path.join(dirpath, f))
files.sort()

src = {f: open(f, encoding="utf-8", errors="replace").read() for f in files}

pat_type = re.compile(r'^\s*(?:@[\w.]+(?:\([^)]*\))?\s+)*(?:(?:public|private|fileprivate|internal|open|final|indirect|nonisolated)\s+)*\b(struct|class|enum|protocol|actor)\s+([A-Za-z_][A-Za-z0-9_]*)')
pat_ext = re.compile(r'^\s*(?:(?:public|private|fileprivate|internal)\s+)*\bextension\s+([A-Za-z_][A-Za-z0-9_.]*)')
pat_alias = re.compile(r'^\s*(?:(?:public|private|fileprivate|internal)\s+)*\btypealias\s+([A-Za-z_][A-Za-z0-9_]*)')
MODS = r'(?:(?:public|private(?:\(set\))?|fileprivate|internal|open|static|class|final|override|mutating|nonmutating|nonisolated(?:\(unsafe\))?|convenience|required|lazy|weak|unowned|dynamic|async|distributed)\s+)*'
pat_func = re.compile(r'^\s*(?:@[\w.]+(?:\([^)]*\))?\s+)*' + MODS + r'\bfunc\s+([A-Za-z_][A-Za-z0-9_]*)')
pat_init = re.compile(r'^\s*(?:@[\w.]+(?:\([^)]*\))?\s+)*' + MODS + r'\binit\b')
pat_var  = re.compile(r'^\s*(?:@[\w.]+(?:\([^)]*\))?\s+)*' + MODS + r'\b(?:var|let)\s+([A-Za-z_][A-Za-z0-9_]*)')
pat_case = re.compile(r'^\s*case\s+([a-z_][A-Za-z0-9_]*)\s*(?:\(|=|,|$)')

decls = []
for f in files:
    lines = src[f].split("\n")
    # scope stack of ('type'|'func'|'other', name)
    stack = []
    in_block_comment = False
    for i, raw in enumerate(lines, 1):
        line = raw
        stripped = line.strip()
        if in_block_comment:
            if "*/" in stripped: in_block_comment = False
            continue
        if stripped.startswith("/*"):
            if "*/" not in stripped: in_block_comment = True
            continue
        code = re.sub(r'//.*$', '', line)
        code_nostr = re.sub(r'"(?:\\.|[^"\\])*"', '""', code)
        kind_here = None; name_here = None
        if stripped and not stripped.startswith("//"):
            in_func = any(k == "func" for k, _ in stack)
            m = pat_type.match(code)
            if m:
                kind_here, name_here = m.group(1), m.group(2)
            elif pat_ext.match(code):
                kind_here, name_here = "extension", pat_ext.match(code).group(1)
            elif pat_alias.match(code):
                kind_here, name_here = "typealias", pat_alias.match(code).group(1)
            elif pat_func.match(code):
                kind_here, name_here = "func", pat_func.match(code).group(1)
            elif pat_init.match(code):
                kind_here, name_here = "init", "init"
            elif pat_case.match(code) and not in_func and any(k=="enum" for k,_ in stack):
                kind_here, name_here = "case", pat_case.match(code).group(1)
            elif pat_var.match(code):
                kind_here, name_here = "prop", pat_var.match(code).group(1)
            if kind_here and kind_here not in ("extension",) and not in_func:
                owner = next((n for k, n in reversed(stack) if k in ("struct","class","enum","protocol","actor","extension")), None)
                decls.append({"kind": kind_here, "name": name_here, "file": f, "line": i,
                              "owner": owner, "src": stripped[:200],
                              "scopedepth": len(stack)})
        opens = code_nostr.count("{"); closes = code_nostr.count("}")
        if opens:
            push_kind = kind_here if kind_here in ("struct","class","enum","protocol","actor","extension","func","init") else "other"
            stack.append((push_kind, name_here))
            for _ in range(opens - 1):
                stack.append(("other", None))
        for _ in range(closes):
            if stack: stack.pop()

json.dump(decls, open(sys.argv[1], "w"))
print("files:", len(files), "decls:", len(decls))
