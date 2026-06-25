# BMSemi SNN Image Compression Demo

This folder packages a simple Caravel + X1 IP demo chip for image compression and storage.

The demo was created from the `BMsemi/IMPACT_SNN_RERAM_submit` working tree and uses the existing Neuromorphic X1/ReRAM-style IP as the storage block. The top-level hardened design is still `user_project_wrapper`, but the user logic inside the wrapper is now an image-compression controller called `image_compression_storage`.

## What This Demo Does

The design implements a tiny threshold-based image compressor for demo purposes.

It accepts small grayscale pixel values from Caravel firmware, compares each pixel against a threshold, stores the compressed `1` bits into the X1 IP, and later reads the stored compressed bits back from X1.

The compressor uses a simple rule:

```text
if pixel >= threshold:
    compressed bit = 1
else:
    compressed bit = 0
```

For this first demo, the image block size is 4x4 pixels, or 16 total pixel positions.

```text
pixel index:  0  1  2  3
              4  5  6  7
              8  9 10 11
             12 13 14 15
```

The X1 IP is used as a compact bit-storage array:

```text
X1 row    = image block ID
X1 column = pixel index
X1 value  = compressed bit
```

For example:

```text
block ID = 1
pixel index = 3
pixel value = 200
threshold = 128

200 >= 128, so compressed bit = 1
The RTL stores X1[row 1][col 3] = 1
```

If a pixel is below threshold, the compressed bit is `0`. In the demo flow, below-threshold pixels are not programmed into X1, so they remain zero after reset.

## Why This Is A Good Simple Demo

This demo proves a full beginner-visible chip flow:

```text
Caravel firmware command
    -> image compression RTL
    -> X1 IP program/read operation
    -> compressed bit stored in X1
    -> firmware reads the bit back later
    -> cocotb pass/fail result
    -> OpenLane hardens user_project_wrapper
    -> final GDS is generated
```

It is intentionally not a full JPEG or PNG compressor. It is a simple hardware demonstrator showing how image data can be reduced to a sparse/binary compressed representation and stored in the X1 IP.

## Main RTL Blocks

### `user_project_wrapper.v`

This is the Caravel user wrapper. In this cleaned package it connects only the image-compression/X1 demo path:

- Caravel Wishbone bus
- logic analyzer debug output
- user IRQs
- analog and scan pins needed by the X1 macro
- `image_compression_storage`
- default GPIO output/output-enable values for unused pads

The image compressor instance is:

```verilog
image_compression_storage img_comp_inst (...);
```

The original `adaptive_fabric_top_tapeout` instance from the IMPACT reference repo has been removed. The wrapper now contains only the X1 image-compression demo logic.

### `image_compression_storage.v`

This is the main demo controller.

It performs four jobs:

1. Receives 32-bit commands from firmware over Wishbone.
2. Buffers loaded 8-bit pixel values.
3. Compresses loaded pixels using a threshold.
4. Programs and reads compressed bits through the X1 IP.

Internally it instantiates:

```verilog
nvm_neuron_core_256x64 x1_core (...);
```

The X1 core then instantiates the `Neuromorphic_X1_wb` hard macro through the existing `nvm_synapse_matrix` hierarchy.

## Host Register Map

Firmware accesses this design through the Caravel user project Wishbone interface.

The important word offsets are:

```text
word offset 0 = status/debug register
word offset 1 = command register at address 0x3000_0004
word offset 2 = result register
word offset 3 = compressed mask/debug ID
```

The beginner-visible command address is:

```text
0x3000_0004
```

## Status Register

The status word is produced by `debug_status`.

Important status fields:

```text
configured        = X1 configuration completed
busy              = controller is processing a command
done              = last command completed
error             = invalid command or rejected command
compressed_ready  = compressed mask is valid
count             = number of 1 bits in compressed block
block             = active image block ID
state             = internal controller state
```

The user IRQ mapping is:

```text
user_irq[0] = compressed_ready
user_irq[1] = done
user_irq[2] = error
```

## Command Word Format

Firmware writes one 32-bit command word to word offset 1.

```text
[31:28] opcode
[27:24] block ID
[23:16] pixel value
[15:8]  threshold
[3:0]   pixel index / field index
```

Supported opcodes:

```text
0x2 = LOAD_PIXEL
0x3 = COMPRESS_BLOCK
0x4 = READ_BIT
0x5 = CLEAR_BLOCK
0x6 = READ_MASK
```

