#!/bin/bash

# Set variables
DRIVER_NAME=it87
DRIVER_BUILD_DIR=$BUILD_DIR/$DRIVER_NAME
DRIVER_PACKAGE_DIR=$DRIVER_BUILD_DIR/package
DRIVER_OUTPUT_DIR=$WORK_DIR/$KERNEL_V

# Create driver build directory
mkdir $DRIVER_BUILD_DIR
cd $DRIVER_BUILD_DIR

# Clone from Github, checkout master and get latest commit date
git clone --depth 1 https://github.com/frankcrawford/it87 $DRIVER_NAME
cd $DRIVER_BUILD_DIR/$DRIVER_NAME
git checkout master
DRIVER_V_PKG="$(git log -1 --format="%cs" | sed 's/-//g')"

# Build driver
make -j${CPU_COUNT} KERNEL_BUILD=$KERNEL_DIR

# Copy Kernel module and compress it
mkdir -p $DRIVER_PACKAGE_DIR/lib/modules/${KERNEL_V}-mos/kernel/drivers/hwmon/
cp $DRIVER_BUILD_DIR/$DRIVER_NAME/it87.ko $DRIVER_PACKAGE_DIR/lib/modules/${KERNEL_V}-mos/kernel/drivers/hwmon/

while read -r line
do
  xz --check=crc32 --lzma2 $line
done < <(find $DRIVER_PACKAGE_DIR/lib/modules/${KERNEL_V}-mos/kernel/drivers/hwmon -name "*.ko")

# Create Debian control file
mkdir $DRIVER_PACKAGE_DIR/DEBIAN
cat > $DRIVER_PACKAGE_DIR/DEBIAN/control << EOF
Package: ${DRIVER_NAME}-driver
Version: $DRIVER_V_PKG
Architecture: amd64
Maintainer: ich777
Description: $DRIVER_NAME drivers for MOS
EOF

# Create Debian package and md5 checksum
cd $DRIVER_BUILD_DIR
dpkg-deb --build package $DRIVER_OUTPUT_DIR/${DRIVER_NAME}_${DRIVER_V_PKG}-1+mos_amd64.deb

# Check filesize - depending if module build was successful
MIN_SIZE=1
PACKAGE_SIZE=$(stat -c%s $DRIVER_OUTPUT_DIR/${DRIVER_NAME}_${DRIVER_V_PKG}-1+mos_amd64.deb)
if [ "$PACKAGE_SIZE" -lt "$MIN_SIZE" ] ; then
  echo "ERROR: Package filesize to low, deleting package: ${DRIVER_NAME}_${DRIVER_V_PKG}-1+mos_amd64.deb"
  discord_push_notification "$DRIVER_NAME" "Compilation failed for $DRIVER_V_PKG" "1"
  rm -f $DRIVER_OUTPUT_DIR/${DRIVER_NAME}_${DRIVER_V_PKG}-1+mos_amd64.deb
else
  md5sum $DRIVER_OUTPUT_DIR/${DRIVER_NAME}_${DRIVER_V_PKG}-1+mos_amd64.deb | awk '{print $1}' > $DRIVER_OUTPUT_DIR/${DRIVER_NAME}_${DRIVER_V_PKG}-1+mos_amd64.deb.md5
fi
exit 0
