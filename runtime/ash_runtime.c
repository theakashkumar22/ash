/*
 * ash_runtime.c — Ash Language Standard Library
 *
 * §1  io      print (always available), io.input(), io.read_file(), io.write_file()
 * §2  string  str_concat, str_len, str_upper, str_lower, str_contains, str_slice, conversions
 * §3  math    sqrt, pow, abs, floor, ceil, round, sin, cos, tan, log, log2, min, max, clamp
 * §4  os      exit, getenv, argc, argv
 * §5  memory  alloc, free
 *
 * One file by design: ash compiles programs by passing this single file to
 * zig cc alongside the generated C. No separate library needed. Dead code is
 * stripped automatically by the linker at -O2.
 */

#include "ash_runtime.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <math.h>
#include <ctype.h>

/* ═══════════════════════════════════════════════════════════════════════════
   §1  IO
   ═══════════════════════════════════════════════════════════════════════════ */

/* ── print helpers (used by print() builtin, no import needed) ── */

void ash_print_int(int64_t val)    { printf("%lld", (long long)val); }
void ash_print_float(double val)   { printf("%g", val); }
void ash_print_bool(int val)       { printf("%s", val ? "true" : "false"); }
void ash_print_string(const char* val) { if (val) printf("%s", val); }
void ash_print_newline(void)       { printf("\n"); }

/* ── io module functions (require: import io) ── */

/*
 * io.input("prompt")
 * Prints prompt, reads a line from stdin, returns it as a string.
 * Trailing newline is stripped.
 */
const char* ash_io_input(const char* prompt) {
    if (prompt && *prompt) {
        printf("%s", prompt);
        fflush(stdout);
    }
    char* buf = (char*)malloc(4096);
    if (!buf) { fprintf(stderr, "ash: out of memory\n"); exit(1); }
    if (!fgets(buf, 4096, stdin)) {
        buf[0] = '\0';
        return buf;
    }
    /* strip trailing newline */
    size_t len = strlen(buf);
    if (len > 0 && buf[len - 1] == '\n') buf[len - 1] = '\0';
    if (len > 1 && buf[len - 2] == '\r') buf[len - 2] = '\0';
    return buf;
}

/*
 * io.read_file("path")
 * Returns entire file contents as a string, or "" on error.
 */
const char* ash_io_read_file(const char* path) {
    if (!path) return "";
    FILE* f = fopen(path, "rb");
    if (!f) {
        fprintf(stderr, "ash: io.read_file: cannot open '%s'\n", path);
        return "";
    }
    fseek(f, 0, SEEK_END);
    long size = ftell(f);
    rewind(f);
    char* buf = (char*)malloc((size_t)size + 1);
    if (!buf) { fclose(f); fprintf(stderr, "ash: out of memory\n"); exit(1); }
    size_t read = fread(buf, 1, (size_t)size, f);
    buf[read] = '\0';
    fclose(f);
    return buf;
}

/*
 * io.write_file("path", content)
 * Writes content to path, overwriting if it exists.
 * Prints an error to stderr on failure.
 */
void ash_io_write_file(const char* path, const char* content) {
    if (!path) return;
    FILE* f = fopen(path, "wb");
    if (!f) {
        fprintf(stderr, "ash: io.write_file: cannot open '%s' for writing\n", path);
        return;
    }
    if (content) fwrite(content, 1, strlen(content), f);
    fclose(f);
}

/* ═══════════════════════════════════════════════════════════════════════════
   §2  STRING
   ═══════════════════════════════════════════════════════════════════════════ */

static char* ash__dup(const char* s) {
    if (!s) s = "";
    size_t n = strlen(s);
    char* p = (char*)malloc(n + 1);
    if (!p) { fprintf(stderr, "ash: out of memory\n"); exit(1); }
    memcpy(p, s, n + 1);
    return p;
}

const char* ash_str_concat(const char* a, const char* b) {
    if (!a) a = "";
    if (!b) b = "";
    size_t la = strlen(a), lb = strlen(b);
    char* r = (char*)malloc(la + lb + 1);
    if (!r) { fprintf(stderr, "ash: out of memory\n"); exit(1); }
    memcpy(r, a, la); memcpy(r + la, b, lb); r[la + lb] = '\0';
    return r;
}

