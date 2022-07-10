"""Firmware update example application for PySOEM.

Note: PySOEM >= 1.0.6 is required.
"""

import sys
import argparse
import logging
import struct

import pysoem

logger = logging.getLogger(__name__)


class FirmwareUpdateError(Exception):
    pass


def argument_parsing(cmd_line_args):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('interface_name', type=str,
                        help='ID of the network adapter used for the EtherCAT network.')
    parser.add_argument('device_position', type=int, choices=range(1, 2**16), metavar="1..65535",
                        help='Position of the device in the EtherCAT network to be updated.')
    parser.add_argument('update_file', type=argparse.FileType('rb'),
                        help='Path to the file to be uploaded.')
    return parser.parse_args(cmd_line_args)


def main(cmd_line_args):
    script_args = argument_parsing(cmd_line_args)

    master = pysoem.Master()
    master.open(script_args.interface_name)

    logger.info('Enumerate devices in the network..')
    number_of_devices_found = master.config_init()
    logger.info('..Number of devices found: %d.' % number_of_devices_found)
    if number_of_devices_found == 0:
        raise FirmwareUpdateError(f'No device found at the given interface: {script_args.interface_name}!')
    elif script_args.device_position > number_of_devices_found:
        raise FirmwareUpdateError(f'Requested to update device in position {script_args.device_position}, but only {number_of_devices_found} devices are available!')

    device = master.slaves[script_args.device_position-1]

    logger.info('Request Init state for the target device in position %d.' % script_args.device_position)
    device.state = pysoem.INIT_STATE
    device.write_state()
    device.state_check(pysoem.INIT_STATE, 3_000_000)
    if device.state != pysoem.INIT_STATE:
        raise FirmwareUpdateError('The device did not go into Init state!')

    boot_rx_mbx = device.eeprom_read(pysoem.SiiOffset.BOOT_RX_MBX)
    rx_mbx_addr, rx_mbx_len = struct.unpack('HH', boot_rx_mbx)
    boot_tx_mbx = device.eeprom_read(pysoem.SiiOffset.BOOT_TX_MBX)
    tx_mbx_addr, tx_mbx_len = struct.unpack('HH', boot_tx_mbx)
    logger.info('Update SM0: {Address: 0x%4.4x; Length: %4d}' % (rx_mbx_addr, rx_mbx_len))
    device.amend_mbx(mailbox='out', start_address=rx_mbx_addr, size=rx_mbx_len)
    logger.info('Update SM1: {Address: 0x%4.4x; Length: %4d}' % (tx_mbx_addr, tx_mbx_len))
    device.amend_mbx(mailbox='in', start_address=tx_mbx_addr, size=tx_mbx_len)

    logger.info('Request Boot state for the device.')
    device.state = pysoem.BOOT_STATE
    device.write_state()
    device.state_check(pysoem.BOOT_STATE, 3_000_000)
    if device.state != pysoem.BOOT_STATE:
        raise FirmwareUpdateError('The device did not go into Boot state!')

    logger.info('Send file to the device using FoE write.')
    device.foe_write(filename=script_args.update_file.name[:-4],
                     password=0,
                     data=script_args.update_file.read(),
                     timeout=6_000_000)
    logger.info('Download completed.')

    logger.info('Request Init state for the device.')
    device.state = pysoem.INIT_STATE
    device.write_state()

    master.close()
    logger.info('Finished.')


if __name__ == '__main__':
    try:
        main(sys.argv[1:])
    except Exception as e:
        print(e, file=sys.stderr)
        sys.exit(1)
