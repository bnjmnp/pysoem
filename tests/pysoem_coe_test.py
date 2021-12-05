
import struct
import pytest
import pysoem


@pytest.fixture
def el1259(pysoem_env):
    pysoem_env.config_init()
    pysoem_env.config_map()
    return pysoem_env.get_el1259()


def get_obj_from_od(od, index):
    return next(obj for obj in od if obj.index == index)


def test_access_not_existing_object(el1259):
    # read
    with pytest.raises(pysoem.SdoError) as excinfo:
        el1259.sdo_read(0x1111, 0, 1)
    assert excinfo.value.abort_code == 0x06020000
    assert excinfo.value.desc == 'The object does not exist in the object directory'

    # write
    with pytest.raises(pysoem.SdoError) as excinfo:
        el1259.sdo_write(0x1111, 0, bytes(4))
    assert excinfo.value.abort_code == 0x06020000
    assert excinfo.value.desc == 'The object does not exist in the object directory'


def test_write_a_ro_object(el1259):

    with pytest.raises(pysoem.SdoError) as excinfo:
        el1259.sdo_write(0x1008, 0, b'test')

    assert excinfo.value.abort_code == 0x08000021
    assert excinfo.value.desc == 'Data cannot be transferred or stored to the application because of local control'


def test_compare_eeprom_against_coe_0x1018(el1259):
    sdo_man = struct.unpack('I', el1259.sdo_read(0x1018, 1))[0]
    assert sdo_man == el1259.man
    sdo_id = struct.unpack('I', el1259.sdo_read(0x1018, 2))[0]
    assert sdo_id == el1259.id
    sdo_rev = struct.unpack('I', el1259.sdo_read(0x1018, 3))[0]
    assert sdo_rev == el1259.rev

    sdo_sn = struct.unpack('I', el1259.sdo_read(0x1018, 4))[0]
    # serial number is expected to be at word address 0x0E
    eeprom_sn = struct.unpack('I', el1259.eeprom_read(0x0E))[0]
    assert sdo_sn == eeprom_sn


def test_device_name(el1259):
    name_size = len(el1259.name)

    # test with given string size
    sdo_name = el1259.sdo_read(0x1008, 0, name_size).decode('utf-8')
    assert sdo_name == el1259.name

    # test without given string size
    sdo_name = el1259.sdo_read(0x1008, 0).decode('utf-8')
    assert sdo_name == el1259.name


def test_read_buffer_to_small(el1259):
    with pytest.raises(pysoem.PacketError) as excinfo:
        el1259.sdo_read(0x1008, 0, 3).decode('utf-8')
    assert 4 == excinfo.value.slave_pos
    assert 3 == excinfo.value.error_code
    assert 'Data container too small for type', excinfo.value.desc


def test_write_to_1c1x_while_in_safeop(el1259):
    for index in [0x1c12, 0x1c13]:
        with pytest.raises(pysoem.SdoError) as excinfo:
            el1259.sdo_write(index, 0, bytes(1))
        assert excinfo.value.abort_code == 0x08000022
        assert excinfo.value.desc == 'Data cannot be transferred or stored to the application because of the present device state'

@pytest.mark.skip
def test_read_timeout(pysoem_env):
    """Test timeout

    TODO: test an object that really errors when the timeout is to low
    """
    master = pysoem_env.get_master()
    old_sdo_read_timeout = master.sdo_read_timeout
    assert old_sdo_read_timeout == 700000
    master.sdo_read_timeout = 0
    assert master.sdo_read_timeout == 0
    master.sdo_read_timeout = old_sdo_read_timeout
    assert master.sdo_read_timeout == 700000


@pytest.mark.skip
def test_write_timeout(pysoem_env):
    """Test timeout

    TODO: test an object that really errors when the timeout is to low
    """
    master = pysoem_env.get_master()
    old_sdo_write_timeout = master.sdo_write_timeout
    assert old_sdo_write_timeout == 700000
    master.sdo_write_timeout = 0
    assert master.sdo_write_timeout == 0
    master.sdo_write_timeout = old_sdo_write_timeout
    assert master.sdo_write_timeout == 700000


def test_sdo_info_var(el1259):

    obj_0x1000 = get_obj_from_od(el1259.od, 0x1000)

    assert 'Device type' == obj_0x1000.name
    assert obj_0x1000.object_code == 7
    assert obj_0x1000.data_type == pysoem.ECT_UNSIGNED32
    assert obj_0x1000.bit_length == 32
    assert obj_0x1000.obj_access == 0x0007


def test_sdo_info_rec(el1259):

    obj_0x1018 = get_obj_from_od(el1259.od, 0x1018)

    assert 'Identity' == obj_0x1018.name
    assert obj_0x1018.object_code == 9

    entry_vendor_id = obj_0x1018.entries[1]
    assert entry_vendor_id.name == 'Vendor ID'
    assert entry_vendor_id.data_type == pysoem.ECT_UNSIGNED32
    assert entry_vendor_id.bit_length == 32
    assert entry_vendor_id.obj_access == 0x0007
