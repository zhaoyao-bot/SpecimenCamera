//
//  Microscope.metal
//  显微镜模拟器: 目镜光学效果 shader
//
//  说明:
//  - SwiftUI 负责平移/缩放与三焦面混合(GPU 无损合成), 本 shader 只做"光学":
//    1) 横向色差: 视野边缘 R/B 通道分离
//    2) 暗角 + 圆形视场光阑, 圆外全黑
//    3) 轻微噪点颗粒感
//  - 离焦不再用卷积模拟: 由三焦面真实数据插值(bottom/mid/top opacity 混合)完成
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

// 显微目镜视野(混合后的最终画面)
[[ stitchable ]] half4 microscopeView(
    float2 pos,
    SwiftUI::Layer layer,
    float2 viewSize)
{
    float2 p = pos - viewSize * 0.5f;
    float r = length(p);
    float viewRadius = min(viewSize.x, viewSize.y) * 0.5f;
    float rn = r / viewRadius;                 // 归一化半径

    float2 uv = pos / viewSize;
    float3 col = float3(layer.sample(uv).rgb);

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
