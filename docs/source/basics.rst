======
Basics
======

Obtaining a Device Instance
---------------------------

Like in the example from the beginning, accessing a device in a network is done by a Masters :py:attr:`pysoem.Master.slaves` list.


.. code-block:: python

   import pysoem

   master = pysoem.Master()

   master.open('Your network adapters ID')

   if master.config_init() > 0:
       device_foo = master.slaves[0]
       device_bar = master.slaves[1]
   else:
       print('no device found')

   master.close()

With the device reference you can access some information that was read out from the device during :py:func:`pysoem.Master.config_init`.
For example the devices names:

.. code-block:: python

    print(device_foo.name)
    print(device_bar.name)

You can also read and wirte CoE objects, and read input process data and wirte output process data, with the device reference.
This will be covered in the next sections.