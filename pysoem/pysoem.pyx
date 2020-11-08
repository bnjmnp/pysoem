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

cpdef enum ec_datatype:
    ECT_BOOLEAN         = 0x0001,
    ECT_INTEGER8        = 0x0002,
    ECT_INTEGER16       = 0x0003,
    ECT_INTEGER32       = 0x0004,
    ECT_UNSIGNED8       = 0x0005,
    ECT_UNSIGNED16      = 0x0006,
    ECT_UNSIGNED32      = 0x0007,
    ECT_REAL32          = 0x0008,
    ECT_VISIBLE_STRING  = 0x0009,
    ECT_OCTET_STRING    = 0x000A,
    ECT_UNICODE_STRING  = 0x000B,
    ECT_TIME_OF_DAY     = 0x000C,
    ECT_TIME_DIFFERENCE = 0x000D,
    ECT_DOMAIN          = 0x000F,
    ECT_INTEGER24       = 0x0010,
    ECT_REAL64          = 0x0011,
    ECT_INTEGER64       = 0x0015,
    ECT_UNSIGNED24      = 0x0016,
    ECT_UNSIGNED64      = 0x001B,
    ECT_BIT1            = 0x0030,
    ECT_BIT2            = 0x0031,
    ECT_BIT3            = 0x0032,
    ECT_BIT4            = 0x0033,
    ECT_BIT5            = 0x0034,
    ECT_BIT6            = 0x0035,
    ECT_BIT7            = 0x0036,
    ECT_BIT8            = 0x0037

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
        self._ecx_contextt.DCtime = &self._ec_DCtime
        self._ecx_contextt.SMcommtype = &self._ec_SMcommtype[0]
        self._ecx_contextt.PDOassign = &self._ec_PDOassign[0]
        self._ecx_contextt.PDOdesc = &self._ec_PDOdesc[0]
        self._ecx_contextt.eepSM = &self._ec_SM
        self._ecx_contextt.eepFMMU = &self._ec_FMMU
        self._ecx_contextt.FOEhook = NULL
        self._ecx_contextt.manualstatechange = 0
        
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
          # sanity check
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
        # check for exceptions raised in the config functions
        for slave in self.slaves:
            cd = slave._cd
            if cd.exc_raised:
                raise cd.exc_info[0],cd.exc_info[1],cd.exc_info[2]
        logging.debug('io map size: {}'.format(ret_val))
        # sanity check
        assert(ret_val<=EC_IOMAPSIZE)
        # raise an exception if one or more mailbox errors occured within ecx_config_map_group call
        error_list = self._collect_mailbox_errors()
        if len(error_list) > 0:
            raise ConfigMapError(error_list)
        return ret_val
        
    def config_overlap_map(self):
        """Map all slaves PDOs to overlapping IO map.
        
        Returns:
            int: IO map size (sum of all PDO in an out data)
        """
        cdef _CallbackData cd
        # ecx_config_map_group returns the actual IO map size (not an error value), expect the value to be less than EC_IOMAPSIZE
        ret_val = cpysoem.ecx_config_overlap_map_group(&self._ecx_contextt, &self.io_map, 0)
        # check for exceptions raised in the config functions
        for slave in self.slaves:
            cd = slave._cd
            if cd.exc_raised:
                raise cd.exc_info[0],cd.exc_info[1],cd.exc_info[2]
        logging.debug('io map size: {}'.format(ret_val))
        # sanity check
        assert(ret_val<=EC_IOMAPSIZE)
        # raise an exception if one or more mailbox errors occured within ecx_config_overlap_map_group call
        error_list = self._collect_mailbox_errors()
        if len(error_list) > 0:
            raise ConfigMapError(error_list)

        return ret_val

    def _collect_mailbox_errors(self):
        # collect SDO or mailbox errors that occurred during PDO configuration read in ecx_config_map_group
        error_list = []
        cdef cpysoem.ec_errort err
        while cpysoem.ecx_poperror(&self._ecx_contextt, &err):
            if err.Etype == cpysoem.EC_ERR_TYPE_SDO_ERROR:
                error_list.append(SdoError(err.Slave,
                                           err.Index,
                                           err.SubIdx,
                                           err.AbortCode, cpysoem.ec_sdoerror2string(err.AbortCode).decode('utf8')))
            elif err.Etype == cpysoem.EC_ERR_TYPE_MBX_ERROR:
                error_list.append(MailboxError(err.Slave,
                                               err.ErrorCode,
                                               cpysoem.ec_mbxerror2string(err.ErrorCode).decode('utf8')))
            elif err.Etype == cpysoem.EC_ERR_TYPE_PACKET_ERROR:
                error_list.append(PacketError(err.Slave,
                                              err.ErrorCode))
            else:
                error_list.append(Exception('unexpected error'))
        return error_list
        
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

    def send_overlap_processdata(self):
        """Transmit overlap processdata to slaves.
        
        Returns:
            int: >0 if processdata is transmitted, might only by 0 if config map is not configured properly
        """
        return cpysoem.ecx_send_overlap_processdata(&self._ecx_contextt)
    
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
    
    def _get_dc_time(self):
        return self._ec_DCtime
        
    dc_time = property(_get_dc_time)
        
        
