#!/bin/bash

# Set variables
DRIVER_NAME=wifi
DRIVER_BUILD_DIR=$BUILD_DIR/$DRIVER_NAME
DRIVER_PACKAGE_DIR=$DRIVER_BUILD_DIR/package
DRIVER_OUTPUT_DIR=$WORK_DIR/$KERNEL_V

# Create necessary directories
mkdir -p $DRIVER_BUILD_DIR/linux-firmware $DRIVER_PACKAGE_DIR/lib/firmware
cd $DRIVER_BUILD_DIR

# Clone linux-firmware from GitHub
git clone --depth 1 https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git $DRIVER_BUILD_DIR/firmware-source
cd $DRIVER_BUILD_DIR/firmware-source
DRIVER_V_PKG=$KERNEL_V
$DRIVER_BUILD_DIR/firmware-source/copy-firmware.sh $DRIVER_BUILD_DIR/linux-firmware

# Copy firmware files
cd "$DRIVER_BUILD_DIR/linux-firmware"
for fw_dir in intel/iwlwifi ath9k_htc ath10k ath11k brcm mediatek rtlwifi rtw88 rtw89; do
    mkdir -p "$DRIVER_PACKAGE_DIR/lib/firmware/$(dirname "$fw_dir")"
    cp -a "$fw_dir" "$DRIVER_PACKAGE_DIR/lib/firmware/$(dirname "$fw_dir")/"
done
cp -a carl9170-1.fw rt2*.bin rt3*.bin "$DRIVER_PACKAGE_DIR/lib/firmware/" 2>/dev/null

# Create Debian control file
mkdir $DRIVER_PACKAGE_DIR/DEBIAN
cat > $DRIVER_PACKAGE_DIR/DEBIAN/control << EOF
Package: ${DRIVER_NAME}-driver
Version: $DRIVER_V_PKG
Architecture: amd64
Maintainer: ich777
Description: WiFi drivers and firmwares for MOS
EOF

# Create Debian package and md5 checksum
cd $DRIVER_BUILD_DIR
dpkg-deb --build package $DRIVER_OUTPUT_DIR/${DRIVER_NAME}_${DRIVER_V_PKG}-1+mos_amd64.deb

# Check filesize
MIN_SIZE=35000
PACKAGE_SIZE=$(stat -c%s $DRIVER_OUTPUT_DIR/${DRIVER_NAME}_${DRIVER_V_PKG}-1+mos_amd64.deb)
if [ "$PACKAGE_SIZE" -lt "$MIN_SIZE" ] ; then
  echo "ERROR: Package filesize to low, deleting package: ${DRIVER_NAME}_${DRIVER_V_PKG}-1+mos_amd64.deb"
  discord_push_notification "$DRIVER_NAME" "Compilation failed for $DRIVER_V_PKG" "1"
  rm -f $DRIVER_OUTPUT_DIR/${DRIVER_NAME}_${DRIVER_V_PKG}-1+mos_amd64.deb
else
  md5sum $DRIVER_OUTPUT_DIR/${DRIVER_NAME}_${DRIVER_V_PKG}-1+mos_amd64.deb | awk '{print $1}' > $DRIVER_OUTPUT_DIR/${DRIVER_NAME}_${DRIVER_V_PKG}-1+mos_amd64.deb.md5
fi
exit 0
