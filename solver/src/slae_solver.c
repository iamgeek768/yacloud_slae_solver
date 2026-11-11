/*
 * Параллельный решатель СЛАУ Ax = b методом Якоби (MPI + OpenMP).
 *
 * Ранг 0 читает расширенную матрицу [A|b] из файла и раздаёт строки остальным
 * рангам блоками; каждый ранг считает свою часть итерации в несколько потоков
 * OpenMP, новый вектор x собирается на всех рангах через MPI_Allgatherv.
 *
 * Формат входа:  int64 n, затем n строк по n+1 double (a_i0..a_i,n-1, b_i).
 * Формат выхода: int64 n, затем n double.
 * Код возврата:  0 — сошлось, 2 — исчерпан лимит итераций, 1 — ошибка.
 */
#define _POSIX_C_SOURCE 200809L

#include <errno.h>
#include <limits.h>
#include <math.h>
#include <mpi.h>
#include <omp.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

/* Размер одного сообщения при раздаче строк, в числах double (32 МБ). */
#define CHUNK_DOUBLES (4 * 1024 * 1024)
#define TAG_ROWS 1

static int g_rank;
static char g_host[256] = "unknown";
static const char *g_run_id = "local";

/* Одна JSON-строка в stdout; extra — готовые пары "ключ":значение или NULL. */
static void log_json(const char *level, const char *msg, const char *extra, ...)
{
    char line[1024];
    char ts[32];
    struct timespec now;
    struct tm tm;

    clock_gettime(CLOCK_REALTIME, &now);
    gmtime_r(&now.tv_sec, &tm);
    strftime(ts, sizeof ts, "%Y-%m-%dT%H:%M:%S", &tm);

    int len = snprintf(line, sizeof line,
                       "{\"ts\":\"%s.%03ldZ\",\"level\":\"%s\",\"run_id\":\"%s\",\"rank\":%d,"
                       "\"host\":\"%s\",\"msg\":\"%s\"",
                       ts, now.tv_nsec / 1000000, level, g_run_id, g_rank, g_host, msg);
    if (extra && len < (int)sizeof line - 2) {
        va_list ap;
        line[len++] = ',';
        va_start(ap, extra);
        len += vsnprintf(line + len, sizeof line - (size_t)len, extra, ap);
        va_end(ap);
    }
    if (len > (int)sizeof line - 3)
        len = (int)sizeof line - 3;
    line[len++] = '}';
    line[len++] = '\n';
    line[len] = '\0';
    fputs(line, stdout);
    fflush(stdout);
}

static void die(const char *what, const char *detail)
{
    log_json("ERROR", what, "\"detail\":\"%s\"", detail);
    MPI_Abort(MPI_COMM_WORLD, 1);
    exit(1);
}

static void *xmalloc(size_t bytes)
{
    void *p = malloc(bytes ? bytes : 1);
    if (!p)
        die("out of memory", "malloc failed");
    return p;
}

static void read_exact(void *dst, size_t size, size_t count, FILE *f)
{
    if (fread(dst, size, count, f) != count)
        die("cannot read input", feof(f) ? "file is shorter than its header says" : strerror(errno));
}

struct options {
    const char *input;
    const char *output;
    const char *stats;
    double tol;
    int max_iter;
    int log_every;
};

static struct options parse_args(int argc, char **argv)
{
    struct options o = {NULL, NULL, NULL, 1e-8, 20000, 10};

    for (int i = 1; i < argc; i++) {
        const char *key = argv[i];
        if (i + 1 >= argc)
            die("bad arguments", key);
        const char *val = argv[++i];
        if (!strcmp(key, "--input"))
            o.input = val;
        else if (!strcmp(key, "--output"))
            o.output = val;
        else if (!strcmp(key, "--stats"))
            o.stats = val;
        else if (!strcmp(key, "--tol"))
            o.tol = atof(val);
        else if (!strcmp(key, "--max-iter"))
            o.max_iter = atoi(val);
        else if (!strcmp(key, "--log-every"))
            o.log_every = atoi(val);
        else
            die("unknown argument", key);
    }
    if (!o.input || !o.output)
        die("bad arguments", "--input and --output are required");
    if (o.tol <= 0.0 || o.max_iter < 1 || o.log_every < 1)
        die("bad arguments", "--tol, --max-iter and --log-every must be positive");
    return o;
}

