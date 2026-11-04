#include "machine_init_defs.h"

void machine_custom_init(void) __banked
{
	// OEM init and live register reads agree on the LED pad routing/enables (PR #505)
	{ REG_SET(RTL837X_PIN_MUX_0, 0x20db68bfUL); }
	{ REG_SET(RTL837X_REG_LED_GLB_IO_EN, 0x7f249740UL); }
	// OEM GPIO48 setup selects GPIO rather than I2C SCL1 for the reset button
	reg_bit_clear(RTL837X_PIN_MUX_1, 11);
	reg_bit_clear(RTL837X_PIN_MUX_1, 12);
	reg_bit_set(RTL837X_REG_LED_MODE, 17);
	reg_bit_clear(RTL837X_REG_LED_MODE, 9);
	reg_bit_clear(RTL837X_REG_LED_MODE, 7);
}
