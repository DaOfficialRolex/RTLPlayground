/*
 * sw1: Sodola SL902-SWTGW124AS, PCB SWTG024AS-V2.1.1_19023 (4 x 2.5G + 2 x SFP+).
 *
 * The profile sw1 runs and was tested with, carried over unchanged from the
 * old machine/PCB_SWTG024AS_V2_1_1.{c,h,_init.c} (ported from upstream PR #505)
 * into the single-file layout upstream adopted on 2026-11-23 (#906).
 *
 * Upstream now ships its own profile for this board (SODOLA_SL902_SWTGW124AS,
 * machine/pcb/PCB_SWTG024AS_V2_1_1_19023.c). Same port and SFP tables; it
 * differs in the LED settings and does not set the GPIO48 pin-mux for the
 * reset button that this one does. Switch sw1 over once it is tested there.
 */
#define MACHINE_CHIPSET RTL8372
#include "machine_defs.h"

__code const struct machine machine = {
    MACHINE_COMMON_SETTING,
    .mac_flash_offset = 0x1FC000,
    .n_sfp = 2,
    .log_to_phys_port = {0, 0, 0, 5, 1, 2, 3, 4, 6},
    .phys_to_log_port = {4, 5, 6, 7, 3, 8, 0, 0, 0},
    .is_sfp = {0, 0, 0, 1, 0, 0, 0, 0, 2},

    // SFP port on SDS0 / logical port 3
    .sfp_port[0].pin_detect = GPIO37,
    .sfp_port[0].pin_los = GPIO_NA,
    .sfp_port[0].pin_tx_disable = GPIO_NA,
    .sfp_port[0].sds = 0,
    .sfp_port[0].i2c = I2CBUS( GPIO41_I2C_SDA3_MDIO1, GPIO40_I2C_SCL3_MDC1 ),

    // SFP port on SDS1 / logical port 8
    .sfp_port[1].pin_detect = GPIO38,
    .sfp_port[1].pin_los = GPIO_NA,
    .sfp_port[1].pin_tx_disable = GPIO_NA,
    .sfp_port[1].sds = 1,
    .sfp_port[1].i2c =  I2CBUS( GPIO39_I2C_SDA4, GPIO40_I2C_SCL3_MDC1 ),

    .reset_pin = GPIO48_I2C_SCL1,
    .high_leds = { .mux = LED_29, .enable = LED_27 | LED_28_SYS | LED_29 },
    .port_led_set = { 0, 0, 0, 1, 0, 0, 0, 0, 1},
    .led_sets = {
                    {
                            LEDS_2G5 | LEDS_LINK | LEDS_ACT,
                            LEDS_1G | LEDS_100M | LEDS_10M | LEDS_LINK | LEDS_ACT,
                            LEDS_DUPLEX,
                            LEDS_2G5 | LEDS_LINK | LEDS_ACT
                    },
                    {
                            LEDS_2G5 | LEDS_1G | LEDS_100M | LEDS_LINK | LEDS_ACT,
                            LEDS_10G | LEDS_LINK | LEDS_ACT,
                            LEDS_2G5 | LEDS_LINK,
                            LEDS_COL | LEDS_DUPLEX
                    },
     },
    .led_mux_custom = 1,
    .led_mux = {
                            0x00,0x01,0x04,0x05,0x08,0x09,0x0c,0x3f,0x0d,0x10,0x11,0x0e,0x14,0x11,0x12,0x15,0x15,0x16,0x18,0x19,0x1a,0x19,0x1d,0x1e,0x1c,0x1d,0x20,0x21
            },
};

MACHINE_CUSTOM_INIT(
	// OEM init and live register reads agree on the LED pad routing/enables (PR #505)
	{ REG_SET(RTL837X_PIN_MUX_0, 0x20db68bfUL); }
	{ REG_SET(RTL837X_REG_LED_GLB_IO_EN, 0x7f249740UL); }
	// OEM GPIO48 setup selects GPIO rather than I2C SCL1 for the reset button
	reg_bit_clear(RTL837X_PIN_MUX_1, 11);
	reg_bit_clear(RTL837X_PIN_MUX_1, 12);
	reg_bit_set(RTL837X_REG_LED_MODE, 17);
	reg_bit_clear(RTL837X_REG_LED_MODE, 9);
	reg_bit_clear(RTL837X_REG_LED_MODE, 7);
)
