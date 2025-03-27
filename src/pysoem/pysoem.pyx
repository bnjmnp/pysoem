# Copyright 2021 Benjamin Partzsch
#
# This file is part of the PySOEM project and licenced under the MIT license.
# Check the license terms in the LICENSE file.
#
# PySOEM is a Cython wrapper for the Simple Open EtherCAT Master (SOEM) library
# (https://github.com/OpenEtherCATsociety/SOEM).
#
# EtherCAT is a registered trademark of Beckhoff Automation GmbH.
#
#
"""PySOEM is a Cython wrapper for the SOEM library."""

#
# This will result in the creation of the `pysoem.pysoem` module.
#

cimport cpysoem

import sys
import logging
import collections
import time
import contextlib
import warnings

from cpython.mem cimport PyMem_Malloc, PyMem_Realloc, PyMem_Free
from cpython.bytes cimport PyBytes_FromString, PyBytes_FromStringAndSize
from libc.stdint cimport int8_t, int16_t, int32_t, int64_t, uint8_t, uint16_t, uint32_t, uint64_t
from libc.string cimport memcpy, memset
from socket import ntohs, ntohl

logger = logging.getLogger(__name__)

NONE_STATE = cpysoem.EC_STATE_NONE
INIT_STATE = cpysoem.EC_STATE_INIT
PREOP_STATE = cpysoem.EC_STATE_PRE_OP
BOOT_STATE = cpysoem.EC_STATE_BOOT
SAFEOP_STATE = cpysoem.EC_STATE_SAFE_OP
OP_STATE = cpysoem.EC_STATE_OPERATIONAL
STATE_ACK = cpysoem.EC_STATE_ACK
STATE_ERROR = cpysoem.EC_STATE_ERROR

ECT_REG_WD_DIV = 0x0400
ECT_REG_WD_TIME_PDI = 0x0410
ECT_REG_WD_TIME_PROCESSDATA = 0x0420
ECT_REG_SM0 = 0x0800
ECT_REG_SM1 = ECT_REG_SM0 + 0x08

ECT_COEDET_SDO       = 0x01
ECT_COEDET_SDOINFO   = 0x02
ECT_COEDET_PDOASSIGN = 0x04
ECT_COEDET_PDOCONFIG = 0x08
ECT_COEDET_UPLOAD    = 0x10
ECT_COEDET_SDOCA     = 0x20

cdef class CdefTimeouts:

    cdef cpysoem.Ttimeouts* _t

    def __cinit__(self):
        self._t = &cpysoem.soem_timeouts

    @property
    def ret(self) -> int:
        return self._t.ret

    @ret.setter
    def ret(self, value: int):
        self._t.ret = value

    @property
    def safe(self) -> int:
        return self._t.safe

    @safe.setter
    def safe(self, value: int):
        self._t.safe = value

    @property
    def eeprom(self) -> int:
        return self._t.eeprom

    @eeprom.setter
    def eeprom(self, value: int):
        self._t.eeprom = value

    @property
    def tx_mailbox(self) -> int:
        return self._t.tx_mailbox

    @tx_mailbox.setter
    def tx_mailbox(self, value: int):
        self._t.tx_mailbox = value

    @property
    def rx_mailbox(self) -> int:
        return self._t.rx_mailbox

    @rx_mailbox.setter
    def rx_mailbox(self, value: int):
        self._t.rx_mailbox = value

    @property
    def state(self) -> int:
        return self._t.state

    @state.setter
    def state(self, value: int):
        self._t.state = value

cdef class CdefSettings:

    cdef public CdefTimeouts timeouts

    def __init__(self):
        self.timeouts = CdefTimeouts()

settings = CdefSettings()

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

cdef struct CdefMasterSettings:
    int* sdo_read_timeout
    int* sdo_write_timeout

def find_adapters():
    """Create a list of available network adapters.

    Returns:
        list[Adapter]: Each element of the list has a name an desc attribute.

    """
    cdef cpysoem.ec_adaptert* _ec_adapter = cpysoem.ec_find_adapters()
    Adapter = collections.namedtuple('Adapter', ['name', 'desc'])
    adapters = []
    while not _ec_adapter == NULL:
        adapters.append(Adapter(_ec_adapter.name.decode('utf8'), _ec_adapter.desc))
        _ec_adapter = _ec_adapter.next
    return adapters


@contextlib.contextmanager
def open(ifname):
    """Context manager function to create a Master object.

    .. versionadded:: 1.1.0
    """
    master = Master()
    master.open(ifname)
    yield master
    master.close()


def al_status_code_to_string(code):
    """Look up text string that belongs to AL status code.
    
    Args:
        arg1 (uint16): AL status code as defined in EtherCAT protocol.
    
    Returns:
        str: A verbal description of status code
    
    """
    return cpysoem.ec_ALstatuscode2string(code).decode('utf8');


ctypedef struct _contextt_and_master:
    # Sneaky struct to allow getting a reference to the CdefMaster object from an ecx_contextt pointer
    cpysoem.ecx_contextt ecx_contextt
    void *master

class Master(CdefMaster):
    """Representing a logical EtherCAT master device.

    For each network interface you can have a Master instance.

    Attributes:
        slaves: Gets a list of the slaves found during config_init. The slave instances are of type :class:`CdefSlave`.
        sdo_read_timeout: timeout for SDO read access for all slaves connected
        sdo_write_timeout: timeout for SDO write access for all slaves connected
    """
    pass


cdef enum:
    EC_MAXSLAVE = 200
    EC_MAXGROUP = 1
    EC_MAXEEPBITMAP = 128
    EC_MAXEEPBUF = EC_MAXEEPBITMAP * 32
    EC_MAXMAPT = 8
    EC_IOMAPSIZE = 4096

