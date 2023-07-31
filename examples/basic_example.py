"""Toggles the state of a digital output on an EL1259.

Usage: python basic_example.py <adapter>

This example expects a physical slave layout according to _expected_slave_layout, seen below.
Timeouts are all given in us.
"""

import os
import sys
import struct
import time
import threading
import dataclasses
import typing
import argparse


import pysoem


BECKHOFF_VENDOR_ID = 0x0000_0002
EK1100_PRODUCT_CODE = 0x044C_2C52
EL3002_PRODUCT_CODE = 0x0BBA_3052
EL1259_PRODUCT_CODE = 0x04EB_3052


@dataclasses.dataclass
class Device:
    name: str
    vendor_id: int
    product_code: int
    config_func: typing.Callable = None


class BasicExample:
    def __init__(self, ifname, ifname_red):
        self._ifname = ifname
        self._ifname_red = ifname_red
        self._pd_thread_stop_event = threading.Event()
        self._ch_thread_stop_event = threading.Event()
        self._actual_wkc = 0
        self._master = pysoem.Master()
        self._master.in_op = False
        self._master.do_check_state = False
        self._expected_slave_layout = {
            0: Device("EK1100", BECKHOFF_VENDOR_ID, EK1100_PRODUCT_CODE),
            1: Device("EL3002", BECKHOFF_VENDOR_ID, EL3002_PRODUCT_CODE),
            2: Device("EL1259", BECKHOFF_VENDOR_ID, EL1259_PRODUCT_CODE, self.el1259_setup)
        }

    def el1259_setup(self, slave_pos):
        """Config function that will be called when transitioning from PreOP state to SafeOP state."""
        slave = self._master.slaves[slave_pos]

        # Enable the digital output.
        slave.sdo_write(index=0x8001, subindex=2, data=struct.pack("B", 1))

        # Select rx PDOs.
        rx_map_obj = [
            0x1603,
            0x1607,
            0x160B,
            0x160F,
            0x1611,
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
        rx_map_obj_bytes = struct.pack(
            "Bx" + "".join(["H" for _ in range(len(rx_map_obj))]), len(rx_map_obj), *rx_map_obj)
        slave.sdo_write(index=0x1C12, subindex=0, data=rx_map_obj_bytes, ca=True)

    def _processdata_thread(self):
        """Background thread that sends and receives the process-data frame in a 10ms interval."""
        while not self._pd_thread_stop_event.is_set():
            self._master.send_processdata()
            self._actual_wkc = self._master.receive_processdata(timeout=100_000)
            if not self._actual_wkc == self._master.expected_wkc:
                print("incorrect wkc")
            time.sleep(0.01)

    def _pdo_update_loop(self):
        """The actual application code used to toggle the digital output at the EL1259 in an endless loop.

        Called when all slaves reached OP state.
        Updates the rx PDO of the EL1259 every second.
        """
        self._master.in_op = True

        output_len = len(self._master.slaves[2].output)

        tmp = bytearray([0 for i in range(output_len)])

        toggle = True
        try:
            while 1:
                if toggle:
                    tmp[0] = 0x00
                else:
                    tmp[0] = 0x02
                self._master.slaves[2].output = bytes(tmp)

                toggle ^= True

                time.sleep(1)

        except KeyboardInterrupt:
            # ctrl-C abort handling
            print("stopped")

    def run(self):
        self._master.open(self._ifname, self._ifname_red)

        if not self._master.config_init() > 0:
            self._master.close()
            raise BasicExampleError("no slave found")

        for i, slave in enumerate(self._master.slaves):
            if not ((slave.man == self._expected_slave_layout[i].vendor_id) and
                    (slave.id == self._expected_slave_layout[i].product_code)):
                self._master.close()
                raise BasicExampleError("unexpected slave layout")
            slave.config_func = self._expected_slave_layout[i].config_func
            slave.is_lost = False

        self._master.config_map()

        if self._master.state_check(pysoem.SAFEOP_STATE, timeout=50_000) != pysoem.SAFEOP_STATE:
            self._master.close()
            raise BasicExampleError("not all slaves reached SAFEOP state")
        
        slave.dc_sync(act=True, sync0_cycle_time=10_000_000)  # time is given in ns -> 10,000,000ns = 10ms

        self._master.state = pysoem.OP_STATE

        check_thread = threading.Thread(target=self._check_thread)
        check_thread.start()
        proc_thread = threading.Thread(target=self._processdata_thread)
        proc_thread.start()

        # send one valid process data to make outputs in slaves happy
        self._master.send_processdata()
        self._master.receive_processdata(timeout=2000)
        # request OP state for all slaves

        self._master.write_state()

        all_slaves_reached_op_state = False
        for i in range(40):
            self._master.state_check(pysoem.OP_STATE, timeout=50_000)
            if self._master.state == pysoem.OP_STATE:
                all_slaves_reached_op_state = True
                break

        if all_slaves_reached_op_state:
            self._pdo_update_loop()

        self._pd_thread_stop_event.set()
        self._ch_thread_stop_event.set()
        proc_thread.join()
        check_thread.join()
        self._master.state = pysoem.INIT_STATE
        # request INIT state for all slaves
        self._master.write_state()
        self._master.close()

        if not all_slaves_reached_op_state:
            raise BasicExampleError("not all slaves reached OP state")

    @staticmethod
    def _check_slave(slave, pos):
        if slave.state == (pysoem.SAFEOP_STATE + pysoem.STATE_ERROR):
            print(f"ERROR : slave {pos} is in SAFE_OP + ERROR, attempting ack.")
            slave.state = pysoem.SAFEOP_STATE + pysoem.STATE_ACK
            slave.write_state()
        elif slave.state == pysoem.SAFEOP_STATE:
            print(f"WARNING : slave {pos} is in SAFE_OP, try change to OPERATIONAL.")
            slave.state = pysoem.OP_STATE
            slave.write_state()
        elif slave.state > pysoem.NONE_STATE:
            if slave.reconfig():
                slave.is_lost = False
                print(f"MESSAGE : slave {pos} reconfigured")
        elif not slave.is_lost:
            slave.state_check(pysoem.OP_STATE)
            if slave.state == pysoem.NONE_STATE:
                slave.is_lost = True
                print(f"ERROR : slave {pos} lost")
        if slave.is_lost:
            if slave.state == pysoem.NONE_STATE:
                if slave.recover():
                    slave.is_lost = False
                    print(f"MESSAGE : slave {pos} recovered")
            else:
                slave.is_lost = False
                print(f"MESSAGE : slave {pos} found")

    def _check_thread(self):
        while not self._ch_thread_stop_event.is_set():
            if self._master.in_op and ((self._actual_wkc < self._master.expected_wkc) or self._master.do_check_state):
                self._master.do_check_state = False
                self._master.read_state()
                for i, slave in enumerate(self._master.slaves):
                    if slave.state != pysoem.OP_STATE:
                        self._master.do_check_state = True
                        BasicExample._check_slave(slave, i)
                if not self._master.do_check_state:
                    print("OK : all slaves resumed OPERATIONAL.")
            time.sleep(0.01)


class BasicExampleError(Exception):
    def __init__(self, message):
        super().__init__(message)
        self.message = message


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Example code for PySOEM.")
    parser.add_argument("iface", type=str, help="ID of the network adapter used.")
    parser.add_argument("ifname_red", nargs="?", type=str, help="Optional: ID of the second network adapter used (for redundancy).")
    args = parser.parse_args()

    try:
        BasicExample(args.iface, args.ifname_red).run()
    except BasicExampleError as err:
        print(f"{os.path.basename(__file__)} failed: {err.message}")
        sys.exit(1)
