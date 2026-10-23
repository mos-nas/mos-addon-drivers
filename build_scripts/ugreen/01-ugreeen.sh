#!/bin/bash

# Set variables
DRIVER_NAME=ugreen-leds
DRIVER_BUILD_DIR=$BUILD_DIR/$DRIVER_NAME
DRIVER_PACKAGE_DIR=$DRIVER_BUILD_DIR/package
DRIVER_OUTPUT_DIR=$WORK_DIR/$KERNEL_V

# Create driver build directory
mkdir -p $DRIVER_BUILD_DIR
cd $DRIVER_BUILD_DIR

# Clone from Github and get latest commit date
git clone --depth 1 https://github.com/miskcoo/ugreen_leds_controller $DRIVER_NAME
cd $DRIVER_BUILD_DIR/$DRIVER_NAME
DRIVER_V_PKG="$(git log -1 --format="%cs" | sed 's/-//g')"

# Build driver
cd $DRIVER_BUILD_DIR/$DRIVER_NAME/kmod
make -C $KERNEL_DIR M=$DRIVER_BUILD_DIR/$DRIVER_NAME/kmod modules

# Create directory, move modules to package directory and compress modules
mkdir -p $DRIVER_PACKAGE_DIR/lib/modules/${KERNEL_V}-mos/extra
cp $DRIVER_BUILD_DIR/$DRIVER_NAME/kmod/led-ugreen.ko $DRIVER_PACKAGE_DIR/lib/modules/${KERNEL_V}-mos/extra/
while read -r module
do
  xz --check=crc32 --lzma2 $module
done < <(find $DRIVER_PACKAGE_DIR/lib/modules/${KERNEL_V}-mos/extra -name "*.ko")

# Userspace helpers (kernel-independent, shipped with the driver like bcachefs-tools)
cd $DRIVER_BUILD_DIR/$DRIVER_NAME/scripts
g++ -std=c++17 -O2 -static blink-disk.cpp -o ugreen-blink-disk
g++ -std=c++17 -O2 -static check-standby.cpp -o ugreen-check-standby
strip ugreen-blink-disk ugreen-check-standby
mkdir -p $DRIVER_PACKAGE_DIR/usr/bin
cp ugreen-blink-disk ugreen-check-standby $DRIVER_PACKAGE_DIR/usr/bin/

# Add License
mkdir -p $DRIVER_PACKAGE_DIR/usr/share/doc/$DRIVER_NAME
cat $DRIVER_BUILD_DIR/$DRIVER_NAME/LICENSE* >> $DRIVER_PACKAGE_DIR/usr/share/doc/$DRIVER_NAME/LICENSE

# Create Debian control file
mkdir $DRIVER_PACKAGE_DIR/DEBIAN
cat > $DRIVER_PACKAGE_DIR/DEBIAN/control << EOF
Package: ${DRIVER_NAME}-driver
Version: $DRIVER_V_PKG
Architecture: amd64
Maintainer: ich777
Description: UGREEN NAS LED driver and binaries for MOS
EOF

# Create Debian package and md5 checksum
cd $DRIVER_BUILD_DIR
dpkg-deb --build package $DRIVER_OUTPUT_DIR/${DRIVER_NAME}_${DRIVER_V_PKG}-1+mos_amd64.deb

# Check filesize
MIN_SIZE=500000
PACKAGE_SIZE=$(stat -c%s $DRIVER_OUTPUT_DIR/${DRIVER_NAME}_${DRIVER_V_PKG}-1+mos_amd64.deb)
if [ "$PACKAGE_SIZE" -lt "$MIN_SIZE" ] ; then
  echo "ERROR: Package filesize to low, deleting package: ${DRIVER_NAME}_${DRIVER_V_PKG}-1+mos_amd64.deb"
  discord_push_notification "$DRIVER_NAME" "Compilation failed for $DRIVER_V_PKG" "1"
  rm -f $DRIVER_OUTPUT_DIR/${DRIVER_NAME}_${DRIVER_V_PKG}-1+mos_amd64.deb
else
  md5sum $DRIVER_OUTPUT_DIR/${DRIVER_NAME}_${DRIVER_V_PKG}-1+mos_amd64.deb | awk '{print $1}' > $DRIVER_OUTPUT_DIR/${DRIVER_NAME}_${DRIVER_V_PKG}-1+mos_amd64.deb.md5
fi
exit 0
