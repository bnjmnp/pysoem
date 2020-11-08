
import sys

import pysoem


def write_file_to_first_slave(ifname, file_path):
    master = pysoem.Master()

    master.open(ifname)

    try:
        if master.config_init() > 0:

            first_slave = master.slaves[0]

            with open(file_path, 'rb') as file:
                file_data = file.read()
                first_slave.foe_write('data.bin', 0, file_data)
        else:
            print('no slave available')
    except Exception as ex:
        raise ex
    finally:
        master.close()


if __name__ == '__main__':

    print('script started')

    if len(sys.argv) > 1:
        write_file_to_first_slave(sys.argv[1], sys.argv[2])
    else:
        print('usage: python write_foe.py <ifname> <file>')
