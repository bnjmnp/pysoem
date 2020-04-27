import sys
import os
import codecs
import re

from setuptools import setup, find_packages, Extension
from Cython.Build import cythonize


soem_sources = []
soem_inc_dirs = []

if sys.platform.startswith('win'):
    soem_macros = [('WIN32', ''), ('_CRT_SECURE_NO_WARNINGS', '')]
    soem_lib_dirs = [os.path.join('.', 'soem', 'oshw', 'win32', 'wpcap', 'Lib', 'x64')]
    soem_libs = ['wpcap', 'Packet', 'Ws2_32', 'Winmm']
    soem_inc_dirs.append(os.path.join('.', 'soem', 'oshw', 'win32', 'wpcap', 'Include'))
    os_name = 'win32'
elif sys.platform.startswith('linux'):
    soem_macros = []
    soem_lib_dirs = []
    soem_libs = ['pthread', 'rt'] 
    os_name = 'linux'

soem_macros.append(('EC_VER2', ''))

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

        
here = os.path.abspath(os.path.dirname(__file__))

def read(*parts):
    with codecs.open(os.path.join(here, *parts), 'r') as fp:
        return fp.read()

def find_version(*file_paths):
    version_file = read(*file_paths)
    version_match = re.search(r"^__version__ = ['\"]([^'\"]*)['\"]",
                              version_file, re.M)
    if version_match:
        return version_match.group(1)
    raise RuntimeError("Unable to find version string.")

    
setup(name='pysoem',
      version=find_version("pysoem", "__init__.py"),
      description='Cython wrapper for the SOEM Library',
      author='Benjamin Partzsch',
      author_email='benjamin_partzsch@web.de',
      url='https://github.com/bnjmnp/pysoem',
      license='GPLv2',
      long_description=readme(),
      ext_modules=cythonize([Extension('pysoem.pysoem',
                                       ['pysoem/pysoem.pyx'] + soem_sources,
                                       define_macros=soem_macros,
                                       libraries=soem_libs,
                                       library_dirs=soem_lib_dirs,
                                       include_dirs=['./pysoem'] + soem_inc_dirs)]),
      packages=['pysoem'],
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