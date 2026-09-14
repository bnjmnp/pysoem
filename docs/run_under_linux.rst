=========================================
Running PySOEM Python Scripts under Linux
=========================================

What's the issue?
-----------------

Because Linux restricts raw Ethernet communications for applications we need special procedures to execute Python code that uses PySOEM.

Option 1: Use Linux capabilities to enable the ``CAP_NET_RAW`` capability
-------------------------------------------------------------------------

.. code-block:: bash

   sudo setcap cap_net_raw+ep /usr/bin/python3``

With this the ``python3`` executable should run pysoem scripts just fine.
To later remove the set capability run:

.. code-block:: bash

   sudo setcap cap_net_raw+ep /usr/bin/python3``

Option 2: Use a Docker Container
--------------------------------

.. code-block:: bash

   docker run --cap-add=NET_RAW --cap-add=NET_ADMIN …``

This won't work because SOEM does some low level network adapter settings that will always fail inside a container.

Option 3: Run Python with root access (Bad practice)
----------------------------------------------------

You also need to forward your ``PATH`` environment variable, otherwise your Python interpreter cannot be found.

.. code-block:: bash

   sudo env "PATH=$PATH" python <your-pysoem-python-script>``

If you run other applications you may need to forward more environment variables.

For example when running ``tox``

.. code-block:: bash

  sudo env "PATH=$PATH" "PYENV_ROOT=$PYENV_ROOT" "PYTHONPATH=$(python3 -c "import sys; print(':'.join(p for p in sys.path))")" tox -c tox_pypi.ini -- --iface=enp3s0