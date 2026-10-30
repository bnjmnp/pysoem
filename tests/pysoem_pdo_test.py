import struct
import time

import pytest

import pysoem


class El1259ConfigFunction:
    def __init__(
        self, device, disable_complete_access=False, rx_map_obj=None, tx_map_obj=None
    ):
        self._device = device
        self._disable_complete_access = disable_complete_access
        self._rx_map_obj = rx_map_obj or [
            0x1603,
            0x1607,
            0x160B,
            0x160F,
            0x1613,
            0x1617,
            0x161B,
            0x161F,
            0x1620,
            0x1621,
            0x1622,
            0x1623,
            0x1624,
            0x1625,
            0x1626,
            0x1627,
        ]
        self._tx_map_obj = tx_map_obj or [
            0x1A00,
            0x1A01,
            0x1A02,
            0x1A03,
            0x1A04,
            0x1A05,
            0x1A06,
            0x1A07,
            0x1A08,
            0x1A0C,
            0x1A10,
            0x1A14,
            0x1A18,
            0x1A1C,
            0x1A20,
            0x1A24,
        ]

    def fn(self, slave_pos):
        """
        struct format characters
        B - uint8
        x - pac byte
        H - uint16
        """

        self._device.sdo_write(0x8001, 2, struct.pack("B", 1))

        pack_fmt = "Bx" + "".join(["H" for _ in range(len(self._rx_map_obj))])
        rx_map_obj_bytes = struct.pack(
            pack_fmt, len(self._rx_map_obj), *self._rx_map_obj
        )
        self._device.sdo_write(0x1C12, 0, rx_map_obj_bytes, True)

        pack_fmt = "Bx" + "".join(["H" for _ in range(len(self._tx_map_obj))])
        tx_map_obj_bytes = struct.pack(
            pack_fmt, len(self._tx_map_obj), *self._tx_map_obj
        )
        self._device.sdo_write(0x1C13, 0, tx_map_obj_bytes, True)

        self._device.dc_sync(1, 1000000)

        if self._disable_complete_access:
            self._device._disable_complete_access()


@pytest.mark.parametrize("overlapping_enable", [False, True])
def test_io_toggle(pysoem_env, overlapping_enable):
    pysoem_env.config_init()
    el1259 = pysoem_env.get_el1259()
    pysoem_env.el1259_config_func = El1259ConfigFunction(el1259).fn
    pysoem_env.config_map(overlapping_enable)
    pysoem_env.go_to_op_state()

    output_len = len(el1259.output)

    tmp = bytearray([0 for _ in range(output_len)])

    for i in range(8):
        out_offset = 12 * i
        in_offset = 4 * i

        tmp[out_offset] = 0x02
        el1259.output = bytes(tmp)
        time.sleep(0.1)
        assert el1259.input[in_offset] & 0x04 == 0x04

        tmp[out_offset] = 0x00
        el1259.output = bytes(tmp)
        time.sleep(0.1)
        assert el1259.input[in_offset] & 0x04 == 0x00


def test_clear_pdo_mapping(pysoem_env):
    """Change an EL1259 PDO mapping from X to Y and return it to OP."""
    pysoem_env.config_init()
    master = pysoem_env.get_master()
    el1259 = pysoem_env.get_el1259()
    pysoem_env.el1259_config_func = El1259ConfigFunction(el1259).fn
    pysoem_env.config_map()

    mailbox_sms = el1259._fprd(0x0800, 16)
    assert any(el1259._fprd(0x0810, 8))
    assert any(el1259._fprd(0x0818, 8))
    assert any(el1259._fprd(0x0600, 64))

    mapping_x = (len(el1259.input), len(el1259.output))
    assert mapping_x[0] > 0 and mapping_x[1] > 0

    def enter_op_state():
        master.state = pysoem.OP_STATE
        master.write_state()
        for _ in range(400):
            master.send_processdata()
            master.receive_processdata(timeout=10000)
            if el1259.state_check(pysoem.OP_STATE, 1000) == pysoem.OP_STATE:
                return
        pytest.fail("EL1259 could not reach OP state")

    el1259.output = bytes(len(el1259.output))
    enter_op_state()
    assert el1259.state == pysoem.OP_STATE

    with pytest.raises(RuntimeError, match="INIT or PREOP"):
        el1259.clear_pdo_mapping()

    master.state = pysoem.PREOP_STATE
    master.write_state()
    assert master.state_check(pysoem.PREOP_STATE, 50000) == pysoem.PREOP_STATE
    el1259.clear_pdo_mapping()

    assert el1259._fprd(0x0800, 16) == mailbox_sms
    assert el1259._fprd(0x0810, 8) == bytes(8)
    assert el1259._fprd(0x0818, 8) == bytes(8)
    assert el1259._fprd(0x0600, 64) == bytes(64)
    assert el1259.input == b""
    assert el1259.output == b""
    with pytest.raises(RuntimeError, match="PDO mapping is not configured"):
        el1259.output = bytes(1)

    pysoem_env.el1259_config_func = El1259ConfigFunction(
        el1259, rx_map_obj=[0x1603], tx_map_obj=[0x1A00]
    ).fn
    pysoem_env.config_map()
    assert any(el1259._fprd(0x0600, 64))
    mapping_y = (len(el1259.input), len(el1259.output))
    assert mapping_y != mapping_x

    el1259.output = bytes(len(el1259.output))
    enter_op_state()
    assert el1259.state == pysoem.OP_STATE