cdef class CdefMaster:
    """Representing a logical EtherCAT master device.
    
    Please do not use this class directly, but the class Master instead.
    Master is a typical Python object, with all it's benefits over
    cdef classes. For example you can add new attributes dynamically.
    """

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

    cdef _contextt_and_master _ecx__contextt_and_master
    cdef cpysoem.ecx_contextt *_ecx_contextt
    cdef char io_map[EC_IOMAPSIZE]
    cdef CdefMasterSettings _settings
    cdef public int sdo_read_timeout
    cdef public int sdo_write_timeout
    cdef readonly cpysoem.boolean context_initialized

    state = property(_get_state, _set_state)
    expected_wkc  = property(_get_expected_wkc)
    dc_time = property(_get_dc_time)
    manual_state_change = property(_get_manual_state_change, _set_manual_state_change)

    def __cinit__(self):
        self._ecx__contextt_and_master.master = <void*>self
        self._ecx_contextt = &self._ecx__contextt_and_master.ecx_contextt

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
        self._ecx_contextt.EOEhook = NULL
        self._ecx_contextt.manualstatechange = 0
        
        self.slaves = None
        self.sdo_read_timeout = 700000
        self.sdo_write_timeout = 700000
        self._settings.sdo_read_timeout = &self.sdo_read_timeout
        self._settings.sdo_write_timeout = &self.sdo_write_timeout
        self.context_initialized = False
        
    def open(self, ifname, ifname_red=None):
        """Initialize and open network interface.

        On Linux the name of the interface is the same as usd by the system, e.g. ``eth0``, and as displayed by
        ``ip addr``.

        On Windows the names of the interfaces look like ``\\Device\\NPF_{1D123456-1E12-1C12-12F1-1234E123453B}``.
        Finding the kind of name that SOEM expects is not straightforward. The most practical way is to use the
        :func:`~find_adapters` method to find your available interfaces.

        Args:
            ifname(str): Interface name.
            ifname_red(:obj:`str`, optional): Interface name of the second network interface card for redundancy.
                Put to None if not used.
        
        Raises:
            ConnectionError: When the specified interface dose not exist or
                you have no permission to open the interface
        """
        if ifname_red is None:
            ret_val = cpysoem.ecx_init(self._ecx_contextt, ifname.encode('utf8'))
        else:
            ret_val = cpysoem.ecx_init_redundant(self._ecx_contextt, &self._ecx_redport, ifname.encode('utf8'), ifname_red.encode('utf8'))
        if ret_val == 0:
            raise ConnectionError('could not open interface {}'.format(ifname))

        self.context_initialized = True

    def check_context_is_initialized(self):
        if not self.context_initialized:
            raise NetworkInterfaceNotOpenError("SOEM Network interface is not initialized or has been closed. Call Master.open() first")

        
    def config_init(self, usetable=False):
        """Enumerate and init all slaves.
        
        Args:
            usetable (bool): True when using configtable to init slaves, False otherwise
        
        Returns:
            int: Working counter of slave discover datagram = number of slaves found, -1 when no slave is connected
        """
        self.check_context_is_initialized()
        self.slaves = []
        ret_val = cpysoem.ecx_config_init(self._ecx_contextt, usetable)
        if ret_val > 0:
          for i in range(self._ec_slavecount):
              self.slaves.append(self._get_slave(i))
        return ret_val
        
    def config_map(self):
        """Map all slaves PDOs in IO map.
        
        Returns:
            int: IO map size (sum of all PDO in an out data)
        """
        self.check_context_is_initialized()
        cdef _CallbackData cd
        # ecx_config_map_group returns the actual IO map size (not an error value), expect the value to be less than EC_IOMAPSIZE
        ret_val = cpysoem.ecx_config_map_group(self._ecx_contextt, &self.io_map, 0)
        # check for exceptions raised in the config functions
        for slave in self.slaves:
            cd = slave._cd
            if cd.exc_raised:
                raise cd.exc_info[0], cd.exc_info[1], cd.exc_info[2]
        logger.debug('io map size: {}'.format(ret_val))
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
        self.check_context_is_initialized()
        cdef _CallbackData cd
        # ecx_config_map_group returns the actual IO map size (not an error value), expect the value to be less than EC_IOMAPSIZE
        ret_val = cpysoem.ecx_config_overlap_map_group(self._ecx_contextt, &self.io_map, 0)
        # check for exceptions raised in the config functions
        for slave in self.slaves:
            cd = slave._cd
            if cd.exc_raised:
                raise cd.exc_info[0],cd.exc_info[1],cd.exc_info[2]
        logger.debug('io map size: {}'.format(ret_val))
        # raise an exception if one or more mailbox errors occured within ecx_config_overlap_map_group call
        error_list = self._collect_mailbox_errors()
        if len(error_list) > 0:
            raise ConfigMapError(error_list)

        return ret_val

    def _collect_mailbox_errors(self):
        # collect SDO or mailbox errors that occurred during PDO configuration read in ecx_config_map_group
        error_list = []
        cdef cpysoem.ec_errort err
        while cpysoem.ecx_poperror(self._ecx_contextt, &err):
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
        self.check_context_is_initialized()
        return cpysoem.ecx_configdc(self._ecx_contextt)
        
    def close(self):
        """Close the network interface.
        
        """
        # ecx_close returns nothing
        self.context_initialized = False
        cpysoem.ecx_close(self._ecx_contextt)

    def read_state(self):
        """Read all slaves states.
        
        Returns:
            int: lowest state found
        """
        self.check_context_is_initialized()
        return cpysoem.ecx_readstate(self._ecx_contextt)
        
    def write_state(self):
        """Write all slaves state.
        
        The function does not check if the actual state is changed.
        
        Returns:
            int: Working counter or EC_NOFRAME
        """
        self.check_context_is_initialized()
        return cpysoem.ecx_writestate(self._ecx_contextt, 0)
        
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
        self.check_context_is_initialized()
        return cpysoem.ecx_statecheck(self._ecx_contextt, 0, expected_state, timeout)
        
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
        self.check_context_is_initialized()
        return cpysoem.ecx_send_processdata(self._ecx_contextt)

    def send_overlap_processdata(self):
        """Transmit overlap processdata to slaves.
        
        Returns:
            int: >0 if processdata is transmitted, might only by 0 if config map is not configured properly
        """
        self.check_context_is_initialized()
        return cpysoem.ecx_send_overlap_processdata(self._ecx_contextt)
    
    def receive_processdata(self, timeout=2000):
        """Receive processdata from slaves.

        Second part from send_processdata().
        Received datagrams are recombined with the processdata with help from the stack.
        If a datagram contains input processdata it copies it to the processdata structure.

        Args:
            timeout (int): Timeout in us.
        Returns
            int: Working Counter
        """
        self.check_context_is_initialized()
        return cpysoem.ecx_receive_processdata(self._ecx_contextt, timeout)
    
    def _get_slave(self, int pos):
        if pos < 0:
            raise IndexError('requested slave device is not available')
        if pos >= self._ec_slavecount:
            raise IndexError('requested slave device is not available')
        ethercat_slave = CdefSlave(pos+1)
        ethercat_slave._master = self
        ethercat_slave._ecx_contextt = self._ecx_contextt
        ethercat_slave._ec_slave = &self._ec_slave[pos+1] # +1 as _ec_slave[0] is reserved
        ethercat_slave._the_masters_settings = &self._settings
        return ethercat_slave
        
    def _get_state(self):
        """Can be used to check if all slaves are in Operational state, or to request a new state for all slaves.

        Make sure to call write_state(), once a new state for all slaves was set.
        """
        return self._ec_slave[0].state

    def _set_state(self, value):
        self._ec_slave[0].state = value
    
    def _get_expected_wkc(self):
        """Calculates the expected Working Counter"""
        return (self._ec_group[0].outputsWKC * 2) + self._ec_group[0].inputsWKC
    
    def _get_dc_time(self):
        """DC time in ns required to synchronize the EtherCAT cycle with SYNC0 cycles.

        Note EtherCAT cycle here means the call of send_processdata and receive_processdata."""
        return self._ec_DCtime
    
    def _set_manual_state_change(self, int manual_state_change):
        """Set manualstatechange variable in context.
        
        Flag to control legacy automatic state change or manual state change in functions
        config_init() and config_map()
        Flag value == 0 is legacy automatic state
        Flag value != 0 and states must be handled manually
        Args:
            manual_state_change (int): The manual state change flag.

        .. versionadded:: 1.0.5
        """
        self._ecx_contextt.manualstatechange = manual_state_change

    def _get_manual_state_change(self):        
        return self._ecx_contextt.manualstatechange

    def set_eoe_callback(self, callback):
        """Sets the callback for when EOE data is recieved.

        Args:
            callback: Callable with arguments (bytes eoe_packet, int slave)
        """
        if callback is None:
            cpysoem.ecx_EOEdefinehook(self._ecx_contextt, NULL)
            self._eoe_callback = None
        else:
            cpysoem.ecx_EOEdefinehook(self._ecx_contextt, &_eoe_hook)
            self._eoe_callback = callback
        
        
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

