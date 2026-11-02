#!/usr/bin/env node
/**
 * DSH Remote 应用图标生成器（零依赖：Node 内置 zlib 手写 PNG）
 *
 * 图标在 1024×1024 设计坐标系里用「有符号距离场（SDF）」描述，
 * 同一个场景可按任意尺寸重绘，因此 1024 分层图与 152 启动图永远一致。
 *
 * 用法：
 *   node scripts/icon/gen-icons.mjs                 # 候选预览 + 上架素材（dist/icon、dist/store）
 *   node scripts/icon/gen-icons.mjs --store         # 只生成华为应用市场图标（默认候选 E）
 *   node scripts/icon/gen-icons.mjs --store E       # 指定候选生成上架图标
 *   node scripts/icon/gen-icons.mjs --install E     # 把候选 E 写入鸿蒙资源
 */
import { deflateSync } from 'node:zlib';
import { writeFileSync, mkdirSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
/* 图标资源有两处副本，必须同时更新：
 *  · AppScope/resources ：应用图标（桌面显示的就是这一份）
 *  · entry/../media     ：模块/Ability 图标 + 启动页图标 startIcon */
const APP_MEDIA = join(ROOT, 'harmonyos/AppScope/resources/base/media');
const MEDIA = join(ROOT, 'harmonyos/entry/src/main/resources/base/media');
const OUT = join(ROOT, 'dist/icon');
/** 华为应用市场（AppGallery Connect）上架素材输出目录 */
const STORE = join(ROOT, 'dist/store');
/** 上架素材使用的候选：与包内当前安装的图标保持一致（E = 平面柚子） */
const STORE_KEY = 'E';
const DESIGN = 1024;
/** 主体整体放大系数：让图标在启动器里更「满」，同时不碰系统圆角裁切 */
const FG_ZOOM = 1.12;

/* ────────────────────────────── 数学 / SDF ────────────────────────────── */

const TAU = Math.PI * 2;
const hypot = Math.hypot;
const clamp01 = (v) => (v < 0 ? 0 : v > 1 ? 1 : v);
const D2R = Math.PI / 180;

const sdRoundRect = (x, y, cx, cy, hw, hh, r) => {
  const qx = Math.abs(x - cx) - (hw - r);
  const qy = Math.abs(y - cy) - (hh - r);
  return hypot(Math.max(qx, 0), Math.max(qy, 0)) + Math.min(Math.max(qx, qy), 0) - r;
};
const sdCircle = (x, y, cx, cy, r) => hypot(x - cx, y - cy) - r;

const sdCapsule = (x, y, ax, ay, bx, by, r) => {
  const px = x - ax;
  const py = y - ay;
  const bax = bx - ax;
  const bay = by - ay;
  const dd = bax * bax + bay * bay;
  const t = dd > 0 ? clamp01((px * bax + py * bay) / dd) : 0;
  return hypot(px - bax * t, py - bay * t) - r;
};

/** 折线（圆头圆角）→ SDF */
const sdPolyline = (pts, r) => (x, y) => {
  let d = Infinity;
  for (let i = 0; i < pts.length - 1; i++) {
    d = Math.min(d, sdCapsule(x, y, pts[i][0], pts[i][1], pts[i + 1][0], pts[i + 1][1], r));
  }
  return d;
};

/** 圆弧（用短线段逼近，端头圆润）→ SDF */
const sdArc = (cx, cy, rad, a0, a1, halfW, segs = 64) => {
  const pts = [];
  for (let i = 0; i <= segs; i++) {
    const a = (a0 + ((a1 - a0) * i) / segs) * D2R;
    pts.push([cx + Math.cos(a) * rad, cy + Math.sin(a) * rad]);
  }
  return sdPolyline(pts, halfW);
};

/** 圆环描边：|sdRoundRect| - w/2 */
const sdRing = (sd, w) => (x, y) => Math.abs(sd(x, y)) - w / 2;

/* 参数化包装：先给圆心/端点，再逐像素求值 */
const rr = (cx, cy, hw, hh, r) => (x, y) => sdRoundRect(x, y, cx, cy, hw, hh, r);
const circ = (cx, cy, r) => (x, y) => sdCircle(x, y, cx, cy, r);
const cap = (ax, ay, bx, by, r) => (x, y) => sdCapsule(x, y, ax, ay, bx, by, r);
const poly = (pts, r) => sdPolyline(pts, r);

/* ────────────────────────────── 颜色 ────────────────────────────── */

const hex = (h) => [
  parseInt(h.slice(1, 3), 16),
  parseInt(h.slice(3, 5), 16),
  parseInt(h.slice(5, 7), 16),
];

const CREAM = hex('#F5F1E3');
const CREAM_HI = hex('#FDFAEF');
const CREAM_LO = hex('#E8DDC0');
const OLIVE_HI = hex('#56774B');
const OLIVE_LO = hex('#3A5330');
const SHADOW = hex('#20180C');
const OLIVE = hex('#47643C');
const OLIVE_DEEP = hex('#2A3823');
const OLIVE_MID = hex('#4E6B44');
const TERRA = hex('#A95F3F');
const SAND = hex('#E7C39F');
const PAPER = hex('#FAF6EA');
const PAPER_DEEP = hex('#E2DCC5');

const solid = (c, a = 1) => ({ kind: 'solid', c, a });
const lin = (x0, y0, x1, y1, stops) => ({ kind: 'lin', x0, y0, x1, y1, stops });

const stopsAt = (st, t) => {
  let i = 0;
  while (i < st.length - 2 && t > st[i + 1][0]) i++;
  const [t0, c0] = st[i];
  const [t1, c1] = st[i + 1];
  const k = t1 === t0 ? 0 : (t - t0) / (t1 - t0);
  return [
    c0[0] + (c1[0] - c0[0]) * k,
    c0[1] + (c1[1] - c0[1]) * k,
    c0[2] + (c1[2] - c0[2]) * k,
    1,
  ];
};

function paintAt(p, x, y) {
  if (p.kind === 'solid') return [p.c[0], p.c[1], p.c[2], p.a];
  if (p.kind === 'radial') {
    const d = Math.hypot(x - p.cx, y - p.cy);
    const t = clamp01((d - (p.r0 ?? 0)) / Math.max(1e-6, p.r1 - (p.r0 ?? 0)));
    return stopsAt(p.stops, t);
  }
  const dx = p.x1 - p.x0;
  const dy = p.y1 - p.y0;
  const t = clamp01(((x - p.x0) * dx + (y - p.y0) * dy) / (dx * dx + dy * dy || 1));
  const st = p.stops;
  let i = 0;
  while (i < st.length - 2 && t > st[i + 1][0]) i++;
  const [t0, c0] = st[i];
  const [t1, c1] = st[i + 1];
  const k = t1 === t0 ? 0 : (t - t0) / (t1 - t0);
  return [
    c0[0] + (c1[0] - c0[0]) * k,
    c0[1] + (c1[1] - c0[1]) * k,
    c0[2] + (c1[2] - c0[2]) * k,
    1,
  ];
}

/* ────────────────────────────── 光栅化 ────────────────────────────── */

/** 预乘 alpha 的浮点画布 */
function canvas(w, h, zoom = 1) {
  return { w, h, px: new Float64Array(w * h * 4), z: zoom };
}

/**
 * 画一个图形。
 * op: { sd, paint, alpha?, mode?: 'over'|'erase', glow?: 衰减宽度, clip? }
 * sd 以 1024 设计坐标书写，这里统一按 s 缩放。
 */
function draw(cv, s, op, clip) {
  const { w, h, px } = cv;
  const sd = op.sd;
  const mode = op.mode || 'over';
  const baseA = op.alpha ?? 1;
  const glow = op.glow ?? 0;
  const paint = op.paint;

  const z = cv.z || 1;
  const C0 = DESIGN / 2;
  for (let y = 0; y < h; y++) {
    const dy = y + 0.5;
    const Y = (dy / s - C0) / z + C0;
    for (let x = 0; x < w; x++) {
      const dx = x + 0.5;
      const d = sd((dx / s - C0) / z + C0, Y) * s * z; // 像素单位的距离
      let cov;
      if (glow > 0) {
        cov = clamp01(-d / (glow * s));
        if (cov <= 0) continue;
        cov = cov * cov * (3 - 2 * cov);
      } else {
        if (d >= 1) continue;
        cov = clamp01(0.5 - d);
      }
      if (clip) {
        const dc = clip((dx / s - C0) / z + C0, Y) * s * z;
        if (dc >= 1) continue;
        cov *= clamp01(0.5 - dc);
        if (cov <= 0) continue;
      }
      let a = cov * baseA;
      const o = (y * w + x) * 4;
      if (mode === 'erase') {
        const k = 1 - a;
        px[o] *= k;
        px[o + 1] *= k;
        px[o + 2] *= k;
        px[o + 3] *= k;
        continue;
      }
      let r, g, b, pa;
      if (paint.kind === 'solid') {
        r = paint.c[0];
        g = paint.c[1];
        b = paint.c[2];
        pa = paint.a ?? 1;
      } else {
        const q = paintAt(paint, (dx / s - C0) / z + C0, Y);
        r = q[0];
        g = q[1];
        b = q[2];
        pa = q[3];
      }
      a *= pa;
      if (a <= 0) continue;
      const ia = 1 - a;
      px[o] = r * a + px[o] * ia;
      px[o + 1] = g * a + px[o + 1] * ia;
      px[o + 2] = b * a + px[o + 2] * ia;
      px[o + 3] = a + px[o + 3] * ia;
    }
  }
}

/* ────────────────────────────── PNG 编码 ────────────────────────────── */

const CRC_TABLE = (() => {
  const t = new Uint32Array(256);
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    t[n] = c >>> 0;
  }
  return t;
})();

