// Metal shader source, compiled at runtime (keeps the Swift package free of resource bundling).
//
// Everything on the fretboard is one instanced quad with a signed-distance-field fragment shader.
// params.x selects the primitive kind:
//   0 wood board   1 rounded rect / soft shadow   2 string   3 note marker
//   4 text (atlas) 5 ring                          6 pearl inlay   7 background vignette

enum ShaderSource {
    static let code = """
#include <metal_stdlib>
using namespace metal;

struct Instance {
    float4 rect;     // center.xy, size.wh  (points, top-left origin)
    float4 color;
    float4 color2;
    float4 params;   // kind, radius/thickness, softness/pad, extra
    float4 uv;       // atlas rect (u0, v0, u1, v1)
};

struct Uniforms {
    float2 viewport;
    float  time;
    float  scale;
};

struct VOut {
    float4 position [[position]];
    float2 local;
    float2 uv;
    float2 tex;
    float4 color    [[flat]];
    float4 color2   [[flat]];
    float4 params   [[flat]];
    float2 halfSize [[flat]];
};

vertex VOut vmain(uint vid [[vertex_id]],
                  uint iid [[instance_id]],
                  const device Instance *instances [[buffer(0)]],
                  constant Uniforms &u [[buffer(1)]]) {
    Instance I = instances[iid];
    float2 corner = float2(float(vid & 1u), float(vid >> 1u));
    float2 hs = I.rect.zw * 0.5;
    int kind = int(I.params.x + 0.5);
    float pad = (kind == 4) ? 0.0 : (I.params.z + 1.5);
    float2 ext = hs + pad;
    float2 local = (corner * 2.0 - 1.0) * ext;
    float2 p = I.rect.xy + local;

    VOut o;
    o.position = float4(p.x / u.viewport.x * 2.0 - 1.0, 1.0 - p.y / u.viewport.y * 2.0, 0.0, 1.0);
    o.local = local;
    o.uv = local / max(hs * 2.0, float2(0.0001)) + 0.5;
    o.tex = mix(I.uv.xy, I.uv.zw, o.uv);
    o.color = I.color;
    o.color2 = I.color2;
    o.params = I.params;
    o.halfSize = hs;
    return o;
}

static float hash21(float2 p) {
    p = fract(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

static float vnoise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    float2 w = f * f * (3.0 - 2.0 * f);
    float a = hash21(i);
    float b = hash21(i + float2(1.0, 0.0));
    float c = hash21(i + float2(0.0, 1.0));
    float d = hash21(i + float2(1.0, 1.0));
    return mix(mix(a, b, w.x), mix(c, d, w.x), w.y);
}

static float fbm(float2 p) {
    float v = 0.0;
    float a = 0.5;
    for (int i = 0; i < 5; i++) {
        v += a * vnoise(p);
        p = p * 2.03 + float2(17.0, 9.0);
        a *= 0.5;
    }
    return v;
}

static float sdRoundBox(float2 p, float2 b, float r) {
    r = min(r, min(b.x, b.y));
    float2 q = abs(p) - b + r;
    return length(max(q, float2(0.0))) + min(max(q.x, q.y), 0.0) - r;
}

static float4 premul(float3 c, float a) {
    return float4(c * a, a);
}

fragment float4 fmain(VOut in [[stage_in]],
                      texture2d<float> atlas [[texture(0)]],
                      constant Uniforms &u [[buffer(1)]]) {
    constexpr sampler smp(filter::linear, address::clamp_to_edge);
    int kind = int(in.params.x + 0.5);
    float2 p = in.local;
    float2 b = in.halfSize;
    float aa = 0.8 / max(u.scale, 1.0);

    switch (kind) {
    case 0: { // ---------- wood
        float d = sdRoundBox(p, b, in.params.y);
        float a = 1.0 - smoothstep(-aa, aa, d);
        float2 q = p + b;
        float warp = fbm(q * float2(0.004, 0.03)) * 6.0;
        float g = fbm(float2(q.x * 0.006, q.y * 0.11 + warp));
        float lines = 0.5 + 0.5 * sin(q.y * 0.55 + g * 14.0);
        float t = clamp(g * 0.9 + lines * 0.25 - 0.1, 0.0, 1.0);
        float3 c = mix(in.color.rgb, in.color2.rgb, t);
        float pores = smoothstep(0.93, 1.0, vnoise(q * float2(0.35, 2.2)));
        c *= 1.0 - pores * 0.3;
        float edge = smoothstep(0.0, 14.0, -d);
        c *= mix(0.6, 1.0, edge);
        c += 0.035 * (1.0 - abs(clamp(in.uv.y, 0.0, 1.0) * 2.0 - 1.0));
        return premul(c, a);
    }
    case 1: { // ---------- rounded rect / soft shadow
        float soft = max(in.params.z, aa);
        float d = sdRoundBox(p, b, in.params.y);
        float a = 1.0 - smoothstep(-soft, soft, d);
        int g = int(in.params.w + 0.5);
        float ux = clamp(in.uv.x, 0.0, 1.0);
        float uy = clamp(in.uv.y, 0.0, 1.0);
        float t = uy;
        if (g == 1) { t = 1.0 - abs(ux * 2.0 - 1.0); }
        if (g == 2) { t = 1.0 - abs(uy * 2.0 - 1.0); }
        float4 c = mix(in.color, in.color2, t);
        return premul(c.rgb, c.a * a);
    }
    case 2: { // ---------- string (cylinder)
        float v = clamp(p.y / max(b.y, 0.001), -1.0, 1.0);
        float a = 1.0 - smoothstep(b.y - aa, b.y + aa, abs(p.y));
        a *= 1.0 - smoothstep(b.x - 1.0, b.x, abs(p.x));
        float shade = sqrt(max(0.0, 1.0 - v * v));
        float3 c = mix(in.color2.rgb, in.color.rgb, shade);
        float spec = pow(max(0.0, 1.0 - abs(v + 0.35) * 2.2), 3.0);
        c += spec * 0.45;
        if (in.params.w > 0.5) {
            float wind = 0.5 + 0.5 * sin(p.x * 2.2 + v * 2.5);
            c *= mix(0.7, 1.05, wind);
        }
        return premul(c, a * in.color.a);
    }
    case 3: { // ---------- note marker (glossy disc + optional glow)
        float r = b.x;
        float d = length(p) - r;
        float a = 1.0 - smoothstep(-aa, aa, d);
        float2 lp = p / r;
        float l = clamp(1.15 - length(lp - float2(-0.35, -0.45)) * 0.75, 0.0, 1.0);
        float3 c = mix(in.color2.rgb, in.color.rgb, l);
        float rim = smoothstep(-r * 0.18, 0.0, d);
        c = mix(c, in.color2.rgb * 0.7, rim * 0.55);
        float gl = 1.0 - smoothstep(0.0, 0.45, length((lp - float2(0.0, -0.5)) * float2(0.8, 1.6)));
        c += gl * 0.22;
        float alpha = in.color.a;
        float4 body = premul(c, a * alpha);
        float glowAmt = in.params.w;
        if (glowAmt > 0.0) {
            float gd = max(d, 0.0);
            float glow = exp(-gd / max(r * 0.35, 1.0)) * glowAmt * (1.0 - a) * 0.8;
            float4 gcol = premul(in.color.rgb, clamp(glow, 0.0, 1.0) * alpha);
            body = body + gcol * (1.0 - body.a);
        }
        return body;
    }
    case 4: { // ---------- text from glyph atlas
        float s = atlas.sample(smp, in.tex).r;
        return premul(in.color.rgb, s * in.color.a);
    }
    case 5: { // ---------- ring (quad half size = radius + thickness)
        float th = in.params.y;
        float r = b.x - th;
        float d = abs(length(p) - r) - th * 0.5;
        float a = 1.0 - smoothstep(-aa, aa, d);
        return premul(in.color.rgb, a * in.color.a);
    }
    case 6: { // ---------- mother-of-pearl inlay
        float r = b.x;
        float d = length(p) - r;
        float a = 1.0 - smoothstep(-aa, aa, d);
        float n = fbm(p * 0.25 + float2(3.1, 7.7));
        float3 c = mix(in.color.rgb, in.color2.rgb, n);
        c += 0.06 * (0.5 + 0.5 * sin(n * 9.0 + p.x * 0.3));
        float e = smoothstep(-r * 0.35, 0.0, d);
        c *= 1.0 - e * 0.2;
        return premul(c, a * in.color.a);
    }
    case 7: { // ---------- background vignette
        float2 uv = in.uv;
        float t = clamp(length((uv - float2(0.5, 0.45)) * float2(1.0, 1.4)), 0.0, 1.0);
        float3 c = mix(in.color.rgb, in.color2.rgb, smoothstep(0.1, 0.9, t));
        return float4(c, 1.0);
    }
    default:
        return float4(0.0);
    }
}
"""
}
