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
* Cython (installed into your Python distribution)
* GCC (installed on your machine)
* Python scripts that use PySOEM must be executed under administrator privileges

Windows
^^^^^^^

* Python 3 / 64 Bit
* `Npcap <https://nmap.org/npcap/>`_ [*]_ or `WinPcap <https://www.winpcap.org/>`_

.. [*] Make sure you check "Install Npcap in WinPcap API-compatible Mode" during the install

Installation
------------
::

  python -m pip install pysoem

or

::

  pip install pysoem

Consider using a `virtualenv <https://virtualenv.pypa.io/en/stable/>`_.


Usage
-----
Please have a look at the examples on GitHub.


Changes
-------

v1.0.0
^^^^^^^
* API change: remove the size parameter for `foe_write`
* Introduces overlap map support

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
* Exposes ec_DCtime (`dc_time`) for DC synchronization

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
