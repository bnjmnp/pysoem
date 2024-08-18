PySOEM
======

PySOEM is a Cython wrapper for the Simple Open EtherCAT Master Library (https://github.com/OpenEtherCATsociety/SOEM).

Introduction
------------

PySOEM enables basic system testing of EtherCAT slave devices with Python.

Features

* input process data read and output process data write
* SDO read and write
* EEPROM read and write
* FoE read and write

Todo

* EoE

Beware that real-time applications need some special considerations.

Requirements
------------

Linux
^^^^^

* Python 3
* Python scripts that use PySOEM must be executed under administrator privileges

Windows
^^^^^^^

* Python 3 / 64 Bit
* `Npcap <https://nmap.org/npcap/>`_ [*]_ or `WinPcap <https://www.winpcap.org/>`_

.. [*] Make sure you check "Install Npcap in WinPcap API-compatible Mode" during the install

macOS (new with PySOEM 1.1.5)
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

* Python 3

Installation
------------
::

  python -m pip install pysoem

or

::

  pip install pysoem

Consider using a `virtualenv <https://virtualenv.pypa.io>`_.


Usage
-----
Although there are some pieces missing, the documentation is hosted on "Read the Docs" at: `pysoem.readthedocs.io <https://pysoem.readthedocs.io>`_.

Please also have a look at `the examples on GitHub <https://github.com/bnjmnp/pysoem/tree/master/examples>`_.

Contribution
------------

Any contributions are welcome and highly appreciated.
Let's discuss any (major) API change, or large piles of new code first.
Using `this pysoem chat room on gitter <https://gitter.im/pysoem/pysoem>`_ is one communication channel option.


Changes
-------

v1.1.8
^^^^^^^
* Fixes null pointer issues when reading not initialized properties ``config_func`` and ``setup_func``.

v1.1.7
^^^^^^^
* Adds ``add_emergency_callback()`` to allow a better handling of emergency messages.
* Improves auto-completion.

v1.1.6
^^^^^^^
* Adds working counter check on SDO read and write.
* Fixes issues with ``config_init()`` when it's called multiple times.

v1.1.5
^^^^^^^
* Adds support for redundancy mode, ``master.open()`` provides now an optional second parameter for the redundancy port.

v1.1.4
^^^^^^^
* Fixes Cython compiling issues.

v1.1.3
^^^^^^^
* Adds function ``_disable_complete_access()`` that stops config_map() from using "complete access" for SDO requests.

v1.1.0
^^^^^^^
* Changed the data type for the ``name`` attribute of SDO info CdefCoeObject and CdefCoeObjectEntry, they are of type bytes now instead of a regular Python 3 string.
* Also changed the ``desc`` attribute of the ``find_adapters()`` list elements to ``bytes``.
* Introduces the ``open()`` context manager function.
* Adds the ``setup_func`` that will maybe later replace the ``config_func``.

v1.0.8
^^^^^^^
* Version bump only to re-upload to PyPI with windows-wheel for Python 3.11

v1.0.7
^^^^^^^
* Fix issues with timeouts at ``amend_mbx`` and ``set_watchdog``.

v1.0.6
^^^^^^^
* Introduces ``amend_mbx`` and ``set_watchdog``, though this is rather experimental
* New example ``firmware_update.py``.

v1.0.5
^^^^^^^
* Introduces the ``manual_state_change`` property

v1.0.4
^^^^^^^
* Proper logging
* Introduces ``mbx_receive``

v1.0.3
^^^^^^^
* Fix the FoE password issue

v1.0.2
^^^^^^^
* Licence change to MIT licence
* Introduces configurable timeouts for SDO read and SDO write
* Improved API docs

v1.0.1
^^^^^^^
* API change: remove the size parameter for ``foe_write``
* Introduces overlap map support

v1.0.0
^^^^^^^
* No Cython required to install the package from the source distribution

v0.1.1
^^^^^^^
* Introduces FoE

v0.1.0
^^^^^^^
* Update of the underlying SOEM

v0.0.18
^^^^^^^
* Fixes bug when Ibytes = 0 and Ibits > 0

v0.0.17
^^^^^^^
* Exposes ec_DCtime (``dc_time``) for DC synchronization

v0.0.16
^^^^^^^
* Improvement on SDO Aborts

v0.0.15
^^^^^^^
* SDO info read

v0.0.14
^^^^^^^
* Readme update only

v0.0.13
^^^^^^^
* Initial publication
