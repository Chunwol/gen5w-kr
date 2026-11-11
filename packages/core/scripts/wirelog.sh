#!/system/bin/sh
# Wireless-only Android log (2 x 5 MiB). The full ring in logring.sh covers only
# a few minutes on this unit, so a failed CarPlay attempt is often gone before
# the log is saved. These tags log little, so this file covers hours.
HOLD_SCRIPT=${0%/*}/install-hold.sh
. "$HOLD_SCRIPT"
install_hold_wait
LOGRING_FILE=wireless.txt
LOGRING_FILTER='Gen5wWireless:V gen5w-wireless:V Gen5wDrive:S System.err:V JNIHelp:V AndroidRuntime:E WifiService:V WifiStateMachine:V WifiHW:V hostapd:V wpa_supplicant:V SoftapController:V NetworkManagementService:V PhoneProjection:V Iap2Service:V CarPlay_:V DiPOManager:V BTCMService:V HfDeviceBTCMSppApi:D BluetoothAdapter:V dnsmasq:V BTCMStateMachine:V BluetoothHfDevice:V HfDeviceService:V A2dpStateMachine:V bt-btif:W iAP2:V IAP2:V Tethering:V TetherController:V WifiSettings:V *:S'
. "${0%/*}/logring.sh"
