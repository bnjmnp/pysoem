"""Tests for pysoem functions that are based on register level communication."""
import pytest


@pytest.fixture
def watchdog_device(pysoem_env):
    pysoem_env.config_init()
    return pysoem_env.get_xmc_test_device()


@pytest.fixture
def watchdog_register_fix(watchdog_device):
    """Fixture to clean up after the test_watchdog_update() did run.
    
    Saves the watchdog settings prior to the test run and restores them after the test run.
    """
    timeout_ms = 4000
    assert watchdog_device._fprd(0x400, 2, timeout_ms) == bytes([0xC2, 0x09])
    old_wd_time_pdi = watchdog_device._fprd(0x410, 2, timeout_ms)
    old_wd_time_processdata = watchdog_device._fprd(0x420, 2, timeout_ms)
    yield None
    watchdog_device._fpwr(0x410, old_wd_time_pdi, timeout_ms)
    watchdog_device._fpwr(0x420, old_wd_time_processdata, timeout_ms)


@pytest.mark.parametrize('wd', ['pdi', 'processdata'])
@pytest.mark.parametrize('time_ms,expected_reg_value,expect_a_warning', [
    (100, 1000, False),
    (10, 100, False),
    (1, 10, False),
    (0.1, 1, False),
    (0.15, 1, True),
    (0.2555, 2, True),
    (0, 0, False),
    (6553.6, AttributeError(), False),
])
def test_watchdog_update(watchdog_device, watchdog_register_fix, recwarn, wd, time_ms, expected_reg_value, expect_a_warning):
    """Test the set_watchdog() function of the CdefSlave object."""
    wd_reg = {
        'pdi': 0x410,
        'processdata': 0x420,
    }
    if isinstance(expected_reg_value, AttributeError):
        with pytest.raises(AttributeError) as exec_info:
            watchdog_device.set_watchdog(wd_type=wd, wd_time_ms=time_ms)
        assert exec_info.value.args[0] == "wd_time_ms is limited to 6553.5 ms"
    else:
        watchdog_divider = 100000
        expected_watchdog_time = expected_reg_value*watchdog_divider/1000000.0
        if expect_a_warning:
            with pytest.warns(UserWarning) as record:
                watchdog_device.set_watchdog(wd_type=wd, wd_time_ms=time_ms)
            assert record[0].message.args[0] == f"The actual set watchdog time ({expected_watchdog_time} ms) differs from the requested watchdog time ({time_ms} ms) due to resolution limits of the hardware!"
            assert len(record) == 1, "More then one warning was emitted!"
            
        else:
            watchdog_device.set_watchdog(wd_type=wd, wd_time_ms=time_ms)
            assert len(recwarn) == 0, "A warning was emitted unexpectedly!"
        assert watchdog_device._fprd(address=wd_reg[wd], size=2, timeout_us=4000) == expected_reg_value.to_bytes(2, byteorder='little', signed=False)
        assert watchdog_device.get_watchdog(wd_type=wd) == expected_watchdog_time
