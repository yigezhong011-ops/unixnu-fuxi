/* USB gestures with coordinates plus the screenshot provider, for the t50 kernel. Lives in the free
 * space of copyio_test at +0x1000, past the screenshot code and the GPU tables.
 *
 * verb_hook replaces the one call to sxnu_control_parse_verb. It adds two verbs, in hex:
 *   TAP-xxxx-yyyy                 a tap
 *   SWP-xxxx-yyyy-xxxx-yyyy-mmmm  a drag taking mmmm ms; equal end points make a long press
 * Both are answered as SCREENSHOT, so CRC, sequence and the reply go through the existing path. The
 * hook runs before the CRC check, so it only leaves the gesture in a mailbox; the capture performs
 * it. A bad frame never reaches the capture, and the next verb clears the mailbox.
 *
 * x is 0..30479 across the screen. y is 0..20319 and is mirrored below, so it runs from the bottom.
 */
typedef unsigned char u8;
typedef unsigned int u32;
typedef unsigned long u64;

#ifndef TAP_HOLD_MS
#define TAP_HOLD_MS 40
#endif
#define VERB_SCREENSHOT 5
#define AXIS_MAX 20319
#define X_MAX 30479 /* touchAction's clamp; x_pt = x * 360 / 30480 */

#define ADDR_TOUCH_SEQ    0xfffffff00c1846ecUL
#define ADDR_TOUCH_COUNT  0xfffffff00c1846f0UL
#define ADDR_TOUCH_XS     0xfffffff00c1846f4UL
#define ADDR_TOUCH_YS     0xfffffff00c184724UL
#define ADDR_TOUCH_IDS    0xfffffff00c184754UL
#define ADDR_TOUCH_SINK   0xfffffff00c2324f0UL
#define ADDR_TOUCH_CTX    0xfffffff00c2324e8UL
#define ADDR_TOUCH_HID    0xfffffff00c1846e4UL
#define ADDR_FENCE_WAIT   0xfffffff00c18044cUL
#define ADDR_SUBMIT_IBS   0xfffffff00c180420UL
#define ADDR_PRINTF       0xfffffff00b8cc820UL

/* The mailbox: slots 10 and 11 of the touch arrays. The driver fills only slots below its contact
 * count, and the panel reports at most ten fingers. */
#define M_X0   ((volatile int *)(ADDR_TOUCH_XS + 40))
#define M_Y0   ((volatile int *)(ADDR_TOUCH_YS + 40))
#define M_X1   ((volatile int *)(ADDR_TOUCH_IDS + 40))
#define M_Y1   ((volatile int *)(ADDR_TOUCH_XS + 44))
#define M_MS   ((volatile int *)(ADDR_TOUCH_YS + 44))
#define M_KIND ((volatile int *)(ADDR_TOUCH_IDS + 44))

static inline u64 counter(void)
{
  u64 v;
  __asm__ volatile("mrs %0, cntvct_el0" : "=r"(v));
  return v;
}

static inline u64 counter_freq(void)
{
  u64 v;
  __asm__ volatile("mrs %0, cntfrq_el0" : "=r"(v));
  return v;
}

__attribute__((noinline)) static void wait_ms(u64 ms)
{
  const u64 start = counter(), ticks = counter_freq() * ms / 1000;
  while (counter() - start < ticks)
    __asm__ volatile("yield");
}

/* One publish, the same sequence as TouchProbe.cpp: odd seq, the slots, even seq, then the sink. */
__attribute__((noinline)) static void touch_publish(u32 count, int x, int y)
{
  volatile u32 *seq = (volatile u32 *)ADDR_TOUCH_SEQ;
  *seq = *seq + 1;
  __asm__ volatile("dmb ish" ::: "memory");
  *(volatile u32 *)ADDR_TOUCH_COUNT = count;
  if (count) {
    *(volatile int *)ADDR_TOUCH_XS = x;
    *(volatile int *)ADDR_TOUCH_YS = AXIS_MAX - y;
    *(volatile int *)ADDR_TOUCH_IDS = 1;
  }
  __asm__ volatile("dmb ish" ::: "memory");
  *seq = *seq + 1;
  void (*sink)(void *) = *(void *volatile *)ADDR_TOUCH_SINK;
  if (sink)
    sink(*(void *volatile *)ADDR_TOUCH_CTX);
}

__attribute__((noinline)) static void touch_swipe(int x0, int y0, int x1, int y1, int ms)
{
  const int steps = ms / 10 < 1 ? 1 : ms / 10;
  touch_publish(1, x0, y0);
  for (int i = 1; i <= steps; i++) {
    wait_ms(10);
    touch_publish(1, x0 + (x1 - x0) * i / steps, y0 + (y1 - y0) * i / steps);
  }
  touch_publish(0, x1, y1);
}

