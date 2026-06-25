#include <firmware_apis.h>

#define IMG_STATUS_OFFSET_WORD  0u
#define IMG_CMD_OFFSET_WORD     1u
#define IMG_RESULT_OFFSET_WORD  2u

#define IMG_STATUS_READY        (1u << 16)
#define IMG_STATUS_CONFIGURED   (1u << 15)
#define IMG_STATUS_ERROR        (1u << 14)
#define IMG_STATUS_DONE         (1u << 13)
#define IMG_STATUS_BUSY         (1u << 12)

#define IMG_OP_LOAD_PIXEL       0x2u
#define IMG_OP_COMPRESS_BLOCK   0x3u
#define IMG_OP_READ_BIT         0x4u
#define IMG_OP_CLEAR_BLOCK      0x5u
#define IMG_OP_READ_MASK        0x6u

static unsigned int pack_img_cmd(
    unsigned int op,
    unsigned int block,
    unsigned int pixel,
    unsigned int threshold,
    unsigned int index
) {
    return ((op & 0xFu) << 28) |
           ((block & 0xFu) << 24) |
           ((pixel & 0xFFu) << 16) |
           ((threshold & 0xFFu) << 8) |
           (index & 0xFu);
}

static unsigned int img_status(void) {
    return USER_readWord(IMG_STATUS_OFFSET_WORD);
}

static unsigned int img_result(void) {
    return USER_readWord(IMG_RESULT_OFFSET_WORD);
}

static unsigned int wait_configured(void) {
    unsigned int status = 0;
    for (unsigned int i = 0; i < 3000; i++) {
        status = img_status();
        if ((status & IMG_STATUS_CONFIGURED) && !(status & IMG_STATUS_BUSY))
            return 1u;
    }
    return 0u;
}

static unsigned int run_command(unsigned int command) {
    unsigned int status = 0;

    USER_writeWord(command, IMG_CMD_OFFSET_WORD);

    for (unsigned int i = 0; i < 1000; i++) {
        status = img_status();
        if ((status & IMG_STATUS_BUSY) || !(status & IMG_STATUS_DONE))
            break;
    }

    for (unsigned int i = 0; i < 12000; i++) {
        status = img_status();
        if ((status & IMG_STATUS_DONE) && !(status & IMG_STATUS_BUSY))
            return (status & IMG_STATUS_ERROR) ? 0u : 1u;
    }

    return 0u;
}

static unsigned int count_bits(unsigned int value) {
    unsigned int count = 0;
    for (unsigned int i = 0; i < 16; i++) {
        if (value & (1u << i))
            count++;
    }
    return count;
}

void main() {
    unsigned int ok = 1u;
    unsigned int result;
    unsigned int expected_mask = 0u;
    const unsigned int block = 1u;
    const unsigned int threshold = 128u;
    const unsigned int bright_index = 3u;
    const unsigned int dark_index = 8u;
    const unsigned int bright_pixel = 200u;
    const unsigned int dark_pixel = 64u;

    ManagmentGpio_outputEnable();
    ManagmentGpio_write(0);
    enableHkSpi(0);
    User_enableIF();

    if (!wait_configured()) ok = 0u;

    expected_mask = (1u << bright_index);

    if (!run_command(pack_img_cmd(IMG_OP_LOAD_PIXEL, block, bright_pixel, 0u, bright_index)))
        ok = 0u;
    if (!run_command(pack_img_cmd(IMG_OP_LOAD_PIXEL, block, dark_pixel, 0u, dark_index)))
        ok = 0u;

    if (!run_command(pack_img_cmd(IMG_OP_COMPRESS_BLOCK, block, 0u, threshold, 0u)))
        ok = 0u;
    result = img_result();
    if ((result & 0xFFFFu) != expected_mask) ok = 0u;
    if (((result >> 16) & 0xFFu) != count_bits(expected_mask)) ok = 0u;

    if (!run_command(pack_img_cmd(IMG_OP_READ_BIT, block, 0u, 0u, bright_index))) ok = 0u;
    if ((img_result() & 1u) != 1u) ok = 0u;

    if (!run_command(pack_img_cmd(IMG_OP_READ_BIT, block, 0u, 0u, dark_index))) ok = 0u;
    if ((img_result() & 1u) != 0u) ok = 0u;

    ManagmentGpio_write(ok ? 1 : 0);
    while (1);
}
