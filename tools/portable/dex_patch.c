#include "dex_patch.h"
#include <stdint.h>
#include <string.h>
#define MAX 65536u
static unsigned char *raw, *d;
static size_t total, len, base;
static int bad;
static uint32_t ns, nt, np, nf, nm, nc, so, to, po, fo, mo, co;
static uint32_t codes[MAX], oper[MAX], width[MAX], classes[MAX];
static int range(size_t p, size_t n, size_t limit) {
  if (p > limit || n > limit - p) {
    bad = 1;
    return 0;
  }
  return 1;
}
static uint32_t r32(size_t p) {
  if (!range(p, 4, len))
    return 0;
  return d[p] | (uint32_t)d[p + 1] << 8 | (uint32_t)d[p + 2] << 16 |
         (uint32_t)d[p + 3] << 24;
}
static uint32_t r16(size_t p) {
  if (!range(p, 2, len))
    return 0;
  return d[p] | d[p + 1] << 8;
}
static void w16(size_t p, uint32_t v) {
  if (range(p, 2, len)) {
    d[p] = v;
    d[p + 1] = v >> 8;
  }
}
static void w32(size_t p, uint32_t v) {
  w16(p, v);
  w16(p + 2, v >> 16);
}
static uint32_t leb(size_t *p) {
  uint32_t v = 0;
  unsigned i;
  for (i = 0; i < 5; i++) {
    unsigned b;
    if (!range(*p, 1, len))
      return 0;
    b = d[(*p)++];
    if (i == 4 && (b & 240)) {
      bad = 1;
      return 0;
    }
    v |= (b & 127) << (7 * i);
    if (!(b & 128))
      return v;
  }
  bad = 1;
  return 0;
}
static const char *str(uint32_t i) {
  size_t p, q;
  if (i >= ns) {
    bad = 1;
    return "";
  }
  p = r32(so + i * 4);
  leb(&p);
  if (bad || p >= len) {
    bad = 1;
    return "";
  }
  q = p;
  while (q < len && d[q])
    q++;
  if (q == len) {
    bad = 1;
    return "";
  }
  return (const char *)d + p;
}
static const char *typ(uint32_t i) {
  if (i >= nt) {
    bad = 1;
    return "";
  }
  return str(r32(to + i * 4));
}
static int part(const char **s, const char *t) {
  while (*t) {
    if (*(*s)++ != *t++)
      return 0;
  }
  return 1;
}
static int method_eq(uint32_t i, const char *name) {
  size_t p;
  uint32_t proto, n, j;
  const char *s = name;
  if (i >= nm)
    return 0;
  p = mo + i * 8;
  proto = r16(p + 2);
  if (proto >= np) {
    bad = 1;
    return 0;
  }
  if (!part(&s, typ(r16(p))) || !part(&s, "->") || !part(&s, str(r32(p + 4))) ||
      !part(&s, "("))
    return 0;
  p = po + proto * 12;
  n = r32(p + 8);
  if (n) {
    uint32_t count = r32(n);
    if (!range(n + 4, (size_t)count * 2, len))
      return 0;
    for (j = 0; j < count; j++)
      if (!part(&s, typ(r16(n + 4 + j * 2))))
        return 0;
  }
  return part(&s, ")") && part(&s, typ(r32(p + 4))) && !*s;
}
static int field_eq(uint32_t i, const char *name) {
  size_t p;
  const char *s = name;
  if (i >= nf)
    return 0;
  p = fo + i * 8;
  return part(&s, typ(r16(p))) && part(&s, "->") && part(&s, str(r32(p + 4))) &&
         part(&s, ":") && part(&s, typ(r16(p + 2))) && !*s;
}
static int findmethod(const char *n) {
  uint32_t i;
  int found = -1;
  for (i = 0; i < nm; i++)
    if (method_eq(i, n)) {
      if (found >= 0)
        bad = 1;
      found = i;
    }
  if (found < 0)
    bad = 1;
  return found;
}
static int findfield(const char *n) {
  uint32_t i;
  int found = -1;
  for (i = 0; i < nf; i++)
    if (field_eq(i, n)) {
      if (found >= 0)
        bad = 1;
      found = i;
    }
  if (found < 0)
    bad = 1;
  return found;
}
static int findstr(const char *n) {
  uint32_t i;
  int found = -1;
  for (i = 0; i < ns; i++)
    if (!strcmp(str(i), n)) {
      if (found >= 0)
        bad = 1;
      found = i;
    }
  if (found < 0 || found > 65535)
    bad = 1;
  return found;
}
static int findtype(const char *n) {
  uint32_t i;
  int found = -1;
  for (i = 0; i < nt; i++)
    if (!strcmp(typ(i), n)) {
      if (found >= 0)
        bad = 1;
      found = i;
    }
  if (found < 0 || found > 65535)
    bad = 1;
  return found;
}
static void table(unsigned pos, unsigned width_, uint32_t *count,
                  uint32_t *off) {
  *count = r32(pos);
  *off = r32(pos + 4);
  if (*count > MAX || !range(*off, (size_t)*count * width_, len))
    bad = 1;
}
static int parse(void) {
  uint32_t i, j, k;
  size_t p;
  table(56, 4, &ns, &so);
  table(64, 4, &nt, &to);
  table(72, 12, &np, &po);
  table(80, 8, &nf, &fo);
  table(88, 8, &nm, &mo);
  table(96, 32, &nc, &co);
  if (bad)
    return 0;
  for (i = 0; i < ns; i++)
    str(i);
  for (i = 0; i < nt; i++)
    typ(i);
  for (i = 0; i < np && !bad; i++) {
    uint32_t params = r32(po + i * 12 + 8), count;
    str(r32(po + i * 12));
    typ(r32(po + i * 12 + 4));
    if (params) {
      count = r32(params);
      if (count > MAX) {
        bad = 1;
        break;
      }
      if (!range(params + 4, (size_t)count * 2, len))
        break;
      for (j = 0; j < count && !bad; j++)
        typ(r16(params + 4 + j * 2));
    }
  }
  for (i = 0; i < nf && !bad; i++) {
    typ(r16(fo + i * 8));
    typ(r16(fo + i * 8 + 2));
    str(r32(fo + i * 8 + 4));
  }
  for (i = 0; i < nm && !bad; i++) {
    typ(r16(mo + i * 8));
    if (r16(mo + i * 8 + 2) >= np)
      bad = 1;
    str(r32(mo + i * 8 + 4));
  }
  for (i = 0; i < nm; i++)
    codes[i] = oper[i] = width[i] = 0;
  for (i = 0; i < nc && !bad; i++) {
    uint32_t counts[4], idx;
    classes[i] = r32(co + i * 32);
    typ(classes[i]);
    p = r32(co + i * 32 + 24);
    if (!p)
      continue;
    for (j = 0; j < 4; j++) {
      counts[j] = leb(&p);
      if (counts[j] > MAX)
        bad = 1;
    }
    if (bad)
      break;
    for (j = 0; j < 2 && !bad; j++) {
      idx = 0;
      for (k = 0; k < counts[j] && !bad; k++) {
        uint32_t delta = leb(&p);
        if (delta >= nf || idx >= nf - delta || (k && delta == 0)) {
          bad = 1;
          break;
        }
        idx += delta;
        if (r16(fo + idx * 8) != classes[i]) {
          bad = 1;
          break;
        }
        leb(&p);
      }
    }
    for (j = 2; j < 4; j++) {
      idx = 0;
      for (k = 0; k < counts[j] && !bad; k++) {
        uint32_t delta = leb(&p), code;
        size_t start;
        if (delta >= nm || idx >= nm - delta) {
          bad = 1;
          break;
        }
        idx += delta;
        if ((k && delta == 0) || r16(mo + idx * 8) != classes[i]) {
          bad = 1;
          break;
        }
        leb(&p);
        start = p;
        code = leb(&p);
        if (oper[idx]) {
          bad = 1;
          break;
        }
        oper[idx] = start;
        width[idx] = p - start;
        codes[idx] = code;
        if (code) {
          if ((code & 3) || !range(code, 16, len) ||
              r16(code) < r16(code + 2) || r32(code + 12) > len / 2 ||
              !range(code + 16, (size_t)r32(code + 12) * 2, len))
            bad = 1;
        }
      }
    }
  }
  return !bad;
}
static uint32_t code(const char *n) {
  int i = findmethod(n);
  if (i < 0)
    return 0;
  if (!codes[i])
    bad = 1;
  return codes[i];
}
/* KitKat (DEX035/ODEX036) opcodes with no defined meaning in a file:
 * unused 0x3e-0x43, 0x73, 0x79-0x7a, 0xff, and the debugger-only breakpoint
 * 0xec. An unknown instruction has no trustworthy width or effect, so any
 * method containing one is an unreviewed shape and is refused. */
