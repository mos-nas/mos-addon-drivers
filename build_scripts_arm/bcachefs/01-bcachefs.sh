#!/bin/bash

# Set variables
DRIVER_NAME=bcachefs
DRIVER_BUILD_DIR=$BUILD_DIR/$DRIVER_NAME
DRIVER_PACKAGE_DIR=$DRIVER_BUILD_DIR/package
DRIVER_OUTPUT_DIR=$WORK_DIR/$KERNEL_V

# Create driver build directory
mkdir $DRIVER_BUILD_DIR
cd $DRIVER_BUILD_DIR

# Clone bcachefs from Github, checkout and get commit date
git clone --depth=1 --filter=tree:0 --sparse https://github.com/koverstreet/bcachefs $DRIVER_NAME
cd $DRIVER_BUILD_DIR/$DRIVER_NAME
git sparse-checkout set fs/bcachefs
DRIVER_V_PKG="$(git log -1 --format="%cs" | sed 's/-//g')"

# Build driver
cd $DRIVER_BUILD_DIR/$DRIVER_NAME
make -C $KERNEL_DIR M=$PWD/fs/bcachefs CONFIG_BCACHEFS_FS=m modules modules -j$(nproc -all)

# Create directory, move modules to package directory and compress modules
mkdir -p $DRIVER_PACKAGE_DIR/lib/modules/${KERNEL_V}-mos/kernel/fs/bcachefs
cp $DRIVER_BUILD_DIR/$DRIVER_NAME/fs/bcachefs/bcachefs.ko $DRIVER_PACKAGE_DIR/lib/modules/${KERNEL_V}-mos/kernel/fs/bcachefs/
while read -r module
do
  xz --check=crc32 --lzma2 $module
done < <(find $DRIVER_PACKAGE_DIR/lib/modules/${KERNEL_V}-mos/kernel -name "*.ko")

# Add bcachefs-tools License
mkdir -p $DRIVER_PACKAGE_DIR/usr/share/doc/$DRIVER_NAME
cat $DRIVER_BUILD_DIR/$DRIVER_NAME/COPYING* >> $DRIVER_PACKAGE_DIR/usr/share/doc/$DRIVER_NAME/LICENSE

# Clone bcachefs-tools from Github
cd $DRIVER_BUILD_DIR
git clone https://github.com/koverstreet/bcachefs-tools $DRIVER_NAME-tools

# Build binaries
cd $DRIVER_BUILD_DIR/$DRIVER_NAME-tools
make PREFIX=/usr ROOT_SBINDIR=/sbin PKGCONFIG_UDEVDIR=/usr/lib/udev -j$(nproc --all)

# Create directory, move modules to package directory and compress modules
make install DESTDIR=$DRIVER_PACKAGE_DIR PREFIX=/usr ROOT_SBINDIR=/sbin PKGCONFIG_UDEVDIR=/usr/lib/udev -j$(nproc --all)
rm -rf $DRIVER_PACKAGE_DIR/usr/src

# Add bcachefs-tools License
mkdir -p $DRIVER_PACKAGE_DIR/usr/share/doc/$DRIVER_NAME-tools
cat $DRIVER_BUILD_DIR/$DRIVER_NAME-tools/COPYING* >> $DRIVER_PACKAGE_DIR/usr/share/doc/$DRIVER_NAME-tools/LICENSE

# Create Debian control file
mkdir $DRIVER_PACKAGE_DIR/DEBIAN
cat > $DRIVER_PACKAGE_DIR/DEBIAN/control << EOF
Package: ${DRIVER_NAME}-driver
Version: $DRIVER_V_PKG
Architecture: arm64
Maintainer: ich777
Description: $DRIVER_NAME driver and tools for MOS
EOF

# Create Debian package and md5 checksum
cd $DRIVER_BUILD_DIR
dpkg-deb --build package $DRIVER_OUTPUT_DIR/${DRIVER_NAME}_${DRIVER_V_PKG}-1+mos_arm64.deb

# Check filesize
MIN_SIZE=19000000
PACKAGE_SIZE=$(stat -c%s $DRIVER_OUTPUT_DIR/${DRIVER_NAME}_${DRIVER_V_PKG}-1+mos_arm64.deb)
if [ "$PACKAGE_SIZE" -lt "$MIN_SIZE" ] ; then
  echo "ERROR: Package filesize to low, deleting package: ${DRIVER_NAME}_${DRIVER_V_PKG}-1+mos_arm64.deb"
  discord_push_notification "$DRIVER_NAME" "Compilation failed for $DRIVER_V_PKG" "1"
  rm -f $DRIVER_OUTPUT_DIR/${DRIVER_NAME}_${DRIVER_V_PKG}-1+mos_arm64.deb
else
  md5sum $DRIVER_OUTPUT_DIR/${DRIVER_NAME}_${DRIVER_V_PKG}-1+mos_arm64.deb | awk '{print $1}' > $DRIVER_OUTPUT_DIR/${DRIVER_NAME}_${DRIVER_V_PKG}-1+mos_arm64.deb.md5
fi
exit 0
