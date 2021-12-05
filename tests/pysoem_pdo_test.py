

import time
import struct
import pytest

import pysoem


class El1259ConfigFunction:

    def __init__(self, device):
        self._device = device

    def fn(self, slave_pos):
        """
        struct format characters
        B - uint8
        x - pac byte
        H - uint16
        """

        self._device.sdo_write(0x8001, 2, struct.pack('B', 1))

        rx_map_obj = [0x1603, 0x1607, 0x160B, 0x160F, 0x1613, 0x1617, 0x161B, 0x161F,
                      0x1620, 0x1621, 0x1622, 0x1623, 0x1624, 0x1625, 0x1626, 0x1627]
        pack_fmt = 'Bx' + ''.join(['H' for _ in range(len(rx_map_obj))])
        rx_map_obj_bytes = struct.pack(pack_fmt, len(rx_map_obj), *rx_map_obj)
        self._device.sdo_write(0x1c12, 0, rx_map_obj_bytes, True)

        tx_map_obj = [0x1A00, 0x1A01, 0x1A02, 0x1A03, 0x1A04, 0x1A05, 0x1A06, 0x1A07, 0x1A08,
                      0x1A0C, 0x1A10, 0x1A14, 0x1A18, 0x1A1C, 0x1A20, 0x1A24]
        pack_fmt = 'Bx' + ''.join(['H' for _ in range(len(tx_map_obj))])
        tx_map_obj_bytes = struct.pack(pack_fmt, len(tx_map_obj), *tx_map_obj)
        self._device.sdo_write(0x1c13, 0, tx_map_obj_bytes, True)

        self._device.dc_sync(1, 1000000)


@pytest.mark.parametrize('overlapping_enable', [False, True])
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