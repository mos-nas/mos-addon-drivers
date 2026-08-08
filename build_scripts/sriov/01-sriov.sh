#!/bin/bash

# Set variables
DRIVER_NAME=sriov
DRIVER_BUILD_DIR=$BUILD_DIR/$DRIVER_NAME
DRIVER_PACKAGE_DIR=$DRIVER_BUILD_DIR/package
DRIVER_OUTPUT_DIR=$WORK_DIR/$KERNEL_V

# Create driver build directory
mkdir $DRIVER_BUILD_DIR
cd $DRIVER_BUILD_DIR

# Clone from Github, checkout master and get latest commit date
git clone https://github.com/strongtz/i915-sriov-dkms sriov
cd $DRIVER_BUILD_DIR/sriov
if [[ "$KERNEL_V" == 6.18.* || "$KERNEL_V" == 6.19.* ]]; then
  git checkout kernel-v6.19
else
  git checkout master
fi
DRIVER_V_PKG="$(git log -1 --format="%cs" | sed 's/-//g')"

# Build driver and install modules to package dir
make -j$(nproc --all) M=$DRIVER_BUILD_DIR/sriov -C $KERNEL_DIR

# Create directory, move modules to package directory and compress modules
mkdir -p $DRIVER_PACKAGE_DIR/lib/modules/${KERNEL_V}-mos/kernel/drivers/gpu/drm/{i915,xe} $DRIVER_PACKAGE_DIR/lib/modules/${KERNEL_V}-mos/updates/compat
cp $DRIVER_BUILD_DIR/sriov/drivers/gpu/drm/i915/*.ko $DRIVER_PACKAGE_DIR/lib/modules/${KERNEL_V}-mos/kernel/drivers/gpu/drm/i915/
cp $DRIVER_BUILD_DIR/sriov/drivers/gpu/drm/xe/xe.ko $DRIVER_PACKAGE_DIR/lib/modules/${KERNEL_V}-mos/kernel/drivers/gpu/drm/xe/
cp $DRIVER_BUILD_DIR/sriov/compat/intel_sriov_compat.ko $DRIVER_PACKAGE_DIR/lib/modules/${KERNEL_V}-mos/updates/compat/intel_sriov_compat.ko
while read -r module
do
  xz --check=crc32 --lzma2 $module
done < <(find $DRIVER_PACKAGE_DIR/lib/modules/${KERNEL_V}-mos/ -name "*.ko")

# Add License
mkdir -p $DRIVER_PACKAGE_DIR/usr/share/doc/$DRIVER_NAME
cat $DRIVER_BUILD_DIR/sriov/COPYING* >> $DRIVER_PACKAGE_DIR/usr/share/doc/$DRIVER_NAME/LICENSE

# Create Debian control file
mkdir $DRIVER_PACKAGE_DIR/DEBIAN
cat > $DRIVER_PACKAGE_DIR/DEBIAN/control << EOF
Package: $DRIVER_NAME
Version: $DRIVER_V_PKG
Architecture: amd64
Maintainer: ich777
Description: $DRIVER_NAME drivers for MOS
EOF

# Create Debian package and md5 checksum
cd $DRIVER_BUILD_DIR
dpkg-deb --build package $DRIVER_OUTPUT_DIR/${DRIVER_NAME}_${DRIVER_V_PKG}-1+mos_amd64.deb

# Check filesize
MIN_SIZE=2000000
PACKAGE_SIZE=$(stat -c%s $DRIVER_OUTPUT_DIR/${DRIVER_NAME}_${DRIVER_V_PKG}-1+mos_amd64.deb)
if [ "$PACKAGE_SIZE" -lt "$MIN_SIZE" ] ; then
  echo "ERROR: Package filesize to low, deleting package: ${DRIVER_NAME}_${DRIVER_V_PKG}-1+mos_amd64.deb"
  discord_push_notification "$DRIVER_NAME" "Compilation failed for $DRIVER_V_PKG" "1"
  rm -f $DRIVER_OUTPUT_DIR/${DRIVER_NAME}_${DRIVER_V_PKG}-1+mos_amd64.deb
else
  md5sum $DRIVER_OUTPUT_DIR/${DRIVER_NAME}_${DRIVER_V_PKG}-1+mos_amd64.deb | awk '{print $1}' > $DRIVER_OUTPUT_DIR/${DRIVER_NAME}_${DRIVER_V_PKG}-1+mos_amd64.deb.md5
fi
exit 0
