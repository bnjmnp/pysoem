"""Run some basic tests against an Beckhoff EL1259

This test expects a physical slave layout according to PySoemTestEnvironment._expected_slave_layout, see below.

Run this tests with the unit testing framework that comes with python: `python -m unittest pysoem_test`.

In order to run the tests you need to provide a test_config.py that contains two variables as seen below.

```py
ifname = '\\Device\\NPF_{2BBC7456-5AED-4F27-AECA-292762639099}'
expected_pysoem_version = '0.0.18'
```
Thees values must reflect your setup.
"""

import time
import unittest
import collections
import struct
import threading

import pysoem

import test_config


class PySoemTestEnvironment:
    """Setup a basic pysoem test fixture that is needed for most of tests"""

    BECKHOFF_VENDOR_ID = 0x0002
    EK1100_PRODUCT_CODE = 0x044c2c52
    EL3002_PRODUCT_CODE = 0x0bba3052
    EL1259_PRODUCT_CODE = 0x04eb3052

    def __init__(self):
        self._ifname = test_config.ifname
        self._master = pysoem.Master()
        self._master.in_op = False
        self._master.do_check_state = False
        self._proc_thread_handle = None
        self._check_thread_handle = None
        self._pd_thread_stop_event = threading.Event()
        self._ch_thread_stop_event = threading.Event()
        self._actual_wkc = 0

        self.SlaveSet = collections.namedtuple('SlaveSet', 'name vendor_id product_code config_func')

        self.el3002_config_func = None
        self.el1259_config_func = None
        self._expected_slave_layout = None

    def setup(self):

        self._expected_slave_layout = {
            0: self.SlaveSet('XMC43-Test-Device', 0, 0x12783456, None),
            1: self.SlaveSet('EK1100', self.BECKHOFF_VENDOR_ID, self.EK1100_PRODUCT_CODE, None),
            2: self.SlaveSet('EL3002', self.BECKHOFF_VENDOR_ID, self.EL3002_PRODUCT_CODE, self.el3002_config_func),
            3: self.SlaveSet('EL1259', self.BECKHOFF_VENDOR_ID, self.EL1259_PRODUCT_CODE, self.el1259_config_func),
        }
        self._master.open(self._ifname)

        assert self._master.config_init(False) > 0

        self._master.config_dc()
        for i, slave in enumerate(self._master.slaves):
            assert slave.man == self._expected_slave_layout[i].vendor_id
            assert slave.id == self._expected_slave_layout[i].product_code
            slave.config_func = self._expected_slave_layout[i].config_func
            slave.is_lost = False

        self._master.config_map()
        assert self._master.state_check(pysoem.SAFEOP_STATE) == pysoem.SAFEOP_STATE

    def go_to_op_state(self):
        self._master.state = pysoem.OP_STATE

        self._proc_thread_handle = threading.Thread(target=self._processdata_thread)
        self._proc_thread_handle.start()
        self._check_thread_handle = threading.Thread(target=self._check_thread)
        self._check_thread_handle.start()

        self._master.write_state()
        for _ in range(400):
            self._master.state_check(pysoem.OP_STATE, 50000)
            if self._master.state == pysoem.OP_STATE:
                all_slaves_reached_op_state = True
                break
        assert 'all_slaves_reached_op_state' in locals(), 'could not reach OP state'
        self._master.in_op = True

    def teardown(self):
        self._pd_thread_stop_event.set()
        self._ch_thread_stop_event.set()
        if self._proc_thread_handle:
            self._proc_thread_handle.join()
        if self._check_thread_handle:
            self._check_thread_handle.join()

        self._master.state = pysoem.INIT_STATE
        self._master.write_state()
        self._master.close()

    def get_master(self):
        return self._master

    def get_slaves(self):
        return self._master.slaves

    def _processdata_thread(self):
        while not self._pd_thread_stop_event.is_set():
            self._master.send_processdata()
            self._actual_wkc = self._master.receive_processdata(10000)
            time.sleep(0.01)

    @staticmethod
    def _check_slave(slave, pos):
        if slave.state == (pysoem.SAFEOP_STATE + pysoem.STATE_ERROR):
            print(
                'ERROR : slave {} is in SAFE_OP + ERROR, attempting ack.'.format(pos))
            slave.state = pysoem.SAFEOP_STATE + pysoem.STATE_ACK
            slave.write_state()
        elif slave.state == pysoem.SAFEOP_STATE:
            print(
                'WARNING : slave {} is in SAFE_OP, try change to OPERATIONAL.'.format(pos))
            slave.state = pysoem.OP_STATE
            slave.write_state()
        elif slave.state > pysoem.NONE_STATE:
            if slave.reconfig():
                slave.is_lost = False
                print('MESSAGE : slave {} reconfigured'.format(pos))
        elif not slave.is_lost:
            slave.state_check(pysoem.OP_STATE)
            if slave.state == pysoem.NONE_STATE:
                slave.is_lost = True
                print('ERROR : slave {} lost'.format(pos))
        if slave.is_lost:
            if slave.state == pysoem.NONE_STATE:
                if slave.recover():
                    slave.is_lost = False
                    print(
                        'MESSAGE : slave {} recovered'.format(pos))
            else:
                slave.is_lost = False
                print('MESSAGE : slave {} found'.format(pos))

    def _check_thread(self):
        while not self._ch_thread_stop_event.is_set():
            if self._master.in_op and ((self._actual_wkc < self._master.expected_wkc) or self._master.do_check_state):
                self._master.do_check_state = False
                self._master.read_state()
                for i, slave in enumerate(self._master.slaves):
                    if slave.state != pysoem.OP_STATE:
                        self._master.do_check_state = True
                        self._check_slave(slave, i)
                if not self._master.do_check_state:
                    print('OK : all slaves resumed OPERATIONAL.')
            time.sleep(0.01)


