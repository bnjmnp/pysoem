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

import unittest
import collections
import struct

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
        self.SlaveSet = collections.namedtuple('SlaveSet', 'name product_code config_func')

        self.el3002_config_func = None
        self.el1259_config_func = None
        self._expected_slave_layout = None

    def setup(self):

        self._expected_slave_layout = {0: self.SlaveSet('EK1100', self.EK1100_PRODUCT_CODE, None),
                                       1: self.SlaveSet('EL3002', self.EL3002_PRODUCT_CODE, self.el3002_config_func),
                                       2: self.SlaveSet('EL1259', self.EL1259_PRODUCT_CODE, self.el1259_config_func)}
        self._master.open(self._ifname)

        assert self._master.config_init(False) > 0

        for i, slave in enumerate(self._master.slaves):
            assert slave.man == self.BECKHOFF_VENDOR_ID
            assert slave.id == self._expected_slave_layout[i].product_code
            slave.config_func = self._expected_slave_layout[i].config_func
            slave.is_lost = False

        self._master.config_map()

        assert(self._master.state_check(pysoem.SAFEOP_STATE) == pysoem.SAFEOP_STATE)

    def teardown(self):
        self._master.state = pysoem.INIT_STATE
        self._master.write_state()
        self._master.close()

    def get_master(self):
        return self._master

    def get_slaves(self):
        return self._master.slaves


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
        self._el1259 = self._test_env.get_slaves()[2]

    def tearDown(self):
        self._test_env.teardown()

    def test_access_not_existing_object(self):

        # read
        with self.assertRaises(pysoem.SdoError) as ex1:
            self._el1259.sdo_read(0x1111, 0, 1)

        # write
        with self.assertRaises(pysoem.SdoError) as ex2:
            self._el1259.sdo_write(0x1111, 0, bytes(4))

        self.assertEqual(ex1.exception.abort_code, 0x06020000)
        self.assertEqual(ex1.exception.desc, 'The object does not exist in the object directory')
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
        self.assertEqual(3, cm.exception.slave_pos)
        self.assertEqual(3, cm.exception.error_code)
        self.assertEqual('Data container too small for type', cm.exception.desc)


def get_obj_from_od(od, index):
    return next(obj for obj in od if obj.index == index)


class PySoemTestSdoInfo(unittest.TestCase):
    """Test SDO Info read"""

    def setUp(self):
        self._test_env = PySoemTestEnvironment()
        self._test_env.setup()
        self._el1259 = self._test_env.get_slaves()[2]

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


if __name__ == '__main__':
    unittest.main()
