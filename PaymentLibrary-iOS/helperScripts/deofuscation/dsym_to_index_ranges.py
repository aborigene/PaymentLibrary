#!/usr/bin/env python3
import argparse, json, re, sys, shutil, subprocess, threading
from functools import lru_cache

p = argparse.ArgumentParser()
p.add_argument('--di', required=True)       # output de: xcrun dwarfdump --debug-info (ou --all)
p.add_argument('--dr', required=True)       # output de: xcrun dwarfdump --debug-ranges (ou --all, contendo .debug_ranges)
p.add_argument('--uuid', required=True)
p.add_argument('--image', required=True)
p.add_argument('--arch', required=True)
p.add_argument('--mapping', required=False) # opcional: JSON { "obf":"Original.Name", ... }
p.add_argument('--swift-demangle', dest='do_demangle', action='store_true', help='Ativa demangle de nomes Swift via xcrun swift-demangle')
p.add_argument('--no-swift-demangle', dest='do_demangle', action='store_false', help='Desativa demangle de nomes Swift')
p.add_argument('--swift-demangle-bin', default='xcrun', help='Prefixo para chamar a ferramenta (default: xcrun)')
p.add_argument('--verbose', action='store_true')
p.set_defaults(do_demangle=True)
args = p.parse_args()

# --------------------------- util: log ----------------------------------------
def vlog(msg):
    if args.verbose:
        print(msg, file=sys.stderr)

# --------------------------- mapping opcional ---------------------------------
name_map = {}
if args.mapping:
    try:
        with open(args.mapping, 'r', encoding='utf-8') as f:
            name_map = json.load(f)
    except Exception as e:
        print(f"// WARN: failed to read mapping.json: {e}", file=sys.stderr)

# --------------------------- ranges (.debug_ranges) ---------------------------
ranges_map = {}
rx_dr = re.compile(r'^\s*([0-9a-fA-F]{4,})\s+([0-9A-Fa-fx]+)\s+([0-9A-Fa-fx]+)')
pairs = 0
with open(args.dr, 'r', encoding='utf-8', errors='ignore') as f:
    for raw in f:
        m = rx_dr.match(raw)
        if not m: 
            continue
        off = int(m.group(1),16)
        a,b = m.group(2).lower(), m.group(3).lower()
        if not a.startswith('0x'): a='0x'+a
        if not b.startswith('0x'): b='0x'+b
        s,e = int(a,16), int(b,16)
        if s==0 and e==0:
            continue
        ranges_map.setdefault(off, []).append((s,e))
        pairs += 1
vlog(f"[DR] offsets={len(ranges_map)} pairs={pairs}")

# --------------------------- parsers DIEs -------------------------------------
rx_any_tag  = re.compile(r'\b(DW_TAG_|TAG_)(\w+)')
rx_low      = re.compile(r'DW_AT_low_pc\s*\(\s*(?:addr:\s*)?0x([0-9a-fA-F]+)\s*\)')
rx_hia      = re.compile(r'DW_AT_high_pc\s*\(\s*(?:addr:\s*)?0x([0-9a-fA-F]+)\s*\)')
rx_hiud     = re.compile(r'DW_AT_high_pc\s*\(\s*udata:\s*([0-9]+)\s*\)')
rx_ranges   = re.compile(r'DW_AT_ranges\s*\(\s*0x([0-9a-fA-F]+)\s*\)')
rx_name     = re.compile(r'DW_AT_name\s*\("(.+?)"\)')
rx_link     = re.compile(r'DW_AT_linkage_name\s*\("(.+?)"\)')
rx_abs      = re.compile(r'DW_AT_abstract_origin\s*\(\s*0x([0-9a-fA-F]+)\s*\)')
rx_spec     = re.compile(r'DW_AT_specification\s*\(\s*0x([0-9a-fA-F]+)\s*\)')
rx_die_off  = re.compile(r'^\s*0x([0-9a-fA-F]+):')