int main(int argc, char **argv)
{
    int provided, size;

    MPI_Init_thread(&argc, &argv, MPI_THREAD_FUNNELED, &provided);
    MPI_Comm_rank(MPI_COMM_WORLD, &g_rank);
    MPI_Comm_size(MPI_COMM_WORLD, &size);
    gethostname(g_host, sizeof g_host - 1);
    if (getenv("SLAE_RUN_ID"))
        g_run_id = getenv("SLAE_RUN_ID");

    struct options opt = parse_args(argc, argv);
    double t_start = MPI_Wtime();

    /* Размерность читает ранг 0 и рассылает остальным. */
    FILE *in = NULL;
    int64_t n64 = 0;
    if (g_rank == 0) {
        in = fopen(opt.input, "rb");
        if (!in)
            die("cannot open input", strerror(errno));
        read_exact(&n64, sizeof n64, 1, in);
        if (n64 < 1 || n64 >= INT_MAX)
            die("bad input", "matrix dimension is out of range");
        if (size > n64)
            die("bad input", "more MPI processes than matrix rows");
    }
    MPI_Bcast(&n64, 1, MPI_INT64_T, 0, MPI_COMM_WORLD);

    const int n = (int)n64;
    const size_t stride = (size_t)n + 1;

    /* Блочное распределение строк: первые n % size рангов получают на строку больше. */
    int *counts = xmalloc((size_t)size * sizeof *counts);
    int *displs = xmalloc((size_t)size * sizeof *displs);
    for (int p = 0, off = 0; p < size; p++) {
        counts[p] = n / size + (p < n % size ? 1 : 0);
        displs[p] = off;
        off += counts[p];
    }
    const int rows = counts[g_rank];
    const int first = displs[g_rank];

    int chunk_rows = (int)(CHUNK_DOUBLES / stride);
    if (chunk_rows < 1)
        chunk_rows = 1;

    /* Локальная часть расширенной матрицы: rows строк по n+1 чисел. */
    double *ab = xmalloc((size_t)rows * stride * sizeof *ab);

    if (g_rank == 0) {
        /* Свои строки идут в файле первыми; чужие читаем и отправляем блоками,
         * поэтому полная матрица в памяти ранга 0 не хранится. */
        read_exact(ab, sizeof *ab, (size_t)rows * stride, in);
        double *buf = xmalloc((size_t)chunk_rows * stride * sizeof *buf);
        for (int p = 1; p < size; p++) {
            for (int sent = 0; sent < counts[p]; sent += chunk_rows) {
                int cnt = counts[p] - sent < chunk_rows ? counts[p] - sent : chunk_rows;
                read_exact(buf, sizeof *buf, (size_t)cnt * stride, in);
                MPI_Send(buf, (int)((size_t)cnt * stride), MPI_DOUBLE, p, TAG_ROWS, MPI_COMM_WORLD);
            }
        }
        free(buf);
        fclose(in);
    } else {
        for (int got = 0; got < rows; got += chunk_rows) {
            int cnt = rows - got < chunk_rows ? rows - got : chunk_rows;
            MPI_Recv(ab + (size_t)got * stride, (int)((size_t)cnt * stride), MPI_DOUBLE, 0, TAG_ROWS,
                     MPI_COMM_WORLD, MPI_STATUS_IGNORE);
        }
    }

    double bb_local = 0.0, bb = 0.0;
    int bad_diag_local = 0, bad_diag = 0;
    for (int i = 0; i < rows; i++) {
        const double *row = ab + (size_t)i * stride;
        bb_local += row[n] * row[n];
        if (fabs(row[first + i]) < 1e-300)
            bad_diag_local = 1;
    }
    MPI_Allreduce(&bb_local, &bb, 1, MPI_DOUBLE, MPI_SUM, MPI_COMM_WORLD);
    MPI_Allreduce(&bad_diag_local, &bad_diag, 1, MPI_INT, MPI_MAX, MPI_COMM_WORLD);
    if (bad_diag) {
        if (g_rank == 0)
            die("bad input", "zero on the main diagonal, Jacobi method is not applicable");
        MPI_Finalize();
        return 1;
    }
    const double b_norm = bb > 0.0 ? sqrt(bb) : 1.0;

    log_json("INFO", "rank ready", "\"rows\":%d,\"first_row\":%d,\"threads\":%d", rows, first,
             omp_get_max_threads());
    MPI_Barrier(MPI_COMM_WORLD);
    const double t_read = MPI_Wtime() - t_start;
    if (g_rank == 0)
        log_json("INFO", "matrix distributed", "\"n\":%d,\"procs\":%d,\"t_read_sec\":%.3f", n, size,
                 t_read);

    double *x = xmalloc((size_t)n * sizeof *x);
    double *x_local = xmalloc((size_t)rows * sizeof *x_local);
    memset(x, 0, (size_t)n * sizeof *x);

    /* Итерации Якоби: x_new = x + D^-1 (b - A x). Невязка считается для текущего x,
     * поэтому при выходе из цикла она соответствует тому вектору, который записывается. */
    const double t_solve_start = MPI_Wtime();
    int iterations = 0, converged = 0;
    double residual = 0.0;
    for (;;) {
        double rr_local = 0.0, rr = 0.0;

        #pragma omp parallel for schedule(static) reduction(+ : rr_local)
        for (int i = 0; i < rows; i++) {
            const double *row = ab + (size_t)i * stride;
            double s = 0.0;
            #pragma omp simd reduction(+ : s)
            for (int j = 0; j < n; j++)
                s += row[j] * x[j];
            const double r = row[n] - s;
            x_local[i] = x[first + i] + r / row[first + i];
            rr_local += r * r;
        }

        MPI_Allreduce(&rr_local, &rr, 1, MPI_DOUBLE, MPI_SUM, MPI_COMM_WORLD);
        residual = sqrt(rr) / b_norm;
        if (residual < opt.tol) {
            converged = 1;
            break;
        }
        if (iterations >= opt.max_iter)
            break;

        MPI_Allgatherv(x_local, rows, MPI_DOUBLE, x, counts, displs, MPI_DOUBLE, MPI_COMM_WORLD);
        iterations++;
        if (g_rank == 0 && iterations % opt.log_every == 0)
            log_json("INFO", "iteration", "\"iter\":%d,\"residual\":%.6e", iterations, residual);
    }
    const double t_solve = MPI_Wtime() - t_solve_start;
    const double t_total = MPI_Wtime() - t_start;

    if (g_rank == 0) {
        FILE *out = fopen(opt.output, "wb");
        if (!out)
            die("cannot open output", strerror(errno));
        if (fwrite(&n64, sizeof n64, 1, out) != 1 || fwrite(x, sizeof *x, (size_t)n, out) != (size_t)n ||
            fclose(out) != 0)
            die("cannot write output", strerror(errno));

        if (opt.stats) {
            FILE *st = fopen(opt.stats, "w");
            if (!st)
                die("cannot open stats", strerror(errno));
            fprintf(st,
                    "{\"run_id\":\"%s\",\"n\":%d,\"procs\":%d,\"threads\":%d,\"iterations\":%d,"
                    "\"residual\":%.6e,\"converged\":%s,\"t_read_sec\":%.6f,\"t_solve_sec\":%.6f,"
                    "\"t_total_sec\":%.6f}\n",
                    g_run_id, n, size, omp_get_max_threads(), iterations, residual,
                    converged ? "true" : "false", t_read, t_solve, t_total);
            if (fclose(st) != 0)
                die("cannot write stats", strerror(errno));
        }

        log_json(converged ? "INFO" : "WARN", converged ? "solved" : "not converged",
                 "\"n\":%d,\"procs\":%d,\"threads\":%d,\"iterations\":%d,\"residual\":%.6e,"
                 "\"t_solve_sec\":%.3f,\"t_total_sec\":%.3f",
                 n, size, omp_get_max_threads(), iterations, residual, t_solve, t_total);
    }

    free(x_local);
    free(x);
    free(ab);
    free(displs);
    free(counts);
    MPI_Finalize();
    return converged ? 0 : 2;
}