const crc32 = (buf) => {
  let c = 0xffffffff;
  for (let i = 0; i < buf.length; i++) c = CRC_TABLE[(c ^ buf[i]) & 0xff] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
};

const chunk = (type, data) => {
  const len = Buffer.alloc(4);
  len.writeUInt32BE(data.length);
  const body = Buffer.concat([Buffer.from(type, 'latin1'), data]);
  const crc = Buffer.alloc(4);
  crc.writeUInt32BE(crc32(body));
  return Buffer.concat([len, body, crc]);
};

/** 预乘浮点画布 → 直通 alpha 的 RGBA8 PNG */
function encodePNG(cv) {
  const { w, h, px } = cv;
  const raw = Buffer.alloc((w * 4 + 1) * h);
  let o = 0;
  for (let y = 0; y < h; y++) {
    raw[o++] = 0; // filter: none
    for (let x = 0; x < w; x++) {
      const i = (y * w + x) * 4;
      const a = px[i + 3];
      if (a <= 0.0001) {
        raw[o++] = 0;
        raw[o++] = 0;
        raw[o++] = 0;
        raw[o++] = 0;
      } else {
        const k = 1 / a;
        raw[o++] = Math.max(0, Math.min(255, Math.round(px[i] * k)));
        raw[o++] = Math.max(0, Math.min(255, Math.round(px[i + 1] * k)));
        raw[o++] = Math.max(0, Math.min(255, Math.round(px[i + 2] * k)));
        raw[o++] = Math.max(0, Math.min(255, Math.round(a * 255)));
      }
    }
  }
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(w, 0);
  ihdr.writeUInt32BE(h, 4);
  ihdr[8] = 8; // bit depth
  ihdr[9] = 6; // RGBA
  const png = Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk('IHDR', ihdr),
    chunk('IDAT', deflateSync(raw, { level: 9 })),
    chunk('IEND', Buffer.alloc(0)),
  ]);
  return { png, raw, w, h };
}

