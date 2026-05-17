#!/bin/bash

# Set variables
DRIVER_NAME=tbs
DRIVER_BUILD_DIR=$BUILD_DIR/$DRIVER_NAME
DRIVER_PACKAGE_DIR=$DRIVER_BUILD_DIR/package
DRIVER_OUTPUT_DIR=$WORK_DIR/$KERNEL_V

# Create driver build directory
mkdir $DRIVER_BUILD_DIR
cd $DRIVER_BUILD_DIR

# Get newest version from TBS and construct URL
BASE_URL="https://www.tbsiptv.com/download/common/"
LATEST_FILE=$(curl -s 'https://www.tbsiptv.com/index.php?route=product/download/search&dkeyword=Linux+Driver+Beta' | grep -oE 'tbsdvb_v[0-9]+\.tar\.bz2')
FULL_URL="${BASE_URL}${LATEST_FILE}"
DRIVER_V_PKG="$(echo "$LATEST_FILE" | cut -d'_' -f2 | cut -d'.' -f1 | tr -d 'v')"

# Download latest version
wget -O $DRIVER_BUILD_DIR/tbs.tar.bz2 "$FULL_URL"
tar -C $DRIVER_BUILD_DIR -xf $DRIVER_BUILD_DIR/tbs.tar.bz2
cd $DRIVER_BUILD_DIR/tbsdvb


# Build driver and install modules to package dir
make -j$(nproc --all) CONFIG_DVB_STB6100=m KCFLAGS="-DCONFIG_MEDIA_TUNER_TDA18271_MODULE=1 -DCONFIG_MEDIA_TUNER_TDA8290_MODULE=1 -DCONFIG_DVB_STV6110x_MODULE=1 -DCONFIG_DVB_STV6111_MODULE=1" KDIR=$KERNEL_DIR
make install -j$(nproc --all) MDIR=$DRIVER_PACKAGE_DIR CONFIG_DVB_STB6100=m KCFLAGS="-DCONFIG_MEDIA_TUNER_TDA18271_MODULE=1 -DCONFIG_MEDIA_TUNER_TDA8290_MODULE=1 -DCONFIG_DVB_STV6110x_MODULE=1 -DCONFIG_DVB_STV6111_MODULE=1"

# Add License
# No license in package

# Add Firmware files
mkdir -p $DRIVER_PACKAGE_DIR/lib/firmware
FIRMWARE_ARCHIVE=$(find "$DRIVER_BUILD_DIR/tbsdvb" -maxdepth 1 -name 'tbs-tuner-firmwares*.tar.bz2')
tar  -C $DRIVER_PACKAGE_DIR/lib/firmware/ -xf $FIRMWARE_ARCHIVE

# Remove unecessary filese from modules directory
cd $DRIVER_PACKAGE_DIR/lib/modules/${KERNEL_V}-mos
rm * 2>/dev/null

# Create Debian control file
mkdir $DRIVER_PACKAGE_DIR/DEBIAN
cat > $DRIVER_PACKAGE_DIR/DEBIAN/control << EOF
Package: $DRIVER_NAME
Version: $DRIVER_V_PKG
Architecture: amd64
Maintainer: ich777
Description: TBS drivers for MOS
EOF

# Create Debian package and md5 checksum
cd $DRIVER_BUILD_DIR
dpkg-deb --build package $DRIVER_OUTPUT_DIR/dvb-${DRIVER_NAME}_${DRIVER_V_PKG}-1+mos_amd64.deb

# Check filesize
MIN_SIZE=950000
PACKAGE_SIZE=$(stat -c%s $DRIVER_OUTPUT_DIR/dvb-${DRIVER_NAME}_${DRIVER_V_PKG}-1+mos_amd64.deb)
if [ "$PACKAGE_SIZE" -lt "$MIN_SIZE" ] ; then
  echo "ERROR: Package filesize to low, deleting package: dvb-${DRIVER_NAME}_${DRIVER_V_PKG}-1+mos_amd64.deb"
  discord_push_notification "$DRIVER_NAME" "Compilation failed for $DRIVER_V_PKG" "1"
  rm -f $DRIVER_OUTPUT_DIR/dvb-${DRIVER_NAME}_${DRIVER_V_PKG}-1+mos_amd64.deb
else
  md5sum $DRIVER_OUTPUT_DIR/dvb-${DRIVER_NAME}_${DRIVER_V_PKG}-1+mos_amd64.deb | awk '{print $1}' > $DRIVER_OUTPUT_DIR/dvb-${DRIVER_NAME}_${DRIVER_V_PKG}-1+mos_amd64.deb.md5
fi
exit 0
