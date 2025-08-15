#!/usr/bin/env zsh

#set -e
setopt nullglob
typeset -g UPDATE_DONE DEVICE BUILD IPSW_URL SYS DISK
UPDATE_DONE=0
DEVICE=""
BUILD=""
IPSW_URL=""
SYS=""
DISK=""

function check_root() {
  if [[ "$EUID" -ne "0" ]]; then
    sudo echo -n ""
    if [[ "$?" -ne "0" ]]; then
      echo "[!] Failed to execute as sudo!"
      exit -1
    fi
  fi
}

function check_apt_cmd() {
    if [[ -z "$(command -v apt-get)" ]]; then
      echo "[!] apt-get not installed!"
      exit -2
    fi
}

function apt_run_update() {
    if [[ ${UPDATE_DONE} != 1 ]]; then
      echo -n "[*] Running apt update... "
      sudo apt-get -yqq update 2>/dev/null 1>/dev/null || true
      echo "Done"
      UPDATE_DONE=1
    fi
}

function apt_run_install() {
    echo "[*] Running apt install \"$1\"..."
    sudo apt-get install $1
    res=$?
    echo "Done"
    if [[ "$res" -ne "0" ]]; then
      echo "[!] Installing \"$1\" failed!"
      exit -3
    fi
}

function check_ipsw_cmd() {
    if [[ -z "$(command -v ipsw)" ]]; then
      echo "[!] ipsw not installed!"
      check_apt_cmd
      apt_run_update
      apt_run_install ipsw
    fi
}

function check_hdik_cmd() {
    if [[ -z "$(command -v hdik)" ]]; then
      echo "[!] hdik command not found!"
      exit -4
    fi
}

function get_device() {
    res=$(sysctl hw.product)
    char=": "
    DEVICE="${res#*$char}"
    if [[ -z "${DEVICE}" ]]; then
      echo "[!] Failed to get device!"
      exit -15
    fi
    DEVICE=$(echo ${DEVICE} | tr -d '\n')
}

function get_build() {
    res=$(sysctl kern.osversion)
    char=": "
    BUILD="${res#*$char}"
    if [[ -z "${BUILD}" ]]; then
      echo "[!] Failed to get build!"
      exit -16
    fi
    BUILD=$(echo ${BUILD} | tr -d '\n')
}

function get_ipsw_url() {
  echo -n "[*] Getting IPSW URL... "
  IPSW_URL=$(ipsw download ipsw -d "${DEVICE}" -b "${BUILD}" -u | head -n1 | tr -d '\n')
  if [[ -z "${IPSW_URL}" ]]; then
    echo "[!] Failed to get IPSW URL for device: \"${DEVICE}\" build: \"${BUILD}\"!"
    exit -5
  fi
  echo "Done"
}

function cleanup_disks() {
    sudo umount -f /private/var/mnt/ 2>/dev/null 1>/dev/null
    sudo rm -rf /private/var/mnt/ 2>/dev/null 1>/dev/null
    sudo hdik -e ${DISK} 2>/dev/null 1>/dev/null
}

function cleanup_files() {
    rm -rf "${BUILD}__${DEVICE}"
}

function get_ipsw_system_dmg_path() {
  echo -n "[*] Getting IPSW System DMG path... "
  sys=$(ipsw info ${IPSW_URL} -r | grep SystemOS)
  char="= "
  SYS="${sys#*$char}"
  if [[ -z "${SYS}" ]]; then
    echo "[!] Failed to get System DMG path for device: \"${DEVICE}\" build: \"${BUILD}\"!"
    exit -6
  fi
  echo "Done"
}

function get_ipsw_system_dmg() {
    if [[ ! -f "${BUILD}__${DEVICE}/${SYS}" ]]; then
      echo "[*] This may take a while"
      echo "[*] Getting IPSW System DMG..."
      ipsw download ipsw -d "${DEVICE}" -b "${BUILD}" --pattern "${SYS}\$"
      if [[ ! -f "${BUILD}__${DEVICE}/${SYS}" ]]; then
        echo "[!] Failed to get System DMG for device: \"${DEVICE}\" build: \"${BUILD}\"!"
        exit -7
      fi
      echo "Done"
    fi
}

function hdik_create_disk() {
    echo -n "[*] Creating disk node... "
    res=$(sudo hdik "${BUILD}__${DEVICE}/${SYS}")
    if [[ "$?" -ne "0" || -z "${res}" ]]; then
      echo "[!] Failed to create disk node for \"${BUILD}__${DEVICE}/${SYS}\"!"
      exit -8
    fi
    res=$(echo ${res} | tail -n1)
    char=" "
    res=${res%%$char*}
    DISK=$(echo ${res} | tr -d '\n')
    echo "Done"
}

function mount_disk() {
    echo -n "[*] Mounting disk... "
    sudo mkdir /private/var/mnt/ 2>/dev/null
    if [[ -z "$(sudo stat /private/var/mnt/)" ]]; then
      echo "[!] Failed to create mountpoint \"/private/var/mnt/\" for \"${DISK}\"!"
      cleanup_disks
      exit -9
    fi
    sudo mount -t apfs -o ro ${DISK} "/private/var/mnt/"
    if [[ "$?" -ne "0" ]]; then
      echo "[!] Failed to mount \"${DISK}\" at \"/private/var/mnt/\"!"
      exit -10
    fi
    echo "Done"
}

function check_mount() {
    files=("/private/var/mnt/System/Library/Caches/com.apple.dyld/dyld_shared_cache_arm64*")
    if [[ -z ${files} ]]; then
      echo "[!] Failed to find \"/private/var/mnt/System/Library/Caches/com.apple.dyld/dyld_shared_cache_arm64*\"!"
      cleanup_disks
      exit -11
    fi
}

function install_sharedcache() {
    echo "[*] This may take a while"
    echo -n "[*] Installing shared_cache... "
    sudo cp -a /private/var/mnt/System/Library/Caches/com.apple.dyld /var/jb/basebin/.fakelib/shared_cache
    files=("/var/jb/basebin/.fakelib/shared_cachedyld_shared_cache_arm64*")
    if [[ -z ${files} ]]; then
      echo "[!] Failed to install shared cached at \"/var/jb/basebin/.fakelib/shared_cache/dyld_shared_cache_arm64*\"!"
      cleanup_disks
      exit -12
    fi
    sudo chown -R root:admin /var/jb/basebin/.fakelib/shared_cache
    if [[ "$?" -ne "0" ]]; then
      echo "[!] Failed to chown shared cache at \"/var/jb/basebin/.fakelib/shared_cache/dyld_shared_cache_arm64*\"!"
      cleanup_disks
      exit -13
    fi
    sudo chmod -R 0755 /var/jb/basebin/.fakelib/shared_cache
    if [[ "$?" -ne "0" ]]; then
      echo "[!] Failed to chmod shared cache at \"/var/jb/basebin/.fakelib/shared_cache/dyld_shared_cache_arm64*\"!"
      cleanup_disks
      exit -14
    fi
    echo "Done"
}

check_root
check_ipsw_cmd
check_hdik_cmd
get_device
get_build
get_ipsw_url
get_ipsw_system_dmg_path
get_ipsw_system_dmg
hdik_create_disk
mount_disk
check_mount
install_sharedcache
cleanup_disks
cleanup_files
