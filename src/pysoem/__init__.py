__version__ = '1.1.8'


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
    ECT_BOOLEAN,
    ECT_INTEGER8,
    ECT_INTEGER16,
    ECT_INTEGER32,
    ECT_UNSIGNED8,
    ECT_UNSIGNED16,
    ECT_UNSIGNED32,
    ECT_REAL32,
    ECT_VISIBLE_STRING,
    ECT_OCTET_STRING,
    ECT_UNICODE_STRING,
    ECT_TIME_OF_DAY,
    ECT_TIME_DIFFERENCE,
    ECT_DOMAIN,
    ECT_INTEGER24,
    ECT_REAL64,
    ECT_INTEGER64,
    ECT_UNSIGNED24,
    ECT_UNSIGNED64,
    ECT_BIT1,
    ECT_BIT2,
    ECT_BIT3,
    ECT_BIT4,
    ECT_BIT5,
    ECT_BIT6,
    ECT_BIT7,
    ECT_BIT8,
)

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
