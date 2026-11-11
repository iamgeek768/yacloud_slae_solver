#!/usr/bin/env bash

set -euo pipefail
cd "$(dirname "$0")/.."

export OMPI_ALLOW_RUN_AS_ROOT=1 OMPI_ALLOW_RUN_AS_ROOT_CONFIRM=1

make -s -C solver
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

echo "== инструменты: точное решение проходит проверку, нулевой вектор — нет"
python3 tools/gen_matrix.py --n 50 --out "$tmp/s.bin" --x-true "$tmp/sx.bin" >/dev/null
python3 tools/verify.py --matrix "$tmp/s.bin" --x "$tmp/sx.bin" --x-true "$tmp/sx.bin" >/dev/null
python3 -c 'import sys, numpy as np; f = open(sys.argv[1], "wb"); np.array([50], dtype="<i8").tofile(f); np.zeros(50).tofile(f)' "$tmp/zero.bin"
if python3 tools/verify.py --matrix "$tmp/s.bin" --x "$tmp/zero.bin" >/dev/null; then
  echo "verify.py принял неверное решение" >&2
  exit 1
fi

# n = 301 не делится на 2, 3 и 4: проверяется неравномерное распределение строк.
python3 tools/gen_matrix.py --n 301 --seed 1 --out "$tmp/m.bin" --x-true "$tmp/xt.bin" >/dev/null
for np in 1 2 3 4; do
  echo "== решатель: np=$np"
  OMP_NUM_THREADS=2 mpirun --oversubscribe -np "$np" solver/build/slae_solver \
    --input "$tmp/m.bin" --output "$tmp/x$np.bin" --stats "$tmp/s$np.json" --tol 1e-10 \
    > "$tmp/log$np.jsonl"
  jq -e . "$tmp/log$np.jsonl" >/dev/null
  test "$(jq -s '[.[] | select(.msg == "rank ready")] | length' "$tmp/log$np.jsonl")" -eq "$np"
  python3 tools/verify.py --matrix "$tmp/m.bin" --x "$tmp/x$np.bin" --x-true "$tmp/xt.bin" --tol 1e-6
  jq -e --argjson np "$np" '.converged == true and .procs == $np and .n == 301' "$tmp/s$np.json" >/dev/null
done

echo "== решатель: исчерпание max-iter даёт код возврата 2"
rc=0
mpirun --oversubscribe -np 2 solver/build/slae_solver --input "$tmp/m.bin" --output "$tmp/xi.bin" \
  --stats "$tmp/si.json" --tol 1e-14 --max-iter 3 >/dev/null 2>&1 || rc=$?
test "$rc" -eq 2
jq -e '.converged == false and .iterations == 3' "$tmp/si.json" >/dev/null

echo "== решатель: отсутствующий входной файл даёт ненулевой код"
if mpirun --oversubscribe -np 2 solver/build/slae_solver --input "$tmp/nope.bin" --output "$tmp/xn.bin" >/dev/null 2>&1; then
  echo "решатель не сообщил об ошибке" >&2
  exit 1
fi

echo "ALL OK"