/* Four hex digits, or -1. */
__attribute__((noinline)) static int hex4(const u8 *p)
{
  int v = 0;
  for (int i = 0; i < 4; i++) {
    const u8 c = p[i];
    int d;
    if (c >= '0' && c <= '9')
      d = c - '0';
    else if (c >= 'a' && c <= 'f')
      d = c - 'a' + 10;
    else
      return -1;
    v = v * 16 + d;
  }
  return v;
}

/* Returns 1 for a valid gesture verb, which is then in the mailbox. */
__attribute__((noinline)) static int gesture_parse(const u8 *t, u64 n)
{
  int kind;
  if (n == 13 && t[0] == 'T' && t[1] == 'A' && t[2] == 'P')
    kind = 1;
  else if (n == 28 && t[0] == 'S' && t[1] == 'W' && t[2] == 'P')
    kind = 2;
  else
    return 0;
  const int x0 = hex4(t + 4), y0 = hex4(t + 9);
  int x1 = x0, y1 = y0, ms = TAP_HOLD_MS;
  if (kind == 2) {
    x1 = hex4(t + 14);
    y1 = hex4(t + 19);
    ms = hex4(t + 24);
  }
  if (x0 < 0 || y0 < 0 || x1 < 0 || y1 < 0 || ms < 10 || ms > 1000 ||
      x0 > X_MAX || y0 > AXIS_MAX || x1 > X_MAX || y1 > AXIS_MAX)
    return 0;
  *M_X0 = x0;
  *M_Y0 = y0;
  *M_X1 = x1;
  *M_Y1 = y1;
  *M_MS = ms;
  *M_KIND = kind;
  return 1;
}

int verb_hook(const u8 *text, u64 bytes)
{
  if (gesture_parse(text, bytes))
    return VERB_SCREENSHOT;
  *M_KIND = 0;
  return ((int (*)(const u8 *, u64))ADDR_PARSE_VERB)(text, bytes);
}

__attribute__((noinline)) static int shot_capture(void *cookie, u8 *rgb, u64 capacity, u32 *width, u32 *height)
{
  (void)cookie;
  u64 video[18];
  const volatile u8 *base = *(const volatile u8 *const volatile *)ADDR_GOP_VIRTUAL;
  u32 w = *(const volatile u32 *)ADDR_GOP_WIDTH, h = *(const volatile u32 *)ADDR_GOP_HEIGHT;
  if (!base || !w || !h || ((int (*)(u64 *))ADDR_PE_CURRENT_CONSOLE)(video))
    return 0;
  u64 stride = video[1];
  u32 outw = w / 3, outh = h / 3;
  if (stride < (u64)w * 4 || (u64)outw * outh * 3 > capacity)
    return 0;
  for (u32 y = 0; y < outh; y++) {
    const volatile u32 *row = (const volatile u32 *)(base + (u64)y * 3 * stride);
    for (u32 x = 0; x < outw; x++) {
      u32 p = row[x * 3] & 0xf8f8f8;
      *rgb++ = (u8)(p >> 16);
      *rgb++ = (u8)(p >> 8);
      *rgb++ = (u8)p;
    }
  }
  *width = outw;
  *height = outh;
  return 1;
}

/* XNU's printf reads every variadic argument from the stack (Darwin ABI), but this file is built for
 * ELF, where a variadic call fills x1-x7 first. Declaring seven unused register parameters puts the
 * real values on the stack in 8-byte slots, which is where printf looks. */
typedef int (*darwin_printf8)(const char *, u64, u64, u64, u64, u64, u64, u64,
                              u64, u64, u64, u64, u64, u64, u64, u64);

/* g=gesture kind, hid=touch reports, seq=touch sequence (2 per publish), calls=fence waits,
 * to=fence timeouts, sub/done=fences at the last timeout, ibs=submissions. */
__attribute__((noinline)) static void report(u32 kind)
{
  const volatile u32 *fw = (const volatile u32 *)ADDR_FENCE_WAIT;
  ((darwin_printf8)ADDR_PRINTF)("FUXI120S g=%u hid=%u seq=%u calls=%u to=%u sub=%u done=%u ibs=%u\n",
                                0, 0, 0, 0, 0, 0, 0,
                                kind,
                                *(const volatile u32 *)ADDR_TOUCH_HID,
                                *(const volatile u32 *)ADDR_TOUCH_SEQ,
                                fw[0], fw[1], fw[4], fw[5],
                                *(const volatile u32 *)ADDR_SUBMIT_IBS);
}

__attribute__((noinline)) static int capture_after_gesture(void *cookie, u8 *rgb, u64 capacity, u32 *width, u32 *height)
{
  const int kind = *M_KIND;
  if (kind) {
    *M_KIND = 0;
    touch_swipe(*M_X0, *M_Y0, *M_X1, *M_Y1, *M_MS);
  }
  report((u32)kind);
  return shot_capture(cookie, rgb, capacity, width, height);
}

/* Entered from the GOP mapping checkpoint right after the mapping is published. */
void touch_entry(void)
{
  ((int (*)(void *, void *))ADDR_REGISTER_SCREENSHOT)((void *)capture_after_gesture, 0);
}
