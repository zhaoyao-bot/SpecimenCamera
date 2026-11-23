#!/usr/bin/env python3
"""
Richardson-Lucy 去卷积（Taichi GPU 加速）

反复执行:
    模糊估计   = PSF      ⊛ 当前估计
    修正因子   = 观测图 / 模糊估计
    当前估计  ⊛= PSF翻转 ⊛ 修正因子

PSF 默认用显微衍射极限的高斯近似:
    sigma_um = 0.21 * wavelength / NA
    sigma_px = sigma_um * px_per_um        (px_per_um 来自 App 标定的标尺)

用法
----
    # 直接指定像素 sigma
    python3 richardson_lucy.py input.png -o out.png --sigma-px 2.5 --iters 30

    # 从光学参数推导 sigma(推荐, 与 App 标定的 px/μm 配合)
    python3 richardson_lucy.py input.png \
        --px-per-um 3.2 --na 0.65 --wavelength-nm 550 --iters 50

    # 无 GPU 也能跑(自动回退 CPU)
    python3 richardson_lucy.py input.png --arch cpu
"""

import argparse
import sys

import numpy as np
from PIL import Image

import taichi as ti

EPS = 1e-6


def build_psf_sigma(args) -> float:
    """sigma(px)：优先用 --sigma-px，否则由光学参数推导。"""
    if args.sigma_px:
        return args.sigma_px
    if not args.px_per_um:
        sys.exit("需要 --sigma-px 或 --px-per-um 之一")
    lam_um = args.wavelength_nm / 1000.0
    sigma_um = 0.21 * lam_um / args.na
    return sigma_um * args.px_per_um


def main():
    ap = argparse.ArgumentParser(description="Richardson-Lucy deconvolution (Taichi)")
    ap.add_argument("input", help="输入图像(PNG/JPG)")
    ap.add_argument("-o", "--output", default="deconv.png", help="输出图像")
    ap.add_argument("--sigma-px", type=float, default=0, help="高斯 PSF 的像素 sigma")
    ap.add_argument("--px-per-um", type=float, default=0, help="标定的像素/微米")
    ap.add_argument("--na", type=float, default=0.65, help="物镜数值孔径")
    ap.add_argument("--wavelength-nm", type=float, default=550, help="中心波长 nm")
    ap.add_argument("--iters", type=int, default=30, help="RL 迭代次数")
    ap.add_argument("--arch", default="gpu", choices=["gpu", "cpu"], help="计算后端")
    args = ap.parse_args()

    ti.init(arch=ti.gpu if args.arch == "gpu" else ti.cpu)

    sigma = build_psf_sigma(args)
    print(f"PSF sigma = {sigma:.2f} px, iters = {args.iters}")

    # ---- 读图并归一化到 [0,1] (RL 在泊松噪声假设下要求正值) ----
    obs = np.asarray(Image.open(args.input).convert("RGB"), dtype=np.float32)
    H, W, C = obs.shape
    scale = max(float(obs.max()), 1e-9)
    obs_n = obs / scale

    # ---- 高斯核(可分离: 横向/纵向两个 1D pass, O(R) 而非 O(R^2)) ----
    R = max(1, int(np.ceil(3.0 * sigma)))
    xs = np.arange(-R, R + 1, dtype=np.float32)
    g = np.exp(-(xs * xs) / (2.0 * sigma * sigma))
    g /= g.sum()
    print(f"kernel radius = {R}")

    # ---- Taichi fields ----
    obs_f = ti.field(ti.f32, shape=(H, W, C))
    est = ti.field(ti.f32, shape=(H, W, C))
    blurred = ti.field(ti.f32, shape=(H, W, C))
    ratio = ti.field(ti.f32, shape=(H, W, C))
    tmp1 = ti.field(ti.f32, shape=(H, W, C))
    tmp2 = ti.field(ti.f32, shape=(H, W, C))
    gauss = ti.field(ti.f32, shape=2 * R + 1)

    obs_f.from_numpy(obs_n)
    est.from_numpy(obs_n.copy())
    gauss.from_numpy(g)

    # ---- 可分离卷积 (flip=True 表示用 PSF 翻转核; 高斯偶对称等价, 保留通用性) ----
    @ti.kernel
    def conv_h(src: ti.template(), dst: ti.template(), flip: ti.i32):
        for i, j, c in src:
            acc = 0.0
            for k in range(-R, R + 1):
                jj = j - k if flip else j + k
                jj = ti.max(0, ti.min(W - 1, jj))  # clamp 边界
                acc += src[i, jj, c] * gauss[k + R]
            dst[i, j, c] = acc

    @ti.kernel
    def conv_v(src: ti.template(), dst: ti.template(), flip: ti.i32):
        for i, j, c in src:
            acc = 0.0
            for k in range(-R, R + 1):
                ii = i - k if flip else i + k
                ii = ti.max(0, ti.min(H - 1, ii))
                acc += src[ii, j, c] * gauss[k + R]
            dst[i, j, c] = acc

    @ti.kernel
    def compute_ratio():
        for i, j, c in blurred:
            ratio[i, j, c] = obs_f[i, j, c] / ti.max(blurred[i, j, c], EPS)

    @ti.kernel
    def apply_correction():
        for i, j, c in est:
            est[i, j, c] *= ti.max(tmp2[i, j, c], 0.0)

    # ---- RL 主循环 ----
    for it in range(1, args.iters + 1):
        # 1) 模糊估计 = PSF ⊛ 当前估计
        conv_h(est, tmp1, 0)
        conv_v(tmp1, blurred, 0)

        # 2) 修正因子 = 观测图 / 模糊估计
        compute_ratio()

        # 3) 当前估计 ⊛= PSF翻转 ⊛ 修正因子
        conv_h(ratio, tmp1, 1)
        conv_v(tmp1, tmp2, 1)
        apply_correction()

        if it % 5 == 0 or it == 1 or it == args.iters:
            print(f"iter {it}/{args.iters} done")

    # ---- 输出 ----
    out = est.to_numpy() * scale
    out = np.clip(out, 0, 255).astype(np.uint8)
    Image.fromarray(out).save(args.output)
    print(f"已保存: {args.output}")


if __name__ == "__main__":
    main()