@pytest.mark.parametrize("disable_complete_access", [False, True])
def test_disable_complete_access(pysoem_env, disable_complete_access):
    """Very basic sanity check if disable_complete_access does not do any damage."""
    pysoem_env.config_init()
    el1259 = pysoem_env.get_el1259()
    pysoem_env.el1259_config_func = El1259ConfigFunction(
        el1259, disable_complete_access
    ).fn
    pysoem_env.config_map()
    pysoem_env.go_to_op_state()
    time.sleep(1)


@pytest.mark.parametrize(
    "method_name",
    [
        "config_map",
        "config_overlap_map",
        "send_processdata",
        "send_overlap_processdata",
        "receive_processdata",
        "get_expected_wkc",
    ],
)
@pytest.mark.parametrize("group", [-1, 2, 0.5, True])
def test_group_api_rejects_invalid_group_without_opening_interface(method_name, group):
    """Reject invalid group indices without opening an EtherCAT interface."""
    master = pysoem.Master()

    with pytest.raises(ValueError, match="Invalid group"):
        getattr(master, method_name)(group=group)


def test_expected_wkc_property_preserves_group_zero_behavior():
    """Keep the expected-WKC property equivalent to selecting group 0."""
    master = pysoem.Master()

    assert master.expected_wkc == master.get_expected_wkc()
    assert master.expected_wkc == master.get_expected_wkc(group=0)


@pytest.mark.parametrize("overlapping_enable", [False, True])
def test_selected_group_process_data(pysoem_env, overlapping_enable):
    """Exchange PDOs for one selected group while peers remain outside OP.

    Requires the Beckhoff EtherCAT layout provided by ``pysoem_env``.
    """
    pysoem_env.config_init()
    master = pysoem_env.get_master()
    el1259 = pysoem_env.get_el1259()
    assert el1259.man == pysoem_env.BECKHOFF_VENDOR_ID
    assert el1259.id == pysoem_env.EL1259_PRODUCT_CODE

    master.config_dc()
    master.read_state()
    peer_states = {
        index: slave.state
        for index, slave in enumerate(master.slaves)
        if slave is not el1259
    }
    for slave in master.slaves:
        slave.group = 0
        slave.is_lost = False
    el1259.group = 1
    el1259.config_func = El1259ConfigFunction(el1259).fn

    if overlapping_enable:
        master.config_overlap_map(group=1)
    else:
        master.config_map(group=1)

    assert el1259.state_check(pysoem.SAFEOP_STATE, 50_000) == pysoem.SAFEOP_STATE
    el1259.state = pysoem.OP_STATE
    el1259.write_state()

    for _ in range(400):
        if overlapping_enable:
            master.send_overlap_processdata(group=1)
        else:
            master.send_processdata(group=1)
        working_counter = master.receive_processdata(timeout=10_000, group=1)
        if el1259.state_check(pysoem.OP_STATE, 1_000) == pysoem.OP_STATE:
            break
        time.sleep(0.01)

    assert el1259.state == pysoem.OP_STATE
    expected_wkc = master.get_expected_wkc(group=1)
    assert expected_wkc > 0
    if overlapping_enable:
        master.send_overlap_processdata(group=1)
    else:
        master.send_processdata(group=1)
    working_counter = master.receive_processdata(timeout=10_000, group=1)
    assert working_counter == expected_wkc

    master.read_state()
    assert all(
        master.slaves[index].state == state for index, state in peer_states.items()
    )
