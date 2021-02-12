#include "matmul.h"

#define MIN(a,b) ((a)<(b)?(a):(b))

void matmul(double *c, const double *a, const double *b, int64_t M, int64_t N, int64_t P) {
  // We work on 4 rows of the matrix at once
  int64_t block_size = 4;
  int64_t block_size_p;

  // Set the vector configuration
  asm volatile ("vsetvli %0, %1, e64, m4" : "=r" (block_size_p) : "r" (P));

  // Slice the matrix into a manageable number of columns p_
  for (int64_t p = 0; p < P; p += block_size_p) {
    // Set the vector length
    int64_t p_ = MIN(P - p, block_size_p);
    asm volatile ("vsetvli zero, %0, e64, m4" :: "r" (p_));

    // Find pointers to the submatrices
    const double *b_ = b + p;
    double *c_ = c + p;

    // Iterate over the rows
    for (int64_t m = 0; m < M; m += block_size) {
      // Find pointer to the submatrices
      const double *a_ = a + m*N;
      double *c__ = c_ + m*P;

      // Call the kernels
      matmul_vec_4x4_slice_init(c__, P);
      matmul_vec_4x4(c__, a_, b_, N, P);
    }
  }
}

void matmul_vec_4x4_slice_init(double *c, int64_t P) {
  // Helper variables
  int64_t ldc = P << 3;

  asm volatile ("vle64.v v0,  (%0); add %0, %0, %1" : "+r" (c) : "r" (ldc));
  asm volatile ("vle64.v v4,  (%0); add %0, %0, %1" : "+r" (c) : "r" (ldc));
  asm volatile ("vle64.v v8,  (%0); add %0, %0, %1" : "+r" (c) : "r" (ldc));
  asm volatile ("vle64.v v12, (%0);"                : "+r" (c) : "r" (ldc));
}

void matmul_vec_4x4(double *c, const double *a, const double *b, int64_t N, int64_t P) {
  // Helper variables
  int64_t lda = N << 3;
  int64_t ldb = P << 3;
  int64_t ldc = P << 3;

  // Temporary variables
  double t0, t1, t2, t3;

  // Original pointer
  const double *a_ = a;

  // Prefetch one row of matrix B
  asm volatile ("vle64.v v16, (%0); add %0, %0, %1" : "+r" (b) : "r" (ldb));

  // Prefetch one row of scalar floating point values
  asm volatile ("fld %1, (%0); add %0, %0, %2" : "+r" (a), "=f" (t0) : "r" (lda));
  asm volatile ("fld %1, (%0); add %0, %0, %2" : "+r" (a), "=f" (t1) : "r" (lda));
  asm volatile ("fld %1, (%0); add %0, %0, %2" : "+r" (a), "=f" (t2) : "r" (lda));
  asm volatile ("fld %1, (%0);"                : "+r" (a), "=f" (t3));

  // Compute the multiplication
  int64_t n = 0;

  while (n < N) {
    // Load one row of B
    asm volatile ("vle64.v v20, (%0); add %0, %0, %1" : "+r" (b) : "r" (ldb)); n++;

    // Calculate pointer to the matrix A
    a = a_ + n;

    asm volatile ("vfmacc.vf v0, %0, v16" :: "f" (t0));
    asm volatile ("fld %1, (%0); add %0, %0, %2" : "+r" (a), "=f" (t0) : "r" (lda));
    asm volatile ("vfmacc.vf v4, %0, v16" :: "f" (t1));
    asm volatile ("fld %1, (%0); add %0, %0, %2" : "+r" (a), "=f" (t1) : "r" (lda));
    asm volatile ("vfmacc.vf v8, %0, v16" :: "f" (t2));
    asm volatile ("fld %1, (%0); add %0, %0, %2" : "+r" (a), "=f" (t2) : "r" (lda));
    asm volatile ("vfmacc.vf v12, %0, v16" :: "f" (t3));
    asm volatile ("fld %1, (%0);"                : "+r" (a), "=f" (t3));

    if (n == N-1)
      break;

    // Load one row of B
    asm volatile ("vle64.v v16, (%0); add %0, %0, %1" : "+r" (b) : "r" (ldb)); n++;
    a = (const double*) a_ + n;

    asm volatile ("vfmacc.vf v0, %0, v20" :: "f" (t0));
    asm volatile ("fld %1, (%0); add %0, %0, %2" : "+r" (a), "=f" (t0) : "r" (lda));
    asm volatile ("vfmacc.vf v4, %0, v20" :: "f" (t1));
    asm volatile ("fld %1, (%0); add %0, %0, %2" : "+r" (a), "=f" (t1) : "r" (lda));
    asm volatile ("vfmacc.vf v8, %0, v20" :: "f" (t2));
    asm volatile ("fld %1, (%0); add %0, %0, %2" : "+r" (a), "=f" (t2) : "r" (lda));
    asm volatile ("vfmacc.vf v12, %0, v20" :: "f" (t3));
    asm volatile ("fld %1, (%0);"                : "+r" (a), "=f" (t3));
  }

  // Last iteration: store results
  asm volatile ("vfmacc.vf v0, %0, v20" :: "f" (t0));
  asm volatile ("vse64.v v0, (%0); add %0, %0, %1" : "+r" (c) : "r" (ldc));
  asm volatile ("vfmacc.vf v4, %0, v20" :: "f" (t1));
  asm volatile ("vse64.v v4, (%0); add %0, %0, %1" : "+r" (c) : "r" (ldc));
  asm volatile ("vfmacc.vf v8, %0, v20" :: "f" (t2));
  asm volatile ("vse64.v v8, (%0); add %0, %0, %1" : "+r" (c) : "r" (ldc));
  asm volatile ("vfmacc.vf v12, %0, v20" :: "f" (t3));
  asm volatile ("vse64.v v12, (%0);"               : "+r" (c)            );
}