/* ────────────────────────────── 图标场景 ──────────────────────────────
 *
 * 每个候选 = { bg(cv, s), fg(cv, s) }：
 *   bg 铺满整张画布（会被启动器裁成系统形状）
 *   fg 只画主体（透明底，按系统安全区缩放）
 * 坐标一律写在 1024 设计空间，draw 内部按 s 换算。
 */

/** 柔和投影：主体下方一层模糊暗色，给奶油/橄榄色块一点体积感 */
const shadow = (cv, s, sdShape, color = SHADOW, alpha = 0.22, dy = 16, glow = 26) =>
  draw(cv, s, {
    sd: (x, y) => sdShape(x, y - dy),
    paint: solid(color),
    alpha,
    glow,
  });

const creamPaint = (cy, hh) => lin(0, cy - hh, 0, cy + hh, [[0, CREAM_HI], [1, CREAM_LO]]);
const olivePaint = (cy, hh) => lin(0, cy - hh, 0, cy + hh, [[0, OLIVE_HI], [1, OLIVE_LO]]);

/* ────────────────────────────── 柚子切面 ──────────────────────────────
 *
 * 形态：一整片柚子/柠檬切面 —— 外圈白皮、6 瓣果肉、加粗白瓣缝、果心。
 * 构图按图标来：切面直接铺满安全区，不要照片式的四周留白（边角交给系统圆角裁切）。
 * 共同几何用「内部为负」的 SDF 描述，两种质感复用：
 *   D 串珠版：整颗小圆珠铺满果皮与果肉，靠珠子排列自然收边
 *   E 简约平面版（当前使用）：平涂果肉 + 粗瓣缝，只在最外圈留一条极淡描边
 */