static int unused_opcode(unsigned op) {
  return (op >= 0x3e && op <= 0x43) || op == 0x73 || op == 0x79 ||
         op == 0x7a || op == 0xec || op == 0xff;
}
/* Instruction decoder includes optimized Dalvik opcodes and bounded payloads.
 */
static unsigned step(uint32_t c, uint32_t pc, uint32_t count) {
  unsigned op = r16(c + 16 + pc * 2) & 255, w = 1;
  uint32_t word = r16(c + 16 + pc * 2);
  if (unused_opcode(op)) {
    bad = 1;
    return 0;
  }
  if (op == 2 || op == 5 || op == 8 || op == 0x13 || op == 0x15 || op == 0x16 ||
      op == 0x19 || op == 0x1a || op == 0x1c || op == 0x1f || op == 0x20 ||
      op == 0x22 || op == 0x23 || op == 0x29 || (op >= 0x2d && op < 0x3e) ||
      (op >= 0x44 && op < 0x6e) || (op >= 0x90 && op < 0xb0) ||
      (op >= 0xd0 && op < 0xec) || (op >= 0xf2 && op < 0xf8) ||
      (op >= 0xfc && op < 0xff) || op == 0xed)
    w = 2;
  if (op == 3 || op == 6 || op == 9 || op == 0x14 || op == 0x17 || op == 0x1b ||
      (op >= 0x24 && op <= 0x26) || (op >= 0x2a && op <= 0x2c) ||
      (op >= 0x6e && op < 0x73) || (op >= 0x74 && op < 0x79) ||
      (op >= 0xee && op <= 0xf0) || (op >= 0xf8 && op < 0xfc))
    w = 3;
  if (op == 0x18)
    w = 5;
  if (!op && word) {
    uint32_t n;
    if (pc + 4 > count) {
      bad = 1;
      return 0;
    }
    n = r16(c + 16 + (pc + 1) * 2);
    if (word == 0x100)
      w = 4 + 2 * n;
    else if (word == 0x200)
      w = 2 + 4 * n;
    else if (word == 0x300) {
      uint32_t x = r32(c + 16 + (pc + 2) * 2);
      if ((uint64_t)n * x > 0x7ffffff0u) {
        bad = 1;
        return 0;
      }
      w = 4 + (n * x + 1) / 2;
    } else {
      bad = 1;
      return 0;
    }
  }
  if (w > count - pc) {
    bad = 1;
    return 0;
  }
  return w;
}
static int boundary(uint32_t c, uint32_t target) {
  uint32_t pc = 0, n = r32(c + 12);
  while (pc < n && !bad) {
    unsigned w = step(c, pc, n);
    if (pc == target)
      return 1;
    if (!w)
      return 0;
    pc += w;
  }
  return 0;
}
static void validate(uint32_t c) {
  uint32_t p = 0, n = r32(c + 12);
  while (p < n && !bad) {
    unsigned w = step(c, p, n);
    if (!w)
      break;
    p += w;
  }
}
/* Destination register of the instruction at pc, or -1 when it writes none.
 * *pair is set when the write covers vN and vN+1 (wide values). Branches,
 * stores, invokes and returns write no register; their results are only
 * observable through a later move-result, which is itself a write here. */