class SdoError(Exception):
    """Sdo read or write abort
    
    Attributes:
        slave_pos (int): position of the slave
        abort_code (int): specified sdo abort code
        desc (str): error description
    """
    
    def __init__(self, slave_pos, index, subindex, abort_code, desc):
        self.slave_pos = slave_pos
        self.index = index
        self.subindex = subindex
        self.abort_code = abort_code
        self.desc = desc


class SdoInfoError(Exception):
    """Errors during Object directory info read
    
    Attributes:
        message (str): error message
    """

    def __init__(self, message):
        self.message = message


class MailboxError(Exception):
    """Errors in mailbox communication
    
    Attributes:
        slave_pos (int): position of the slave
        error_code (int): error code
        desc (str): error description
    """

    def __init__(self, slave_pos, error_code, desc):
        self.slave_pos = slave_pos
        self.error_code = error_code
        self.desc = desc


class PacketError(Exception):
    """Errors related to mailbox communication 
    
    Attributes:
        slave_pos (int): position of the slave
        error_code (int): error code
        message (str): error message
        desc (str): error description
    """

    # based on the comments in the soem code
    _code_desc = {
      1: 'Unexpected frame returned',
      3: 'Data container too small for type',
    }
    
    def __init__(self, slave_pos, error_code):
        self.slave_pos = slave_pos
        self.error_code = error_code
        
    def _get_desc(self):
        return self._code_desc[self.error_code]
        
    desc = property(_get_desc)


