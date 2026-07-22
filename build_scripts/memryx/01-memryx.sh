#!/bin/bash

# Set variables
DRIVER_NAME=memryx
DRIVER_BUILD_DIR=$BUILD_DIR/$DRIVER_NAME
DRIVER_PACKAGE_DIR=$DRIVER_BUILD_DIR/package
DRIVER_OUTPUT_DIR=$WORK_DIR/$KERNEL_V

# Create driver build directory
mkdir $DRIVER_BUILD_DIR
cd $DRIVER_BUILD_DIR

# Clone from Github, checkout master and get latest commit date
git clone --depth 1 https://github.com/memryx/mx3_driver_pub $DRIVER_NAME
cd $DRIVER_BUILD_DIR/$DRIVER_NAME
git checkout v2.1.0
DRIVER_V_PKG="$(git log -1 --format="%cs" | sed 's/-//g')"

# Fix for missing headers
cp $DRIVER_BUILD_DIR/$DRIVER_NAME/kdriver/include/* $DRIVER_BUILD_DIR/$DRIVER_NAME/kdriver/linux/pcie/

# Build driver
cd $DRIVER_BUILD_DIR/$DRIVER_NAME/kdriver/linux/pcie
make -C $KERNEL_DIR M=$DRIVER_BUILD_DIR/$DRIVER_NAME/kdriver/linux/pcie \
  KCPPFLAGS="-I$DRIVER_BUILD_DIR/$DRIVER_NAME/kdriver/include" \
  EXTRA_CFLAGS="-I$DRIVER_BUILD_DIR/$DRIVER_NAME/kdriver/include" \
  modules -j$(nproc --all)

MODULE_BUILD=$?

# Copy Kernel module and compress it
mkdir -p $DRIVER_PACKAGE_DIR/lib/modules/${KERNEL_V}-mos/updates
cp $DRIVER_BUILD_DIR/$DRIVER_NAME/kdriver/linux/pcie/memx_cascade_plus_pcie.ko $DRIVER_PACKAGE_DIR/lib/modules/${KERNEL_V}-mos/updates/

while read -r line
do
  xz --check=crc32 --lzma2 $line
done < <(find $DRIVER_PACKAGE_DIR/lib/modules/${KERNEL_V}-mos/updates -name "*.ko")

# Add firmware
mkdir -p $DRIVER_PACKAGE_DIR/lib/firmware/
cp $DRIVER_BUILD_DIR/$DRIVER_NAME/firmware/* $DRIVER_PACKAGE_DIR/lib/firmware/
rm -rf $DRIVER_PACKAGE_DIR/lib/firmware/*.md

# Download install script
wget -O $DRIVER_BUILD_DIR/install.sh "https://developer.memryx.com/deb/install_2p1.sh"

# Extract files from install script
ARCHIVE="$(awk '/^__ARCHIVE_SECTION__/ {print NR + 1; exit 0; }' $DRIVER_BUILD_DIR/install.sh)"
mkdir -p $DRIVER_BUILD_DIR/mxa_manager
tail -n+$ARCHIVE $DRIVER_BUILD_DIR/install.sh | tar xJ -C $DRIVER_BUILD_DIR/mxa_manager
unset ARCHIVE

# Remove all unnecessary files and copy over files
rm -rf $DRIVER_BUILD_DIR/mxa_manager/x86_64/lib/firmware \
  $DRIVER_BUILD_DIR/mxa_manager/x86_64/lib/systemd \
  $DRIVER_BUILD_DIR/mxa_manager/x86_64/usr/include \
  $DRIVER_BUILD_DIR/mxa_manager/x86_64/usr/src \
  $DRIVER_BUILD_DIR/mxa_manager/x86_64/opt \
  $DRIVER_BUILD_DIR/mxa_manager/x86_64/etc/ld.so.conf.d \
  $DRIVER_BUILD_DIR/mxa_manager/x86_64/etc/modules-load.d

find $DRIVER_BUILD_DIR/mxa_manager/x86_64 -type f \( -name "*.h" -o -name "*.a" -o -name "*.pc" -o -name "*.cmake" \) -delete
find $DRIVER_BUILD_DIR/mxa_manager/x86_64 -type d -empty -delete

cp -R $DRIVER_BUILD_DIR/mxa_manager/x86_64/* $DRIVER_PACKAGE_DIR/

# Add libgomp1
cd $DRIVER_BUILD_DIR
apt-get update
apt-get -y download libgomp1 || true
dpkg --instdir=$DRIVER_PACKAGE_DIR/ -i $DRIVER_BUILD_DIR/libgomp1_*.deb

# Create Debian control file
mkdir $DRIVER_PACKAGE_DIR/DEBIAN
cat > $DRIVER_PACKAGE_DIR/DEBIAN/control << EOF
Package: ${DRIVER_NAME}-driver
Version: $DRIVER_V_PKG
Architecture: amd64
Maintainer: ich777
Description: MemryX drivers for MOS
EOF

# Create Debian package and md5 checksum
cd $DRIVER_BUILD_DIR
dpkg-deb --build package $DRIVER_OUTPUT_DIR/${DRIVER_NAME}_${DRIVER_V_PKG}-1+mos_amd64.deb

# Check filesize - depending if module build was successful
if [ "$MODULE_BUILD" = "0" ] ; then
  MIN_SIZE=950000
else
  MIN_SIZE=9999999999
fi
PACKAGE_SIZE=$(stat -c%s $DRIVER_OUTPUT_DIR/${DRIVER_NAME}_${DRIVER_V_PKG}-1+mos_amd64.deb)
if [ "$PACKAGE_SIZE" -lt "$MIN_SIZE" ] ; then
  echo "ERROR: Package filesize to low, deleting package: ${DRIVER_NAME}_${DRIVER_V_PKG}-1+mos_amd64.deb"
  discord_push_notification "$DRIVER_NAME" "Compilation failed for $DRIVER_V_PKG" "1"
  rm -f $DRIVER_OUTPUT_DIR/${DRIVER_NAME}_${DRIVER_V_PKG}-1+mos_amd64.deb
else
  md5sum $DRIVER_OUTPUT_DIR/${DRIVER_NAME}_${DRIVER_V_PKG}-1+mos_amd64.deb | awk '{print $1}' > $DRIVER_OUTPUT_DIR/${DRIVER_NAME}_${DRIVER_V_PKG}-1+mos_amd64.deb.md5
fi
exit 0
