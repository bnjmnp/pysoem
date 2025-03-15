
import os
import pytest
import pysoem


test_dir = os.path.dirname(os.path.abspath(__file__))


def test_foe_good(pysoem_env):
    pysoem_env.config_init()
    test_slave = pysoem_env.get_xmc_test_device()

    for file_path in ['foe_testdata/random_data_01.bin', 'foe_testdata/random_data_02.bin']:
        with open(os.path.join(test_dir, file_path), 'rb') as file:
            random_data = file.read()

        # write
        test_slave.foe_write('test.bin', 0, random_data)
        # read back
        reread_data = test_slave.foe_read('test.bin', 0, 8192)
        # and check if the reread data is the same as the written data
        assert reread_data[:len(random_data)] == random_data


def test_foe_fails(pysoem_env):
    pysoem_env.config_init()
    test_slave = pysoem_env.get_device_without_foe()

    # expect foe READ to fail
    with pytest.raises(pysoem.MailboxError) as excinfo:
        test_slave.foe_read('test.bin', 0, 8192)

    assert excinfo.value.error_code == 2
    assert excinfo.value.desc == 'The mailbox protocol is not supported'

    # expect foe WRITE to fail
    with pytest.raises(pysoem.MailboxError) as excinfo:
        test_slave.foe_write('test.bin', 0, bytes(32))

    assert excinfo.value.error_code == 2
    assert excinfo.value.desc == 'The mailbox protocol is not supported'

def test_foe_nonexistent_file(pysoem_env):
    """Test that reading a non-existent file raises an appropriate exception."""
    pysoem_env.config_init()
    test_slave = pysoem_env.get_xmc_test_device()
    
    # Expect foe_read to fail for a non-existent file
    with pytest.raises(pysoem.FoeError) as excinfo: 
        test_slave.foe_read('nonexistent.bin', 0, 8192)

    # Expect foe_write to fail for a non-existent file
    with pytest.raises(pysoem.FoeError) as excinfo: 
        test_slave.foe_write('nonexistent.bin', 0, b"test-data")