class Emergency(Exception):
    """Emergency message.

    Attributes:
        slave_pos (int): position of the slave
        error_code (int): error code
        error_reg (int): error register
        b1 (int): data byte [0]
        w1 (int): data bytes [1,2]
        w2 (int): data bytes [3,4]
    """

    def __init__(self, slave_pos, error_code, error_reg, b1, w1, w2):
        self.slave_pos = slave_pos
        self.error_code = error_code
        self.error_reg = error_reg
        self.b1 = b1
        self.w1 = w1
        self.w2 = w2

    def __str__(self):
        b1w1w2_bytes = bytes([self.b1]) + self.w1.to_bytes(length=2, byteorder='little') + self.w2.to_bytes(length=2, byteorder='little')
        b1w1w2_str = ','.join(format(x, '02x') for x in b1w1w2_bytes)
        return f'Slave {self.slave_pos}:  {self.error_code:04x}, {self.error_reg:02x}, ({b1w1w2_str})'


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


class WkcError(Exception):
    """Working counter error.

    Attributes:
        message (str): error message
        wkc (int): Working counter
    """

    def __init__(self, message=None, wkc=None):
        self.message = message
        self.wkc = wkc

class NetworkInterfaceNotOpenError(Exception):
    """Error when a master or slave method is used and the context has not been initialized."""
    pass

class EoeInvalidRxDataError(Exception):
    """Error when recieved EOE data is invalid"""
    pass

cdef class _CallbackData:
    cdef:
        object slave
        object func
        object exc_raised
        object exc_info


class SiiOffset:
    """Item offsets in SII general section."""
    # Took it from ethercattype.h but no type was given.
    MAN = 0x0008
    ID = 0x000A
    REV = 0x000B
    BOOT_RX_MBX = 0x0014
    BOOT_TX_MBX = 0x0016
    STD_RX_MBX = 0x0018
    STD_TX_MBX = 0x001A
    MBX_PROTO = 0x001C


cdef enum:
    EC_TIMEOUTRXM = 700000
    STATIC_SDO_READ_BUFFER_SIZE = 256

ctypedef struct _eoe_rx_data:
    uint8_t _rxfragmentno
    uint16_t _rxframesize
    uint16_t _rxframeoffset
    uint16_t _rxframeno
    uint8_t _rxbuf[1500] # TODO: Make MTU configurable?
    int _size_of_rx