static int destination(uint32_t c, uint32_t pc, int *pair) {
  uint32_t word = r16(c + 16 + pc * 2);
  unsigned op = word & 255, a4 = (word >> 8) & 15, aa = word >> 8;
  *pair = 0;
  switch (op) {
  /* vA (4-bit), one register */
  case 0x01: case 0x07: case 0x12: case 0x20: case 0x21: case 0x23:
  case 0x52: case 0x54: case 0x55: case 0x56: case 0x57: case 0x58:
  case 0x7b: case 0x7c: case 0x7f: case 0x82: case 0x84: case 0x85:
  case 0x87: case 0x8a: case 0x8c: case 0x8d: case 0x8e: case 0x8f:
  case 0xe3: case 0xe7: case 0xf2: case 0xf4:
    return a4;
  /* vA (4-bit), wide pair */
  case 0x04: case 0x53: case 0x7d: case 0x7e: case 0x80: case 0x81:
  case 0x83: case 0x86: case 0x88: case 0x89: case 0x8b: case 0xe8:
  case 0xf3:
    *pair = 1;
    return a4;
  /* vAA (8-bit), one register */
  case 0x02: case 0x08: case 0x0a: case 0x0c: case 0x0d: case 0x13:
  case 0x14: case 0x15: case 0x1a: case 0x1b: case 0x1c: case 0x1f:
  case 0x22: case 0x2d: case 0x2e: case 0x2f: case 0x30: case 0x31:
  case 0x44: case 0x46: case 0x47: case 0x48: case 0x49: case 0x4a:
  case 0x60: case 0x62: case 0x63: case 0x64: case 0x65: case 0x66:
  case 0xe5: case 0xfd:
    return aa;
  /* vAA (8-bit), wide pair */
  case 0x05: case 0x0b: case 0x16: case 0x17: case 0x18: case 0x19:
  case 0x45: case 0x61: case 0xea:
    *pair = 1;
    return aa;
  /* vAAAA (16-bit) */
  case 0x03: case 0x09:
    return r16(c + 18 + pc * 2);
  case 0x06:
    *pair = 1;
    return r16(c + 18 + pc * 2);
  default:
    break;
  }
  if (op >= 0xb0 && op <= 0xcf) { /* binop/2addr: vA = vA op vB */
    *pair = (op >= 0xbb && op <= 0xc5) || op >= 0xcb;
    return a4;
  }
  if (op >= 0xd0 && op <= 0xd7) /* binop/lit16 */
    return a4;
  if (op >= 0x90 && op <= 0xaf) { /* binop: vAA = vBB op vCC */
    *pair = (op >= 0x9b && op <= 0xa5) || op >= 0xab;
    return aa;
  }
  if (op >= 0xd8 && op <= 0xe2) /* binop/lit8 */
    return aa;
  return -1;
}
#define CAPABILITY_LIMIT 4096u
/* Prove that v3 holds the int constant 1 at every instruction after pc 1:
 * the method begins with const/4 v2,#0; const/4 v3,#1 (entry always runs both),
 * nothing else writes v3 (directly or as half of a wide pair), the method has
 * no payload/switch data that could hide a second instruction stream, and every
 * branch lands on an instruction boundary of this linear decoding. Anything
 * else is an unreviewed shape: refuse instead of guessing the stored value. */
