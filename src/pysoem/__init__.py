__version__ = '1.1.12'


# Classes:
from pysoem.pysoem import (
    Master,
    SdoError,
    Emergency,
    SdoInfoError,
    MailboxError,
    PacketError,
    ConfigMapError,
    EepromError,
    WkcError,
    NetworkInterfaceNotOpenError,
    SiiOffset,
)

# State constants:
from pysoem.pysoem import (
    NONE_STATE,
    INIT_STATE,
    PREOP_STATE,
    BOOT_STATE,
    SAFEOP_STATE,
    OP_STATE,
    STATE_ACK,
    STATE_ERROR,
)

# ECT constants:
from pysoem.pysoem import (
    ECT_REG_WD_DIV,
    ECT_REG_WD_TIME_PDI,
    ECT_REG_WD_TIME_PROCESSDATA,
    ECT_REG_SM0,
    ECT_REG_SM1,
    ECT_COEDET_SDO,
    ECT_COEDET_SDOINFO,
    ECT_COEDET_PDOASSIGN,
    ECT_COEDET_PDOCONFIG,
    ECT_COEDET_UPLOAD,
    ECT_COEDET_SDOCA,
)
globals().update(pysoem.ec_datatype.__members__)

# Functions:
from pysoem.pysoem import (
    find_adapters,
    open,
    al_status_code_to_string,
)

# Raw Cdefs:
from pysoem.pysoem import (
    CdefMaster,
    CdefSlave,
    CdefCoeObjectEntry,
)

# Settings:
from pysoem.pysoem import (
    settings
)