The cocotb demo uses the minimal proof flow:

```text
LOAD_PIXEL bright pixel
LOAD_PIXEL dark pixel
COMPRESS_BLOCK with threshold 128
READ_BIT bright pixel index, expect 1
READ_BIT dark pixel index, expect 0
```

## How Compression Works Internally

The RTL has a small pixel buffer:

```verilog
reg [7:0] pixel_buf [0:15];
```

It also tracks which pixels were loaded:

```verilog
reg [15:0] valid_mask_r;
```

When firmware sends `LOAD_PIXEL`, the RTL stores:

```text
pixel_buf[index] = pixel value
valid_mask[index] = 1
```

When firmware sends `COMPRESS_BLOCK`, the RTL loops from pixel index 0 to 15.

For each loaded pixel:

```text
if pixel_buf[index] >= threshold:
    compressed_mask[index] = 1
    program X1[block][index] = 1
else:
    compressed_mask[index] = 0
    do not program X1, so it remains 0
```

The X1 program command is generated by:

```verilog
x1_program_cmd(row, col)
```

The X1 read command is generated by:

```verilog
x1_read_cmd(row, col)
```

## State Machine

The main state machine in `image_compression_storage.v` uses these major states:

```text
ST_CFG_WRITE
    Send three startup configuration words to X1.

ST_IDLE
    Wait for firmware command.

ST_COMPRESS_NEXT
    Choose the next pixel index and decide whether it should be stored.

ST_COMPRESS_WRITE
    Wait for X1 acknowledge after programming a compressed 1 bit.

ST_READ_CMD
    Send X1 read command for one compressed bit.

ST_READ_POP
    Wait until X1 returns the read data.

ST_CLEAR_NEXT / ST_CLEAR_WRITE
    Clear a block, if that operation is used.

ST_MASK_NEXT / ST_MASK_CMD / ST_MASK_POP
    Read all 16 compressed bits from X1, if that operation is used.

ST_DONE
    Mark command complete and return to idle.
```

## X1 Startup Configuration

After reset, the controller writes three configuration words into X1:

```text
0xA203_C40F
0x0F03_0D43
0x4200_0C03
```

Only after those writes are acknowledged does the RTL set `configured_r = 1`.

Firmware waits for `configured_r` before sending compression commands.

## Cocotb Verification

The test is located at:

```text
verilog/dv/cocotb/user_proj_tests/image_compression_storage/
```

Files:

```text
image_compression_storage.c     firmware test
image_compression_storage.py    cocotb wrapper
image_compression_storage.yaml  cocotb test registration
```

The firmware test performs:

```text
1. Enable Caravel user interface.
2. Wait until X1 is configured.
3. Load a bright pixel.
4. Load a dark pixel.
5. Compress the block using threshold 128.
6. Check compressed mask and count.
7. Read bright pixel bit back from X1 and expect 1.
8. Read dark pixel bit back from X1 and expect 0.
9. Drive management GPIO high on pass.
```

The successful RTL cocotb run was:

```text
TESTS=1 PASS=1 FAIL=0 SKIP=0
```

After removing `adaptive_fabric_top_tapeout` and pruning unused RTL files, the cleaned package was re-run from `/home/vboxuser/BMSemi_SNN_image_comp` and also passed:

```text
clean_image_package_rtl_20260625_093753
TESTS=1 PASS=1 FAIL=0 SKIP=0
```

The logs are included under:

```text
reports/image_compression_rtl_nowave_20260624_174122.log
reports/clean_image_package_rtl_20260625_093753.log
```

## OpenLane Hardening

The OpenLane/LibreLane config is:

```text
openlane/user_project_wrapper/config.json
```

The important macro instance path is:

```text
img_comp_inst.x1_core.synapse_matrix_inst.X1_inst
```

That is the X1 hard macro instance used for macro placement and PDN connections.

The signoff SDC also cuts timing through this macro instance:

```text
openlane/user_project_wrapper/signoff.sdc
```

## Final Generated Views

The package includes final generated wrapper views under:

```text
results/final_views/
```

Important outputs:

```text
results/final_views/gds/user_project_wrapper.gds
results/final_views/def/user_project_wrapper.def
results/final_views/lef/user_project_wrapper.lef
results/final_views/lib/user_project_wrapper.lib
results/final_views/spef/user_project_wrapper.spef
results/final_views/verilog/gl/user_project_wrapper.v
```