dies = []
cur = None
with open(args.di, 'r', encoding='utf-8', errors='ignore') as f:
    for raw in f:
        line = raw.rstrip('\n')
        mtag = rx_any_tag.search(line)
        if mtag:
            if cur: dies.append(cur)
            cur = {'tag': f"DW_TAG_{mtag.group(2)}"}
            moff = rx_die_off.match(line)
            if moff: cur['off'] = int(moff.group(1),16)
            continue
        if cur is None:
            continue
        m = rx_low.search(line)
        if m: cur['low'] = int(m.group(1),16); continue
        m = rx_hia.search(line)
        if m and 'low' in cur: cur['high'] = int(m.group(1),16); continue
        m = rx_hiud.search(line)
        if m and 'low' in cur: cur['high'] = cur['low'] + int(m.group(1)); continue
        m = rx_ranges.search(line)
        if m: cur['ranges_off'] = int(m.group(1),16); continue
        m = rx_name.search(line)
        if m: cur['name'] = m.group(1); continue
        m = rx_link.search(line)
        if m and 'name' not in cur: cur['name'] = m.group(1); continue
        m = rx_abs.search(line)
        if m: cur['abs'] = int(m.group(1),16); continue
        m = rx_spec.search(line)
        if m: cur['spec'] = int(m.group(1),16); continue
if cur: dies.append(cur)

subs = sum(1 for d in dies if d.get('tag') in ('DW_TAG_subprogram','DW_TAG_inlined_subroutine'))
vlog(f"[DI] total_DIEs={len(dies)}  subprogram_like={subs}")

dies_by_off = { d['off']: d for d in dies if 'off' in d }

def resolve_name(d, seen=None):
    if seen is None: seen=set()
    nm = d.get('name')
    if nm: return name_map.get(nm, nm)
    for k in ('abs','spec'):
        if k in d:
            ref = d[k]
            if ref in seen: 
                continue
            seen.add(ref)
            d2 = dies_by_off.get(ref)
            if d2:
                nm2 = resolve_name(d2, seen)
                if nm2: return name_map.get(nm2, nm2)
    return None

# --------------------------- Swift demangle (CLI) ------------------------------
# Detecta "cara de Swift" e usa xcrun swift-demangle --compact
SWIFT_MANGLED_RX = re.compile(r'^(_?\$s|_T|\$S)')

def has_swift_demangle() -> bool:
    # precisa do Xcode CLI; checamos rápido
    if shutil.which(args.swift_demangle_bin) is None:
        return False
    try:
        # xcrun swift-demangle -help  (ou sem args) deve retornar exit 0/usage
        subprocess.run([args.swift_demangle_bin, 'swift-demangle', '-help'],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
        return True
    except Exception:
        return False

_swift_ok = args.do_demangle and has_swift_demangle()
if args.do_demangle and not _swift_ok:
    print("// WARN: 'xcrun swift-demangle' não parece disponível; nomes Swift ficarão 'mangled'.", file=sys.stderr)

# cache LRU para acelerar
@lru_cache(maxsize=100_000)
def swift_demangle_one(mangled: str) -> str:
    if not _swift_ok:
        return mangled
    if not SWIFT_MANGLED_RX.match(mangled):
        return mangled
    try:
        # --compact evita o "mangled ---> demangled"
        out = subprocess.run(
            [args.swift_demangle_bin, 'swift-demangle', '--compact', mangled],
            check=False, capture_output=True, text=True
        )
        s = (out.stdout or '').strip()
        # se não demanglar, devolve original (comportamento da ferramenta) :contentReference[oaicite:2]{index=2}
        return s if s else mangled
    except Exception:
        return mangled

def maybe_demangle(name: str) -> str:
    if not name: 
        return name
    # aplica mapping opcional primeiro (se houver)
    mapped = name_map.get(name, name)
    # depois tenta demangle Swift (se habilitado)
    return swift_demangle_one(mapped)

# --------------------------- Emissão ------------------------------------------
funcs = []
miss_name = 0
for d in dies:
    if d.get('tag') not in ('DW_TAG_subprogram','DW_TAG_inlined_subroutine'):
        continue
    name = resolve_name(d) or d.get('name')
    name = maybe_demangle(name) if name else None

    if 'low' in d and 'high' in d and d['high'] > d['low']:
        if name: funcs.append({'start': d['low'], 'end': d['high'], 'name': name})
        else: miss_name += 1

    roff = d.get('ranges_off')
    if roff is not None and roff in ranges_map:
        for s,e in ranges_map[roff]:
            if e > s:
                if name: funcs.append({'start': s, 'end': e, 'name': name})
                else: miss_name += 1

vlog(f"[EMIT] funcs={len(funcs)}  miss_name_on_emittable={miss_name}")

funcs.sort(key=lambda x: (x['start'], x['end']))
print(json.dumps({
    'image': args.image,
    'uuid': args.uuid,
    'arch': args.arch,
    'functions': funcs
}, ensure_ascii=False))
