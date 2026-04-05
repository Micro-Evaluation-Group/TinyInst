// Minimal test target for -instrument_ranges_file testing.
// Contains distinct functions at known offsets to verify
// that only configured ranges get instrumented.
#include <stdio.h>
#include <string.h>

#ifdef _MSC_VER
#define NOINLINE __declspec(noinline)
#else
#define NOINLINE __attribute__((noinline))
#endif

NOINLINE void func_a(void) {
    volatile int x = 0;
    for (int i = 0; i < 10; i++) x += i;
    printf("func_a: %d\n", x);
}

NOINLINE void func_b(void) {
    volatile int y = 100;
    for (int i = 0; i < 5; i++) y -= i;
    printf("func_b: %d\n", y);
}

NOINLINE void func_c(void) {
    volatile int z = 42;
    z = z * 2 + 1;
    printf("func_c: %d\n", z);
}

int main(int argc, char **argv) {
    if (argc > 1 && strcmp(argv[1], "input") == 0) {
        func_a();
        func_b();
        func_c();
    }
    return 0;
}
