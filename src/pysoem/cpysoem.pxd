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

from libc.stdint cimport int8_t, int16_t, int32_t, int64_t, uint8_t, uint16_t, uint32_t, uint64_t

cdef extern from "ethercat.h":
    
    DEF EC_MAXBUF = 16
    DEF EC_MAXMBX = 1486
    DEF EC_BUFSIZE = 1518
    
    ec_adaptert* ec_find_adapters()
        
    # from osal.h
    
    ctypedef int8_t              boolean
    ctypedef int8_t              int8
    ctypedef int16_t             int16
    ctypedef int32_t             int32
    ctypedef int64_t             int64
    ctypedef uint8_t             uint8
    ctypedef uint16_t            uint16
    ctypedef uint32_t            uint32
    ctypedef uint64_t            uint64
    ctypedef float               float32
    ctypedef double              float64
    ctypedef uint8               ec_mbxbuft[EC_MAXMBX]

    ctypedef uint8               ec_bufT[EC_BUFSIZE]
    
    ctypedef struct ec_timet:
        uint32 sec
        uint32 usec
    
    # from ethercattype.h
    
    ctypedef enum ec_err_type:
        EC_ERR_TYPE_SDO_ERROR         = 0
        EC_ERR_TYPE_EMERGENCY         = 1
        EC_ERR_TYPE_PACKET_ERROR      = 3
        EC_ERR_TYPE_SDOINFO_ERROR     = 4
        EC_ERR_TYPE_FOE_ERROR         = 5
        EC_ERR_TYPE_FOE_BUF2SMALL     = 6
        EC_ERR_TYPE_FOE_PACKETNUMBER  = 7
        EC_ERR_TYPE_SOE_ERROR         = 8
        EC_ERR_TYPE_MBX_ERROR         = 9
        EC_ERR_TYPE_FOE_FILE_NOTFOUND = 10
        
    ctypedef enum ec_state:
        EC_STATE_NONE           = 0x00
        EC_STATE_INIT           = 0x01
        EC_STATE_PRE_OP         = 0x02
        EC_STATE_BOOT           = 0x03
        EC_STATE_SAFE_OP        = 0x04
        EC_STATE_OPERATIONAL    = 0x08
        EC_STATE_ACK            = 0x10
        EC_STATE_ERROR          = 0x10
   
    ctypedef struct ec_errort:
        ec_timet Time
        boolean     Signal
        uint16      Slave
        uint16      Index
        uint8       SubIdx
        ec_err_type Etype
        # union - General abortcode
        int32   AbortCode
        # union - Specific error for Emergency mailbox
        uint16  ErrorCode
        uint8   ErrorReg
        uint8   b1
        uint16  w1
        uint16  w2
    
    # from nicdrv.h
        
    ctypedef struct ec_stackT:
        int     *sock
        ec_bufT *(*txbuf) #[EC_MAXBUF]
        int     *(*txbuflength) #[EC_MAXBUF]
        ec_bufT *tempbuf
        ec_bufT *(*rxbuf) #[EC_MAXBUF]
        int     *(*rxbufstat) #[EC_MAXBUF]
        int     *(*rxsa) #[EC_MAXBUF]
        
    ctypedef struct ecx_redportt:
        ec_stackT stack
        int       sockhandle
        ec_bufT   *rxbuf #[EC_MAXBUF]
        int       *rxbufstat #[EC_MAXBUF]
        int       *rxsa #[EC_MAXBUF]
        ec_bufT   tempinbuf
        
    ctypedef struct ecx_portt:
        pass
    
    # from eethercatmain.h
    
    ctypedef struct ec_adaptert:
        char* name
        char* desc
        ec_adaptert* next
        
    ctypedef struct ec_fmmut:
        uint32  LogStart
        uint16  LogLength
        uint8   LogStartbit
        uint8   LogEndbit
        uint16  PhysStart
        uint8   PhysStartBit
        uint8   FMMUtype
        uint8   FMMUactive
        uint8   unused1
        uint16  unused2
    
    ctypedef struct ec_smt:
        uint16  StartAddr
        uint16  SMlength
        uint32  SMflags
    
    ctypedef struct ec_slavet:
        uint16           state
        uint16           ALstatuscode
        uint16           configadr
        uint16           aliasadr
        uint32           eep_man
        uint32           eep_id
        uint32           eep_rev
        uint16           Itype
        uint16           Dtype
        uint16           Obits
        uint32           Obytes
        uint8            *outputs
        uint8            Ostartbit
        uint16           Ibits
        uint32           Ibytes
        uint8            *inputs
        uint8            Istartbit
        ec_smt           *SM #[EC_MAXSM]
        uint8            *SMtype #[EC_MAXSM]
        ec_fmmut         *FMMU #[EC_MAXFMMU]
        uint8            FMMU0func
        uint8            FMMU1func
        uint8            FMMU2func
        uint8            FMMU3func
        uint16           mbx_l
        uint16           mbx_wo
        uint16           mbx_rl
        uint16           mbx_ro
        uint16           mbx_proto
        uint8            mbx_cnt
        boolean          hasdc
        uint8            ptype
        uint8            topology
        uint8            activeports
        uint8            consumedports
        uint16           parent
        uint8            parentport
        uint8            entryport
        int32            DCrtA
        int32            DCrtB
        int32            DCrtC
        int32            DCrtD
        int32            pdelay
        uint16           DCnext
        uint16           DCprevious
        int32            DCcycle
        int32            DCshift
        uint8            DCactive
        uint16           configindex
        uint16           SIIindex
        uint8            eep_8byte
        uint8            eep_pdi
        uint8            CoEdetails
        uint8            FoEdetails
        uint8            EoEdetails
        uint8            SoEdetails
        int16            Ebuscurrent
        uint8            blockLRW
        uint8            group
        uint8            FMMUunused
        boolean          islost
        int              (*PO2SOconfig)(uint16 slave, void* user)
        int              (*PO2SOconfigx)(ecx_contextt* context, uint16 slave)
        void*            user
        char             *name #[EC_MAXNAME + 1]
    
    ctypedef struct ec_groupt:
        uint32           logstartaddr
        uint32           Obytes
        uint8            *outputs
        uint32           Ibytes
        uint8            *inputs
        boolean          hasdc
        uint16           DCnext
        int16            Ebuscurrent
        uint8            blockLRW
        uint16           nsegments
        uint16           Isegment
        uint16           Ioffset
        uint16           outputsWKC
        uint16           inputsWKC
        boolean          docheckstate
        uint32           *IOsegment #[EC_MAXIOSEGMENTS]    

    ctypedef struct ec_idxstackT:
        uint8   pushed
        uint8   pulled
        uint8   *idx #[EC_MAXBUF]
        void    **data #[EC_MAXBUF]
        uint16  *length #[EC_MAXBUF]

    ctypedef struct ec_eringt:
        int16     head
        int16     tail
        ec_errort *Error #[EC_MAXELIST + 1]        
        
    ctypedef struct ec_SMcommtypet:
        uint8   n
        uint8   nu1
        uint8   *SMtype #[EC_MAXSM]

    ctypedef struct ec_PDOassignt:
        uint8   n
        uint8   nu1
        uint16  *index #[256]
        
    ctypedef struct ec_PDOdesct:
        uint8   n
        uint8   nu1
        uint32  *PDO #[256]
    
    ctypedef struct ec_eepromSMt:
        uint16  Startpos
        uint8   nSM
        uint16  PhStart
        uint16  Plength
        uint8   Creg
        uint8   Sreg
        uint8   Activate
        uint8   PDIctrl     
        
    ctypedef struct ec_eepromFMMUt:
        uint16  Startpos
        uint8   nFMMU
        uint8   FMMU0
        uint8   FMMU1
        uint8   FMMU2
        uint8   FMMU3
    
    ctypedef struct ecx_contextt:
        ecx_portt     *port
        ec_slavet      *slavelist
        int            *slavecount
        int            maxslave
        ec_groupt      *grouplist
        int            maxgroup
        uint8          *esibuf
        uint32         *esimap
        uint16         esislave
        ec_eringt      *elist
        ec_idxstackT   *idxstack
        boolean        *ecaterror
        int64          *DCtime
        ec_SMcommtypet *SMcommtype
        ec_PDOassignt  *PDOassign
        ec_PDOdesct    *PDOdesc
        ec_eepromSMt   *eepSM
        ec_eepromFMMUt *eepFMMU
        int            (*FOEhook)(uint16 slave, int packetnumber, int datasize)
        int            (*EOEhook)(ecx_contextt* context, uint16 slave, void* eoembx)
        int            manualstatechange
        
    ctypedef struct ec_ODlistt:
        uint16  Slave
        uint16  Entries
        uint16  *Index #[EC_MAXODLIST]
        uint16  *DataType #[EC_MAXODLIST]
        uint8   *ObjectCode #[EC_MAXODLIST]
        uint8   *MaxSub #[EC_MAXODLIST]
        char    **Name #[EC_MAXODLIST][EC_MAXNAME+1]
         
    ctypedef struct ec_OElistt:
        uint16 Entries
        uint8  *ValueInfo #[EC_MAXOELIST]
        uint16 *DataType #[EC_MAXOELIST]
        uint16 *BitLength #[EC_MAXOELIST]
        uint16 *ObjAccess #[EC_MAXOELIST]
        char   **Name #[EC_MAXOELIST][EC_MAXNAME+1]
    
    int ecx_init(ecx_contextt* context, char* ifname)
    int ecx_init_redundant(ecx_contextt *context, ecx_redportt *redport, const char *ifname, char *if2name)
    void ecx_close(ecx_contextt *context)
    int ecx_config_init(ecx_contextt *context, uint8 usetable)
    int ecx_config_map_group(ecx_contextt *context, void *pIOmap, uint8 group)
    int ecx_config_overlap_map_group(ecx_contextt *context, void *pIOmap, uint8 group)
    int ecx_SDOread(ecx_contextt *context, uint16 slave, uint16 index, uint8 subindex, boolean CA, int *psize, void *p, int timeout)
    int ecx_SDOwrite(ecx_contextt *context, uint16 slave, uint16 index, uint8 subindex, boolean CA, int psize, void *p, int Timeout)
    int ecx_readODlist(ecx_contextt *context, uint16 Slave, ec_ODlistt *pODlist)
    int ecx_readODdescription(ecx_contextt *context, uint16 Item, ec_ODlistt *pODlist)
    int ecx_readOE(ecx_contextt *context, uint16 Item, ec_ODlistt *pODlist, ec_OElistt *pOElist)
    
    int ecx_readstate(ecx_contextt *context)
    int ecx_writestate(ecx_contextt *context, uint16 slave)
    uint16 ecx_statecheck(ecx_contextt *context, uint16 slave, uint16 reqstate, int timeout)
    
    int ecx_send_processdata(ecx_contextt *context)
    int ecx_send_overlap_processdata(ecx_contextt *context)
    int ecx_receive_processdata(ecx_contextt *context, int timeout)
    
    int ecx_recover_slave(ecx_contextt *context, uint16 slave, int timeout)
    int ecx_reconfig_slave(ecx_contextt *context, uint16 slave, int timeout)

    int ecx_mbxreceive(ecx_contextt *context, uint16 slave, ec_mbxbuft *mbx, int timeout)
    void ec_clearmbx(ec_mbxbuft *Mbx)
    boolean ecx_poperror(ecx_contextt *context, ec_errort *Ec)
    const char* ec_sdoerror2string(uint32 sdoerrorcode)
    char* ec_mbxerror2string(uint16 errorcode)
    
    boolean ecx_configdc(ecx_contextt *context)
    void ecx_dcsync0(ecx_contextt *context, uint16 slave, boolean act, uint32 CyclTime, int32 CyclShift)
    void ecx_dcsync01(ecx_contextt *context, uint16 slave, boolean act, uint32 CyclTime0, uint32 CyclTime1, int32 CyclShift)
    
    char* ec_ALstatuscode2string(uint16 ALstatuscode)
    
    uint32 ecx_readeeprom(ecx_contextt *context, uint16 slave, uint16 eeproma, int timeout)
    int ecx_writeeeprom(ecx_contextt *context, uint16 slave, uint16 eeproma, uint16 data, int timeout)

    int ecx_FOEread(ecx_contextt *context, uint16 slave, char *filename, uint32 password, int *psize, void *p, int timeout)
    int ecx_FOEwrite(ecx_contextt *context, uint16 slave, char *filename, uint32 password, int psize, void *p, int timeout)

    int ecx_FPWR(ecx_portt *port, uint16 ADP, uint16 ADO, uint16 length, void *data, int timeout)
    int ecx_FPRD(ecx_portt *port, uint16 ADP, uint16 ADO, uint16 length, void *data, int timeout)
