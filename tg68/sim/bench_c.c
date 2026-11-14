/* bench c: a small compiled-C workload for the simulator (step 15).
 * Not Dhrystone, but the same kinds of work: records and pointers, string
 * copy and compare, integer arithmetic, calls with parameters, a switch,
 * array indexing, globals.  Built with gcc -O2 -m68020, linked to run from
 * fast RAM at $08010000 with its stack in fast RAM; test_c.s copies it
 * there from the ROM and calls run() twice (the second pass is timed).
 * Everything is initialised data (no .bss), no library calls. */
#define D  __attribute__((section(".data")))
#define NI __attribute__((noinline))
typedef struct rec { struct rec *next; int kind; int val; char name[20]; } rec;

static rec  D ra = { 0, 1, 10, "ALPHA RECORD ONE" };
static rec  D rb = { 0, 2, 20, "BRAVO RECORD TWO" };
static int  D arr[32] = { 1 };
static short D sarr[16] = { 1 };
static int  D mat[8][8] = { { 1 } };
static char D s1[24] = "DHRYSTONE-LIKE, 1ST STR";
static char D s2[24] = "DHRYSTONE-LIKE, 2ND STR";
int  D g_int = 1;
char D g_c1 = 'A', g_c2 = 'B';

static NI int  f_cmp(const char *a, const char *b) { while (*a && *a == *b) { a++; b++; } return *a - *b; }
static NI void f_cpy(char *d, const char *s) { while ((*d++ = *s++)) ; }
static NI int  f_kind(int k, int v)
{
    switch (k) {
    case 0: return v + 1;
    case 1: return v * 3;
    case 2: return v - g_int;
    case 3: return v ^ 0x55;
    default: return v;
    }
}
static NI void f_rec(rec *p, rec *q)
{
    *q = *p;                       /* structure copy */
    q->val = f_kind(p->kind, p->val);
    q->kind = (p->kind + 1) & 3;
    p->next = q;
    if (f_cmp(p->name, q->name) == 0) q->name[0]++;
}
static NI int f_arr(int *a, int n, int x)
{
    int i, s = 0;
    for (i = 0; i < n; i++) { a[i] = a[i] + x + i; s += a[i]; }
    return s;
}
static NI int f_mat(int m[8][8], int r, int c)
{
    int i;
    for (i = c; i < c + 3; i++) m[r][i & 7] = r + i;
    m[r + 1 & 7][c] += 1;
    g_int = m[r][c];
    return m[r][c + 1 & 7];
}
static NI int f_short(short *p, int n)
{
    int i, s = 0;
    for (i = 0; i < n; i++) { p[i] = (short)(p[i] * 5 + i); s += p[i]; }
    return s;
}
static NI char f_ch(char a, char b) { return (a == b) ? a : (char)(a + 1); }

__attribute__((section(".text.entry"))) int run(void)
{
    int it, sum = 0;
    rec *p = &ra, *q = &rb, *t;
    for (it = 0; it < 12; it++) {
        f_rec(p, q);
        sum += q->val;
        sum += f_arr(arr, 12, it);
        sum += f_mat(mat, it & 7, (it + 3) & 7);
        if (f_cmp(s1, s2) < 0) { f_cpy(s2, s1); s2[it & 7]++; }
        else                     s1[(it + 1) & 7]++;
        sum += f_short(sarr, 8);
        g_c1 = f_ch(g_c1, g_c2);
        sum = (sum << 1 | (unsigned)sum >> 31) + g_int + g_c1;
        if (sum % 7 > 3) sum += sum / 5;
        t = p; p = q; q = t;
    }
    return sum;
}
