#ifndef _SOEM_CONFIG_H
#define _SOEM_CONFIG_H

typedef struct {
    int ret;
    int safe;
    int eeprom;
    int tx_mailbox;
    int rx_mailbox;
    int state;
} Ttimeouts;

extern Ttimeouts soem_timeouts;

/** timeout value in us for tx frame to return to rx */
#define EC_TIMEOUTRET      soem_timeouts.ret
/** timeout value in us for safe data transfer, max. triple retry */
#define EC_TIMEOUTRET3     (EC_TIMEOUTRET * 3)
/** timeout value in us for return "safe" variant (f.e. wireless) */
#define EC_TIMEOUTSAFE     soem_timeouts.safe
/** timeout value in us for EEPROM access */
#define EC_TIMEOUTEEP      soem_timeouts.eeprom
/** timeout value in us for tx mailbox cycle */
#define EC_TIMEOUTTXM      soem_timeouts.tx_mailbox
/** timeout value in us for rx mailbox cycle */
#define EC_TIMEOUTRXM      soem_timeouts.rx_mailbox
/** timeout value in us for check statechange */
#define EC_TIMEOUTSTATE    soem_timeouts.state

#endif /* _SOEM_CONFIG_H */