class PySoemTest(unittest.TestCase):
    def test_version(self):
        self.assertEqual(test_config.expected_pysoem_version, pysoem.__version__)


class PySoemTestConfigFunc(unittest.TestCase):
    """Check if an exception in a config_func callback causes config_init to fail"""

    class MyVeryOwnExceptionType(Exception):
        pass
        
    def setUp(self):
        self._test_env = PySoemTestEnvironment()

    def el1259_config_func(self, slave):
        raise self.MyVeryOwnExceptionType()

    def test(self):
        self._test_env.el1259_config_func = self.el1259_config_func

        with self.assertRaises(self.MyVeryOwnExceptionType) as ex:
            self._test_env.setup()
            self.assertTrue(isinstance(ex.exception, self.MyVeryOwnExceptionType))

    def tearDown(self):
        self._test_env.teardown()


class PySoemTestSdo(unittest.TestCase):
    """Test SDO communication"""

    def setUp(self):
        self._test_env = PySoemTestEnvironment()
        self._test_env.setup()
        self._el1259 = self._test_env.get_slaves()[3]

    def tearDown(self):
        self._test_env.teardown()

    def test_access_not_existing_object(self):

        # read
        with self.assertRaises(pysoem.SdoError) as ex1:
            self._el1259.sdo_read(0x1111, 0, 1)
        self.assertEqual(ex1.exception.abort_code, 0x06020000)
        self.assertEqual(ex1.exception.desc, 'The object does not exist in the object directory')

        # write
        with self.assertRaises(pysoem.SdoError) as ex2:
            self._el1259.sdo_write(0x1111, 0, bytes(4))
        self.assertEqual(ex2.exception.abort_code, 0x06020000)
        self.assertEqual(ex2.exception.desc, 'The object does not exist in the object directory')

    def test_write_a_ro_object(self):

        with self.assertRaises(pysoem.SdoError) as ex:
            self._el1259.sdo_write(0x1008, 0, b'test')

        self.assertEqual(ex.exception.abort_code, 0x08000021)
        self.assertEqual(ex.exception.desc, 'Data cannot be transferred or stored to the application '
                                            'because of local control')
        
    def test_compare_eeprom_against_coe_0x1018(self):
        
        sdo_man = struct.unpack('I', self._el1259.sdo_read(0x1018, 1))[0]
        self.assertEqual(sdo_man, self._el1259.man)
        sdo_id = struct.unpack('I', self._el1259.sdo_read(0x1018, 2))[0]
        self.assertEqual(sdo_id, self._el1259.id)
        sdo_rev = struct.unpack('I', self._el1259.sdo_read(0x1018, 3))[0]
        self.assertEqual(sdo_rev, self._el1259.rev)

        sdo_sn = struct.unpack('I', self._el1259.sdo_read(0x1018, 4))[0]
        # serial number is expected to be at word address 0x0E
        eeprom_sn = struct.unpack('I', self._el1259.eeprom_read(0x0E))[0]
        self.assertEqual(sdo_sn, eeprom_sn)

    def test_device_name(self):

        name_size = len(self._el1259.name)

        # test with given string size
        sdo_name = self._el1259.sdo_read(0x1008, 0, name_size).decode('utf-8')
        self.assertEqual(sdo_name, self._el1259.name)

        # test without given string size
        sdo_name = self._el1259.sdo_read(0x1008, 0).decode('utf-8')
        self.assertEqual(sdo_name, self._el1259.name)
        
    def test_read_buffer_to_small(self):
        
        with self.assertRaises(pysoem.PacketError) as cm:
            self._el1259.sdo_read(0x1008, 0, 3).decode('utf-8')
        self.assertEqual(4, cm.exception.slave_pos)
        self.assertEqual(3, cm.exception.error_code)
        self.assertEqual('Data container too small for type', cm.exception.desc)

    def test_write_to_1c1x_while_in_safeop(self):

        for index in [0x1c12, 0x1c13]:
            with self.assertRaises(pysoem.SdoError) as ex1:
                self._el1259.sdo_write(index, 0, bytes(1))
            self.assertEqual(ex1.exception.abort_code, 0x08000022)
            self.assertEqual(ex1.exception.desc, 'Data cannot be transferred or stored to the application '
                                                 'because of the present device state')