int     ash_str_eq(const char* a, const char* b) {
    if (!a && !b) return 1;
    if (!a || !b) return 0;
    return strcmp(a, b) == 0;
}
int64_t ash_str_len(const char* s)  { return s ? (int64_t)strlen(s) : 0; }

const char* ash_str_slice(const char* s, int64_t start, int64_t end) {
    if (!s) return "";
    int64_t len = (int64_t)strlen(s);
    if (start < 0) start = 0;
    if (end > len) end = len;
    if (start >= end) return "";
    int64_t sz = end - start;
    char* r = (char*)malloc((size_t)sz + 1);
    if (!r) { fprintf(stderr, "ash: out of memory\n"); exit(1); }
    memcpy(r, s + start, (size_t)sz); r[sz] = '\0';
    return r;
}

const char* ash_str_upper(const char* s) {
    char* r = ash__dup(s);
    for (size_t i = 0; r[i]; i++) r[i] = (char)toupper((unsigned char)r[i]);
    return r;
}

const char* ash_str_lower(const char* s) {
    char* r = ash__dup(s);
    for (size_t i = 0; r[i]; i++) r[i] = (char)tolower((unsigned char)r[i]);
    return r;
}

int ash_str_contains(const char* hay, const char* needle) {
    if (!hay || !needle) return 0;
    return strstr(hay, needle) != NULL;
}

const char* ash_str_int(int64_t n) {
    char* buf = (char*)malloc(24);
    if (!buf) { fprintf(stderr, "ash: out of memory\n"); exit(1); }
    snprintf(buf, 24, "%lld", (long long)n);
    return buf;
}

const char* ash_str_float(double n) {
    char* buf = (char*)malloc(32);
    if (!buf) { fprintf(stderr, "ash: out of memory\n"); exit(1); }
    snprintf(buf, 32, "%g", n);
    return buf;
}

int64_t ash_parse_int(const char* s)   { return s ? (int64_t)strtoll(s, NULL, 10) : 0; }
double  ash_parse_float(const char* s) { return s ? strtod(s, NULL) : 0.0; }

/* ═══════════════════════════════════════════════════════════════════════════
   §3  MATH
   ═══════════════════════════════════════════════════════════════════════════ */

double  ash_math_sqrt(double x)              { return sqrt(x); }
double  ash_math_pow(double b, double e)     { return pow(b, e); }
double  ash_math_floor(double x)             { return floor(x); }
double  ash_math_ceil(double x)              { return ceil(x); }
double  ash_math_round(double x)             { return round(x); }
double  ash_math_sin(double x)               { return sin(x); }
double  ash_math_cos(double x)               { return cos(x); }
double  ash_math_tan(double x)               { return tan(x); }
double  ash_math_log(double x)               { return log(x); }
double  ash_math_log2(double x)              { return log2(x); }
double  ash_math_abs_float(double x)         { return x < 0.0 ? -x : x; }
int64_t ash_math_abs_int(int64_t x)          { return x < 0 ? -x : x; }
int64_t ash_math_min_int(int64_t a, int64_t b)  { return a < b ? a : b; }
int64_t ash_math_max_int(int64_t a, int64_t b)  { return a > b ? a : b; }
double  ash_math_min_float(double a, double b)  { return a < b ? a : b; }
double  ash_math_max_float(double a, double b)  { return a > b ? a : b; }
int64_t ash_math_clamp_int(int64_t v, int64_t lo, int64_t hi) {
    if (v < lo) return lo;
    if (v > hi) return hi;
    return v;
}

/* ═══════════════════════════════════════════════════════════════════════════
   §4  OS
   ═══════════════════════════════════════════════════════════════════════════ */

static int    _ash_argc = 0;
static char** _ash_argv = NULL;

