
import pytest
import pysoem


def test_version():
    assert isinstance(pysoem.__version__, str)


def test_find_adapters():
    pysoem.find_adapters()


def test_config_function_exception(pysoem_env):
    """Check if an exception in a config_func callback causes config_init to fail"""
    class DummyException(Exception):
        pass

    def el1259_config_func(slave_pos):
        raise DummyException()

    pysoem_env.config_init()
    pysoem_env.el1259_config_func = el1259_config_func

    with pytest.raises(DummyException) as excinfo:
        pysoem_env.config_map()
    assert isinstance(excinfo.value, DummyException)
