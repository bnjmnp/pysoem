
Running Tests
^^^^^^^^^^^^^

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