/*
 * Symbols the rest of this tree expects from the touch archive that OddlyLabs' FTS probe does not define.
 *
 * BootLog.c (carried over from sheng) reads the Novatek probe's stroke and extent statistics; the FTS probe keeps
 * no such statistics, so they stay at their initial values here. native_owner_root_accepted_checkpoint is called
 * from bsd_init by zzz-boot-progress.patch; its definition comes from offline-owner-root-binding-audit.patch,
 * which this configuration does not apply, so a weak no-op keeps the link whole.
 */
#include <stdint.h>

volatile int32_t native_touch_strokes[16][7];
volatile uint32_t native_touch_stroke_count;
volatile int32_t native_touch_extent[4] = {0x7fffffff, -1, 0x7fffffff, -1};

__attribute__((weak)) void
native_owner_root_accepted_checkpoint(int apple, int owner)
{
	(void)apple;
	(void)owner;
}
