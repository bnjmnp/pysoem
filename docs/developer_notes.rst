===============
Developer Notes
===============
Helper Makefile
---------------
.. code-block:: makefile

   include .env
   
   build:
     python -m pip install build
     python -m build 
   
   clean:
     -rm src/pysoem/pysoem.c
     -rm src/pysoem/*.pyd
     -rm -rf src/pysoem.egg-info
     -rm -rf src/pysoem/__pycache__
     -rm -rf src/__pycache__
     -rm -rf tests/__pycache__
     -rm -rf build
     -rm -rf dist
     -rm -rf .pytest_cache
   
   uninstall:
     python -m pip uninstall -y pysoem
   
   install_local:
     python -m pip install .

   install_github:
     python -m pip install git+https://github.com/bnjmnp/pysoem.git
   
   install_testpypi:
     python -m pip install -i https://test.pypi.org/simple/ pysoem
   
   install_pypi:
     python -m pip install pysoem
   
   test:
     python -m pip install pytest
     pytest tests --ifname=$(IFACE)
   
   tox_local:
     python -m pip install tox
     python -m tox run -r -c tests/tox_local.ini -- --ifname=$(IFACE)
   
   tox_test_pypi:
     python -m pip install tox
     python -m tox run -r -c tests/tox_test_pypi.ini -- --ifname=$(IFACE)
   
   tox_pypi:
     python -m pip install tox
     python -m tox run -r -c tests/tox_pypi.ini -- --ifname=$(IFACE)
   
   run_basic_example:
     python examples/basic_example.py $(IFACE)

Important notice, for the indentation tabs must be used!

For the targets that need hardware you need to specify the adapter-id via the ``IFACE`` variable ether

* during the the make call like: ``make <target> IFACE=<adapter-id>`` or
* by creating an environment variable with the same name or
* ``IFACE`` is put into an ``.env`` file which is already imported by the above makefile. For example the ``.env`` should look like this:
     .. code-block:: makefile
     
        IFACE=<adapter-id>

Running Tests
-------------

TODO: Add information about the hardware setup for testing.

Because the tests require hardware they certainly cannot be run on a CI/CD system.

To run tests with the currently active Python distribution use:
::

  python -m pytest --ifname="<your-nic-id>

To run the tests locally for all specified Python versions, independent of the operating system run `tox <https://tox.wiki/en/latest/index.html>`_ inside the test directory.

* Use ``tox run -c tox_local.ini -- --ifname="<your-nic-id>"`` to test pysoem build locally.
* Use ``tox run -c tox_test_pypi.ini -- --ifname="<your-nic-id>"`` to test pysoem downloaded from TestPyPI.
* Use ``tox run -c tox_pypi.ini -- --ifname="<your-nic-id>"`` to test pysoem downloaded from PyPI.

Python versions not installed on your machine will be skipped.