const CITRUS = {
  R_EDGE: 446, // 果皮外缘
  R_RIND_IN: 396, // 果皮内缘（白皮厚 50）
  R_FLESH: 382, // 果肉外缘（与果皮之间留一圈白瓤）
  R_CORE: 44, // 果心白瓤半径
  SEGS: 6, // 6 瓣：瓣数少一点更干净
  PITH_RAY: 16, // 瓣缝半宽（线条加粗：全宽 32）
  SPACING: 19, // 珠子间距（仅串珠版）
};

const C0 = DESIGN / 2;
const FLESH_IN = hex('#FCE483');
const FLESH_MID = hex('#F7CB40');
const FLESH_OUT = hex('#EAAF16');
const FLESH_FLAT = hex('#F8C63C'); // 简约版果肉：平涂
const PITH = hex('#FBF7EB'); // 白皮 / 白瓤 / 瓣缝：略带暖白，纯白底上仍能看出果皮
const RIND_EDGE = hex('#E9DFC6'); // 极淡的外描边，把圆形轮廓收住

const hash01 = (i, j, k) => {
  let h = Math.imul(i + 91, 374761393) ^ Math.imul(j + 173, 668265263) ^ Math.imul(k + 37, 2147483647);
  h = Math.imul(h ^ (h >>> 13), 1274126177);
  return ((h ^ (h >>> 16)) >>> 0) / 4294967296;
};

const lerpCol = (a, b, t) => [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t];
const mulCol = (c, k) => [c[0] * k, c[1] * k, c[2] * k];

/** 到最近分隔射线的垂直距离 */
function pithDist(x, y) {
  const step = (Math.PI * 2) / CITRUS.SEGS;
  const ang = Math.atan2(y, x);
  const m = ((ang % step) + step) % step;
  const dAng = Math.min(m, step - m);
  return Math.hypot(x, y) * Math.sin(dAng);
}

/** 果皮白环（内部为负） */
const rindSd = (x, y) => {
  const r = Math.hypot(x, y);
  return Math.max(r - CITRUS.R_EDGE, CITRUS.R_RIND_IN - r);
};

/** 果肉（内部为负）：圆环 ∩ 离开瓣缝 */
const fleshSd = (x, y) => {
  const r = Math.hypot(x, y);
  return Math.max(r - CITRUS.R_FLESH, CITRUS.R_CORE - r, CITRUS.PITH_RAY - pithDist(x, y));
};

/** 果肉按半径取色：内浅外深 */
const fleshColAt = (r) => {
  const t = clamp01((r - CITRUS.R_CORE) / (CITRUS.R_FLESH - CITRUS.R_CORE));
  return t < 0.5 ? lerpCol(FLESH_IN, FLESH_MID, t / 0.5) : lerpCol(FLESH_MID, FLESH_OUT, (t - 0.5) / 0.5);
};

/* ── 背景：纯白 ── */

/** 图标背景统一纯白（桌面 / 启动页 / 上架素材共用），不做奶油橘渐变 */
const WHITE = hex('#FFFFFF');

const whiteBg = (cv, s) => draw(cv, s, { sd: () => -DESIGN, paint: solid(WHITE) });

/* ── 平面版（简约） ── */

/** 简约画法：白皮 + 平涂果肉 + 粗瓣缝 + 一条极淡外描边，不画渐变/内阴影/高光 */
function drawCitrusFlat(cv, s) {
  // 果肉：平涂（瓣缝与果心由下层白瓤透出来）
  draw(cv, s, { sd: (x, y) => fleshSd(x - C0, y - C0), paint: solid(FLESH_FLAT) });

  // 果皮外缘一条极淡描边：白底上把圆形轮廓收住（简约版只有这一条线）
  draw(cv, s, {
    sd: (x, y) => Math.abs(Math.hypot(x - C0, y - C0) - CITRUS.R_EDGE) - 1.5,
    paint: solid(RIND_EDGE),
    alpha: 0.5,
  });
}

