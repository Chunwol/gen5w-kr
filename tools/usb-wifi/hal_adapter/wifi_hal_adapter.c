/*
 * OEM HAL Wi-Fi Adapter for Hyundai/Kia Gen5W (Telechips TCC897X / Android 4.4.2)
 *
 * Intercepts Wi-Fi driver and firmware path calls from libandroid_runtime and netd,
 * enabling USB Wi-Fi dongles (ath9k_htc) while transparently delegating all other
 * hardware legacy functions to the original stock library (libhardware_legacy_stock.so).
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <dlfcn.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <sys/stat.h>
#include <sys/types.h>

#define STOCK_LIB_PATH "/system/lib/libhardware_legacy_stock.so"
#define DONGLE_FLAG_PROP "persist.gen5w.wifi.backend"
#define DRIVER_STATUS_PROP "wlan.driver.status"

/* Android property stubs */
extern int property_get(const char *key, char *value, const char *default_value);
extern int property_set(const char *key, const char *value);

static void *stock_handle = NULL;

static void *get_stock_handle(void) {
    if (!stock_handle) {
        stock_handle = dlopen(STOCK_LIB_PATH, RTLD_LOCAL);
    }
    return stock_handle;
}

static void *get_stock_symbol(const char *name) {
    void *h = get_stock_handle();
    if (!h) return NULL;
    return dlsym(h, name);
}

/* Check if running in USB dongle mode */
static int is_dongle_mode(void) {
    char val[92];
    if (property_get(DONGLE_FLAG_PROP, val, "") > 0) {
        if (strcmp(val, "dongle") == 0 || strcmp(val, "usb") == 0) {
            return 1;
        }
    }
    /* Auto-detect: if wlan interface exists without bcmdhd in proc/modules */
    if (access("/sys/class/net/wlan0", F_OK) == 0) {
        FILE *f = fopen("/proc/modules", "r");
        if (f) {
            char line[128];
            int has_ath = 0;
            while (fgets(line, sizeof(line), f)) {
                if (strncmp(line, "ath9k_htc", 9) == 0) {
                    has_ath = 1;
                    break;
                }
            }
            fclose(f);
            if (has_ath) return 1;
        }
    }
    return 0;
}

/* --- Intercepted Wi-Fi Functions --- */

int is_wifi_driver_loaded(void) {
    if (is_dongle_mode()) {
        if (access("/sys/class/net/wlan0", F_OK) == 0) {
            char status[92];
            if (property_get(DRIVER_STATUS_PROP, status, "") > 0 && strcmp(status, "ok") == 0) {
                return 1;
            }
            property_set(DRIVER_STATUS_PROP, "ok");
            return 1;
        }
        return 0;
    }
    int (*fn)(void) = (int (*)(void))get_stock_symbol("is_wifi_driver_loaded");
    if (fn) return fn();
    return 0;
}

int wifi_load_driver(void) {
    if (is_dongle_mode()) {
        if (is_wifi_driver_loaded()) {
            return 0;
        }
        /* Run helper script if wlan0 not ready yet */
        if (access("/system/bin/gen5w-dongle-load", X_OK) == 0) {
            system("/system/bin/gen5w-dongle-load");
        }
        int retry = 20;
        while (retry-- > 0) {
            if (access("/sys/class/net/wlan0", F_OK) == 0) {
                property_set(DRIVER_STATUS_PROP, "ok");
                return 0;
            }
            usleep(100000);
        }
        property_set(DRIVER_STATUS_PROP, "failed");
        return -1;
    }
    int (*fn)(void) = (int (*)(void))get_stock_symbol("wifi_load_driver");
    if (fn) return fn();
    return -1;
}

int wifi_unload_driver(void) {
    if (is_dongle_mode()) {
        property_set(DRIVER_STATUS_PROP, "unloaded");
        return 0;
    }
    int (*fn)(void) = (int (*)(void))get_stock_symbol("wifi_unload_driver");
    if (fn) return fn();
    return 0;
}

int wifi_change_fw_path(const char *fwpath) {
    if (is_dongle_mode()) {
        /* ath9k_htc does not need firmware swapping between STA and AP modes */
        return 0;
    }
    int (*fn)(const char *) = (int (*)(const char *))get_stock_symbol("wifi_change_fw_path");
    if (fn) return fn(fwpath);
    return 0;
}

const char *wifi_get_fw_path(int fw_type) {
    if (is_dongle_mode()) {
        return "";
    }
    const char *(*fn)(int) = (const char *(*)(int))get_stock_symbol("wifi_get_fw_path");
    if (fn) return fn(fw_type);
    return "";
}

/* --- Forwarding for all remaining hardware legacy functions --- */

