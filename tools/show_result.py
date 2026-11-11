#!/usr/bin/env python3
"""Распаковывает решение из x.bin и печатает его вместе со статистикой запуска.

Использование:
    python3 tools/show_result.py results/<run_id>
    python3 tools/show_result.py results/<run_id> --matrix data/example_3x3.bin
    python3 tools/show_result.py results/<run_id>/x.bin --x-true data/example_3x3_x_true.bin

Если передан каталог, берутся x.bin и result.json из него. С --matrix для каждого
уравнения выводится подстановка решения (для систем до 20 уравнений) и общая невязка.
"""
import argparse
import json
import os
import sys

import numpy as np

SHOW_ALL_UP_TO = 20


def read_vector(path):
    with open(path, "rb") as f:
        n = int(np.fromfile(f, dtype="<i8", count=1)[0])
        v = np.fromfile(f, dtype="<f8", count=n)
    if v.size != n:
        sys.exit(f"{path}: ожидалось {n} чисел, прочитано {v.size}")
    return v


def print_stats(path):
    with open(path) as f:
        s = json.load(f)
    print(f"Запуск {s['run_id']}:")
    print(f"  уравнений:        {s['n']}")
    print(f"  MPI-процессов:    {s['procs']}, потоков OpenMP: {s['threads']}")
    print(f"  итераций:         {s['iterations']}")
    print(f"  невязка:          {s['residual']:.3e}")
    print(f"  сошлось:          {'да' if s['converged'] else 'нет'}")
    print(f"  время решения:    {s['t_solve_sec']:.3f} с (всего {s['t_total_sec']:.3f} с)")
    print()


def print_solution(x):
    print(f"Решение, значений: {x.size}")
    if x.size <= SHOW_ALL_UP_TO:
        for i, v in enumerate(x):
            print(f"  x{i + 1} = {v:.10f}")
    else:
        for i in range(5):
            print(f"  x{i + 1} = {x[i]:.10f}")
        print("  ...")
        for i in range(x.size - 5, x.size):
            print(f"  x{i + 1} = {x[i]:.10f}")
        print(f"  минимум {x.min():.6f}, максимум {x.max():.6f}")
    print()


def check_matrix(path, x):
    with open(path, "rb") as f:
        n = int(np.fromfile(f, dtype="<i8", count=1)[0])
        if n != x.size:
            print(f"Проверка пропущена: в {path} {n} уравнений, а в решении {x.size}.")
            return
        rr = bb = 0.0
        if n <= SHOW_ALL_UP_TO:
            print(f"Подстановка решения в уравнения ({path}):")
        for start in range(0, n, 256):
            rows = min(256, n - start)
            blk = np.fromfile(f, dtype="<f8", count=rows * (n + 1)).reshape(rows, n + 1)
            lhs = blk[:, :n] @ x
            r = lhs - blk[:, n]
            rr += float(r @ r)
            bb += float(blk[:, n] @ blk[:, n])
            if n <= SHOW_ALL_UP_TO:
                for i in range(rows):
                    print(f"  уравнение {start + i + 1}: левая часть = {lhs[i]:.10f}, "
                          f"правая часть = {blk[i, n]:g}, разница = {r[i]:.2e}")
    print(f"Относительная невязка ||Ax - b|| / ||b|| = {(rr / bb) ** 0.5 if bb else rr ** 0.5:.3e}")
    print()


def main():
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("path", help="каталог results/<run_id> или файл x.bin")
    p.add_argument("--matrix", help="файл системы для подстановки решения")
    p.add_argument("--x-true", dest="x_true", help="файл с точным решением для сравнения")
    args = p.parse_args()

    if os.path.isdir(args.path):
        x_path = os.path.join(args.path, "x.bin")
        stats_path = os.path.join(args.path, "result.json")
    else:
        x_path = args.path
        stats_path = os.path.join(os.path.dirname(args.path), "result.json")
    if not os.path.exists(x_path):
        sys.exit(f"нет файла {x_path}: сначала скачайте результат (make results RUN=<run_id>)")

    if os.path.exists(stats_path):
        print_stats(stats_path)
    x = read_vector(x_path)
    print_solution(x)

    if args.matrix:
        if os.path.exists(args.matrix):
            check_matrix(args.matrix, x)
        else:
            print(f"Проверка пропущена: нет файла {args.matrix}.")
    if args.x_true:
        err = float(np.max(np.abs(x - read_vector(args.x_true))))
        print(f"Максимальное отклонение от точного решения: {err:.3e}")


if __name__ == "__main__":
    main()
