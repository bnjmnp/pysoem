import sys
import os

from setuptools import setup, Extension
from Cython.Build import cythonize


soem_sources = []
soem_inc_dirs = []

if sys.platform.startswith('win'):
    soem_macros = [('WIN32', '')]
    soem_lib_dirs = [os.path.join('.', 'soem', 'oshw', 'win32', 'wpcap', 'Lib', 'x64')]
    soem_libs = ['wpcap', 'Packet', 'Ws2_32', 'Winmm']
    soem_inc_dirs.append(os.path.join('.', 'soem', 'oshw', 'win32', 'wpcap', 'Include'))
    os_name = 'win32'
elif sys.platform.startswith('linux'):
    soem_macros = []
    soem_lib_dirs = []
    soem_libs = ['pthread', 'rt'] 
    os_name = 'linux'

soem_sources.extend([os.path.join('.', 'soem', 'osal', os_name, 'osal.c'),
                     os.path.join('.', 'soem', 'oshw', os_name, 'oshw.c'),
                     os.path.join('.', 'soem', 'oshw', os_name, 'nicdrv.c'),
                     os.path.join('.', 'soem', 'soem', 'ethercatbase.c'),
                     os.path.join('.', 'soem', 'soem', 'ethercatcoe.c'),
                     os.path.join('.', 'soem', 'soem', 'ethercatconfig.c'),
                     os.path.join('.', 'soem', 'soem', 'ethercatdc.c'),
                     os.path.join('.', 'soem', 'soem', 'ethercatfoe.c'),
                     os.path.join('.', 'soem', 'soem', 'ethercatmain.c'),
                     os.path.join('.', 'soem', 'soem', 'ethercatprint.c'),
                     os.path.join('.', 'soem', 'soem', 'ethercatsoe.c')])

soem_inc_dirs.extend([os.path.join('.', 'soem', 'oshw', os_name),
                      os.path.join('.', 'soem', 'osal', os_name),
                      os.path.join('.', 'soem', 'oshw'),
                      os.path.join('.', 'soem', 'osal'),
                      os.path.join('.', 'soem', 'soem')])


def readme():
    """see: http://python-packaging.readthedocs.io/en/latest/metadata.html"""
    with open('README.rst') as f:
        return f.read()

def version():
    """see: https://packaging.python.org/guides/single-sourcing-package-version/"""
    with open('VERSION') as f:
        return f.read().strip()


setup(name='pysoem',
      version=version(),
      description='Cython wrapper for the SOEM Library',
      author='Benjamin Partzsch',
      author_email='benjamin_partzsch@web.de',
      url='https://github.com/bnjmnp/pysoem',
      license='GPLv2',
      long_description=readme(),
      ext_modules=cythonize([Extension("pysoem",
                                       ["pysoem.pyx"] + soem_sources,
                                       define_macros=soem_macros,
                                       libraries=soem_libs,
                                       library_dirs=soem_lib_dirs,
                                       include_dirs=soem_inc_dirs)]),
      classifiers=[
        'Development Status :: 2 - Pre-Alpha',
        'License :: OSI Approved :: GNU General Public License v2 (GPLv2)',
        'Programming Language :: Python',
        'Programming Language :: Cython',
        'Programming Language :: C',
        'Programming Language :: Python :: 3',
        'Programming Language :: Python :: Implementation :: CPython',
        'Topic :: Scientific/Engineering'
      ]
)