/* ── 串珠版 ── */

const beadList = (() => {
  const { SPACING, R_EDGE } = CITRUS;
  const sy = SPACING * 0.8660254;
  const beads = [];
  const cols = Math.ceil((R_EDGE + SPACING) / SPACING) + 1;
  const rows = Math.ceil((R_EDGE + SPACING) / sy) + 1;
  const rb = SPACING * 0.46;
  const margin = rb * 0.55; // 珠子中心离边界留一点距离 → 瓣缝/白瓤是干净的细线

  for (let j = -rows; j <= rows; j++) {
    const rowOff = j & 1 ? SPACING * 0.5 : 0;
    for (let i = -cols; i <= cols; i++) {
      const x = i * SPACING + rowOff + (hash01(i, j, 1) - 0.5) * SPACING * 0.05;
      const y = j * sy + (hash01(i, j, 2) - 0.5) * SPACING * 0.05;
      const r = Math.hypot(x, y);
      let col = null;
      if (rindSd(x, y) < -margin) col = hex('#FFFDF7');
      else if (fleshSd(x, y) < -margin) col = fleshColAt(r);
      if (!col) continue;
      const jitter = 1 + (hash01(i, j, 3) - 0.5) * 0.035;
      beads.push({
        x: C0 + x,
        y: C0 + y,
        r: rb * (0.97 + hash01(i, j, 4) * 0.05),
        c: mulCol(col, jitter),
      });
    }
  }
  return beads;
})();

function drawCitrusBeads(cv, s) {
  const z = cv.z || 1;
  const toPx = (d) => ((d - C0) * z + C0) * s;
  const { w, px } = cv;
  const S = s * z;

  const paint = (cx, cy, rad, shadeFn) => {
    const pad = 2;
    const x0 = Math.max(0, Math.floor(toPx(cx - rad - pad)));
    const x1 = Math.min(cv.w - 1, Math.ceil(toPx(cx + rad + pad)));
    const y0 = Math.max(0, Math.floor(toPx(cy - rad - pad)));
    const y1 = Math.min(cv.h - 1, Math.ceil(toPx(cy + rad + pad)));
    if (x0 > x1 || y0 > y1) return;
    for (let y = y0; y <= y1; y++) {
      const dY = ((y + 0.5) / s - C0) / z + C0;
      const ry = dY - C0;
      for (let x = x0; x <= x1; x++) {
        const dX = ((x + 0.5) / s - C0) / z + C0;
        const rx = dX - C0;
        const dx = dX - cx;
        const dy = dY - cy;
        const dl = Math.hypot(dx, dy);
        let cov = clamp01(0.5 - (dl - rad) * S);
        if (cov <= 0) continue;
        // 只画在切面里：外缘是干净的圆，瓣缝/白瓤里不出珠子
        cov *= clamp01(0.5 - Math.min(rindSd(rx, ry), fleshSd(rx, ry)) * S);
        if (cov <= 0) continue;
        const c = shadeFn(dx, dy, dl, rad);
        const a = cov * c[3];
        if (a <= 0) continue;
        const o = (y * w + x) * 4;
        const ia = 1 - a;
        px[o] = c[0] * a + px[o] * ia;
        px[o + 1] = c[1] * a + px[o + 1] * ia;
        px[o + 2] = c[2] * a + px[o + 2] * ia;
        px[o + 3] = a + px[o + 3] * ia;
      }
    }
  };

  for (const b of beadList) paint(b.x + 1.2, b.y + 2.2, b.r, () => [92, 66, 26, 0.18]);
  for (const b of beadList) {
    paint(b.x, b.y, b.r, (dx, dy, dl, rad) => {
      const nx = dx / rad;
      const ny = dy / rad;
      let k = 1 + 0.075 * (-0.5 * nx - 0.75 * ny); // 磨砂质感：只做明暗，不打白高光
      k *= 1 - 0.06 * Math.pow(Math.min(1, dl / rad), 4);
      return [Math.min(255, b.c[0] * k), Math.min(255, b.c[1] * k), Math.min(255, b.c[2] * k), 1];
    });
  }
}

/* 白瓤底衬：果皮、瓣缝、果心都是它（简约版：平涂，不做径向渐变） */
const pithBase = (cv, s) => draw(cv, s, { sd: circ(C0, C0, CITRUS.R_EDGE), paint: solid(PITH) });

