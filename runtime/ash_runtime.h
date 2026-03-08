#ifndef ASH_RUNTIME_H
#define ASH_RUNTIME_H

#include <stdint.h>
#include <stddef.h>

/* ═══════════════════════════════════════════════════════════
   io — print (always available), input and file I/O (import io)
   ═══════════════════════════════════════════════════════════ */

/* print() builtin helpers */
void        ash_print_int(int64_t val);
void        ash_print_float(double val);
void        ash_print_bool(int val);
void        ash_print_string(const char* val);
void        ash_print_newline(void);

/* io module: io.input(), io.read_file(), io.write_file() */
const char* ash_io_input(const char* prompt);
const char* ash_io_read_file(const char* path);
void        ash_io_write_file(const char* path, const char* content);

/* ═══════════════════════════════════════════════════════════
   string — built-in string operations
   ═══════════════════════════════════════════════════════════ */
const char* ash_str_concat(const char* a, const char* b);
int         ash_str_eq(const char* a, const char* b);
int64_t     ash_str_len(const char* s);
const char* ash_str_slice(const char* s, int64_t start, int64_t end);
const char* ash_str_upper(const char* s);
const char* ash_str_lower(const char* s);
int         ash_str_contains(const char* haystack, const char* needle);
const char* ash_str_int(int64_t n);
const char* ash_str_float(double n);
int64_t     ash_parse_int(const char* s);
double      ash_parse_float(const char* s);

/* ═══════════════════════════════════════════════════════════
   math — numeric functions  (import math)
   ═══════════════════════════════════════════════════════════ */
double      ash_math_sqrt(double x);
double      ash_math_pow(double base, double exp);
double      ash_math_abs_float(double x);
int64_t     ash_math_abs_int(int64_t x);
double      ash_math_floor(double x);
double      ash_math_ceil(double x);
double      ash_math_round(double x);
int64_t     ash_math_min_int(int64_t a, int64_t b);
int64_t     ash_math_max_int(int64_t a, int64_t b);
double      ash_math_min_float(double a, double b);
double      ash_math_max_float(double a, double b);
double      ash_math_sin(double x);
double      ash_math_cos(double x);
double      ash_math_tan(double x);
double      ash_math_log(double x);
double      ash_math_log2(double x);
int64_t     ash_math_clamp_int(int64_t val, int64_t lo, int64_t hi);

#define ASH_PI  3.14159265358979323846
#define ASH_E   2.71828182845904523536

/* ═══════════════════════════════════════════════════════════
   os — exit, args, env  (import os)
   ═══════════════════════════════════════════════════════════ */
void        ash_os_exit(int64_t code);
const char* ash_os_getenv(const char* name);
int64_t     ash_os_argc(void);
const char* ash_os_argv(int64_t index);
void        ash_os_init(int argc, char** argv);

/* ═══════════════════════════════════════════════════════════
   arrays / memory
   ═══════════════════════════════════════════════════════════ */
int64_t     ash_array_len(void* arr);
void*       ash_alloc(size_t size);
void        ash_free(void* ptr);

#endif /* ASH_RUNTIME_H */

/* ═══════════════════════════════════════════════════════════
   vec — dynamic typed vector  (no import needed)
   ═══════════════════════════════════════════════════════════

   AshVec is a heap-allocated, resizable array of void* slots.
   Each slot holds either:
     - a cast int64_t / double / int (bool)
     - a const char* (string)
     - another AshVec* (nested vec)

   Use the typed helpers below for safe access.
*/

typedef struct {
    void**   data;
    int64_t  len;
    int64_t  cap;
} AshVec;

AshVec*     ash_vec_new(void);
void        ash_vec_push(AshVec* v, void* item);
void*       ash_vec_pop(AshVec* v);
void*       ash_vec_get(AshVec* v, int64_t i);
void        ash_vec_set(AshVec* v, int64_t i, void* item);
int64_t     ash_vec_len(AshVec* v);
void        ash_vec_clear(AshVec* v);
int         ash_vec_contains_int(AshVec* v, int64_t val);
int         ash_vec_contains_str(AshVec* v, const char* val);

/* Typed push/pop/get helpers */
void        ash_vec_push_int(AshVec* v, int64_t val);
void        ash_vec_push_float(AshVec* v, double val);
void        ash_vec_push_str(AshVec* v, const char* val);
void        ash_vec_push_bool(AshVec* v, int val);
int64_t     ash_vec_get_int(AshVec* v, int64_t i);
double      ash_vec_get_float(AshVec* v, int64_t i);
const char* ash_vec_get_str(AshVec* v, int64_t i);
int         ash_vec_get_bool(AshVec* v, int64_t i);
int64_t     ash_vec_pop_int(AshVec* v);
double      ash_vec_pop_float(AshVec* v);
const char* ash_vec_pop_str(AshVec* v);

/* print a vec for debugging */
void        ash_vec_print_int(AshVec* v);
void        ash_vec_print_float(AshVec* v);
void        ash_vec_print_str(AshVec* v);

/* Typed set helpers — avoid void* cast issues on MSVC/clang */
void ash_vec_set_int  (AshVec* v, int64_t i, int64_t val);
void ash_vec_set_float(AshVec* v, int64_t i, double val);
void ash_vec_set_str  (AshVec* v, int64_t i, const char* val);
void ash_vec_set_bool (AshVec* v, int64_t i, int val);
