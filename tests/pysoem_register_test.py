"""Tests for pysoem functions that are based on register level communication."""
import pytest


@pytest.fixture
def watchdog_device(pysoem_env):
    pysoem_env.config_init()
    return pysoem_env.get_xmc_test_device()


@pytest.fixture
def watchdog_register_fix(watchdog_device):
    assert watchdog_device._fprd(0x400, 2) == bytes([0xC2, 0x09])
    old_wd_time_pdi = watchdog_device._fprd(0x410, 2)
    old_wd_time_processdata = watchdog_device._fprd(0x420, 2)
    yield None
    watchdog_device._fpwr(0x410, old_wd_time_pdi)
    watchdog_device._fpwr(0x420, old_wd_time_processdata)


@pytest.mark.parametrize('wd', ['pdi', 'processdata'])
@pytest.mark.parametrize('time_ms,expected_reg_value', [
    (100, 1000),
    (10, 100),
    (1, 10),
    (0.1, 1),
    (0.15, 1),
    (0.2555, 2),
    (0, 0),
    (6553.6, AttributeError()),
])
def test_watchdog_update(watchdog_device, watchdog_register_fix, wd, time_ms, expected_reg_value):
    """Test the set_watchdog() function of the CdefSlave object."""
    wd_reg = {
        'pdi': 0x410,
        'processdata': 0x420,
    }
    if isinstance(expected_reg_value, AttributeError):
        with pytest.raises(AttributeError):
            watchdog_device.set_watchdog(wd_type=wd, wd_time_ms=time_ms)
    else:
        watchdog_device.set_watchdog(wd_type=wd, wd_time_ms=time_ms)
        assert watchdog_device._fprd(wd_reg[wd], 2) == expected_reg_value.to_bytes(2, byteorder='little', signed=False)