static void prove_v3(uint32_t c, uint32_t n) {
  static unsigned char start[CAPABILITY_LIMIT];
  uint32_t pc;
  if (n < 3 || n > CAPABILITY_LIMIT) {
    bad = 1;
    return;
  }
  for (pc = 0; pc < n; pc++) /* no libc memset in the static ARM build */
    start[pc] = 0;
  for (pc = 0; pc < n && !bad;) {
    uint32_t word = r16(c + 16 + pc * 2);
    unsigned op = word & 255, w = step(c, pc, n);
    int reg, pair;
    if (!w)
      break;
    if ((op == 0 && word) || op == 0x26 || op == 0x2b || op == 0x2c) {
      bad = 1;
      break;
    }
    start[pc] = 1;
    reg = destination(c, pc, &pair);
    if (pc != 1 && (reg == 3 || (pair && reg == 2))) {
      bad = 1;
      break;
    }
    pc += w;
  }
  for (pc = 0; pc < n && !bad;) {
    uint32_t word = r16(c + 16 + pc * 2);
    unsigned op = word & 255, w = step(c, pc, n);
    int64_t target = -1;
    if (!w)
      break;
    if (op == 0x28)
      target = (int64_t)pc + (int8_t)(word >> 8);
    else if (op == 0x29 || (op >= 0x32 && op <= 0x3d))
      target = (int64_t)pc + (int16_t)r16(c + 18 + pc * 2);
    else if (op == 0x2a)
      target = (int64_t)pc + (int32_t)r32(c + 18 + pc * 2);
    if ((op == 0x28 || op == 0x29 || op == 0x2a || (op >= 0x32 && op <= 0x3d)) &&
        (target < 0 || target >= n || !start[target])) {
      bad = 1;
      break;
    }
    pc += w;
  }
}
#define INFO "Lcom/tcc/iap2server/Iap2InitInformationMsg;"
#define SERVICE "Lcom/tcc/iap2server/Iap2Service;"
#define RG_ITEM "Lcom/tcc/iap2server/Iap2InitInformationMsg$RouteGuidanceComponent$RouteGuidanceItem;"
#define W(p) r16(c + 16 + (p) * 2)
static void lane_ident(void) {
  uint32_t c = code(RG_ITEM "->getComponentInfo(Lcom/tcc/iap2/Iap2NotiMsg;)V"),
           n = r32(c + 12), pc;
  int int_arr = findtype("[I"),
      add_int = findmethod("Lcom/tcc/iap2/Iap2NotiMsg$Iap2ObjGroup;->addObject(II[I)V");
  validate(c);
  if (r16(c) < 10 || r16(c + 2) != 2 || r16(c + 4) < 4 || r16(c + 6) != 0 || n < 48) {
    bad = 1;
    return;
  }
  if (W(0) != 0x5712 || W(1) != 0x0612 || W(2) != 0x1512 || W(11) != 0x106e ||
      !method_eq(W(12), "Lcom/tcc/iap2/Iap2NotiMsg;->createIap2NotiObjGroup()Lcom/tcc/iap2/Iap2NotiMsg$Iap2ObjGroup;") ||
      W(14) != 0x000c || !boundary(c, 15) || !boundary(c, 43)) {
    bad = 1;
    return;
  }
  if (W(15) != 0x0071 || W(18) != 0x020c || W(19) != 0x0322 || W(40) != 0x2071 ||
      !method_eq(W(41), "Landroid/util/Log;->d(Ljava/lang/String;Ljava/lang/String;)I") ||
      W(42) != 0x0032) {
    bad = 1;
    return;
  }
  if ((W(43) & 0xff) != 0x13 || (W(43) >> 8) != 2 ||
      (W(45) & 0xff) != 0x23 || ((W(45) >> 8) & 15) != 3 ||
      (W(47) & 0xff) != 0x54 || ((W(47) >> 8) & 15) != 4) {
    bad = 1;
    return;
  }
  for (pc = 0; pc < n && !bad;) {
    uint32_t word = W(pc);
    unsigned op = word & 255, w = step(c, pc, n);
    int64_t target = -1;
    if (!w)
      break;
    if ((op == 0 && word) || op == 0x26 || op == 0x2b || op == 0x2c) {
      bad = 1;
      break;
    }
    if (pc >= 15 && pc < 43) {
      int pair = 0;
      int reg = destination(c, pc, &pair);
      if (pair || (reg >= 0 && reg != 2 && reg != 3 && reg != 4)) {
        bad = 1;
        break;
      }
    }
    if (op == 0x28)
      target = (int64_t)pc + (int8_t)(word >> 8);
    else if (op == 0x29 || (op >= 0x32 && op <= 0x3d))
      target = (int64_t)pc + (int16_t)W(pc + 1);
    else if (op == 0x2a)
      target = (int64_t)pc + (int32_t)r32(c + 18 + pc * 2);
    if ((op == 0x28 || op == 0x29 || op == 0x2a || (op >= 0x32 && op <= 0x3d)) &&
        (target < 0 || target >= n || (target >= 15 && target < 43))) {
      bad = 1;
      break;
    }
    pc += w;
  }
  if (bad)
    return;
  {
    const uint16_t patch[28] = {
        0x7212, (uint16_t)0x5323, (uint16_t)int_arr, 0x0413, 0x0040, 0x044b, 0x0603,
        0x406e, (uint16_t)add_int, 0x3720,
        0x0213, 0x0008, (uint16_t)0x5323, (uint16_t)int_arr, 0x0413, 0x000a, 0x044b, 0x0603,
        0x406e, (uint16_t)add_int, 0x3720,
        0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000};
    unsigned i;
    for (i = 0; i < 28; i++)
      w16(c + 16 + (15 + i) * 2, patch[i]);
  }
}
static void capability(void) {
  uint32_t c = code(INFO "->checkSupportsFeatures()V"), n = r32(c + 12), pc;
  int a = findfield(INFO "->iAP2UsedWifiInformation:I"),
      b = findfield(INFO "->iAP2UsedRouteGuidance:I"), na = 0, nb = 0;
  validate(c);
  if (r16(c) < 4 || r16(c + 16) != 0x212 || r16(c + 18) != 0x1312)
    bad = 1;
  if (!bad)
    prove_v3(c, n);
  for (pc = 0; pc < n && !bad;) {
    unsigned w = step(c, pc, n);
    if ((r16(c + 16 + pc * 2) & 255) == 0x67) {
      uint32_t f = r16(c + 18 + pc * 2);
      if (f == (uint32_t)a || f == (uint32_t)b) {
        if ((r16(c + 16 + pc * 2) >> 8) > 3) {
          bad = 1;
          break;
        }
        if (f == (uint32_t)a)
          na++;
        else
          nb++;
        w16(c + 16 + pc * 2, 0x367);
      }
    }
    pc += w;
  }
  if (na != 1 || nb != 3)
    bad = 1;
  if (!bad)
    lane_ident();
}
static void putleb(uint32_t p, uint32_t v, uint32_t n) {
  uint32_t i;
  for (i = 0; i < n; i++) {
    d[p + i] = (v & 127) | (i + 1 < n ? 128 : 0);
    v >>= 7;
  }
  if (v)
    bad = 1;
}
static void body(uint32_t c, uint32_t regs, uint32_t ins, const uint16_t *words,
                 unsigned n) {
  uint32_t size = r32(c + 12), i;
  if (size < n) {
    bad = 1;
    return;
  }
  w16(c, regs);
  w16(c + 2, ins);
  w16(c + 4, 3);
  w16(c + 6, 0);
  w32(c + 8, 0);
  for (i = 0; i < size; i++)
    w16(c + 16 + i * 2, i < n ? words[i] : 0);
}
static void bluetooth(void) {
  int a = findmethod(SERVICE "->onStartCommand(Landroid/content/Intent;II)I"),
      b = findmethod(SERVICE "->debugTrigger()V");
  uint32_t ca, cb;
  uint16_t w[] = {
      0x538,  44,     0x1a,   0,      0x112,  0x306e, 0,      0x105, 0xa,
      0x4112, 0x1034, 20,     0x5112, 0x1036, 31,     0x11a,  0,     0x206e,
      0,      0x15,   0x10c,  0x2070, 0,      0x14,   0x2070, 0,     0x4,
      0x1228, 0x7b,   0x4112, 0x1034, 14,     0x5112, 0x1036, 11,    0x2070,
      0,      0x4,    0x1012, 0xf}; /* branch displacements set below */
  if (a < 0 || b < 0) {
    return;
  }
  ca = codes[a];
  cb = codes[b];
  if (!ca || !cb || ca == cb) {
    bad = 1;
    return;
  }
  if (r16(ca) != 5 || r16(ca + 2) != 4 || r16(ca + 4) != 0 ||
      r16(ca + 6) != 0 || r32(ca + 12) != 2 || r16(ca + 16) != 0x1012 ||
      r16(ca + 18) != 0xf || r16(cb) != 7 || r16(cb + 2) != 1 ||
      r16(cb + 4) != 3 || r32(cb + 12) < 40) {
    bad = 1;
    return;
  }
  validate(cb);
  w[1] = 38;
  w[11] = 18;
  w[14] = 25;
  w[27] = 0xb28;
  w[31] = 8;
  w[34] = 5;
  w[3] = findstr("com.telechips.android.iap2.component");
  w[6] =
      findmethod("Landroid/content/Intent;->getIntExtra(Ljava/lang/String;I)I");
  w[16] = findstr("serial");
  w[18] = findmethod("Landroid/content/Intent;->getStringExtra(Ljava/lang/"
                     "String;)Ljava/lang/String;");
  w[22] = findmethod(SERVICE "->setDeviceSerial(Ljava/lang/String;)V");
  w[25] = findmethod(SERVICE "->receiveConnect(I)V");
  w[36] = findmethod(SERVICE "->receiveDisconnect(I)V");
  body(cb, 8, 4, w, sizeof(w) / 2);
  {
    uint16_t ret = 0xe;
    body(ca, 1, 1, &ret, 1);
  }
  putleb(oper[a], cb, width[a]);
  putleb(oper[b], ca, width[b]);
  capability();
}
static void gpm(void) {
  uint32_t c = code("Lcom/google/android/projection/service/"
                    "GalConnectionSession;-><init>(Landroid/content/"
                    "Context;Ljava/lang/String;Lcom/google/android/projection/"
                    "service/GalConnectionManager;Lcom/google/android/"
                    "projection/sink/audio/AudioFocusManager;Lcom/google/"
                    "android/projection/sink/audio/MediaPlaybackInfo;)V"),
           n = r32(c + 12), pc, found = 0;
  validate(c);
  for (pc = 0; pc < n && !bad;) {
    unsigned w = step(c, pc, n);
    if (pc + 10 <= n && (W(pc) & 255) == 0x71 &&
        (method_eq(W(pc + 1),
                   "Lcom/google/android/projection/sink/d/d;->bJ()I") ||
         method_eq(W(pc + 1),
                   "Lcom/google/android/projection/sink/d/d;->bG()I")) &&
        W(pc) == 0x71 && W(pc + 2) == 0 && W(pc + 3) == 0xa &&
        W(pc + 4) == 0x313 && W(pc + 5) == 999 && W(pc + 6) == 0x3034 &&
        W(pc + 7) == 11 && pc + 17 < n && boundary(c, pc + 17) &&
        (W(pc + 8) & 255) == 0x22 &&
        !strcmp(typ(W(pc + 9)), "Lcom/google/android/projection/sink/"
                                "navigation/GpmNaviTBTManager;")) {
      found++;
      w16(c + 16 + (pc + 6) * 2, 0);
      w16(c + 16 + (pc + 7) * 2, 0);
    }
    pc += w;
  }
  if (found != 1)
    bad = 1;
}
static void hotspot(void) {
  const char *names[] = {
      "Lcom/hkmc/wifisettings/WifiHotspot;->onPreferenceTreeClick(Landroid/"
      "preference/PreferenceScreen;Landroid/preference/Preference;)Z",
      "Lcom/hkmc/wifisettings/service/a;->handleMessage(Landroid/os/Message;)V",
      "Lcom/hkmc/wifisettings/service/b;->handleMessage(Landroid/os/"
      "Message;)V"};
  int check = findmethod(
      "Lcom/hkmc/wifisettings/common/e;->s(Landroid/content/Context;)Z");
  unsigned i;
  for (i = 0; i < 3; i++) {
    uint32_t c = code(names[i]), n = r32(c + 12), pc, found = 0;
    validate(c);
    for (pc = 0; pc < n && !bad;) {
      unsigned w = step(c, pc, n);
      if ((W(pc) & 255) == 0x71 && W(pc + 1) == (uint32_t)check) {
        uint32_t branch = pc + 4, target;
        found++;
        if (pc + 6 > n || W(pc) != 0x1071 || W(pc + 2) > 15 ||
            W(pc + 2) >= r16(c) || (W(pc + 3) >> 8) >= r16(c) ||
            (W(pc + 3) & 255) != 0xa ||
            W(branch) != ((W(pc + 3) & 0xff00) | 0x39)) {
          bad = 1;
          break;
        }
        target = branch + (int16_t)W(branch + 1);
        if (target <= branch || target >= n || !boundary(c, target)) {
          bad = 1;
          break;
        }
        w16(c + 16 + branch * 2, 0x29);
      }
      pc += w;
    }
    if (found != 1)
      bad = 1;
  }
}
static void dipo(void) {
  uint32_t c = code("Lcom/daudio/app/dipo/service/DipoService;->i(II)V"),
           n = r32(c + 12), pc, marker = 0, switches = 0, sw = 0;
  int mark = findstr("onKeyForService() performPhoneKey Call Key - hasn't "
                     "PTTKey during CarPlay Calling");
  validate(c);
  if (r16(c) != 11 || r16(c + 2) != 3 || r16(c + 6) != 0)
    bad = 1;
  for (pc = 0; pc < n && !bad;) {
    unsigned w = step(c, pc, n);
    if ((W(pc) & 255) == 0x1a && W(pc + 1) == (uint32_t)mark)
      marker++;
    if ((W(pc) & 255) == 0x2b && marker) {
      switches++;
      sw = pc;
    }
    pc += w;
  }
  if (marker != 1 || switches != 1) {
    bad = 1;
    return;
  }
  {
    uint32_t payload = sw + (int32_t)(W(sw + 1) | (uint32_t)W(sw + 2) << 16),
             branch = sw + 3, end, target;
    const char *hook =
        "Lcom/daudio/app/dipo/telechips/CarPlayTelephony;->HookSwitch:Lcom/"
        "daudio/app/dipo/telechips/CarPlayTelephony;";
    if (sw + 5 > n || payload > n || n - payload < 12 || W(payload) != 0x100 ||
        W(payload + 1) != 4 || W(payload + 2) || W(payload + 3) ||
        W(branch) != 0x29 || W(sw) != 0x2b) {
      bad = 1;
      return;
    }
    end = branch + (int16_t)W(branch + 1);
    target = sw + (int32_t)(W(payload + 4) | (uint32_t)W(payload + 5) << 16);
    if (end >= n || W(end) != 0xe || !boundary(c, end) ||
        target != branch + 2 || target > n || n - target < 10 ||
        W(target) != 0x62 || W(target + 5) != 0x62 ||
        !field_eq(W(target + 1), hook) || !field_eq(W(target + 6), hook) ||
        W(target + 2) != 0x30f8 || W(target + 7) != 0x30f8 ||
        W(target + 3) != W(target + 8) || W(target + 4) != 0x408 ||
        W(target + 9) != 0x508) {
      bad = 1;
      return;
    }
    w16(c + 16 + branch * 2, 0x3b);
  }
}
static uint32_t rol(uint32_t x, unsigned n) { return x << n | x >> (32 - n); }
static void sha1(const unsigned char *s, size_t size, unsigned char *out) {
  uint32_t h[] = {0x67452301, 0xefcdab89, 0x98badcfe, 0x10325476, 0xc3d2e1f0};
  size_t blocks = (size + 72) / 64, b, i;
  for (b = 0; b < blocks; b++) {
    uint32_t w[80], a, c, e, f, g, t, bb, dd;
    for (i = 0; i < 16; i++) {
      unsigned j;
      w[i] = 0;
      for (j = 0; j < 4; j++) {
        size_t p = b * 64 + i * 4 + j;
        unsigned char v = p < size ? s[p] : p == size ? 128 : 0;
        if (p >= blocks * 64 - 8)
          v = (unsigned char)((uint64_t)size * 8 >>
                              ((blocks * 64 - 1 - p) * 8));
        w[i] = w[i] << 8 | v;
      }
    }
    for (i = 16; i < 80; i++)
      w[i] = rol(w[i - 3] ^ w[i - 8] ^ w[i - 14] ^ w[i - 16], 1);
    a = h[0];
    bb = h[1];
    c = h[2];
    dd = h[3];
    e = h[4];
    for (i = 0; i < 80; i++) {
      if (i < 20) {
        f = (bb & c) | (~bb & dd);
        g = 0x5a827999;
      } else if (i < 40) {
        f = bb ^ c ^ dd;
        g = 0x6ed9eba1;
      } else if (i < 60) {
        f = (bb & c) | (bb & dd) | (c & dd);
        g = 0x8f1bbcdc;
      } else {
        f = bb ^ c ^ dd;
        g = 0xca62c1d6;
      }
      t = rol(a, 5) + f + e + g + w[i];
      e = dd;
      dd = c;
      c = rol(bb, 30);
      bb = a;
      a = t;
    }
    h[0] += a;
    h[1] += bb;
    h[2] += c;
    h[3] += dd;
    h[4] += e;
  }
  for (i = 0; i < 20; i++)
    out[i] = h[i / 4] >> (24 - (i % 4) * 8);
}
static uint32_t adler(const unsigned char *s, size_t size) {
  uint32_t a = 1, b = 0;
  size_t i;
  for (i = 0; i < size; i++) {
    a = (a + s[i]) % 65521;
    b = (b + a) % 65521;
  }
  return b << 16 | a;
}
static void seal(const char *kind) {
  uint32_t opt = 0, size = 0, deps = 0;
  if (base) {
    unsigned char *save = d;
    size_t slen = len;
    uint32_t pos;
    d = raw;
    len = total;
    opt = r32(24);
    size = r32(28);
    deps = r32(16);
    if (!range(opt, size, total) || deps > opt) {
      bad = 1;
      return;
    }
    pos = opt;
    while (pos < opt + size && !bad) {
      uint32_t tag, length, j;
      if (!range(pos, 8, opt + size))
        break;
      tag = r32(pos);
      length = r32(pos + 4);
      if (tag == 0x41454e44)
        break;
      if (!range(pos + 8, length, opt + size))
        break;
      if (tag == 0x524d4150) {
        uint32_t count = r32(pos + 8);
        if (count != nc || length < 4 ||
            !range(pos + 12, (size_t)count * 4, pos + 8 + length)) {
          bad = 1;
          break;
        }
        for (j = 0; j < count; j++) {
          const char *n;
          d = save;
          len = slen;
          n = typ(classes[j]);
          d = raw;
          len = total;
          if ((!strcmp(kind, "bt") &&
               (!strcmp(n, SERVICE) || !strcmp(n, INFO) ||
                !strcmp(n, RG_ITEM))) ||
              (!strcmp(kind, "route") && !strcmp(n, RG_ITEM)) ||
              (!strcmp(kind, "dipo") &&
               !strcmp(n, "Lcom/daudio/app/dipo/service/DipoService;")) ||
              (!strcmp(kind, "gpm") &&
               !strcmp(n, "Lcom/google/android/projection/service/"
                          "GalConnectionSession;")) ||
              (!strcmp(kind, "hotspot") &&
               (!strcmp(n, "Lcom/hkmc/wifisettings/WifiHotspot;") ||
                !strcmp(n, "Lcom/hkmc/wifisettings/service/a;") ||
                !strcmp(n, "Lcom/hkmc/wifisettings/service/b;"))))
            w32(pos + 12 + j * 4, 0);
        }
      }
      if (length > 0xfffffff0u - pos) {
        bad = 1;
        break;
      }
      pos = (pos + 8 + length + 7) & ~7u;
    }
    d = save;
    len = slen;
  }
  if (bad)
    return;
  sha1(d + 32, len - 32, d + 12);
  w32(8, adler(d + 12, len - 12));
  if (base) {
    uint32_t sum = adler(raw + deps, opt + size - deps);
    unsigned char *save = d;
    size_t slen = len;
    d = raw;
    len = total;
    w32(36, sum);
    d = save;
    len = slen;
  }
}
int dex_patch(const char *kind, unsigned char *data, size_t size) {
  raw = data;
  total = size;
  bad = 0;
  base = 0;
  len = size;
  d = data;
  if (size < 112)
    return 0;
  if (!memcmp(data, "dey\n036\0", 8)) {
    if (size < 40)
      return 0;
    uint32_t dexlen = r32(12), deps = r32(16), deplen = r32(20), opt = r32(24),
             optlen = r32(28);
    base = r32(8);
    if (base < 40 || (base & 7) || !range(base, dexlen, total) ||
        !range(deps, deplen, total) || !range(opt, optlen, total) ||
        deps < base + dexlen || opt < deps + deplen || (opt & 7))
      return 0;
    len = dexlen;
    d = raw + base;
  }
  if (len < 112 || memcmp(d, "dex\n035\0", 8) || r32(32) != len ||
      r32(36) != 112 || r32(40) != 0x12345678)
    return 0;
  if (!parse())
    return 0;
  if (!strcmp(kind, "bt"))
    bluetooth();
  else if (!strcmp(kind, "route"))
    capability();
  else if (!strcmp(kind, "gpm"))
    gpm();
  else if (!strcmp(kind, "dipo"))
    dipo();
  else if (!strcmp(kind, "hotspot"))
    hotspot();
  else
    return 0;
  if (bad)
    return 0;
  seal(kind);
  return !bad;
}