/* 候选 D：串珠柚子切面 */
const D = {
  name: 'D-citrus-beads',
  zoom: 1,
  bg: whiteBg,
  fg(cv, s) {
    pithBase(cv, s);
    draw(cv, s, {
      sd: circ(C0 + 2, C0 + 9, CITRUS.R_EDGE + 3),
      paint: solid(hex('#8A6A31')),
      alpha: 0.16,
      glow: 7,
    });
    drawCitrusBeads(cv, s);
  },
};

/* 候选 E：平面简约柚子切面（当前使用） */
const E = {
  name: 'E-citrus-flat',
  zoom: 1,
  bg: whiteBg,
  fg(cv, s) {
    pithBase(cv, s);
    drawCitrusFlat(cv, s);
  },
};

const CANDIDATES = { D, E };

/* ────────────────────────────── 输出 ────────────────────────────── */

const ROUNDED_MASK = () =>
  rr(DESIGN / 2, DESIGN / 2, DESIGN / 2, DESIGN / 2, DESIGN * 0.235);

/** 合成一张图标：bg + fg（fg 单独一层，镂空处才能露出背景），可选系统形状遮罩 */
function compose(cand, size, { mask = false, layers = 'both' } = {}) {
  const s = size / DESIGN;
  const bg = canvas(size, size);
  if (layers !== 'fg') cand.bg(bg, s);
  if (layers === 'bg') return bg;

  const fg = canvas(size, size, cand.zoom ?? FG_ZOOM);
  cand.fg(fg, s);

  let out;
  if (layers === 'fg') {
    out = fg;
  } else {
    out = canvas(size, size);
    blit(out, bg, 0, 0);
    blit(out, fg, 0, 0);
  }
  if (!mask) return out;

  const clip = ROUNDED_MASK();
  for (let y = 0; y < size; y++) {
    for (let x = 0; x < size; x++) {
      const d = clip((x + 0.5) / s, (y + 0.5) / s) * s;
      const k = clamp01(0.5 - d);
      const o = (y * size + x) * 4;
      out.px[o] *= k;
      out.px[o + 1] *= k;
      out.px[o + 2] *= k;
      out.px[o + 3] *= k;
    }
  }
  return out;
}

/** 把 src 贴到 dst 的 (ox,oy)（简单 over） */
function blit(dst, src, ox, oy) {
  for (let y = 0; y < src.h; y++) {
    const ty = oy + y;
    if (ty < 0 || ty >= dst.h) continue;
    for (let x = 0; x < src.w; x++) {
      const tx = ox + x;
      if (tx < 0 || tx >= dst.w) continue;
      const si = (y * src.w + x) * 4;
      const a = src.px[si + 3];
      if (a <= 0) continue;
      const di = (ty * dst.w + tx) * 4;
      const ia = 1 - a;
      dst.px[di] = src.px[si] + dst.px[di] * ia;
      dst.px[di + 1] = src.px[si + 1] + dst.px[di + 1] * ia;
      dst.px[di + 2] = src.px[si + 2] + dst.px[di + 2] * ia;
      dst.px[di + 3] = a + dst.px[di + 3] * ia;
    }
  }
}

function fillBg(cv, rgb) {
  for (let i = 0; i < cv.px.length; i += 4) {
    cv.px[i] = rgb[0];
    cv.px[i + 1] = rgb[1];
    cv.px[i + 2] = rgb[2];
    cv.px[i + 3] = 1;
  }
}

/** 候选联系表：大图 + 多尺寸小样（浅底 / 深底） */
function contactSheet() {
  const M = 28;
  const hero = 460;
  const sizes = [192, 128, 72, 48, 32];
  const rowH = hero + M;
  const orderCount = Object.keys(CANDIDATES).length;
  const width = M + hero + M + sizes.reduce((a, b) => a + b + M, 0) + 340;
  const height = M + rowH * orderCount;
  const sheet = canvas(width, height);
  fillBg(sheet, hex('#F2F4EE'));

  const order = Object.values(CANDIDATES);
  order.forEach((cand, row) => {
    const oy = M + row * rowH;
    let ox = M;
    blit(sheet, compose(cand, hero, { mask: true }), ox, oy);
    ox += hero + M;

    for (const sz of sizes) {
      blit(sheet, compose(cand, sz, { mask: true }), ox, oy + (hero - sz) / 2);
      ox += sz + M;
    }
    // 深色底对照
    for (const sz of [72, 48]) {
      const tile = canvas(sz + 16, sz + 16);
      fillBg(tile, hex('#12150F'));
      blit(tile, compose(cand, sz, { mask: true }), 8, 8);
      blit(sheet, tile, ox, oy + (hero - sz) / 2);
      ox += sz + 16 + M;
    }
  });
  return sheet;
}

