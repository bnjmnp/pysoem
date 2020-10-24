

def test_foe(pysoem_environment):
    pysoem_environment.setup()
    test_slave = pysoem_environment.get_slave_for_foe_testing()

    for file_path in ['./foe_testdata/random_data_01.bin', './foe_testdata/random_data_02.bin']:
        with open(file_path, 'rb') as file:
            random_data = file.read()

        # write
        test_slave.foe_write('test.bin', 0, len(random_data), random_data)
        # read back
        reread_data = test_slave.foe_read('test.bin', 0, 8192)
        # and check if the reread data is the same as the written data
        assert reread_data[:len(random_data)] == random_data
