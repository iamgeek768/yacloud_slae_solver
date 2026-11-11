#!/usr/bin/env python3
"""Генератор СЛАУ Ax = b со строгим диагональным преобладанием.

Формат matrix.bin: int64 n (little-endian), затем n строк по n+1 float64:
строка i = [a_i0 ... a_i,n-1, b_i]. Формат x_true.bin: int64 n, затем n float64.
"""
import argparse
import sys

import numpy as np


def main():
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("--n", type=int, required=True, help="размерность системы")
    p.add_argument("--out", required=True, help="файл расширенной матрицы")
    p.add_argument("--x-true", dest="x_true", help="файл с точным решением")
    p.add_argument("--seed", type=int, default=42)
    p.add_argument("--dominance", type=float, default=1.1,
                   help="a_ii = dominance * сумма |a_ij|, j != i; ближе к 1 — больше итераций")
    p.add_argument("--block", type=int, default=256, help="строк в блоке записи")
    args = p.parse_args()

    if args.n < 1:
        sys.exit("--n должно быть >= 1")
    if args.dominance <= 1.0:
        sys.exit("--dominance должно быть > 1, иначе сходимость Якоби не гарантирована")

    n = args.n
    rng = np.random.default_rng(args.seed)
    x_true = rng.uniform(-1.0, 1.0, n)

    with open(args.out, "wb") as f:
        np.array([n], dtype="<i8").tofile(f)
        for start in range(0, n, args.block):
            rows = min(args.block, n - start)
            # Внедиагональные элементы одного знака: спектральный радиус матрицы
            # итераций Якоби близок к 1/dominance, число итераций управляемо.
            blk = rng.uniform(0.0, 1.0, (rows, n))
            idx = np.arange(rows)
            blk[idx, start + idx] = 0.0
            diag = args.dominance * blk.sum(axis=1)
            blk[idx, start + idx] = np.where(diag > 0.0, diag, 1.0)
            b = blk @ x_true
            np.hstack([blk, b[:, None]]).astype("<f8").tofile(f)

    if args.x_true:
        with open(args.x_true, "wb") as f:
            np.array([n], dtype="<i8").tofile(f)
            x_true.astype("<f8").tofile(f)

    print(f"n={n} файл={args.out} размер={8 + 8 * n * (n + 1)} байт")


if __name__ == "__main__":
    main()