cdef class CdefSlave:
    """Represents a slave device

    Do not use this class in application code. Instances are created
    by a Master instance on a successful config_init(). They then can be 
    obtained by slaves list
    """
    cdef readonly CdefMaster _master
    cdef cpysoem.ecx_contextt* _ecx_contextt
    cdef cpysoem.ec_slavet* _ec_slave
    cdef CdefMasterSettings* _the_masters_settings
    cdef _pos # keep in mind that first slave has pos 1  
    cdef public _CallbackData _cd
    cdef cpysoem.ec_ODlistt _ex_odlist
    cdef public _emcy_callbacks
    cdef _eoe_rx_data _eoe_rx_info

    name = property(_get_name)
    man = property(_get_eep_man)
    id = property(_get_eep_id)
    rev = property(_get_eep_rev)
    config_func = property(_get_PO2SOconfig, _set_PO2SOconfig)
    setup_func = property(_get_PO2SOconfigEx, _set_PO2SOconfigEx)
    state = property(_get_state, _set_state)
    input = property(_get_input)
    output = property(_get_output, _set_output)
    al_status = property(_get_al_status)
    is_lost = property(_get_is_lost, _set_is_lost)
    od = property(_get_od)

    def __init__(self, pos):
        self._pos = pos
        self._cd = _CallbackData()
        self._cd.slave = self
        self._emcy_callbacks = []

    def dc_sync(self, act, sync0_cycle_time, sync0_shift_time=0, sync1_cycle_time=None):
        """Activate or deactivate SYNC pulses at the slave.

         Args:
            act (bool): True = active, False = deactivate
            sync0_cycle_time (int): Cycltime SYNC0 in ns
            sync0_shift_time (int): Optional SYNC0 shift time in ns
            sync1_cycle_time (int): Optional cycltime for SYNC1 in ns. This time is a delta time in relation to SYNC0.
                                    If CylcTime1 = 0 then SYNC1 fires at the same time as SYNC0.
        """
        self._master.check_context_is_initialized()
    
        if sync1_cycle_time is None:
            cpysoem.ecx_dcsync0(self._ecx_contextt, self._pos, act, sync0_cycle_time, sync0_shift_time)
        else:
            cpysoem.ecx_dcsync01(self._ecx_contextt, self._pos, act, sync0_cycle_time, sync1_cycle_time, sync0_shift_time) 

    def sdo_read(self, index, uint8_t subindex, int size=0, ca=False):
        """Read a CoE object.

        When leaving out the size parameter, objects up to 256 bytes can be read.
        If the size of the object is expected to be bigger, increase the size parameter.

        Args:
            index (int): Index of the object.
            subindex (int): Subindex of the object.
            size (:obj:`int`, optional): The size of the reading buffer.
            ca (:obj:`bool`, optional): complete access

        Returns:
            bytes: The content of the sdo object.

        Raises:
            SdoError: if write fails, the exception includes the SDO abort code  
            MailboxError: on errors in the mailbox protocol
            PacketError: on packet level error
            WkcError: if working counter is not higher than 0, the exception includes the working counter
        """
        if self._ecx_contextt == NULL:
            raise UnboundLocalError()

        self._master.check_context_is_initialized()
        
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
        
        cdef int result = cpysoem.ecx_SDOread(self._ecx_contextt, self._pos, index, subindex, ca,
                                              &size_inout, pbuf, self._the_masters_settings.sdo_read_timeout[0])

        cdef cpysoem.ec_errort err
        while cpysoem.ecx_poperror(self._ecx_contextt, &err):
            assert err.Slave == self._pos

            if (err.Etype == cpysoem.EC_ERR_TYPE_EMERGENCY) and (len(self._emcy_callbacks) > 0):
                self._on_emergency(&err)
            else:
                if pbuf != std_buffer:
                    PyMem_Free(pbuf)
                self._raise_exception(&err)

        if not result > 0:
            if pbuf != std_buffer:
                    PyMem_Free(pbuf)
            raise WkcError(wkc=result)

        try:
            return PyBytes_FromStringAndSize(<char*>pbuf, size_inout)
        finally:
            if pbuf != std_buffer:
                PyMem_Free(pbuf)
            
    def sdo_write(self, index, uint8_t subindex, bytes data, ca=False):
        """Write to a CoE object.
        
        Args:
            index (int): Index of the object.
            subindex (int): Subindex of the object.
            data (bytes): data to be written to the object
            ca (:obj:`bool`, optional): complete access

        Raises:
            SdoError: if write fails, the exception includes the SDO abort code  
            MailboxError: on errors in the mailbox protocol
            PacketError: on packet level error
            WkcError: if working counter is not higher than 0, the exception includes the working counter
        """          
        self._master.check_context_is_initialized()

        cdef int size = len(data)
        cdef int result = cpysoem.ecx_SDOwrite(self._ecx_contextt, self._pos, index, subindex, ca,
                                               size, <unsigned char*>data, self._the_masters_settings.sdo_write_timeout[0])
        
        cdef cpysoem.ec_errort err
        while(cpysoem.ecx_poperror(self._ecx_contextt, &err)):
            if (err.Etype == cpysoem.EC_ERR_TYPE_EMERGENCY) and (len(self._emcy_callbacks) > 0):
                self._on_emergency(&err)
            else:
                self._raise_exception(&err)

        if not result > 0:
            raise WkcError(wkc=result)

    def mbx_receive(self):
        """Read out the slaves out mailbox - to check for emergency messages.

        .. versionadded:: 1.0.4

        :return: Work counter
        :rtype: int
        :raises Emergency: if an emergency message was received
        """
        self._master.check_context_is_initialized()

        cdef cpysoem.ec_mbxbuft buf
        cpysoem.ec_clearmbx(&buf)
        cdef int wkt = cpysoem.ecx_mbxreceive(self._ecx_contextt, self._pos, &buf, 0)

        cdef cpysoem.ec_errort err
        if cpysoem.ecx_poperror(self._ecx_contextt, &err):
            if (err.Etype == cpysoem.EC_ERR_TYPE_EMERGENCY) and (len(self._emcy_callbacks) > 0):
                self._on_emergency(&err)
            else:
                self._raise_exception(&err)

        return wkt
        
    def write_state(self):
        """Write slave state.

        Note: The function does not check if the actual state is changed.
        """
        self._master.check_context_is_initialized()
        return cpysoem.ecx_writestate(self._ecx_contextt, self._pos)
        
    def state_check(self, int expected_state, timeout=2000):
        """Wait for the slave to reach the state that was requested."""
        self._master.check_context_is_initialized()
        return cpysoem.ecx_statecheck(self._ecx_contextt, self._pos, expected_state, timeout)
        
    def reconfig(self, timeout=500):
        """Reconfigure slave.

        :param timeout: local timeout
        :return: Slave state
        :rtype: int
        """
        self._master.check_context_is_initialized()
        return cpysoem.ecx_reconfig_slave(self._ecx_contextt, self._pos, timeout)
        
    def recover(self, timeout=500):
        """Recover slave.

        :param timeout: local timeout
        :return: >0 if successful
        :rtype: int
        """
        self._master.check_context_is_initialized()
        return cpysoem.ecx_recover_slave(self._ecx_contextt, self._pos, timeout)
        
    def eeprom_read(self, int word_address, timeout=20000):
        """Read 4 byte from EEPROM

        Default timeout: 20000 us

        Args:
            word_address (int): EEPROM address to read from
            timeout (:obj:`int`, optional): Timeout value in us

        Returns:
            bytes: EEPROM data
        """
        self._master.check_context_is_initialized()
        cdef uint32_t tmp = cpysoem.ecx_readeeprom(self._ecx_contextt, self._pos, word_address, timeout)
        return PyBytes_FromStringAndSize(<char*>&tmp, 4)
        
    def eeprom_write(self, int word_address, bytes data, timeout=20000):
        """Write 2 byte (1 word) to EEPROM

        Default timeout: 20000 us
        
        Args:
            word_address (int): EEPROM address to write to
            data (bytes): data (only 2 bytes are allowed)
            timeout (:obj:`int`, optional): Timeout value in us

        Raises:
            EepromError: if write fails
            AttributeError: if data size is not 2
        """
        self._master.check_context_is_initialized()
        if not len(data) == 2:
            raise AttributeError()
        cdef uint16_t tmp
        memcpy(<char*>&tmp, <unsigned char*>data, 2)
        cdef int result = cpysoem.ecx_writeeeprom(self._ecx_contextt, self._pos, word_address, tmp, timeout)
        if not result > 0:
            raise EepromError('EEPROM write error')

    def foe_write(self, filename, password, bytes data, timeout = 200000):
        """ Write given data to device using FoE

        Args:
            filename (string): name of the target file
            password (int): password for the target file, accepted range: 0 to 2^32 - 1
            data (bytes): data
            timeout (int): Timeout value in us
        """
        # error handling
        if self._ecx_contextt == NULL:
            raise UnboundLocalError()

        self._master.check_context_is_initialized()

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

        self._master.check_context_is_initialized()

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

    def eoe_set_ip(self, ip=None, netmask=None, gateway=None, mac=None, dns_ip=None, dns_name=None, port=0, timeout=700000):
        """ Set a slave's IP address

        Args:
            str ip: IP address the slave should use, or None to not set.
            str netmask: Netmask the slave should use, or None to not set.
            str gateway: Gateway the slave should use, or None to not set.
            str mac: MAC address to assign, or None to not set.
            str dns_ip: DNS server the slave should use, or None to not set.
            str dns_name: DNS name the slave should use, or None to not set.
            int port: port number on slave if applicable. Defaults to 0.
            int timeout: Timeout in us. Defaults to 700ms.

        Returns:
            int: Workcounter
        """
        import ipaddress

        cdef cpysoem.eoe_param_t ipsettings
        memset(&ipsettings, 0, sizeof(ipsettings))

        if ip is not None:
            ipsettings.ip_set = 1
            ipAddr = ipaddress.ip_address(ip)
            ipsettings.ip.addr = ntohl(ipAddr._ip)

        if netmask is not None:
            ipsettings.subnet_set = 1
            subnetAddr = ipaddress.ip_address(netmask)
            ipsettings.subnet.addr = ntohl(subnetAddr._ip)

        if gateway is not None:
            ipsettings.default_gateway_set = 1
            gatewayAddr = ipaddress.ip_address(gateway)
            ipsettings.default_gateway.addr = ntohl(gatewayAddr._ip)

        if dns_ip is not None:
            ipsettings.dns_ip_set = 1
            dnsAddr = ipaddress.ip_address(dns_ip)
            ipsettings.dns_ip.addr = ntohl(dnsAddr._ip)

        if mac is not None:
            ipsettings.mac_set = 1

            import binascii
            try:
                if type(mac) == str:
                    ipsettings.mac.addr = binascii.unhexlify(bytes(mac, "utf-8").replace(b':', b''))
                else:
                    ipsettings.mac.addr = binascii.unhexlify(mac.replace(b':', b''))
            except Exception as e:
                raise Exception('MAC address must be of the form \'xx:xx:xx:xx:xx:xx\'') from e

        if dns_name is not None:
            ipsettings.dns_name_set = 1
            ipsettings.dns_name = <unsigned char*>dns_name

        return cpysoem.ecx_EOEsetIp(self._ecx_contextt, self._pos, port, &ipsettings, timeout)

    def eoe_get_ip(self, port=0, timeout=700000):
        """Gets EOE IP settings from a slave

        Args:
            int port: port number on slave if applicable. Defaults to 0.
            int timeout: Timeout in us. Defaults to 700ms.

        Returns:
            List of settings: [mac, ip, subnet_mask, gateway_ip, dns_ip, dns_name]. Value is None if setting is not set
        """
        cdef cpysoem.eoe_param_t ipsettings
        cdef cpysoem.ec_errort err

        self._master.check_context_is_initialized()

        memset(&ipsettings, 0, sizeof(ipsettings))

        cdef int result = cpysoem.ecx_EOEgetIp(self._ecx_contextt, self._pos, port, &ipsettings, timeout)

        if result == -cpysoem.EC_ERR_TYPE_MBX_ERROR:
            raise MailboxError(self._pos, 0, "Mainbox error reading eoe IP settings")
        elif result == -cpysoem.EC_ERR_TYPE_PACKET_ERROR:
            raise PacketError(self._pos, 1)

        returnval = [None, None, None, None, None, None]

        if ipsettings.mac_set:
            returnval[0] = "%02x:%02x:%02x:%02x:%02x:%02x"%(
                    ipsettings.mac.addr[0],
                    ipsettings.mac.addr[1],
                    ipsettings.mac.addr[2],
                    ipsettings.mac.addr[3],
                    ipsettings.mac.addr[4],
                    ipsettings.mac.addr[5])
        if ipsettings.ip_set:
            returnval[1] = "%d.%d.%d.%d"%(
                    (ntohl(ipsettings.ip.addr) >> 24) & 0xFF,
                    (ntohl(ipsettings.ip.addr) >> 16) & 0xFF,
                    (ntohl(ipsettings.ip.addr) >>  8) & 0xFF,
                    (ntohl(ipsettings.ip.addr) >>  0) & 0xFF)
        if ipsettings.subnet_set:
            returnval[2] = "%d.%d.%d.%d"%(
                    (ntohl(ipsettings.subnet.addr) >> 24) & 0xFF,
                    (ntohl(ipsettings.subnet.addr) >> 16) & 0xFF,
                    (ntohl(ipsettings.subnet.addr) >>  8) & 0xFF,
                    (ntohl(ipsettings.subnet.addr) >>  0) & 0xFF)
        if ipsettings.default_gateway_set:
            returnval[3] = "%d.%d.%d.%d"%(
                    (ntohl(ipsettings.default_gateway.addr) >> 24) & 0xFF,
                    (ntohl(ipsettings.default_gateway.addr) >> 16) & 0xFF,
                    (ntohl(ipsettings.default_gateway.addr) >>  8) & 0xFF,
                    (ntohl(ipsettings.default_gateway.addr) >>  0) & 0xFF)
        if ipsettings.dns_ip_set:
            returnval[4] = "%d.%d.%d.%d"%(
                    (ntohl(ipsettings.dns_ip_set.addr) >> 24) & 0xFF,
                    (ntohl(ipsettings.dns_ip_set.addr) >> 16) & 0xFF,
                    (ntohl(ipsettings.dns_ip_set.addr) >>  8) & 0xFF,
                    (ntohl(ipsettings.dns_ip_set.addr) >>  0) & 0xFF)
        if ipsettings.dns_name_set:
            returnval[5] = str(ipsettings.dns_name, "utf-8").rstrip('\x00')

        return returnval

    def eoe_send_data(self, bytes data, int port=0, timeout_us=700000):
        """ Send EOE packet to a slave

        Args:
            str data: Raw packet data
            int port: port number on slave if applicable. Defaults to 0.
            int timeout: Timeout in us. Defaults to 700ms.

        Returns:
            int: Workcounter
        """
        self._master.check_context_is_initialized()

        cdef int result = cpysoem.ecx_EOEsend(self._ecx_contextt, self._pos, port, <int>len(data), <unsigned char*>data, timeout_us)
        return result

    def eoe_recv_data(self, int port=0, timeout_us=700000, mtu=1500):
        """ Recieve EOE packet from a slave. Only use if eoe hook has not been set.

        Args:
            int port: port number on slave if applicable. Defaults to 0.
            int timeout: Timeout in us. Defaults to 700ms.
            int mtu: Max packet size. Defaults to 1500.

        Raises:
            EoeInvalidRxDataError: if invalid EOE data is recieved
            PacketError: if the mailbox contains data other than EOE data
            Emergency: if an emergency message was received

        Returns:
            bytes: received data, or None on timeout or if no data is available
        """
        self._master.check_context_is_initialized()
        assert self._master._ecx_contextt.EOEhook == NULL

        cdef unsigned char* pbuf
        cdef int size_inout
        pbuf = <unsigned char*>PyMem_Malloc((mtu)*sizeof(unsigned char))
        size_inout = mtu

        cdef int result = cpysoem.ecx_EOErecv(self._ecx_contextt, self._pos, port, &size_inout, pbuf, timeout_us)

        # error handling
        cdef cpysoem.ec_errort err
        if cpysoem.ecx_poperror(self._ecx_contextt, &err):
            PyMem_Free(pbuf)
            assert err.Slave == self._pos
            self._raise_exception(&err)

        try:
            if result > 0:
                return PyBytes_FromStringAndSize(<char*>pbuf, size_inout)
            elif result == -cpysoem.EC_ERR_TYPE_EOE_INVALID_RX_DATA:
                raise EoeInvalidRxDataError()
            elif result == -cpysoem.EC_ERR_TYPE_PACKET_ERROR:
                raise PacketError(slave_pos=self._pos, error_code=1) # Always an unexpected packet error, so error_code = 1
            else:
                return None
        finally:
            PyMem_Free(pbuf)

    def amend_mbx(self, mailbox, start_address, size):
        """Change the start address and size of a mailbox.

        Note that the slave must me in INIT state to do that.

        :param str mailbox: Ether 'out', or 'in' to specify which mailbox to update.
        :param int start_address: New start address for the mailbox.
        :param int size: New size of the mailbox.

        .. versionadded:: 1.0.6
        """
        self._master.check_context_is_initialized()

        fpwr_timeout_us = 4000
        if mailbox == 'out':
            # Clear the slaves mailbox configuration.
            self._fpwr(ECT_REG_SM0, bytes(sizeof(self._ec_slave.SM[0])))
            self._ec_slave.SM[0].StartAddr = start_address
            self._ec_slave.SM[0].SMlength = size
            self._ec_slave.mbx_wo = start_address
            self._ec_slave.mbx_l = size
            # Update the slaves mailbox configuration.
            self._fpwr(ECT_REG_SM0,
                       PyBytes_FromStringAndSize(<char*>&self._ec_slave.SM[0], sizeof(self._ec_slave.SM[0])),
                       fpwr_timeout_us)
        elif mailbox == 'in':
            # Clear the slaves mailbox configuration.
            self._fpwr(ECT_REG_SM1, bytes(sizeof(self._ec_slave.SM[1])))
            self._ec_slave.SM[1].StartAddr = start_address
            self._ec_slave.SM[1].SMlength = size
            self._ec_slave.mbx_ro = start_address
            self._ec_slave.mbx_rl = size
            # Update the slaves mailbox configuration.
            self._fpwr(ECT_REG_SM1,
                       PyBytes_FromStringAndSize(<char*>&self._ec_slave.SM[1], sizeof(self._ec_slave.SM[1])),
                       fpwr_timeout_us)
        else:
            raise AttributeError()

    def set_watchdog(self, wd_type, wd_time_ms):
        """Change the watchdog time of the PDI or Process Data watchdog.

        .. warning:: This is experimental.

        :param str wd_type: Ether 'pdi', or 'processdata' to specify the watchdog time to be updated.
        :param float wd_time_ms: Watchdog time in ms.

        At the default watchdog time divider the precision is 0.1 ms.

        .. versionadded:: 1.0.6
        """
        self._master.check_context_is_initialized()

        fprd_fpwr_timeout_us = 4000
        wd_type_to_reg_map = {
            'pdi': ECT_REG_WD_TIME_PDI,
            'processdata': ECT_REG_WD_TIME_PROCESSDATA,
        }
        if wd_type not in wd_type_to_reg_map.keys():
            raise AttributeError()
        wd_div_reg = int.from_bytes(self._fprd(ECT_REG_WD_DIV, 2, fprd_fpwr_timeout_us),
                                    byteorder='little',
                                    signed=False)
        wd_div_ns = 40 * (wd_div_reg + 2)
        wd_time_reg = int((wd_time_ms*1000000.0) / wd_div_ns)
        if wd_time_reg > 0xFFFF:
            wd_time_ms_limit = 0xFFFF * wd_div_ns / 1000000.0
            raise AttributeError('wd_time_ms is limited to {} ms'.format(wd_time_ms_limit))
        actual_wd_time_ms = wd_time_reg * wd_div_ns / 1000000.0
        self._fpwr(wd_type_to_reg_map[wd_type],
                   wd_time_reg.to_bytes(2, byteorder='little', signed=False),
                   fprd_fpwr_timeout_us)

    def add_emergency_callback(self, callback):
        """Get notified on EMCY messages from this slave.

        :param callback:
            Callable which must take one argument of an
            :class:`~Emergency` instance.
        """
        self._master.check_context_is_initialized()
        self._emcy_callbacks.append(callback)

    cdef _on_emergency(self, cpysoem.ec_errort* emcy):
        """Notify all emergency callbacks that an emergency message
        was received.

        :param emcy: Emergency object.
        """
        emergency_msg = Emergency(emcy.Slave, 
                               emcy.ErrorCode,
                               emcy.ErrorReg,
                               emcy.b1,
                               emcy.w1,
                               emcy.w2)
        for callback in self._emcy_callbacks:
            callback(emergency_msg)

    def _disable_complete_access(self):
        """Helper function that stops config_map() from using "complete access" for SDO requests for this device.

        This should only be used if your device has issues handling complete access requests but the CoE details of the
        SII tells that SDO complete access is supported by the device. If you need this function something is wrong
        with your device and you should contact the manufacturer about this issue.

        .. warning:: This is experimental.

        .. versionadded:: 1.1.3
        """
        self._ec_slave.CoEdetails &= ~ECT_COEDET_SDOCA

    def _fprd(self, int address, int size, timeout_us=2000):
        """Send and receive of the FPRD cmd primitive (Configured Address Physical Read)."""
        cdef unsigned char* data
        data = <unsigned char*>PyMem_Malloc(size)
        cdef int wkc = cpysoem.ecx_FPRD(self._ecx_contextt.port, self._ec_slave.configadr, address, size, data, timeout_us)
        if wkc != 1:
            PyMem_Free(data)
            raise WkcError()
        try:
            return PyBytes_FromStringAndSize(<char*>data, size)
        finally:
            PyMem_Free(data)

    def _fpwr(self, int address, bytes data, timeout_us=2000):
        """Send and receive of the FPWR cmd primitive (Configured Address Physical Write)."""
        cdef int wkc = cpysoem.ecx_FPWR(self._ecx_contextt.port, self._ec_slave.configadr, address, <int>len(data), <unsigned char*>data, timeout_us)
        if wkc != 1:
            raise WkcError()

    cdef _raise_exception(self, cpysoem.ec_errort* err):
        if err.Etype == cpysoem.EC_ERR_TYPE_SDO_ERROR:
            raise SdoError(err.Slave,
                           err.Index,
                           err.SubIdx,
                           err.AbortCode,
                           cpysoem.ec_sdoerror2string(err.AbortCode).decode('utf8'))
        elif err.Etype == cpysoem.EC_ERR_TYPE_EMERGENCY:
            warnings.warn('This way of catching emergency messages is deprecated, use the add_emergency_callback() function!', FutureWarning)
            raise Emergency(err.Slave,
                            err.ErrorCode,
                            err.ErrorReg,
                            err.b1,
                            err.w1,
                            err.w2)
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
        """Name of the slave, read out from the slaves SII during config_init."""
        return (<bytes>self._ec_slave.name).decode('utf8')
    
    def _get_eep_man(self):
        """Vendor ID of the slave, read out from the slaves SII during config_init."""
        return self._ec_slave.eep_man
    
    def _get_eep_id(self):
        """Product Code of the slave, read out from the slaves SII during config_init."""
        return self._ec_slave.eep_id
    
    def _get_eep_rev(self):
        """Revision Number of the slave, read out from the slaves SII during config_init."""
        return self._ec_slave.eep_rev
        
    def _get_PO2SOconfig(self):
        """Slaves callback function that is called during config_map.
        
        When the state changes from Pre-Operational state to Operational state."""
        if not self._ec_slave.user:
            return None

        return <object>self._ec_slave.user

    def _get_PO2SOconfigEx(self):
        """Alternative callback function that is called during config_map.

        More precisely the function is called during the transition from Pre-Operational to Safe-Operational state.
        Use this instead of the config_func. The difference is that the callbacks signature is fn(CdefSlave: slave).

        .. versionadded:: 1.1.0
        """
        if not self._ec_slave.user:
            return None

        return <object>self._ec_slave.user
    
    def _set_PO2SOconfig(self, value):
        self._cd.func = value
        self._ec_slave.user = <void*>self._cd
        if value is None:
            self._ec_slave.PO2SOconfig = NULL
        else:
            self._ec_slave.PO2SOconfig = _xPO2SOconfig

    def _set_PO2SOconfigEx(self, value):
        self._cd.func = value
        self._ec_slave.user = <void*>self._cd
        if value is None:
            self._ec_slave.PO2SOconfig = NULL
        else:
            self._ec_slave.PO2SOconfig = _xPO2SOconfigEx

    def _get_state(self):
        """Request a new state.

        After a new state has been set, `write_state` must be called.
        """
        return self._ec_slave.state

    def _set_state(self, value):
        self._ec_slave.state = value

    def _get_input(self):
        num_bytes = self._ec_slave.Ibytes
        if (self._ec_slave.Ibytes == 0 and self._ec_slave.Ibits > 0):
            num_bytes = 1
        return PyBytes_FromStringAndSize(<char*>self._ec_slave.inputs, num_bytes)

    def _get_output(self):
        num_bytes = self._ec_slave.Obytes
        if (self._ec_slave.Obytes == 0 and self._ec_slave.Obits > 0):
            num_bytes = 1
        return PyBytes_FromStringAndSize(<char*>self._ec_slave.outputs, num_bytes)

    def _set_output(self, bytes value):
        memcpy(<char*>self._ec_slave.outputs, <char*>value, len(value))
    
    def _get_al_status(self):
        return self._ec_slave.ALstatuscode
    
    def _get_is_lost(self):
        return self._ec_slave.islost

    def _set_is_lost(self, value):
        self._ec_slave.islost = value
    
    def _get_od(self):
        logger.debug('ecx_readODlist()')
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



