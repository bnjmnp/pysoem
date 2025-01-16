import pysoem
import sys
import time
import threading
try:
    from pytun import TunTapDevice, IFF_TAP
except ImportError as e:
    raise Exception("EOE virtual network requires pytun, please install it with 'pip install python-pytun'. Note that this package does not support Windows.") from e


class EoeExample(object):

    @staticmethod
    def _hash_mac(mac):
        return (int(mac[0]) << 40 |
                int(mac[1]) << 32 |
                int(mac[2]) << 24 |
                int(mac[3]) << 16 |
                int(mac[4]) << 8  |
                int(mac[5]) << 0  )

    def __init__(self):
        self._tap = None
        self._mac_map = {}
        self.master = pysoem.Master()
        self._eoe_worker_thread = None
        self._keep_running = True

    def do_eoe_example(self, ifname):
        self.master.open(ifname)

        self._tap = TunTapDevice(flags=IFF_TAP)
        self._tap.addr = "10.12.34.1"
        self._tap.netmask = "255.255.255.0"
        self._tap.up()

        eoe_worker_thread = threading.Thread(target=self._eoe_worker, daemon=True)

        try:
            if self.master.config_init() > 0:
                # Assign IP addresses to each slave
                for slave_pos, slave in enumerate(self.master.slaves):
                    print("Setting slave %d IP address to 10.12.34.%d"%(slave_pos+1, slave_pos+2))
                    slave.eoe_set_ip(ip="10.12.34.%d"%(slave_pos+2), netmask="255.255.255.0", mac="02:00:00:00:00:%02d"%(slave_pos))
                    self._mac_map[self._hash_mac(b"\x02\x00\x00\x00\x00"+slave_pos.to_bytes(1,'little'))] = slave

                # Set eoe callback and start virtual switch thread
                self.master.set_eoe_callback(self.eoe_callback)
                eoe_worker_thread.start()

                print("\nSlave IP info:")
                print("[   mac    ,   ip    , netmask ,  gateway , dns_ip , dns_name]")
                for s in self.master.slaves:
                    try:
                        print(s.eoe_get_ip())
                    except Exception as e:
                        print("Failed to get eoe ip data for slave " + str(e.slave_pos))

                print("EOE network started. Use ctrl+c to exit")
                while True:
                    # EOE callback requires mailbox service. Loop here to do that
                    for s in self.master.slaves:
                        try:
                            wkc = s.mbx_receive()
                        except Exception as e:
                            print("Mail failure: " + e.__str__())
                            time.sleep(0.100)
                    time.sleep(0.010)
            else:
                print('no slave available')
        except Exception as ex:
            raise ex
        finally:
            self._keep_running = False
            self.master.close()
            self._tap.close()

    def _eoe_worker(self):
        while self._keep_running:
            data = self._tap.read(self._tap.mtu)
            extra_data = data[:4]
            data = data[4:] #TODO: Figure out what these bytes are?

            # parse ethernet frame
            eth_header = data[:14]
            # ethernet destination hardware address (MAC)
            eth_dst = eth_header[0:6]
            # ethernet source hardware address (MAC)
            eth_src = eth_header[6:12]

            # forward ethernet frame if dest in mac table, forward ethernet frame to it
            if self._hash_mac(eth_dst) in self._mac_map:
                self._mac_map[self._hash_mac(eth_dst)].eoe_send_data(data)
            # if dest is broadcast address, broadcast ethernet frame to every known slave
            elif eth_dst == b'\xff\xff\xff\xff\xff\xff':
                for slv in self.master.slaves:
                    # TODO: Multithread since sending a packet can take a little while?
                    slv.eoe_send_data(data)
            # otherwise, for simplicity, discard the ethernet frame

    def eoe_callback(self, data, slaveNum):
        if (len(data) < 14):
            # Not enough data for ethernet packet
            return

        # Always send to TAP, let OS networking stack decide what to do with it
        # Also lets wireshark see all packets on network
        # TODO: figure out what the extra data at the beginning of this actually is
        self._tap.write(bytes([0x00, 0x00, data[12], data[13]]) + data)

        # Send to other devices on the network if required
        eth_header = data[:14]
        eth_dst = eth_header[0:6]
        eth_src = eth_header[6:12]

        slaveIdx = slaveNum - 1
        # insert/update mac table
        if (self._hash_mac(eth_src) not in self._mac_map or self._mac_map.get(self._hash_mac(eth_src)) != self.master.slaves[slaveIdx]):
            self._mac_map[self._hash_mac(eth_src)] = self.master.slaves[slaveIdx]
        if self._hash_mac(eth_dst) in self._mac_map:
            self._mac_map[self._hash_mac(eth_dst)].eoe_send_data(data)
        elif eth_dst == b'\xff\xff\xff\xff\xff\xff':
            for slv in self.master.slaves:
                # TODO: Multithread since sending a packet can take a little while?
                if slv is not self.slaves[slaveIdx]:
                    slv.eoe_send_data(data)

if __name__ == '__main__':

    print('script started')
    example = EoeExample()

    if len(sys.argv) > 1:
        example.do_eoe_example(sys.argv[1])
    else:
        print('usage: python eoe_example.py <ifname>')
        print('avalible interfaces:')
        for interface in pysoem.find_adapters():
            print("  " + interface.name)
