#!/usr/bin/env python3
"""
从标本 tile 记录重建网格坐标（无需重拍）。

原理
----
每条记录带有 seq_id / parent_seq / direction，构成一条链：
    当前图的位置 = 父图位置 + 该 direction 的一格位移
从根图（parent_seq = 0）出发，按链累加即可得到每张图的行列坐标。

direction 取值（与 App 一致）:
    right  -> col + 1        左 left   -> col - 1
    bottom -> row + 1        上 top    -> row - 1

用法
----
    python3 rebuild_grid.py tiles.csv
    python3 rebuild_grid.py tiles.csv --stack 568
    python3 rebuild_grid.py tiles.csv --imagej positions.txt --step-px 3000

输入 CSV 需要包含列: stack_id, seq_id, parent_seq, direction
（从数据库导出后直接存成 CSV 即可，tab / 逗号分隔都能自动识别）
"""

import argparse
import csv
import sys
from collections import defaultdict

DELTA = {
    "right": (1, 0),    # (dcol, drow)
    "left": (-1, 0),
    "top": (0, -1),
    "bottom": (0, 1),
}

# 兼容中英文与大小写
ALIAS = {
    "右": "right", "左": "left", "上": "top", "下": "bottom",
    "up": "top", "down": "bottom",
}


def load_rows(path):
    with open(path, newline="", encoding="utf-8-sig") as f:
        sample = f.read(8192)
        f.seek(0)
        try:
            dialect = csv.Sniffer().sniff(sample, delimiters="\t,;")
        except csv.Error:
            dialect = csv.excel_tab if "\t" in sample else csv.excel
        return list(csv.DictReader(f, dialect=dialect))


def norm_dir(value):
    v = (value or "").strip().lower()
    v = ALIAS.get(v, v)
    return v if v in DELTA else None


def rebuild(rows):
    """返回 {seq_id: (row, col, direction)} 以及问题列表。"""
    problems = []
    parent_of = {}
    dir_of = {}
    seqs = []

    for r in rows:
        try:
            seq = int(r["seq_id"])
        except (KeyError, TypeError, ValueError):
            problems.append(f"跳过无法解析 seq_id 的行: {r}")
            continue
        seqs.append(seq)
        parent_of[seq] = int(r.get("parent_seq") or 0)
        dir_of[seq] = norm_dir(r.get("direction"))

    # 建 父 -> 子 映射
    children = defaultdict(list)
    for seq in seqs:
        children[parent_of[seq]].append(seq)

    coords = {}
    roots = children.get(0, [])
    if not roots:
        problems.append("没有找到 parent_seq=0 的根图")
    if len(roots) > 1:
        problems.append(f"存在多个根图 (parent_seq=0): {roots}，它们会被放在同一原点")

    stack = [(root, 0, 0) for root in roots]
    while stack:
        seq, row, col = stack.pop()
        if seq in coords:
            problems.append(f"seq {seq} 被重复访问（父链有环或多父）")
            continue
        coords[seq] = (row, col)

        for child in children.get(seq, []):
            d = dir_of.get(child)
            if d is None:
                problems.append(f"seq {child} 的 direction 无效: {dir_of.get(child)!r}")
                stack.append((child, row, col))
                continue
            dc, dr = DELTA[d]
            stack.append((child, row + dr, col + dc))

    # 未被访问到的（父链断裂）
    for seq in seqs:
        if seq not in coords:
            problems.append(f"seq {seq} 无法从根图连通（父 seq {parent_of.get(seq)} 可能不存在）")

    # 同格冲突
    occupied = defaultdict(list)
    for seq, (row, col) in coords.items():
        occupied[(row, col)].append(seq)
    for cell, seq_list in occupied.items():
        if len(seq_list) > 1:
            problems.append(f"坐标冲突 {cell}: seq {sorted(seq_list)} 落在同一格")

    return coords, dir_of, problems


def ascii_map(coords):
    if not coords:
        return "(无可绘制数据)"
    rows = [rc[0] for rc in coords.values()]
    cols = [rc[1] for rc in coords.values()]
    r0, r1 = min(rows), max(rows)
    c0, c1 = min(cols), max(cols)

    cell_w = max(len(str(s)) for s in coords)
    lines = []
    for r in range(r0, r1 + 1):
        cells = []
        for c in range(c0, c1 + 1):
            hit = [s for s, (rr, cc) in coords.items() if rr == r and cc == c]
            cells.append(str(hit[0]).rjust(cell_w) if hit else "·".rjust(cell_w))
        lines.append("row %2d | " % r + " ".join(cells))
    header = "        " + " ".join(f"c{c}".rjust(cell_w) for c in range(c0, c1 + 1))
    return "\n".join([header] + lines)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("csv_path", help="导出的 tile CSV")
    ap.add_argument("--stack", type=int, default=None, help="只处理指定 stack_id")
    ap.add_argument("--imagej", default=None, help="导出 ImageJ TileConfiguration 文件")
    ap.add_argument("--step-px", type=float, default=0.0,
                    help="每格位移的像素数(视场宽 × (1-重叠率))，用于 ImageJ 绝对坐标")
    ap.add_argument("--out", default=None, help="把重建结果另存为 CSV")
    args = ap.parse_args()

    rows = load_rows(args.csv_path)
    if args.stack is not None:
        rows = [r for r in rows if str(r.get("stack_id", "")).strip() == str(args.stack)]

    if not rows:
        print("没有匹配的数据行")
        sys.exit(1)

    coords, dir_of, problems = rebuild(rows)

    print(f"共 {len(coords)} 张图\n")
    print(f"{'seq':>5} {'direction':>10} {'row':>5} {'col':>5}")
    for seq in sorted(coords):
        row, col = coords[seq]
        print(f"{seq:>5} {str(dir_of.get(seq)):>10} {row:>5} {col:>5}")

    print("\n布局预览:")
    print(ascii_map(coords))

    if problems:
        print("\n⚠️ 发现的问题:")
        for p in problems:
            print("  - " + p)
    else:
        print("\n✅ 校验通过：无坐标冲突、无断链")

    if args.out:
        with open(args.out, "w", newline="", encoding="utf-8") as f:
            w = csv.writer(f)
            w.writerow(["seq_id", "direction", "row", "col"])
            for seq in sorted(coords):
                row, col = coords[seq]
                w.writerow([seq, dir_of.get(seq), row, col])
        print(f"\n已写出: {args.out}")

    if args.imagej:
        if args.step_px <= 0:
            print("\n⚠️ 未提供 --step-px，ImageJ 文件将使用格子索引而非像素坐标")
        step = args.step_px if args.step_px > 0 else 1.0
        with open(args.imagej, "w", encoding="utf-8") as f:
            f.write("# Define the number of dimensions (2D)\n")
            f.write("dim = 2\n")
            f.write("# Define the image coordinates\n")
            for seq in sorted(coords):
                row, col = coords[seq]
                f.write(f"{seq}.jpg; ; ({col * step:.2f}, {row * step:.2f})\n")
        print(f"已写出 ImageJ 坐标文件: {args.imagej}")


if __name__ == "__main__":
    main()
