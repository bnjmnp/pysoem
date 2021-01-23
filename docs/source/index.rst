Welcome to PySOEM's documentation!
==================================

PySOEM enables basic system testing of EtherCAT slave devices with Python. 

PySOEM is a wrapper around the `Simple Open EtherCAT Master`_  (SOEM).
Unlike plain C Library wrappers, PySOEM tries to provide an API that can already be used in a more pythonic way.

.. _`Simple Open EtherCAT Master`: https://github.com/OpenEtherCATsociety/SOEM/

One of the simplest examples to get a EtherCAT network up looks like this.

.. code-block:: python

   import pysoem

   master = pysoem.Master()

   master.open('Your network adapters ID')

   if master.config_init() > 0:
       for device in master.slaves:
           print(f'Found Device {device.name}')
   else:
       print('no device found')

   master.close()

With this script the name of every device in the network will be printed.

.. toctree::
   :maxdepth: 1
   :caption: Getting Started

   Requirements <requirements.rst>
   Installation <installation.rst>

.. toctree::
   :maxdepth: 1
   :caption: User Guide

   Basics <basics.rst>
   Reading and Writing CoE Objects <coe_objects.rst>
   Process Data Exchange <process_data.rst>

.. toctree::
   :maxdepth: 1
   :caption: API Documentation

   Master <master.rst>
   CdefSlave <cdef_slave.rst>
   Exceptions <exceptions.rst>
   Helpers <helpers.rst>