cdef class CdefCoeObject:
    """Object info for objects in the object dictionary.

    Do not create instances of this class, you get instances of this type by the CdefSlave.od property.
    """
    cdef cpysoem.ecx_contextt* _ecx_context
    cdef cpysoem.ec_ODlistt* _ex_odlist
    cdef int _item
    cdef cpysoem.boolean _is_description_read
    cdef cpysoem.boolean _are_entries_read
    cdef cpysoem.ec_OElistt _ex_oelist

    index = property(_get_index)
    data_type = property(_get_data_type)
    name = property(_get_name)
    object_code = property(_get_object_code)
    entries = property(_get_entries)
    bit_length = property(_get_bit_length)
    obj_access = property(_get_obj_access)
    
    def __init__(self, int item):
        self._item = item
        self._is_description_read = False
        self._are_entries_read = False
        
    def _read_description(self):
        cdef int result
        if not self._is_description_read:
          logger.debug('ecx_readODdescription()')
          result = cpysoem.ecx_readODdescription(self._ecx_context, self._item, self._ex_odlist)
          if not result > 0:
              raise SdoInfoError('Sdo Object Info read failed')
          self._is_description_read = True
          
    def _read_entries(self):
        cdef int result
        if not self._are_entries_read:
            logger.debug('ecx_readOE()')
            result = cpysoem.ecx_readOE(self._ecx_context, self._item, self._ex_odlist, &self._ex_oelist)
            if not result > 0:
                raise SdoInfoError('Sdo ObjectEntry Info read failed')
            self._are_entries_read = True
            
    def _get_index(self):
        return self._ex_odlist.Index[self._item]
    
    def _get_data_type(self):
        self._read_description()
        return self._ex_odlist.DataType[self._item]
    
    def _get_object_code(self):
        self._read_description()
        return self._ex_odlist.ObjectCode[self._item]
        
    def _get_name(self):
        self._read_description()
        return self._ex_odlist.Name[self._item]
    
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
    
    def _get_obj_access(self):
        if self._ex_odlist.MaxSub[self._item] == 0:
            return self._ex_oelist.ObjAccess[0]
        else:
            return 0
        

