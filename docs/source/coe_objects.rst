===============================
Reading and Writing CoE Objects
===============================

Although reading and writing CoE objects is pretty straight forward,
type conversions are sometimes an issue.
Usually CoE objects are of type boolean, integer, float or string,
but thees types do not map 1:1 to there Python equivalent.
Because of that, reading and writing CoE objects is done on a raw binary basis,
using the built-in :py:class:`bytes`.
That this the same type one would get when reading a file in binary mode.

.. TODO: cover the 256 byte limit when reading bytes!

CoE object entries of type string
---------------------------------

If the CoE object to be read is a string like the standard object entry 0x1008:00 (Device Name),
one can use the bytes :py:meth:`bytes.decode` method to convert the returned bytes
of :py:meth:`~pysoem.CdefSlave.sdo_read` to a Python 3 string.

.. code-block:: python

   device_name = device.sdo_read(0x1008, 0).decode('utf-8')

Although it is only needed occasionally the other way around would be:

.. code-block:: python

   device.sdo_write(0x2345, 0, 'hello world'.encode('ascii'))

CoE object entries of type integer
----------------------------------

For integer types a similar approach is possible.
Here is an example on how to read the standard object entry 0x1018:01 (Vendor ID), which is a 32 bit unsigned integer, and convert it to an Python built-in :py:class:`int` using :py:meth:`int.from_bytes`.

.. code-block:: python

   vendor_id = int.from_bytes(device.sdo_read(0x1018, 1), byteorder='little', signed=False)

When writing to a 32 bit unsigned integer CoE object entry, :py:meth:`int.to_bytes` could be used like this:

.. code-block:: python

   device.sdo_write(0x3456, 0, (1).to_bytes(4, byteorder='little', signed=False))

Notice that when using to_bytes, the number of bytes must be given as first parameter.

Using the Python standard library :py:mod:`ctypes` module
---------------------------------------------------------

The cytpes types are a bit more flexible, and can also be used for float and boolean types.
Taken the int.from_bytes example from above, the equivalent using ctypes would be:

.. code-block:: python

   import ctypes

   ...
   vendor_id = ctypes.c_uint32.from_buffer_copy(device.sdo_read(0x1018, 1)).value

Here :py:meth:`~ctypes._CData.from_buffer_copy` was used, which is available for all ctypes types.

Doing a write to an 32 bit unsigned integer CoE object entry looks a lot nicer in contrast to the int.to_bytes example:

.. code-block:: python

   device.sdo_write(0x3456, 0, bytes(ctypes.c_uint32(1)))

.. TODO: Beware that this approach works only for little endian machines, as the "byteorder" cannot be given like in the int.from_bytes / int.to_bytes approach.

Note that in the ESI file that comes with an EtherCAT slave, some special PLC types are used that might be unusual to some people.

========  ===========
ESI Type  ctypes Type   
========  ===========
SINT      c_int8 
INT       c_int16 
DINT      c_int32 
LINT      c_int64
USINT     c_uint8 
UINT      c_uint16 
UDINT     c_uint32 
ULINT     c_uint64
REAL      c_float
BOOL      c_bool
========  ===========

.. Beware that in the PLC world a BOOL is supposed to use 1 bit, whereas C uses usually 1 byte.

Using the :py:mod:`struct` module
---------------------------------

Second alternative to use over the int.from_bytes approach could be the struct module.

.. code-block:: python

   import struct
   
   ...
   vendor_id = struct.unpack('I', device.sdo_read(0x1018, 1))[0]

As :py:func:`struct.unpack` returns always a tuple, we need to index the firs element.
The `formate character <https://docs.python.org/3/library/struct.html#format-characters>`_ ``I`` is there to tell the unpack function that we want to convert to a 32 bit unsigned integer.
In the other direction :py:func:`struct.pack` is used:

.. code-block:: python

   device.sdo_write(0x3456, 0, struct.pack('I', 1))

The following list maps the types from the ESI file to the appropriate formate character.

.. TODO: When using struct there might be some issues with alignment.

========   ================
ESI Type   Format Character   
========   ================
SINT       b 
INT        h 
DINT       i 
LINT       q
USINT      B 
UINT       H 
UDINT      I 
ULINT      Q
REAL       f
BOOL       c
========   ================

.. Beware that in the PLC world a BOOL is supposed to use 1 bit, whereas C uses usually 1 byte.




