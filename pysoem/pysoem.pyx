# Copyright 2018 Benjamin Partzsch
#
# This file is part of the PySOEM project and licenced under the
# GNU General Public License version 2. Check the license terms in the LICENSE
# file.
#
# PySOEM is a Cython wrapper for the Simple Open EtherCAT Master (SOEM) library
# (https://github.com/OpenEtherCATsociety/SOEM).
#
# EtherCAT is a registered trademark of Beckhoff Automation GmbH.
#
#
"""PySOEM is a Cython wrapper for the SOEM library."""

cimport cpysoem

import sys
import logging
import collections
import time

from cpython.mem cimport PyMem_Malloc, PyMem_Realloc, PyMem_Free
from cpython.bytes cimport PyBytes_FromString, PyBytes_FromStringAndSize
from libc.stdint cimport int8_t, int16_t, int32_t, int64_t, uint8_t, uint16_t, uint32_t, uint64_t    
from libc.string cimport memcpy


NONE_STATE = cpysoem.EC_STATE_NONE
INIT_STATE = cpysoem.EC_STATE_INIT
PREOP_STATE = cpysoem.EC_STATE_PRE_OP
BOOT_STATE = cpysoem.EC_STATE_BOOT
SAFEOP_STATE = cpysoem.EC_STATE_SAFE_OP
OP_STATE = cpysoem.EC_STATE_OPERATIONAL
STATE_ACK = cpysoem.EC_STATE_ACK
STATE_ERROR = cpysoem.EC_STATE_ERROR

def _get_version():
    with open('VERSION') as f:
        return f.read().strip()
        
__version__ = _get_version()


def find_adapters():
    """Create a list of available network adapters.
    
    Returns:
        list[Adapter]: Each element of the list has a name an desc attribute.
    
    """
    cdef cpysoem.ec_adaptert* _ec_adapter = cpysoem.ec_find_adapters()
    Adapter = collections.namedtuple('Adapter', ['name', 'desc'])
    adapters = []
    while not _ec_adapter == NULL:
        adapters.append(Adapter(_ec_adapter.name.decode('utf8'), _ec_adapter.desc.decode('utf8')))
        _ec_adapter = _ec_adapter.next
    return adapters
    
def al_status_code_to_string(code):
    """Look up text string that belongs to AL status code.
    
    This docstring bases on the comment for function ec_ALstatuscode2string
    in SOEM source code, see https://github.com/OpenEtherCATsociety/SOEM
    
    Args:
        arg1 (uint16): AL status code as defined in EtherCAT protocol.
    
    Returns:
        str: A verbal description of status code
    
    """
    return cpysoem.ec_ALstatuscode2string(code).decode('utf8');
    
    
class Master(CdefMaster):
    """Representing a logical EtherCAT master device.
    
    For each network interface you can have a Master instance.
    
    """
    pass
    
    