cdef class CdefCoeObjectEntry:
    cdef cpysoem.ec_OElistt* _ex_oelist
    cdef int _item

    name = property(_get_name)
    data_type = property(_get_data_type)
    bit_length = property(_get_bit_length)
    obj_access = property(_get_obj_access)

    def __init__(self, int item):
        self._item = item
        
    def _get_name(self):            
        return self._ex_oelist.Name[self._item]

    def _get_data_type(self):
        return self._ex_oelist.DataType[self._item]

    def _get_bit_length(self):
        return self._ex_oelist.BitLength[self._item]
    
    def _get_obj_access(self):
        return self._ex_oelist.ObjAccess[self._item]
        

cdef int _xPO2SOconfig(cpysoem.uint16 slave, void* user) noexcept:
    cdef _CallbackData cd
    cd = <object>user
    cd.exc_raised = False
    try:
        (<object>cd.func)(slave-1)
    except:
        cd.exc_raised = True
        cd.exc_info = sys.exc_info()


cdef int _xPO2SOconfigEx(cpysoem.uint16 slave, void* user) noexcept:
    cdef _CallbackData cd
    cd = <object>user
    cd.exc_raised = False
    try:
        (<object>cd.func)(cd.slave)
    except:
        cd.exc_raised = True
        cd.exc_info = sys.exc_info()

