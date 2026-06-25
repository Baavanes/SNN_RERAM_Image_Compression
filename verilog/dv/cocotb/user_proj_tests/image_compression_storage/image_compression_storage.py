from caravel_cocotb.caravel_interfaces import report_test
from caravel_cocotb.caravel_interfaces import test_configure
import cocotb


@cocotb.test()
@report_test
async def image_compression_storage(dut):
    caravelEnv = await test_configure(dut, timeout_cycles=1200000)
    cocotb.log.info("[TEST] Start image_compression_storage")
    await caravelEnv.release_csb()
    await caravelEnv.wait_mgmt_gpio(1)
    cocotb.log.info("[TEST] X1 image threshold-compress/store/readback flow passed")
