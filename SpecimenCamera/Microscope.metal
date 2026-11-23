//
//  Microscope.metal
//  显微镜模拟器: 目镜光学效果 shader
//
//  说明:
//  - SwiftUI 负责平移/缩放标本大图(GPU 无损合成), 本 shader 只做"光学":
//    1) 散焦: 圆盘 CoC(Circle of Confusion)加权采样 —— 真实离焦 PSF, 非高斯
//    2) 场曲: 视野边缘比中心略糊(真实目镜特性)
//    3) 横向色差: 边缘 R/B 通道分离
//    4) 暗角 + 圆形遮罩(目镜视场光阑), 圆外全黑
//    5) 轻微噪点颗粒感
//  - iOS 平台图形 API 是 Metal, 无法使用 Vulkan/Taichi 运行时;
//    本 shader 与 Taichi 算子同源(并行 PSF 卷积), 性能同级。
//

#include <metal_stdlib>
using namespace metal;
#include <SwiftUI/SwiftUI_Metal.h>

// 简单 hash 噪声
static inline float hash21(float2 p) {
    float3 p3 = fract(float3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

// 显微目镜视野
// viewSize: 渲染区域尺寸(pt); focus: -1(前离焦)..0(合焦)..1(后离焦)
[[ stitchable ]] half4 microscopeView(
    float2 pos,
    SwiftUI::Layer layer,
    float2 viewSize,
    float focus)
{
    float2 p = pos - viewSize * 0.5f;
    float r = length(p);
    float viewRadius = min(viewSize.x, viewSize.y) * 0.5f;
    float rn = r / viewRadius;                 // 归一化半径

    // ---- 散焦(显示点单位): |focus| 控制失焦量; 场曲使边缘额外变糊 ----
    float blur = abs(focus) * 30.0f + rn * rn * 5.0f;
    blur = min(blur, 56.0f);

    float2 uv = pos / viewSize;
    float3 col;
    if (blur < 0.6f) {
        col = float3(layer.sample(uv).rgb);
    } else {
        // 圆盘(CoC)加权采样: 黄金角螺旋分布, 盘边缘权重衰减(模拟衍射核)
        // 注: SwiftUI::Layer 无法按值传给辅助函数, 循环必须内联在 stitchable 函数内
        constexpr int N = 24;
        constexpr float GOLDEN = 2.39996323f;
        float2 radiusUV = blur / viewSize;     // 以归一化 uv 为单位的模糊半径
        float3 acc = float3(0.0f);
        float wsum = 0.0f;
        for (int i = 0; i < N; ++i) {
            float t = (float(i) + 0.5f) / float(N);
            float ang = float(i) * GOLDEN;
            float2 d = float2(cos(ang), sin(ang)) * (sqrt(t) * radiusUV);
            float w = 1.0f - 0.45f * t;
            acc += float3(layer.sample(uv + d).rgb) * w;
            wsum += w;
        }
        col = acc / wsum;
    }

    // ---- 横向色差: 边缘 R/B 分离(合焦时也保留, 更真实) ----
    if (rn > 0.35f) {
        float ca = (rn * rn) * 0.006f;         // uv 偏移量
        float2 dir = (r > 1.0f ? p / r : float2(0.0f)) / viewSize;
        col.r = float3(layer.sample(uv + dir * ca).rgb).r;
        col.b = float3(layer.sample(uv - dir * ca).rgb).b;
    }

    // ---- 暗角 + 圆形视场光阑 ----
    float vig = 1.0f - 0.38f * rn * rn;
    float edge = 1.0f - smoothstep(0.90f, 1.0f, rn);
    float mask = (rn > 1.0f) ? 0.0f : edge;
    col *= vig * mask;

    // ---- 噪点颗粒(传感器/目镜颗粒感), 圆外不加 ----
    col += (hash21(pos) - 0.5f) * 0.035f * mask;

    return half4(half3(col), 1.0h);
}