cdef int _eoe_hook(cpysoem.ecx_contextt* context, cpysoem.uint16 slave, void* eoembx) noexcept:
    cdef int wkc
    # context is actually a _contextt_and_master pointer, cast it and get CdefMaster pointer
    cdef CdefMaster self = <CdefMaster>(<_contextt_and_master*>context).master
    slaveInx = <int>(slave - 1)
    cdef _eoe_rx_data *rxInfo = &(<CdefSlave>self.slaves[slaveInx])._eoe_rx_info

    # Pass received Mbx data to EoE recevive fragment function that
    # that will start/continue fill an Ethernet frame buffer
    rxInfo._size_of_rx = <int>sizeof(rxInfo._rxbuf)
    wkc = cpysoem.ecx_EOEreadfragment(<cpysoem.ec_mbxbuft *>eoembx, # ec_mbxbuft *
        &rxInfo._rxfragmentno, # uint8 *
        &rxInfo._rxframesize, # uint16 *
        &rxInfo._rxframeoffset, # uint16 *
        &rxInfo._rxframeno, # uint16 *
        &rxInfo._size_of_rx, # int *
        rxInfo._rxbuf) # void *

    # wkc == 1 would mean a frame is complete , last fragment flag have been set and all
    # other checks must have past
    if (wkc > 0):
        try:
            self._eoe_callback(PyBytes_FromStringAndSize(<char*>rxInfo._rxbuf, rxInfo._size_of_rx), slave)
        except Exception as e:
            import traceback
            print(traceback.format_exc())

    # No point in returning as unhandled
    return 1