cdef class CdefMaster:
    """Representing a logical EtherCAT master device.
    
    Please do not use this class directly, but the class Master instead.
    Master is a typical Python object, with all it's benefits over
    cdef classes. For example you can add new attributes dynamically.
    
    """
    DEF EC_MAXSLAVE = 200
    DEF EC_MAXGROUP = 1
    DEF EC_MAXEEPBITMAP = 128
    DEF EC_MAXEEPBUF = EC_MAXEEPBITMAP * 32
    DEF EC_MAXMAPT = 8
    DEF EC_IOMAPSIZE = 4096
    
    cdef cpysoem.ec_slavet        _ec_slave[EC_MAXSLAVE]
    cdef int                      _ec_slavecount
    cdef cpysoem.ec_groupt        _ec_group[EC_MAXGROUP]
    cdef cpysoem.uint8            _ec_esibuf[EC_MAXEEPBUF]
    cdef cpysoem.uint32           _ec_esimap[EC_MAXEEPBITMAP]
    cdef cpysoem.ec_eringt        _ec_elist
    cdef cpysoem.ec_idxstackT     _ec_idxstack
    cdef cpysoem.ec_SMcommtypet   _ec_SMcommtype[EC_MAXMAPT]
    cdef cpysoem.ec_PDOassignt    _ec_PDOassign[EC_MAXMAPT]
    cdef cpysoem.ec_PDOdesct      _ec_PDOdesc[EC_MAXMAPT]
    cdef cpysoem.ec_eepromSMt     _ec_SM
    cdef cpysoem.ec_eepromFMMUt   _ec_FMMU
    cdef cpysoem.boolean          _EcatError
    cdef cpysoem.int64            _ec_DCtime
    cdef cpysoem.ecx_portt        _ecx_port
    cdef cpysoem.ecx_redportt     _ecx_redport

    cdef cpysoem.ecx_contextt _ecx_contextt
    cdef char io_map[EC_IOMAPSIZE]
    
    def __cinit__(self):
        self._ecx_contextt.port = &self._ecx_port
        self._ecx_contextt.slavelist = &self._ec_slave[0]
        self._ecx_contextt.slavecount = &self._ec_slavecount
        self._ecx_contextt.maxslave = EC_MAXSLAVE
        self._ecx_contextt.grouplist = &self._ec_group[0]
        self._ecx_contextt.maxgroup = EC_MAXGROUP
        self._ecx_contextt.esibuf = &self._ec_esibuf[0]
        self._ecx_contextt.esimap = &self._ec_esimap[0]
        self._ecx_contextt.esislave = 0
        self._ecx_contextt.elist = &self._ec_elist
        self._ecx_contextt.idxstack = &self._ec_idxstack
        self._EcatError = 0
        self._ecx_contextt.ecaterror = &self._EcatError
        self._ecx_contextt.DCtO = 0
        self._ecx_contextt.DCl = 0
        self._ecx_contextt.DCtime = &self._ec_DCtime
        self._ecx_contextt.SMcommtype = &self._ec_SMcommtype[0]
        self._ecx_contextt.PDOassign = &self._ec_PDOassign[0]
        self._ecx_contextt.PDOdesc = &self._ec_PDOdesc[0]
        self._ecx_contextt.eepSM = &self._ec_SM
        self._ecx_contextt.eepFMMU = &self._ec_FMMU
        self._ecx_contextt.FOEhook = NULL
        
        self.slaves = []
        
    def open(self, ifname):
        """Initialize and open network interface.
        
        Args:
            ifname(str): Interface name. (see find_adapters)
        
        Raises:
            ConnectionError: When the specified interface dose not exist or
                you have no permission to open the interface
        """
        ret_val = cpysoem.ecx_init(&self._ecx_contextt, ifname.encode('utf8'))
        if ret_val == 0:
            raise ConnectionError('could not open interface {}'.format(ifname))
        
    def config_init(self, usetable=False):
        """Enumerate and init all slaves.
        
        Args:
            usetable (bool): True when using configtable to init slaves, False otherwise
        
        Returns:
            int: Workcounter of slave discover datagram = number of slaves found, -1 when no slave is connected
        """
        ret_val = cpysoem.ecx_config_init(&self._ecx_contextt, usetable)
        if ret_val > 0:
          # santiy check
          assert(ret_val==self._ec_slavecount)        
          for i in range(self._ec_slavecount):
              self.slaves.append(self._get_slave(i))
        return ret_val
        
    def config_map(self):
        """Map all slaves PDOs in IO map.
        
        Returns:
            int: IO map size (sum of all PDO in an out data)
        """
        cdef _CallbackData cd
        # ecx_config_map_group returns the actual IO map size (not an error value), expect the value to be less than EC_IOMAPSIZE
        ret_val = cpysoem.ecx_config_map_group(&self._ecx_contextt, &self.io_map, 0)
        for slave in self.slaves:
            cd = slave._cd
            if cd.exc_raised:
                raise cd.exc_info[0],cd.exc_info[1],cd.exc_info[2]
        logging.debug('io map size: {}'.format(ret_val))
        # santiy check
        assert(ret_val<=EC_IOMAPSIZE)
        return ret_val
        
    def config_dc(self):
        """Locate DC slaves, measure propagation delays.
        
        Returns:
            bool: if slaves are found with DC
        """
        return cpysoem.ecx_configdc(&self._ecx_contextt)
        
    def close(self):
        """Close the network interface.
        
        """
        # ecx_close returns nothing
        cpysoem.ecx_close(&self._ecx_contextt)
        
    def read_state(self):
        """Read all slaves states.
        
        Returns:
            int: lowest state found
        """
        return cpysoem.ecx_readstate(&self._ecx_contextt)
        
    def write_state(self):
        """Write all slaves state
        
        The function does not check if the actual state is changed.
        
        Returns:
            int: Workcounter or EC_NOFRAME
        """
        return cpysoem.ecx_writestate(&self._ecx_contextt, 0)
        
    def state_check(self, int expected_state, timeout=50000):
        """Check actual slave state.
        
        This is a blocking function.
        To refresh the state of all slaves read_state() should be called
        
        Args:
            expected_state (int): Requested state
            timeout (int): Timeout value in us
        
        Returns:
            int: Requested state, or found state after timeout
        """
        return cpysoem.ecx_statecheck(&self._ecx_contextt, 0, expected_state, timeout)
        
    def send_processdata(self):
        """Transmit processdata to slaves.
        
        Uses LRW, or LRD/LWR if LRW is not allowed (blockLRW).
        Both the input and output processdata are transmitted.
        The outputs with the actual data, the inputs have a placeholder.
        The inputs are gathered with the receive processdata function.
        In contrast to the base LRW function this function is non-blocking.
        If the processdata does not fit in one datagram, multiple are used.
        In order to recombine the slave response, a stack is used.
        
        Returns:
            int: >0 if processdata is transmitted, might only by 0 if config map is not configured properly
        """
        return cpysoem.ecx_send_processdata(&self._ecx_contextt)
    
    def receive_processdata(self, timeout=2000):
        return cpysoem.ecx_receive_processdata(&self._ecx_contextt, timeout)
        
    def _get_slave(self, int pos):
        if pos < 0:
            raise IndexError('requested slave device is not available')
        if pos >= self._ec_slavecount:
            raise IndexError('requested slave device is not available')
        ethercat_slave = CdefSlave(pos+1)
        ethercat_slave._ecx_contextt = &self._ecx_contextt
        ethercat_slave._ec_slave = &self._ec_slave[pos+1] # +1 as _ec_slave[0] is reserved
        return ethercat_slave
        
    def _get_state(self):
        return self._ec_slave[0].state

    def _set_state(self, value):
        self._ec_slave[0].state = value

    state = property(_get_state, _set_state)
    
    def _get_expected_wkc(self):
        return (self._ec_group[0].outputsWKC * 2) + self._ec_group[0].inputsWKC
        
    expected_wkc  = property(_get_expected_wkc)
        
        
