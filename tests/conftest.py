

import time
import collections
import threading
import pytest

import pysoem


def pytest_addoption(parser):
    parser.addoption('--ifname', action='store')


class PySoemTestEnvironment:
    """Setup a basic pysoem test fixture that is needed for most of tests"""

    BECKHOFF_VENDOR_ID = 0x0002
    EK1100_PRODUCT_CODE = 0x044c2c52
    EL3002_PRODUCT_CODE = 0x0bba3052
    EL1259_PRODUCT_CODE = 0x04eb3052

    def __init__(self, ifname):
        self._is_overlapping_enabled = None
        self._ifname = ifname
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

    def config_init(self):
        self._master.open(self._ifname)
        assert self._master.config_init(False) > 0

    def go_to_preop_state(self):
        self._master.state_check(pysoem.INIT_STATE, 50000)
        assert self._master.state == pysoem.SAFEOP_STATE

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

    def config_map(self, overlapping_enable=False):
        self._is_overlapping_enabled = overlapping_enable

        self._expected_slave_layout = {
            0: self.SlaveSet('XMC43-Test-Device', 0, 0x12783456, None),
            1: self.SlaveSet('EK1100', self.BECKHOFF_VENDOR_ID, self.EK1100_PRODUCT_CODE, None),
            2: self.SlaveSet('EL3002', self.BECKHOFF_VENDOR_ID, self.EL3002_PRODUCT_CODE, self.el3002_config_func),
            3: self.SlaveSet('EL1259', self.BECKHOFF_VENDOR_ID, self.EL1259_PRODUCT_CODE, self.el1259_config_func),
        }
        self._master.config_dc()
        for i, slave in enumerate(self._master.slaves):
            assert slave.man == self._expected_slave_layout[i].vendor_id
            assert slave.id == self._expected_slave_layout[i].product_code
            slave.config_func = self._expected_slave_layout[i].config_func
            slave.is_lost = False

        if self._is_overlapping_enabled:
            self._master.config_overlap_map()
        else:
            self._master.config_map()
        assert self._master.state_check(pysoem.SAFEOP_STATE) == pysoem.SAFEOP_STATE

    def go_to_op_state(self):
        self._master.state_check(pysoem.SAFEOP_STATE, 50000)
        assert self._master.state == pysoem.SAFEOP_STATE

        self._proc_thread_handle = threading.Thread(target=self._processdata_thread)
        self._proc_thread_handle.start()
        self._check_thread_handle = threading.Thread(target=self._check_thread)
        self._check_thread_handle.start()

        self._master.state = pysoem.OP_STATE
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

    def get_el1259(self):
        return self._master.slaves[3]

    def get_xmc_test_device(self):
        return self._master.slaves[0]  # the XMC device

    def get_device_without_foe(self):
        return self._master.slaves[2]  # the EL3002

    def _processdata_thread(self):
        while not self._pd_thread_stop_event.is_set():
            if self._is_overlapping_enabled:
                self._master.send_overlap_processdata()
            else:
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


@pytest.fixture
def pysoem_env(request):
    env = PySoemTestEnvironment(request.config.getoption('--ifname'))
    yield env
    env.teardown()
