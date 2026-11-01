/*
 * Stand-in for the stock Broadcom module name on Gen5W (Korean V039).
 *
 * The stock Wi-Fi HAL (libhardware_legacy.so, left unchanged) loads Wi-Fi by
 * running insmod on /system/wifi/bcmdhd.ko, then checks /proc/modules for
 * "bcmdhd" and reads /sys/module/bcmdhd/parameters/mac_address_read. The dongle
 * package puts this module at that path. It drives no hardware: it only
 * succeeds once the USB dongle (ath9k_htc, loaded by the dongle service) has
 * created the wireless interface, so the stock HAL, supplicant and hostapd then
 * use that interface. Unloading it leaves the dongle driver alone.
 */
#include <linux/delay.h>
#include <linux/kernel.h>
#include <linux/module.h>
#include <linux/moduleparam.h>
#include <linux/netdevice.h>
#include <net/cfg80211.h>
#include <net/net_namespace.h>

/* Parameters the stock HAL passes; accepted so insmod succeeds, otherwise unused. */
static char *iface_name = "wlan0";
static char *firmware_path = "";
static char *nvram_path = "";
static char *clm_path = "";
static char mac_address_read[18];
module_param(iface_name, charp, 0444);
module_param(firmware_path, charp, 0644);
module_param(nvram_path, charp, 0444);
module_param(clm_path, charp, 0444);
module_param_string(mac_address_read, mac_address_read, sizeof(mac_address_read), 0444);

/* The dongle service loads the driver at boot and on hot-plug; allow it time. */
#define WAIT_STEPS 150
#define WAIT_MS 100

static struct net_device *find_wireless(const char *name)
{
	struct net_device *dev = dev_get_by_name(&init_net, name);

	if (dev && !dev->ieee80211_ptr) {
		dev_put(dev);
		dev = NULL;
	}
	return dev;
}

static int __init shim_init(void)
{
	const char *name = (iface_name && iface_name[0]) ? iface_name : "wlan0";
	struct net_device *dev = NULL;
	int i;

	for (i = 0; i < WAIT_STEPS && !(dev = find_wireless(name)); i++)
		msleep(WAIT_MS);
	if (!dev) {
		pr_info("gen5w-dongle: no USB Wi-Fi interface %s\n", name);
		return -ENODEV;
	}
	snprintf(mac_address_read, sizeof(mac_address_read), "%pM", dev->dev_addr);
	dev_put(dev);
	pr_info("gen5w-dongle: using USB Wi-Fi interface %s\n", name);
	return 0;
}

static void __exit shim_exit(void)
{
}

module_init(shim_init);
module_exit(shim_exit);
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("Gen5W USB Wi-Fi stand-in for the stock bcmdhd module name");