class SdoError(Exception):
    """Sdo read or write abort
    
    Attributes:
        abort_code (int): specified sdo abort code
        desc (str): error description
    """
    
    def __init__(self, abort_code, desc):
        self.abort_code = abort_code
        self.desc = desc
        
class EepromError(Exception):
    """EEPROM access error
    
    Attributes:
        message (str): error message
    """

    def __init__(self, message):
        self.message = message
    
cdef class _CallbackData:
    cdef:
        object func
        object exc_raised
        object exc_info
    
cdef class CdefSlave:
    """Represents a slave device

    Do not use this class in application code. Instances are created
    by a Master instance on a successful config_init(). They then can be 
    obtained by slaves list

    Attributes:
        pos(int): A integer specifying logical position in the network.
    """
    
    EC_TIMEOUTRXM = 700000
    STATIC_BUFFER_SIZE = 256
    
    cdef cpysoem.ecx_contextt* _ecx_contextt
    cdef cpysoem.ec_slavet* _ec_slave
    cdef _pos # keep in mind that first slave has pos 1  
    cdef public _CallbackData _cd 
    
    def __init__(self, pos):
        self._pos = pos
        self._cd = _CallbackData()

    def dc_sync(self, act, sync0_cycle_time, sync0_shift_time=0, sync1_cycle_time=None):
    
        if sync1_cycle_time is None:
            cpysoem.ecx_dcsync0(self._ecx_contextt, self._pos, act, sync0_cycle_time, sync0_shift_time)
        else:
            cpysoem.ecx_dcsync01(self._ecx_contextt, self._pos, act, sync0_cycle_time, sync1_cycle_time, sync0_shift_time) 

    def sdo_read(self, index, uint8_t subindex, int size, ca=False):
        if self._ecx_contextt == NULL:
            raise UnboundLocalError()
            
        cdef unsigned char* pbuf = <unsigned char*>PyMem_Malloc((size)*sizeof(unsigned char))
        cdef int size_clone = size
        
        if pbuf == NULL:
            raise MemoryError()
        
        cdef int result = cpysoem.ecx_SDOread(self._ecx_contextt, self._pos, index, subindex, ca, &size_clone, pbuf, self.EC_TIMEOUTRXM)
        
        cdef cpysoem.ec_errort err
        if cpysoem.ecx_poperror(self._ecx_contextt, &err):
            PyMem_Free(pbuf)
            assert(err.Slave == self._pos)
            assert(err.Index == index)
            assert(err.SubIdx == subindex)
            raise SdoError(err.AbortCode, cpysoem.ec_sdoerror2string(err.AbortCode).decode('utf8'))
        
        if not size_clone == size:
            PyMem_Free(pbuf)
            raise AssertionError('less bytes read than requested')            
        
        try:
            return PyBytes_FromStringAndSize(<char*>pbuf, size)
        finally:
            PyMem_Free(pbuf)
            
    def sdo_write(self, index, uint8_t subindex, bytes data, ca=False):
    
        assert(self._ecx_contextt != NULL)
            
        cdef int size = len(data)
        cdef int result = cpysoem.ecx_SDOwrite(self._ecx_contextt, self._pos, index, subindex, ca, size, <unsigned char*>data, self.EC_TIMEOUTRXM)
        
        cdef cpysoem.ec_errort err
        if cpysoem.ecx_poperror(self._ecx_contextt, &err):
            assert(err.Slave == self._pos)
            assert(err.Index == index)
            assert(err.SubIdx == subindex)
            raise SdoError(err.AbortCode, cpysoem.ec_sdoerror2string(err.AbortCode).decode('utf8'))
        
    def write_state(self):
        return cpysoem.ecx_writestate(self._ecx_contextt, self._pos)
        
    def state_check(self, int expected_state, timeout=2000):
        return cpysoem.ecx_statecheck(self._ecx_contextt, self._pos, expected_state, timeout)
        
    def reconfig(self, timeout=500):
        return cpysoem.ecx_reconfig_slave(self._ecx_contextt, self._pos, timeout)
        
    def recover(self, timeout=500):
        return cpysoem.ecx_recover_slave(self._ecx_contextt, self._pos, timeout)
        
    def eeprom_read(self, int word_address, timeout=20000):
        """Read 4 byte from EEPROM
        
        Args:
            word_address (int): EEPROM address to read from
            timeout (int): Timeout value in us
        
        Returns:
            bytes: EEPROM data
        """
        cdef uint32_t tmp = cpysoem.ecx_readeeprom(self._ecx_contextt, self._pos, word_address, timeout)
        return PyBytes_FromStringAndSize(<char*>&tmp, 4)
        
    def eeprom_write(self, int word_address, bytes data, timeout=20000):
        """Write 2 byte (1 word) to EEPROM
        
        Args:
            word_address (int): EEPROM address to write to
            data (bytes): data (only 2 bytes are allowed)
            timeout (int): Timeout value in us
        Raises:
            EepromError: if write fails
            AttributeError: if data size is not 2
        """
        if not len(data) == 2:
            raise AttributeError()
        cdef uint16_t tmp
        memcpy(<char*>&tmp, <unsigned char*>data, 2)
        cdef int result = cpysoem.ecx_writeeeprom(self._ecx_contextt, self._pos, word_address, tmp, timeout)
        if not result > 0:
            raise EepromError('EEPROM write error')
    
    def _get_name(self):
        return (<bytes>self._ec_slave.name).decode('utf8')
        
    name = property(_get_name)
    
    def _get_eep_man(self):
        return self._ec_slave.eep_man
        
    man = property(_get_eep_man)
    
    def _get_eep_id(self):
        return self._ec_slave.eep_id
        
    id = property(_get_eep_id)
    
    def _get_eep_rev(self):
        return self._ec_slave.eep_rev
        
    rev = property(_get_eep_rev)
        
    def _get_PO2SOconfig(self):
        return <object>self._ec_slave.user
    
    def _set_PO2SOconfig(self, value):
        self._cd.func = value
        self._ec_slave.user = <void*>self._cd
        if value is None:
            self._ec_slave.PO2SOconfig = NULL
        else:
            self._ec_slave.PO2SOconfig = _xPO2SOconfig
        
    def _get_input(self):
        return PyBytes_FromStringAndSize(<char*>self._ec_slave.inputs, self._ec_slave.Ibytes)

    input = property(_get_input)
    config_func = property(_get_PO2SOconfig, _set_PO2SOconfig)
    
    def _get_state(self):
        return self._ec_slave.state

    def _set_state(self, value):
        self._ec_slave.state = value

    state = property(_get_state, _set_state)
    
    def _get_output(self):
        return PyBytes_FromStringAndSize(<char*>self._ec_slave.outputs, self._ec_slave.Obytes)

    def _set_output(self, bytes value):
        memcpy(<char*>self._ec_slave.outputs, <char*>value, len(value))
        
    output = property(_get_output, _set_output)
    
    def _get_al_status(self):
        return self._ec_slave.ALstatuscode
       
    al_status = property(_get_al_status)
    
    def _get_is_lost(self):
        return self._ec_slave.islost

    def _set_is_lost(self, value):
        self._ec_slave.islost = value
    
    is_lost = property(_get_is_lost, _set_is_lost)
    

cdef int _xPO2SOconfig(cpysoem.uint16 slave, void* user):
    assert(slave>0)   
    cdef _CallbackData cd
    cd = <object>user
    cd.exc_raised = False
    try:
        (<object>cd.func)(slave-1)
    except:
        cd.exc_raised = True
        cd.exc_info=sys.exc_info()
