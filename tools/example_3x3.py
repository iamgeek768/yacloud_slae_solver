#!/usr/bin/env python3
"""

Система:

    10·x1 + 2·x2 + 1·x3 = 17
     1·x1 + 8·x2 + 2·x3 = 23
     2·x1 + 1·x2 + 9·x3 = 31

Точное решение: x1 = 1, x2 = 2, x3 = 3.

В матричной форме A·x = b:

        | 10  2  1 |        | 17 |
    A = |  1  8  2 |,   b = | 23 |
        |  2  1  9 |        | 31 |

Диагональ преобладает (10 > 2 + 1, 8 > 1 + 2, 9 > 2 + 1), поэтому метод Якоби сходится.

Файл в формате решателя: int64 n, затем n строк по n+1 чисел float64 — [a_i1, ..., a_in, b_i].
Кластер из трёх узлов получает по одной строке на узел.
 
"""
import argparse
import os

import numpy as np

A = np.array([
    [10.0, 2.0, 1.0],
    [1.0, 8.0, 2.0],
    [2.0, 1.0, 9.0],
])
b = np.array([17.0, 23.0, 31.0])
X_TRUE = np.array([1.0, 2.0, 3.0])


def write_vector(path, v):
    with open(path, "wb") as f:
        np.array([len(v)], dtype="<i8").tofile(f)
        v.astype("<f8").tofile(f)


def main():
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("--out", default="data/example_3x3.bin", help="файл системы")
    p.add_argument("--x-true", dest="x_true", default="data/example_3x3_x_true.bin",
                   help="файл с точным решением")
    args = p.parse_args()

    assert np.allclose(A @ X_TRUE, b), "точное решение не удовлетворяет системе"

    for path in (args.out, args.x_true):
        os.makedirs(os.path.dirname(path) or ".", exist_ok=True)

    with open(args.out, "wb") as f:
        np.array([len(b)], dtype="<i8").tofile(f)
        np.hstack([A, b[:, None]]).astype("<f8").tofile(f)
    write_vector(args.x_true, X_TRUE)

    print("Система A·x = b:")
    for i in range(len(b)):
        terms = " + ".join(f"{A[i, j]:g}·x{j + 1}" for j in range(len(b)))
        print(f"  {terms} = {b[i]:g}")
    print(f"Точное решение: {', '.join(f'x{i + 1} = {v:g}' for i, v in enumerate(X_TRUE))}")
    print(f"Записано: {args.out} ({os.path.getsize(args.out)} байт), {args.x_true}")


if __name__ == "__main__":
    main()