void        ash_os_init(int argc, char** argv) { _ash_argc = argc; _ash_argv = argv; }
void        ash_os_exit(int64_t code)          { exit((int)code); }
int64_t     ash_os_argc(void)                  { return (int64_t)_ash_argc; }

/*
 * ash_os_getenv — cross-platform environment variable lookup.
 *
 * On Windows, common Unix names are aliased automatically:
 *   HOME        -> USERPROFILE (or HOMEDRIVE+HOMEPATH)
 *   USER        -> USERNAME
 *   SHELL       -> ComSpec
 *   TMPDIR      -> TEMP
 * All other names are passed through to getenv() unchanged.
 */
const char* ash_os_getenv(const char* name) {
    if (!name) return "";
    const char* v = NULL;

#if defined(_WIN32) || defined(_WIN64)
    /* Alias common Unix env vars to their Windows equivalents */
    if (strcmp(name, "HOME") == 0) {
        v = getenv("USERPROFILE");
        if (!v || !*v) {
            /* fallback: HOMEDRIVE + HOMEPATH */
            const char* drive = getenv("HOMEDRIVE");
            const char* path  = getenv("HOMEPATH");
            if (drive && path) {
                static char home_buf[512];
                snprintf(home_buf, sizeof(home_buf), "%s%s", drive, path);
                return home_buf;
            }
        }
    } else if (strcmp(name, "USER") == 0 || strcmp(name, "LOGNAME") == 0) {
        v = getenv("USERNAME");
    } else if (strcmp(name, "SHELL") == 0) {
        v = getenv("ComSpec");
    } else if (strcmp(name, "TMPDIR") == 0) {
        v = getenv("TEMP");
        if (!v || !*v) v = getenv("TMP");
    } else {
        v = getenv(name);
    }
#else
    v = getenv(name);
#endif

    return (v && *v) ? v : "";
}

const char* ash_os_argv(int64_t i)             {
    if (i < 0 || i >= _ash_argc) return "";
    return _ash_argv[i];
}

/* ═══════════════════════════════════════════════════════════════════════════
   §5  MEMORY / ARRAYS
   ═══════════════════════════════════════════════════════════════════════════ */

void*   ash_alloc(size_t size) {
    void* p = malloc(size);
    if (!p) { fprintf(stderr, "ash: out of memory\n"); exit(1); }
    return p;
}
void    ash_free(void* ptr) { free(ptr); }

/* Placeholder — array length is tracked by the user for now */
int64_t ash_array_len(void* arr) { (void)arr; return 0; }

/* ═══════════════════════════════════════════════════════════════════════════
   §6  VEC — dynamic resizable vector
   ═══════════════════════════════════════════════════════════════════════════ */

#define ASH_VEC_INIT_CAP 8

static void ash_vec__grow(AshVec* v) {
    int64_t new_cap = v->cap == 0 ? ASH_VEC_INIT_CAP : v->cap * 2;
    void** new_data = (void**)realloc(v->data, (size_t)new_cap * sizeof(void*));
    if (!new_data) { fprintf(stderr, "ash: vec out of memory\n"); exit(1); }
    v->data = new_data;
    v->cap  = new_cap;
}

AshVec* ash_vec_new(void) {
    AshVec* v = (AshVec*)malloc(sizeof(AshVec));
    if (!v) { fprintf(stderr, "ash: out of memory\n"); exit(1); }
    v->data = NULL; v->len = 0; v->cap = 0;
    return v;
}

void ash_vec_push(AshVec* v, void* item) {
    if (!v) return;
    if (v->len >= v->cap) ash_vec__grow(v);
    v->data[v->len++] = item;
}

void* ash_vec_pop(AshVec* v) {
    if (!v || v->len == 0) { fprintf(stderr, "ash: vec_pop on empty vec\n"); exit(1); }
    return v->data[--v->len];
}

void* ash_vec_get(AshVec* v, int64_t i) {
    if (!v || i < 0 || i >= v->len) { fprintf(stderr, "ash: vec index %lld out of bounds (len=%lld)\n", (long long)i, v ? (long long)v->len : 0LL); exit(1); }
    return v->data[i];
}

