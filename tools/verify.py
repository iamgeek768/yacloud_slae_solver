#!/usr/bin/env python3
"""Проверка решения СЛАУ: относительная невязка и отклонение от точного решения.

Код возврата 0, если все проверяемые величины меньше --tol, иначе 1.
"""
import argparse
import sys

import numpy as np


def read_vector(path):
    with open(path, "rb") as f:
        n = int(np.fromfile(f, dtype="<i8", count=1)[0])
        v = np.fromfile(f, dtype="<f8", count=n)
    if v.size != n:
        sys.exit(f"{path}: ожидалось {n} значений, прочитано {v.size}")
    return v


def main():
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("--matrix", required=True)
    p.add_argument("--x", required=True)
    p.add_argument("--x-true", dest="x_true")
    p.add_argument("--tol", type=float, default=1e-6)
    p.add_argument("--block", type=int, default=256)
    args = p.parse_args()

    x = read_vector(args.x)
    rr = 0.0
    bb = 0.0
    with open(args.matrix, "rb") as f:
        n = int(np.fromfile(f, dtype="<i8", count=1)[0])
        if x.size != n:
            sys.exit(f"размерность решения {x.size} не совпадает с размерностью системы {n}")
        for start in range(0, n, args.block):
            rows = min(args.block, n - start)
            blk = np.fromfile(f, dtype="<f8", count=rows * (n + 1))
            if blk.size != rows * (n + 1):
                sys.exit(f"{args.matrix}: файл короче, чем заявлено в заголовке")
            blk = blk.reshape(rows, n + 1)
            r = blk[:, :n] @ x - blk[:, n]
            rr += float(r @ r)
            bb += float(blk[:, n] @ blk[:, n])

    residual = (rr / bb) ** 0.5 if bb > 0 else rr ** 0.5
    ok = residual < args.tol
    print(f"n={n} относительная невязка ||Ax-b||/||b|| = {residual:.3e}")

    if args.x_true:
        err = float(np.max(np.abs(x - read_vector(args.x_true))))
        ok = ok and err < args.tol
        print(f"максимальное отклонение от точного решения = {err:.3e}")

    print("OK" if ok else f"FAIL (порог {args.tol:g})")
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
