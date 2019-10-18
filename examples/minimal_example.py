"""Prints the analog-to-digital converted voltage of an EL3002.

Usage: python minimal_example.py <adapter>

This example expects a physical slave layout according to
_expected_slave_layout, see below.
"""

import sys
import struct
import time
import collections

import pysoem


class MinimalExample:

    BECKHOFF_VENDOR_ID = 0x0002
    EK1100_PRODUCT_CODE = 0x044c2c52
    EL3002_PRODUCT_CODE = 0x0bba3052

    def __init__(self, ifname):
        self._ifname = ifname
        self._master = pysoem.Master()
        SlaveSet = collections.namedtuple(
            'SlaveSet', 'slave_name product_code config_func')
        self._expected_slave_mapping = {0: SlaveSet('EK1100', self.EK1100_PRODUCT_CODE, None),
                                        1: SlaveSet('EL3002', self.EL3002_PRODUCT_CODE, self.el3002_setup)}

    def el3002_setup(self, slave_pos):
        slave = self._master.slaves[slave_pos]

        slave.sdo_write(0x1c12, 0, struct.pack('B', 0))

        map_1c13_bytes = struct.pack('BxHH', 2, 0x1A01, 0x1A03)
        slave.sdo_write(0x1c13, 0, map_1c13_bytes, True)

    def run(self):

        self._master.open(self._ifname)

        # config_init returns the number of slaves found
        if self._master.config_init() > 0:

            print("{} slaves found and configured".format(
                len(self._master.slaves)))

            for i, slave in enumerate(self._master.slaves):
                assert(slave.man == self.BECKHOFF_VENDOR_ID)
                assert(
                    slave.id == self._expected_slave_mapping[i].product_code)
                slave.config_func = self._expected_slave_mapping[i].config_func

            # PREOP_STATE to SAFEOP_STATE request - each slave's config_func is called
            self._master.config_map()

            # wait 50 ms for all slaves to reach SAFE_OP state
            if self._master.state_check(pysoem.SAFEOP_STATE, 50000) != pysoem.SAFEOP_STATE:
                self._master.read_state()
                for slave in self._master.slaves:
                    if not slave.state == pysoem.SAFEOP_STATE:
                        print('{} did not reach SAFEOP state'.format(slave.name))
                        print('al status code {} ({})'.format(hex(slave.al_status),
                                                              pysoem.al_status_code_to_string(slave.al_status)))
                raise Exception('not all slaves reached SAFEOP state')

            self._master.state = pysoem.OP_STATE
            self._master.write_state()

            self._master.state_check(pysoem.OP_STATE, 50000)
            if self._master.state != pysoem.OP_STATE:
                self._master.read_state()
                for slave in self._master.slaves:
                    if not slave.state == pysoem.OP_STATE:
                        print('{} did not reach OP state'.format(slave.name))
                        print('al status code {} ({})'.format(hex(slave.al_status),
                                                              pysoem.al_status_code_to_string(slave.al_status)))
                raise Exception('not all slaves reached OP state')

            try:
                while 1:
                    # free run cycle
                    self._master.send_processdata()
                    self._master.receive_processdata(2000)

                    volgage_ch_1_el3002_as_bytes = self._master.slaves[1].input
                    volgage_ch_1_el3002_as_int16 = struct.unpack(
                        'hh', volgage_ch_1_el3002_as_bytes)[0]
                    voltage = volgage_ch_1_el3002_as_int16 * 10 / 0x8000
                    print('EL3002 Ch 1 PDO: {:#06x}; Voltage: {:.4}'.format(
                        volgage_ch_1_el3002_as_int16, voltage))

                    time.sleep(1)

            except KeyboardInterrupt:
                # ctrl-C abort handling
                print('stopped')

            self._master.state = pysoem.INIT_STATE
            # request INIT state for all slaves
            self._master.write_state()
            self._master.close()
        else:
            print('slaves not found')


if __name__ == '__main__':

    print('minimal_example')

    if len(sys.argv) > 1:
        try:
            MinimalExample(sys.argv[1]).run()
        except Exception as expt:
            print(expt)
            sys.exit(1)
    else:
        print('usage: minimal_example ifname')
        sys.exit(1)
