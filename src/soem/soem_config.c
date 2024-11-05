#include "soem_config.h"

/* Default timeouts in us */
Ttimeouts soem_timeouts = {
    .ret = 2000,
    .safe = 20000,
    .eeprom = 20000,
    .tx_mailbox = 20000,
    .rx_mailbox = 700000,
    .state = 2000000
};