class ConfigMapError(Exception):
    """Errors during Object directory info read
    
    Attributes:
        error_list (str): a list of exceptions of type MailboxError or SdoError
    """

    def __init__(self, error_list):
        self.error_list = error_list


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
    DEF STATIC_SDO_READ_BUFFER_SIZE = 256
    
    cdef cpysoem.ecx_contextt* _ecx_contextt
    cdef cpysoem.ec_slavet* _ec_slave
    cdef _pos # keep in mind that first slave has pos 1  
    cdef public _CallbackData _cd
    cdef cpysoem.ec_ODlistt _ex_odlist
    
    def __init__(self, pos):
        self._pos = pos
        self._cd = _CallbackData()

    def dc_sync(self, act, sync0_cycle_time, sync0_shift_time=0, sync1_cycle_time=None):
    
        if sync1_cycle_time is None:
            cpysoem.ecx_dcsync0(self._ecx_contextt, self._pos, act, sync0_cycle_time, sync0_shift_time)
        else:
            cpysoem.ecx_dcsync01(self._ecx_contextt, self._pos, act, sync0_cycle_time, sync1_cycle_time, sync0_shift_time) 

    def sdo_read(self, index, uint8_t subindex, int size=0, ca=False):
        if self._ecx_contextt == NULL:
            raise UnboundLocalError()
        
        cdef unsigned char* pbuf
        cdef uint8_t std_buffer[STATIC_SDO_READ_BUFFER_SIZE]
        cdef int size_inout
        if size == 0:
            pbuf = std_buffer
            size_inout = STATIC_SDO_READ_BUFFER_SIZE
        else:
            pbuf = <unsigned char*>PyMem_Malloc((size)*sizeof(unsigned char))
            size_inout = size
        
        if pbuf == NULL:
            raise MemoryError()
        
        cdef int result = cpysoem.ecx_SDOread(self._ecx_contextt, self._pos, index, subindex, ca, &size_inout, pbuf, self.EC_TIMEOUTRXM)
        
        cdef cpysoem.ec_errort err
        if cpysoem.ecx_poperror(self._ecx_contextt, &err):
            if pbuf != std_buffer:
                PyMem_Free(pbuf)
            assert err.Slave == self._pos
            self._raise_exception(&err)

        try:
            return PyBytes_FromStringAndSize(<char*>pbuf, size_inout)
        finally:
            if pbuf != std_buffer:
                PyMem_Free(pbuf)
            
    def sdo_write(self, index, uint8_t subindex, bytes data, ca=False):            
        cdef int size = len(data)
        cdef int result = cpysoem.ecx_SDOwrite(self._ecx_contextt, self._pos, index, subindex, ca, size, <unsigned char*>data, self.EC_TIMEOUTRXM)
        
        cdef cpysoem.ec_errort err
        if cpysoem.ecx_poperror(self._ecx_contextt, &err):
            self._raise_exception(&err)
        
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

    def foe_write(self, filename, int password, bytes data, timeout = 200000):
        """ Write given data to device using FoE

        Args:
            filename (string): name of the target file
            password (int): password for target file
            psize (int): size of file
            data (bytes): data
            timeout (int): Timeout value in us
        """
        # error handling
        if self._ecx_contextt == NULL:
            raise UnboundLocalError()

        cdef int size = len(data)
        cdef int result = cpysoem.ecx_FOEwrite(self._ecx_contextt, self._pos, filename.encode('utf8'), password, size, <unsigned char*>data, timeout)
        
        # error handling
        cdef cpysoem.ec_errort err
        if cpysoem.ecx_poperror(self._ecx_contextt, &err):
            assert err.Slave == self._pos
            self._raise_exception(&err)

        return result

    def foe_read(self, filename, password, size, timeout = 200000):
        """ Read given filename from device using FoE

        Args:
            filename (string): name of the target file
            password (int): password for target file
            size (int): maximum file size
            timeout (int): Timeout value in us
        """
        if self._ecx_contextt == NULL:
            raise UnboundLocalError()

        # prepare call of c function
        cdef unsigned char* pbuf
        cdef int size_inout
        pbuf = <unsigned char*>PyMem_Malloc((size)*sizeof(unsigned char))
        size_inout = size

        cdef int result = cpysoem.ecx_FOEread(self._ecx_contextt, self._pos, filename.encode('utf8'), password, &size_inout, pbuf, timeout)

        # error handling
        cdef cpysoem.ec_errort err
        if cpysoem.ecx_poperror(self._ecx_contextt, &err):
            PyMem_Free(pbuf)
            assert err.Slave == self._pos
            self._raise_exception(&err)

        # return data
        try:
            return PyBytes_FromStringAndSize(<char*>pbuf, size_inout)
        finally:
            PyMem_Free(pbuf)

    cdef _raise_exception(self, cpysoem.ec_errort* err):
        if err.Etype == cpysoem.EC_ERR_TYPE_SDO_ERROR:
            raise SdoError(err.Slave,
                           err.Index,
                           err.SubIdx,
                           err.AbortCode,
                           cpysoem.ec_sdoerror2string(err.AbortCode).decode('utf8'))
        elif err.Etype == cpysoem.EC_ERR_TYPE_MBX_ERROR:
            raise MailboxError(err.Slave,
                               err.ErrorCode,
                               cpysoem.ec_mbxerror2string(err.ErrorCode).decode('utf8'))
        elif err.Etype == cpysoem.EC_ERR_TYPE_PACKET_ERROR:
            raise PacketError(err.Slave,
                              err.ErrorCode)
        else:
            raise Exception('unexpected error, Etype: {}'.format(err.Etype))
    
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
        num_bytes = self._ec_slave.Ibytes
        if (self._ec_slave.Ibytes == 0 and self._ec_slave.Ibits > 0):
            num_bytes = 1
        return PyBytes_FromStringAndSize(<char*>self._ec_slave.inputs, num_bytes)

    input = property(_get_input)
    config_func = property(_get_PO2SOconfig, _set_PO2SOconfig)

    def _get_state(self):
        return self._ec_slave.state

    def _set_state(self, value):
        self._ec_slave.state = value

    state = property(_get_state, _set_state)
    
    def _get_output(self):
        num_bytes = self._ec_slave.Obytes
        if (self._ec_slave.Obytes == 0 and self._ec_slave.Obits > 0):
            num_bytes = 1
        return PyBytes_FromStringAndSize(<char*>self._ec_slave.outputs, num_bytes)

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
    
    def _get_od(self):
        logging.debug('ecx_readODlist()')
        cdef int result = cpysoem.ecx_readODlist(self._ecx_contextt, self._pos, &self._ex_odlist)
        if not result > 0:
            raise SdoInfoError('Sdo List Info read failed')
        
        coe_objects = []
        for i in range(self._ex_odlist.Entries):
            coe_object = CdefCoeObject(i)
            coe_object._ecx_context = self._ecx_contextt
            coe_object._ex_odlist = &self._ex_odlist
            coe_objects.append(coe_object)
            
        return coe_objects
        
    od = property(_get_od)