These views are kept as the previous successful image-compression demo output. After the source cleanup that removed `adaptive_fabric_top_tapeout`, rerun OpenLane if you need a freshly hardened GDS/DEF/LEF/netlist that exactly matches the cleaned wrapper RTL.

The final GDS from the successful image compression hardening run is:

```text
results/final_views/gds/user_project_wrapper.gds
```

## Signoff Result From The Demo Run

The original hardening run tag was:

```text
image_compression_harden_20260624_175512
```

Summary:

```text
Magic DRC:       0 errors
KLayout DRC:     0 errors
Route DRC:       0 errors
LVS:             0 errors, circuits match uniquely
XOR:             0 differences
Setup timing:    0 violations
Hold timing:     0 violations
Antenna:         2 net / 2 pin violations
Max slew:        35 violations
Max cap:         2 violations
Max fanout:      391 violations
```

The user's stated acceptance allowed a few antenna violations for demo purposes, and the requested 0 DRC and 0 LVS errors were achieved.

The extracted report is included here:

```text
reports/image_compression_report_extract.txt
```

## Re-running Cocotb

From the original VM setup, run:

```bash
cd /home/vboxuser/BMSemi_SNN_image_comp/verilog/dv/cocotb
/home/vboxuser/caravel_user_Neuromorphic_X1_32x32/venv-cocotb/bin/caravel_cocotb \
  -design_info impact_design_info.yaml \
  -t image_compression_storage \
  -sim RTL \
  -tag image_compression_rtl_demo_$(date +%Y%m%d_%H%M%S) \
  -no_wave \
  -compile
```

If the package is moved to another path, update `USER_PROJECT_ROOT` inside:

```text
verilog/dv/cocotb/impact_design_info.yaml
```

## Re-running OpenLane

From the VM:

```bash
cd /home/vboxuser/BMSemi_SNN_image_comp
export PROJECT_ROOT=$PWD
export PDK_ROOT=/home/vboxuser/caravel_user_Neuromorphic_X1_32x32/dependencies/pdks
export PDK=sky130A
export CARAVEL_ROOT=/home/vboxuser/caravel_user_Neuromorphic_X1_32x32/caravel

/home/vboxuser/caravel_user_Neuromorphic_X1_32x32/openlane/.venv/bin/python3 -m librelane \
  -m "$PROJECT_ROOT" \
  -m "$PDK_ROOT" \
  -m "$CARAVEL_ROOT" \
  -m "$HOME/.ipm" \
  --docker-no-tty \
  --dockerized \
  --run-tag image_compression_harden_$(date +%Y%m%d_%H%M%S) \
  --manual-pdk \
  --pdk-root "$PDK_ROOT" \
  --pdk "$PDK" \
  --ef-save-views-to "$PROJECT_ROOT" \
  --overwrite \
  --hide-progress-bar \
  -j 4 \
  openlane/user_project_wrapper/config.json
```

## Folder Contents

The package contains:

```text
README.md
Makefile                              top-level repo Makefile copied from the reference repo
openlane/Makefile                     OpenLane repo-format Makefile
docs/Makefile                         docs repo-format Makefile
verilog/rtl/                         image-compression, X1 wrapper, and required support RTL only
verilog/includes/                    Caravel include list
verilog/dv/cocotb/                   cocotb registration and firmware test
openlane/user_project_wrapper/       OpenLane config, SDC, PDN, DEF template
ip/Neuromorphic_X1_32x32/hdl/        X1 macro stub
gds/Neuromorphic_X1_wb.gds           X1 macro GDS input
lef/Neuromorphic_X1_wb.lef           X1 macro LEF input
lib/Neuromorphic_X1_wb.lib           X1 macro Liberty input
results/final_views/                 generated hardened wrapper views
reports/                             cocotb/OpenLane report extracts
scripts/                             helper scripts from the run
```

## Known Limitations

This is a demo compressor, not a production image codec.

Current simplifications:

- 4x4 block only.
- One threshold for the block.
- Binary output only, 1 bit per pixel.
- No entropy coding.
- No JPEG DCT or PNG-style filtering.
- Below-threshold pixels are left zero rather than explicitly rewritten every run.

Useful next improvements:

- Add multiple block rows for larger images.
- Add `CLEAR_BLOCK` at start of each frame if the same X1 block is reused.
- Add run-length encoding of the 16-bit compressed mask.
- Add block average mode.
- Add edge-detection mode.
- Fix antenna, max slew, max cap, and max fanout warnings for cleaner signoff.
