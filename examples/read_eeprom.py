"""Prints name and description of available network adapters."""

import sys
import pysoem


def read_eeprom_of_first_slave(ifname):
    master = pysoem.Master()
    
    master.open(ifname)
    
    if master.config_init() > 0:
    
        first_slave = master.slaves[0]
        
        for i in range(0, 0x80, 2):
            print('{:04x}:'.format(i), end='')
            print('|'.join('{:02x}'.format(x) for x in first_slave.eeprom_read(i)))
    
    else:
        print('no slave available')
        
    master.close()


if __name__ == '__main__':

    print('script started')

    if len(sys.argv) > 1:
        read_eeprom_of_first_slave(sys.argv[1])
    else:
        print('give ifname as script argument')