cdef class CdefCoeObject:
    cdef cpysoem.ecx_contextt* _ecx_context
    cdef cpysoem.ec_ODlistt* _ex_odlist
    cdef int _item
    cdef cpysoem.boolean _is_description_read
    cdef cpysoem.boolean _are_entries_read
    cdef cpysoem.ec_OElistt _ex_oelist
    
    def __init__(self, int item):
        self._item = item
        self._is_description_read = False
        self._are_entries_read = False
        
    def _read_description(self):
        cdef int result
        if not self._is_description_read:
          logging.debug('ecx_readODdescription()')
          result = cpysoem.ecx_readODdescription(self._ecx_context, self._item, self._ex_odlist)
          if not result > 0:
              raise SdoInfoError('Sdo Object Info read failed')
          self._is_description_read = True
          
    def _read_entries(self):
        cdef int result
        if not self._are_entries_read:
            logging.debug('ecx_readOE()')
            result = cpysoem.ecx_readOE(self._ecx_context, self._item, self._ex_odlist, &self._ex_oelist)
            if not result > 0:
                raise SdoInfoError('Sdo ObjectEntry Info read failed')
            self._are_entries_read = True
            
    def _get_index(self):
        return self._ex_odlist.Index[self._item]
        
    index = property(_get_index)
    
    def _get_data_type(self):
        self._read_description()
        return self._ex_odlist.DataType[self._item]
        
    data_type = property(_get_data_type)
    
    def _get_object_code(self):
        self._read_description()
        return self._ex_odlist.ObjectCode[self._item]
        
    object_code = property(_get_object_code)
        
    def _get_name(self):
        self._read_description()
        return (<bytes>self._ex_odlist.Name[self._item]).decode('utf8')
        
    name = property(_get_name)
    
    def _get_entries(self):
        self._read_description()
        self._read_entries()
        
        if self._ex_odlist.MaxSub[self._item] == 0:
            return []
        else:
            entries = []
            for i in range(self._ex_odlist.MaxSub[self._item]+1):
                entry = CdefCoeObjectEntry(i)
                entry._ex_oelist = &self._ex_oelist
                entries.append(entry)
            return entries

    entries = property(_get_entries)
    
    def _get_bit_length(self):
        cdef int sum = 0
        self._read_description()
        self._read_entries()
        if self._ex_odlist.MaxSub[self._item] == 0:
            return self._ex_oelist.BitLength[0]
        else:
            for i in range(self._ex_odlist.MaxSub[self._item]+1):
                sum += self._ex_oelist.BitLength[i]
            return sum
            
    bit_length = property(_get_bit_length)
    
    def _get_obj_access(self):
        if self._ex_odlist.MaxSub[self._item] == 0:
            return self._ex_oelist.ObjAccess[0]
        else:
            return 0
    
    obj_access = property(_get_obj_access)
        

cdef class CdefCoeObjectEntry:
    cdef cpysoem.ec_OElistt* _ex_oelist
    cdef int _item
    
    def __init__(self, int item):
        self._item = item
        
    def _get_name(self):            
        return (<bytes>self._ex_oelist.Name[self._item]).decode('utf8')
        
    name = property(_get_name)

    def _get_data_type(self):
        return self._ex_oelist.DataType[self._item]
        
    data_type = property(_get_data_type)
    
    def _get_bit_length(self):
        return self._ex_oelist.BitLength[self._item]
    
    bit_length = property(_get_bit_length)
    
    def _get_obj_access(self):
        return self._ex_oelist.ObjAccess[self._item]
    
    obj_access = property(_get_obj_access)
        

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