/** 生成候选预览与联系表 */
function genPreviews() {
  mkdirSync(OUT, { recursive: true });
  for (const [key, cand] of Object.entries(CANDIDATES)) {
    writeFileSync(join(OUT, `${key}-icon-1024.png`), encodePNG(compose(cand, 1024, { mask: true })).png);
    writeFileSync(join(OUT, `${key}-flat-1024.png`), encodePNG(compose(cand, 1024)).png);
    writeFileSync(join(OUT, `${key}-512.png`), encodePNG(compose(cand, 512, { mask: true })).png);
  }
  writeFileSync(join(OUT, 'contact-sheet.png'), encodePNG(contactSheet()).png);
}

/* ──────────────────────── 华为应用市场（AGC）素材 ────────────────────────
 *
 * AGC 上传图标硬性要求：216×216 px、PNG、直角、不透明。
 *   · 直角 —— 不能自己做圆角，商店/桌面由系统裁切；本函数因此不加 mask。
 *   · 不透明 —— 不能有透明通道的孔洞；背景层铺满整张画布保证 alpha 恒为 1。
 *   · 与包内一致 —— 审核会比对市场图标与包内 layered_image 的观感，
 *     这里与 --install 共用同一份 SDF 场景，同一候选渲染，天然不会跑偏。
 */
const STORE_SIZES = [
  { size: 216, file: 'harmonyos-app-icon-216.png', use: 'AGC 上传（必填）' },
  { size: 512, file: 'harmonyos-app-icon-512.png', use: '备用：推广位/第三方渠道' },
  { size: 1024, file: 'harmonyos-app-icon-1024.png', use: '备用：直角原图，可再缩放' },
];

function genStore(key = STORE_KEY) {
  const cand = CANDIDATES[key];
  if (!cand) throw new Error(`未知候选：${key}（可选 ${Object.keys(CANDIDATES).join('/')}）`);
  mkdirSync(STORE, { recursive: true });
  const rows = [];
  for (const { size, file, use } of STORE_SIZES) {
    const { png } = encodePNG(compose(cand, size));
    writeFileSync(join(STORE, file), png);
    rows.push({ file, size, bytes: png.length, use });
  }
  console.log(`上架素材（候选 ${key} · ${cand.name}）→ ${STORE}`);
  for (const r of rows) {
    console.log(`  ${r.file.padEnd(32)} ${String(r.size).padStart(4)}×${r.size}  ${(r.bytes / 1024).toFixed(1)} KB  ${r.use}`);
  }
}

/** 写入鸿蒙资源（必须整数值、1024 分层图 + 152 启动图） */
function install(key) {
  const cand = CANDIDATES[key];
  if (!cand) throw new Error(`未知候选：${key}（可选 A/B/C）`);
  mkdirSync(MEDIA, { recursive: true });
  const bg = encodePNG(compose(cand, 1024, { layers: 'bg' })).png;
  const fg = encodePNG(compose(cand, 1024, { layers: 'fg' })).png;
  const start = encodePNG(compose(cand, 152, { mask: true })).png;
  for (const dir of [APP_MEDIA, MEDIA]) {
    mkdirSync(dir, { recursive: true });
    writeFileSync(join(dir, 'background.png'), bg);
    writeFileSync(join(dir, 'foreground.png'), fg);
  }
  writeFileSync(join(MEDIA, 'startIcon.png'), start);
  console.log(`已写入候选 ${key} (${cand.name})`);
  console.log(`  ${APP_MEDIA}/background.png · foreground.png`);
  console.log(`  ${MEDIA}/background.png · foreground.png · startIcon.png`);
}

const args = process.argv.slice(2);
const iIdx = args.indexOf('--install');
const sIdx = args.indexOf('--store');
if (iIdx >= 0) install((args[iIdx + 1] || 'A').toUpperCase());
else if (sIdx >= 0) genStore((args[sIdx + 1] || STORE_KEY).toUpperCase());
else {
  genPreviews();
  console.log(`预览已生成 → ${OUT}`);
  genStore();
}