void ash_vec_set(AshVec* v, int64_t i, void* item) {
    if (!v || i < 0 || i >= v->len) { fprintf(stderr, "ash: vec index %lld out of bounds\n", (long long)i); exit(1); }
    v->data[i] = item;
}

int64_t ash_vec_len(AshVec* v)   { return v ? v->len : 0; }
void    ash_vec_clear(AshVec* v) { if (v) v->len = 0; }

/* ── typed push / pop / get ── */

/* int — stored as bitcast via union */
typedef union { int64_t i; void* p; } _ash_iv;
typedef union { double  d; void* p; } _ash_dv;

void    ash_vec_push_int(AshVec* v, int64_t val)   { _ash_iv u; u.i = val; ash_vec_push(v, u.p); }
void    ash_vec_push_float(AshVec* v, double val)   { _ash_dv u; u.d = val; ash_vec_push(v, u.p); }
void    ash_vec_push_str(AshVec* v, const char* s)  { ash_vec_push(v, (void*)s); }
void    ash_vec_push_bool(AshVec* v, int val)       { _ash_iv u; u.i = val ? 1 : 0; ash_vec_push(v, u.p); }

int64_t     ash_vec_get_int(AshVec* v, int64_t i)   { _ash_iv u; u.p = ash_vec_get(v,i); return u.i; }
double      ash_vec_get_float(AshVec* v, int64_t i)  { _ash_dv u; u.p = ash_vec_get(v,i); return u.d; }
const char* ash_vec_get_str(AshVec* v, int64_t i)   { return (const char*)ash_vec_get(v,i); }
int         ash_vec_get_bool(AshVec* v, int64_t i)   { _ash_iv u; u.p = ash_vec_get(v,i); return (int)u.i; }

int64_t     ash_vec_pop_int(AshVec* v)   { _ash_iv u; u.p = ash_vec_pop(v); return u.i; }
double      ash_vec_pop_float(AshVec* v) { _ash_dv u; u.p = ash_vec_pop(v); return u.d; }
const char* ash_vec_pop_str(AshVec* v)  { return (const char*)ash_vec_pop(v); }

/* ── contains ── */
int ash_vec_contains_int(AshVec* v, int64_t val) {
    for (int64_t i = 0; i < ash_vec_len(v); i++)
        if (ash_vec_get_int(v, i) == val) return 1;
    return 0;
}
int ash_vec_contains_str(AshVec* v, const char* val) {
    for (int64_t i = 0; i < ash_vec_len(v); i++)
        if (strcmp(ash_vec_get_str(v, i), val) == 0) return 1;
    return 0;
}

/* ── print helpers ── */
void ash_vec_print_int(AshVec* v) {
    printf("[");
    for (int64_t i = 0; i < ash_vec_len(v); i++) {
        if (i) printf(", ");
        printf("%lld", (long long)ash_vec_get_int(v, i));
    }
    printf("]");
}
void ash_vec_print_float(AshVec* v) {
    printf("[");
    for (int64_t i = 0; i < ash_vec_len(v); i++) {
        if (i) printf(", ");
        printf("%g", ash_vec_get_float(v, i));
    }
    printf("]");
}
void ash_vec_print_str(AshVec* v) {
    printf("[");
    for (int64_t i = 0; i < ash_vec_len(v); i++) {
        if (i) printf(", ");
        printf("\"%s\"", ash_vec_get_str(v, i));
    }
    printf("]");
}

/* Typed vec_set helpers */
void ash_vec_set_int  (AshVec* v, int64_t i, int64_t val)     { _ash_iv u; u.i = val; ash_vec_set(v, i, u.p); }
void ash_vec_set_float(AshVec* v, int64_t i, double val)       { _ash_dv u; u.d = val; ash_vec_set(v, i, u.p); }
void ash_vec_set_str  (AshVec* v, int64_t i, const char* val)  { ash_vec_set(v, i, (void*)val); }
void ash_vec_set_bool (AshVec* v, int64_t i, int val)          { _ash_iv u; u.i = val ? 1 : 0; ash_vec_set(v, i, u.p); }
