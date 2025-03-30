import dataclasses

import pytest

import pysoem

BECKHOFF_VENDOR_ID = 0x0002
EK1100_PRODUCT_CODE = 0x044C2C52
EL3002_PRODUCT_CODE = 0x0BBA3052
EL1259_PRODUCT_CODE = 0x04EB3052


@dataclasses.dataclass
class Device:
    name: str
    vendor_id: int
    product_code: int


@pytest.fixture
def revert_global_settings():
    old_timeout_ret = pysoem.settings.timeouts.ret
    old_timeout_safe = pysoem.settings.timeouts.safe
    old_timeout_eeprom = pysoem.settings.timeouts.eeprom
    old_timeout_tx_mailbox = pysoem.settings.timeouts.tx_mailbox
    old_timeout_rx_mailbox = pysoem.settings.timeouts.rx_mailbox
    old_timeout_state = pysoem.settings.timeouts.state
    old_release_gil = pysoem.settings.always_release_gil

    yield None

    pysoem.settings.timeouts.ret = old_timeout_ret
    pysoem.settings.timeouts.safe = old_timeout_safe
    pysoem.settings.timeouts.eeprom = old_timeout_eeprom
    pysoem.settings.timeouts.tx_mailbox = old_timeout_tx_mailbox
    pysoem.settings.timeouts.rx_mailbox = old_timeout_rx_mailbox
    pysoem.settings.timeouts.state = old_timeout_state
    pysoem.settings.always_release_gil = old_release_gil



def test_version():
    assert isinstance(pysoem.__version__, str)


def test_find_adapters():
    pysoem.find_adapters()


def test_config_function_exception(pysoem_env):
    """Check if an exception in a config_func callback causes config_map to fail"""

    class DummyException(Exception):
        pass

    def el1259_config_func(slave_pos):
        raise DummyException()

    pysoem_env.config_init()
    pysoem_env.el1259_config_func = el1259_config_func

    with pytest.raises(DummyException) as excinfo:
        pysoem_env.config_map()
    assert isinstance(excinfo.value, DummyException)


def test_master_context_manager(ifname):
    """Quick check if the open() function context manager works as expected."""
    with pysoem.open(ifname) as master:
        if master.config_init() > 0:
            expected_slave_layout = {
                0: Device("XMC43-Test-Device", 0, 0x12783456),
                1: Device("EK1100", BECKHOFF_VENDOR_ID, EK1100_PRODUCT_CODE),
                2: Device("EL3002", BECKHOFF_VENDOR_ID, EL3002_PRODUCT_CODE),
                3: Device("EL1259", BECKHOFF_VENDOR_ID, EL1259_PRODUCT_CODE),
            }
            for i, slave in enumerate(master.slaves):
                assert slave.man == expected_slave_layout[i].vendor_id
                assert slave.id == expected_slave_layout[i].product_code
        else:
            pytest.fail()


setup_func_was_called = False


def test_setup_function(pysoem_env):
    """Check if the new setup_func works as intended."""

    def el1259_setup_func(slave):
        global setup_func_was_called
        assert slave.id == EL1259_PRODUCT_CODE
        setup_func_was_called = True

    pysoem_env.config_init()
    pysoem_env.el1259_setup_func = el1259_setup_func

    pysoem_env.config_map()  # el1259_setup_func is expected to be called here

    assert setup_func_was_called


def test_call_config_init_twice(pysoem_env):
    """In older versions of pysoem there was an issue calling config_init() multiple times.

    Every time config_init() was called again, the slaves list was extended not updated.
    """
    pysoem_env.config_init()
    assert len(pysoem_env.get_master().slaves) == len(pysoem_env._expected_slave_layout)
    pysoem_env.config_init()
    assert len(pysoem_env.get_master().slaves) == len(pysoem_env._expected_slave_layout)


def test_closed_interface_master(ifname):
    """Quick check if the open() function context manager works as expected."""
    with pysoem.open(ifname) as master:
        if not master.config_init() > 0:
            pytest.fail()

    with pytest.raises(pysoem.NetworkInterfaceNotOpenError) as exec_info:
        master.send_processdata()


def test_closed_interface_slave(ifname):
    """Quick check if the open() function context manager works as expected."""
    with pysoem.open(ifname) as master:
        if master.config_init() > 0:
            slaves = master.slaves

    with pytest.raises(pysoem.NetworkInterfaceNotOpenError) as exec_info:
        slaves[0].sdo_read(0x1018, 1)


def test_tune_timeouts(revert_global_settings):
    assert pysoem.settings.timeouts.ret == 2_000
    pysoem.settings.timeouts.ret = 5_000
    assert pysoem.settings.timeouts.ret == 5_000

    assert pysoem.settings.timeouts.safe == 20_000
    pysoem.settings.timeouts.safe = 70_000
    assert pysoem.settings.timeouts.safe == 70_000

    assert pysoem.settings.timeouts.eeprom == 20_000
    pysoem.settings.timeouts.eeprom = 30_000
    assert pysoem.settings.timeouts.eeprom == 30_000

    assert pysoem.settings.timeouts.tx_mailbox == 20_000
    pysoem.settings.timeouts.tx_mailbox = 90_000
    assert pysoem.settings.timeouts.tx_mailbox == 90_000

    assert pysoem.settings.timeouts.rx_mailbox == 700_000
    pysoem.settings.timeouts.rx_mailbox = 900_000
    assert pysoem.settings.timeouts.rx_mailbox == 900_000

    assert pysoem.settings.timeouts.state == 2_000_000
    pysoem.settings.timeouts.state = 5_000_000
    assert pysoem.settings.timeouts.state == 5_000_000


def test_release_gil(revert_global_settings):
    assert pysoem.settings.always_release_gil == 0
    pysoem.settings.always_release_gil = True
    assert pysoem.settings.always_release_gil == 1

    master = pysoem.Master()
    assert master.always_release_gil == 1
    assert master.check_release_gil(None) == 1
    assert master.check_release_gil(True) == 1
    assert master.check_release_gil(False) == 0

    master.always_release_gil = False
    assert master.always_release_gil == 0
    assert pysoem.settings.always_release_gil == 1
    assert master.check_release_gil(None) == 0
    assert master.check_release_gil(True) == 1
    assert master.check_release_gil(False) == 0

    # New master would be created with pysoem.settings.always_release_gil value
    new_master = pysoem.Master()
    assert new_master.always_release_gil == 1
    assert master.always_release_gil == 0