def get_obj_from_od(od, index):
    return next(obj for obj in od if obj.index == index)


class PySoemTestSdoInfo(unittest.TestCase):
    """Test SDO Info read"""

    def setUp(self):
        self._test_env = PySoemTestEnvironment()
        self._test_env.setup()
        self._el1259 = self._test_env.get_slaves()[3]

    def tearDown(self):
        self._test_env.teardown()

    def test_sdo_info_var(self):

        obj_0x1000 = get_obj_from_od(self._el1259.od, 0x1000)

        self.assertEqual('Device type', obj_0x1000.name)
        self.assertEqual(7, obj_0x1000.object_code)
        self.assertEqual(pysoem.ECT_UNSIGNED32, obj_0x1000.data_type)
        self.assertEqual(32, obj_0x1000.bit_length)
        self.assertEqual(0x0007, obj_0x1000.obj_access)

    def test_sdo_info_rec(self):

        obj_0x1018 = get_obj_from_od(self._el1259.od, 0x1018)

        self.assertEqual('Identity', obj_0x1018.name)
        self.assertEqual(9, obj_0x1018.object_code)

        entry_vendor_id = obj_0x1018.entries[1]
        self.assertEqual('Vendor ID', entry_vendor_id.name)
        self.assertEqual(pysoem.ECT_UNSIGNED32, entry_vendor_id.data_type)
        self.assertEqual(32, entry_vendor_id.bit_length)
        self.assertEqual(0x0007, entry_vendor_id.obj_access)


class PySoemTestPdo(unittest.TestCase):
    """Use the fact that the EL1259's output state can be monitored"""

    def setUp(self):
        self._test_env = PySoemTestEnvironment()

    def el1259_config_func(self, slave_pos):
        """
        struct format characters
        B - uint8
        x - pac byte
        H - uint16
        """
        el1259 = self._test_env.get_slaves()[slave_pos]

        el1259.sdo_write(0x8001, 2, struct.pack('B', 1))

        rx_map_obj = [0x1603, 0x1607, 0x160B, 0x160F, 0x1613, 0x1617, 0x161B, 0x161F,
                      0x1620, 0x1621, 0x1622, 0x1623, 0x1624, 0x1625, 0x1626, 0x1627]
        pack_fmt = 'Bx' + ''.join(['H' for _ in range(len(rx_map_obj))])
        rx_map_obj_bytes = struct.pack(pack_fmt, len(rx_map_obj), *rx_map_obj)
        el1259.sdo_write(0x1c12, 0, rx_map_obj_bytes, True)

        tx_map_obj = [0x1A00, 0x1A01, 0x1A02, 0x1A03, 0x1A04, 0x1A05, 0x1A06, 0x1A07, 0x1A08,
                      0x1A0C, 0x1A10, 0x1A14, 0x1A18, 0x1A1C, 0x1A20, 0x1A24]
        pack_fmt = 'Bx' + ''.join(['H' for _ in range(len(tx_map_obj))])
        tx_map_obj_bytes = struct.pack(pack_fmt, len(tx_map_obj), *tx_map_obj)
        el1259.sdo_write(0x1c13, 0, tx_map_obj_bytes, True)

        el1259.dc_sync(1, 1000000)

    def test_io_toggle(self):
        """Toggle every output and see if the "Ouput State" in the input changes accordingly"""
        self._test_env.el1259_config_func = self.el1259_config_func
        self._test_env.setup()
        self._test_env.go_to_op_state()

        el1259 = self._test_env.get_slaves()[3]
        output_len = len(el1259.output)

        tmp = bytearray([0 for _ in range(output_len)])

        for i in range(8):
            out_offset = 12*i
            in_offset = 4*i

            tmp[out_offset] = 0x02
            el1259.output = bytes(tmp)
            time.sleep(0.1)
            assert el1259.input[in_offset] & 0x04 == 0x04

            tmp[out_offset] = 0x00
            el1259.output = bytes(tmp)
            time.sleep(0.1)
            assert el1259.input[in_offset] & 0x04 == 0x00

    def tearDown(self):
        self._test_env.teardown()


if __name__ == '__main__':
    unittest.main()