#define FORWARD_0(ret_type, name) \
ret_type name(void) { \
    ret_type (*fn)(void) = (ret_type (*)(void))get_stock_symbol(#name); \
    if (fn) return fn(); \
    return (ret_type)0; \
}

#define FORWARD_1(ret_type, name, t1) \
ret_type name(t1 a1) { \
    ret_type (*fn)(t1) = (ret_type (*)(t1))get_stock_symbol(#name); \
    if (fn) return fn(a1); \
    return (ret_type)0; \
}

#define FORWARD_2(ret_type, name, t1, t2) \
ret_type name(t1 a1, t2 a2) { \
    ret_type (*fn)(t1, t2) = (ret_type (*)(t1, t2))get_stock_symbol(#name); \
    if (fn) return fn(a1, a2); \
    return (ret_type)0; \
}

#define FORWARD_3(ret_type, name, t1, t2, t3) \
ret_type name(t1 a1, t2 a2, t3 a3) { \
    ret_type (*fn)(t1, t2, t3) = (ret_type (*)(t1, t2, t3))get_stock_symbol(#name); \
    if (fn) return fn(a1, a2, a3); \
    return (ret_type)0; \
}

#define FORWARD_4(ret_type, name, t1, t2, t3, t4) \
ret_type name(t1 a1, t2 a2, t3 a3, t4 a4) { \
    ret_type (*fn)(t1, t2, t3, t4) = (ret_type (*)(t1, t2, t3, t4))get_stock_symbol(#name); \
    if (fn) return fn(a1, a2, a3, a4); \
    return (ret_type)0; \
}

/* Power / WakeLock */
FORWARD_2(int, acquire_wake_lock, int, const char *)
FORWARD_1(int, release_wake_lock, const char *)

/* UEvent */
FORWARD_0(int, uevent_init)
FORWARD_0(int, uevent_get_fd)
FORWARD_2(int, uevent_next_event, char *, int)
FORWARD_2(int, uevent_add_native_handler, void *, void *)
FORWARD_1(int, uevent_remove_native_handler, void *)

/* Vibrator */
FORWARD_0(int, vibrator_exists)
FORWARD_1(int, vibrator_on, int)
FORWARD_0(int, vibrator_off)

/* DHCP */
FORWARD_4(int, do_dhcp_request, const char *, char *, char *, uint32_t *)
FORWARD_0(const char *, get_dhcp_error_string)

/* Wi-Fi Supplicant & Hostapd Socket Forwarding */
FORWARD_1(int, wifi_delete_config_file, const char *)
FORWARD_1(int, wifi_stop_supplicant, int)
FORWARD_1(int, wifi_connect_on_socket_path, const char *)
FORWARD_1(int, wifi_connect_to_supplicant, const char *)
FORWARD_0(int, wifi_connect_to_hostapd)
FORWARD_3(int, wifi_send_command, const char *, char *, size_t *)
FORWARD_0(int, wifi_supplicant_connection_active)
FORWARD_2(int, wifi_ctrl_recv, char *, size_t *)
FORWARD_2(int, wifi_wait_on_socket, char *, size_t *)
FORWARD_2(int, wifi_wait_for_event, char *, size_t)
FORWARD_0(void, wifi_close_sockets)
FORWARD_0(void, wifi_close_supplicant_connection)
FORWARD_2(int, wifi_start_supplicant, int, const char *)
FORWARD_0(void, wifi_close_hostapd_connection)
FORWARD_3(int, wifi_command, const char *, char *, size_t *)

/* OEM Specific Wi-Fi / BT Functions */
FORWARD_1(int, wifi_read_macaddress, char *)
FORWARD_0(int, wifi_get_module_version)
FORWARD_0(int, wifi_check_module_info)
FORWARD_0(int, wifi_load_driver_RFTestMode)
FORWARD_0(int, wifi_set_CWStart)
FORWARD_0(int, wifi_set_CWStop)
FORWARD_0(int, wifi_setPtestTxEnd)
FORWARD_0(int, wifi_setPtestTxInit)
FORWARD_0(int, wifi_setPtestRxInit)
FORWARD_0(int, wifi_resetPtestRxCount)
FORWARD_0(int, wifi_getPtestRxCount)
FORWARD_0(int, wifi_setPtestRxEnd)
FORWARD_1(int, wifi_ap_set_hidden_ssid, int)
FORWARD_1(int, wifi_setCountryCode, const char *)

/* BSP / Audio Info */
FORWARD_1(int, bsp_version_get_bt_version, char *)
FORWARD_0(int, bsp_version_get_bt_adc)
FORWARD_3(int, daudio_adc_ioctl, int, int, void *)
FORWARD_0(int, enable_802_11h)
FORWARD_0(int, FrequencyAccuracy_Stop)
FORWARD_0(int, pkteng_stop_tx)
FORWARD_0(int, FrequencyAccuracy_start)
FORWARD_0(int, FrequencyAccuracy5G_start)
FORWARD_0(int, pkteng_init_tx_normal)
FORWARD_0(int, pkteng_init_rx_normal)
FORWARD_0(int, pkteng_reset_rx)
FORWARD_1(int, pkteng_count_rx_normal, void *)
FORWARD_1(int, set_hidden_ssid, int)
FORWARD_1(int, set_country_code, const char *)
FORWARD_2(int, wfa_snprintf, char *, const char *)
FORWARD_1(int, wl_cmd, const char *)
FORWARD_1(int, TxDataRate, int)
FORWARD_1(int, TxDataRate5G, int)
FORWARD_1(int, MCS_TxDataRate, int)
FORWARD_1(int, VHT_MCS_TxDataRate, int)
FORWARD_1(int, set_bandwidth, int)
FORWARD_1(int, set_ChannelNo, int)
FORWARD_1(int, enable_open_loop, int)
FORWARD_1(int, set_tx_gain, int)
FORWARD_1(int, set_band, int)
FORWARD_1(int, set_mac_address, const char *)
FORWARD_0(int, test)

/* QEMU fallback stubs */
FORWARD_0(int, qemu_check)
FORWARD_2(int, qemu_control_command, const char *, const char *)
FORWARD_1(int, qemu_channel_open, const char *)
FORWARD_3(int, qemu_command_format, char *, size_t, const char *)
FORWARD_2(int, qemu_control_query, const char *, char *)
FORWARD_0(int, qemu_start_tracing)
FORWARD_0(int, qemu_stop_tracing)
FORWARD_3(int, qemu_add_mapping, unsigned long, unsigned long, const char *)
FORWARD_1(int, qemu_remove_mapping, unsigned long)
