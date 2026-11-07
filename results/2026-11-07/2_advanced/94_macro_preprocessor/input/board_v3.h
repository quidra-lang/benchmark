#ifndef BOARD_V3_H
#define BOARD_V3_H
/* rev 3 board: sensor on SPI1 */
#define SENSOR_BUS spi1
#define SENSOR_CS_PIN 4
static const char board_id[] = BOARD_NAME;
static const char *board_src = __FILE__;
static const int board_line = __LINE__;
#endif
