#!/bin/bash

# Subsurface AppImage build script by Simon Peter
# The purpose of this script is to build the current version of Subsurface (at Qt app) from git, and bundle it
# together with all required runtime dependencies that cannot reasonably be expected to be part of the operating
# system into an AppImage. An AppImage is an ISO file that contains an app and everything that is needed
# to run the app plus a small executable header that mounts the image and runs the app on the target system.
# See http://portablelinuxapps.org/docs/1.0/AppImageKit.pdf for more information.

# Resulting AppImage is known to work on:
# CentOS Linux 7 (Core) - CentOS-7.0-1406-x86_64-GnomeLive.iso
# CentOS Linux release 7.1.1503 (Core) - CentOS-7-x86_64-LiveGNOME-1503.iso
# Fedora 22 (Twenty Two) - Fedora-Live-Workstation-x86_64-22-3.iso
# Ubuntu 15.04 (Vivid Vervet) - ubuntu-15.04-desktop-amd64.iso
# Ubuntu 14.04.1 LTS (Trusty Tahr) - ubuntu-14.04.1-desktop-amd64.iso
# Xubuntu 15.10 (Wily Werewolf) - xubuntu-15.10-desktop-amd64.iso
# openSUSE Tumbleweed (20151012) - openSUSE-Tumbleweed-GNOME-Live-x86_64-Current.iso
# Antergos - antergos-2014.08.07-x86_64.iso
# elementary OS 0.3 Freya - elementary_OS_0.3_freya_amd64.iso

# Halt on errors
set -e

# Be verbose
set -x

# Determine which architecture should be built
if [[ "$1" = "i386" ||  "$1" = "amd64" ]] ; then
	ARCH=$1
else
	echo "Call me with either i386 or amd64"
	exit 1
fi

# Determine whether upload to github-releases should be attempted
if [[ "$2" = "-travis" ]] ; then
	UPLOAD_TO_TRAVIS=1
	shift
else
	UPLOAD_TO_TRAVIS=0
fi

# Enable universe
grep -r "main universe" /etc/apt/sources.list || sudo sed -i -e "s| main| main universe|g" /etc/apt/sources.list

# Install dependencies
sudo apt-get update -q # Make sure universe is enabled
sudo apt-get --yes --force-yes install python-requests p7zip-full pax-utils imagemagick  \
git g++ make autoconf libtool pkg-config \
libxml2-dev libxslt1-dev libzip-dev libsqlite3-dev libusb-1.0-0-dev libssh2-1-dev libcurl4-openssl-dev \
mesa-common-dev libgl1-mesa-dev libgstreamer-plugins-base0.10-0 libxcomposite1 python-software-properties \
libfuse-dev libglib2.0-dev libc6-dev binutils fuse

# Install newer gcc and g++ since cannot be compiled with the stock 4.6.3
sudo add-apt-repository -y ppa:ubuntu-toolchain-r/test
sudo apt-get -q update
sudo apt-get --yes --force-yes install g++-4.8 gcc-4.8
sudo update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-4.8 50
sudo update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-4.8 50
g++ --version
which g++
gcc --version
which gcc

# Install CMake 3.2.2 and Qt 5.5.x # https://github.com/vlc-qt/examples/blob/master/tools/ci/linux/install.sh
if [[ "$ARCH" = "amd64" ]] ; then
	wget --no-check-certificate -c https://www.cmake.org/files/v3.2/cmake-3.2.2-Linux-x86_64.tar.gz
fi
if [[ "$ARCH" = "i386" ]] ; then
	wget --no-check-certificate -c https://cmake.org/files/v3.2/cmake-3.2.2-Linux-i386.tar.gz
fi
tar xf cmake-*.tar.gz

# Quick and dirty way to download the latest Qt - is there an official one?
rm -f Updates.xml
if [[ "$ARCH" = "amd64" ]] ; then
	QT_URL=http://download.qt.io/online/qtsdkrepository/linux_x64/desktop/qt5_55
fi
if [[ "$ARCH" = "i386" ]] ; then
	QT_URL=http://download.qt.io/online/qtsdkrepository/linux_x86/desktop/qt5_55
fi
wget "$QT_URL/Updates.xml"
QTPACKAGES="qt5_essentials.7z qt5_addons.7z icu-linux-g.*?.7z qt5_qtscript.7z qt5_qtlocation.7z qt5_qtpositioning.7z"
for QTPACKAGE in $QTPACKAGES; do
  unset NAME V1 V2
  NAME=$(grep -Pzo "(?s)$QTPACKAGE" Updates.xml | head -n 1)
  V1=$(grep -Pzo "(?s)<PackageUpdate>.*?<Version>.*?<DownloadableArchives>.*?$QTPACKAGE.*?</PackageUpdate>" Updates.xml | grep "<Name>" | tail -n 1 | cut -d ">" -f 2 | cut -d "<" -f 1)
  V2=$(grep -Pzo "(?s)<PackageUpdate>.*?<Version>.*?<DownloadableArchives>.*?$QTPACKAGE.*?</PackageUpdate>" Updates.xml | grep "<Version>" | head -n 1 | cut -d ">" -f 2 | cut -d "<" -f 1)
  wget -c "$QT_URL/"$V1"/"$V2$NAME
done

# wget http://download.qt.io/online/qtsdkrepository/linux_x64/desktop/qt5_55/qt.55.gcc_64/5.5.0-2qt5_essentials.7z
# wget http://download.qt.io/online/qtsdkrepository/linux_x64/desktop/qt5_55/qt.55.gcc_64/5.5.0-2icu-linux-g++-Rhel6.6-x64.7z
# wget http://download.qt.io/online/qtsdkrepository/linux_x64/desktop/qt5_55/qt.55.gcc_64/5.5.0-2qt5_addons.7z
# wget http://download.qt.io/online/qtsdkrepository/linux_x64/desktop/qt5_55/qt.55.qtscript.gcc_64/5.5.0-0qt5_qtscript.7z
# wget http://download.qt.io/online/qtsdkrepository/linux_x64/desktop/qt5_55/qt.55.qtlocation.gcc_64/5.5.0-0qt5_qtlocation.7z

rm -rf $PWD/5.5/
find *.7z -exec 7z x -y {} >/dev/null \;

CMAKE_PATH=$(find $PWD/cmake-*/ -type d | head -n 1)bin
QT_PREFIX=$(find $PWD/5.5/gc*/ -type d | head -n 1)
export LD_LIBRARY_PATH=$QT_PREFIX/lib/:$LD_LIBRARY_PATH # Needed for bundling the libraries into AppDir below
export PATH=$CMAKE_PATH:$QT_PREFIX/bin/:$PATH # Needed at compile time to find Qt and cmake

# Build AppImageKit
if [ ! -d AppImageKit ] ; then
  git clone https://github.com/probonopd/AppImageKit.git
fi
cd AppImageKit/
git stash save
git pull --rebase
cmake .
make clean
make
cd ..

APP=Subsurface
rm -rf ./$APP/$APP.AppDir
mkdir -p ./$APP/$APP.AppDir
cd ./$APP

# Get latest subsurface project from git
if [ ! -d subsurface ] ; then
  git clone git://subsurface-divelog.org/subsurface
fi
cd subsurface/
git stash save
git pull --rebase
cd ..

# this is a bit hackish as the build.sh script isn't setup in
# the best possible way for us
mkdir -p $APP.AppDir/usr
INSTALL_ROOT=$(cd $APP.AppDir/usr; pwd)
sed -i "s|git://subsurface-divelog.org/marble|https://github.com/probonopd/marble.git|g" ./subsurface/scripts/build.sh
sed -i "s,INSTALL_ROOT=.*,INSTALL_ROOT=$INSTALL_ROOT," ./subsurface/scripts/build.sh
sed -i "s,cmake -DCMAKE_BUILD_TYPE=Debug.*,cmake -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=$INSTALL_ROOT .. \\\\," ./subsurface/scripts/build.sh
bash -ex ./subsurface/scripts/build.sh
( cd subsurface/build ; make install )

cp ./subsurface/subsurface.desktop $APP.AppDir/
cp ./subsurface/icons/subsurface-icon.png $APP.AppDir/
mogrify -resize 64x64 $APP.AppDir/subsurface-icon.png

# Bundle dependency libraries into the AppDir
cd $APP.AppDir/
cp ../../AppImageKit/AppRun .
chmod a+x AppRun
# FIXME: How to find out which subset of plugins is really needed? I used strace when running the binary
mkdir -p ./usr/lib/qt5/plugins/
cp -r ../../5.5/gc*/plugins/bearer ./usr/lib/qt5/plugins/
cp -r ../../5.5/gc*/plugins/iconengines ./usr/lib/qt5/plugins/
cp -r ../../5.5/gc*/plugins/imageformats ./usr/lib/qt5/plugins/
cp -r ../../5.5/gc*/plugins/platforminputcontexts ./usr/lib/qt5/plugins/
cp -r ../../5.5/gc*/plugins/platforms ./usr/lib/qt5/plugins/
cp -r ../../5.5/gc*/plugins/platformthemes ./usr/lib/qt5/plugins/
cp -r ../../5.5/gc*/plugins/sensors ./usr/lib/qt5/plugins/
cp -r ../../5.5/gc*/plugins/xcbglintegrations ./usr/lib/qt5/plugins/
cp -a ../../5.5/gc*/lib/libicu* usr/lib
export LD_LIBRARY_PATH=./usr/lib/:../../5.5/gc*/lib/:$LD_LIBRARY_PATH
ldd usr/bin/subsurface | grep "=>" | awk '{print $3}'  |  xargs -I '{}' cp -v '{}' ./usr/lib || true
ldd usr/lib/qt5/plugins/platforms/libqxcb.so | grep "=>" | awk '{print $3}'  |  xargs -I '{}' cp -v '{}' ./usr/lib || true

# The following are assumed to be part of the base system
# Segmentation faults can occur if some of these are left in the AppImage
rm usr/lib/libasn1.so.8 || true
rm usr/lib/libcom_err.so.2 || true
rm usr/lib/libcrypt.so.1 || true
rm usr/lib/libdl.so.2 || true
rm usr/lib/libexpat.so.1 || true
rm usr/lib/libfontconfig.so.1 || true
rm usr/lib/libgcc_s.so.1 || true
rm usr/lib/libglib-2.0.so.0 || true
rm usr/lib/libgpg-error.so.0 || true
rm usr/lib/libgssapi_krb5.so.2 || true
rm usr/lib/libgssapi.so.3 || true
rm usr/lib/libhcrypto.so.4 || true
rm usr/lib/libheimbase.so.1 || true
rm usr/lib/libheimntlm.so.0 || true
rm usr/lib/libhx509.so.5 || true
rm usr/lib/libICE.so.6 || true
rm usr/lib/libidn.so.11 || true
rm usr/lib/libk5crypto.so.3 || true
rm usr/lib/libkeyutils.so.1 || true
rm usr/lib/libkrb5.so.26 || true
rm usr/lib/libkrb5.so.3 || true
rm usr/lib/libkrb5support.so.0 || true
rm usr/lib/liblber-2.4.so.2 || true
rm usr/lib/libldap_r-2.4.so.2 || true
rm usr/lib/libm.so.6 || true
rm usr/lib/libp11-kit.so.0 || true
rm usr/lib/libpcre.so.3 || true
rm usr/lib/libpthread.so.0 || true
rm usr/lib/libresolv.so.2 || true
rm usr/lib/libroken.so.18 || true
rm usr/lib/librt.so.1 || true
rm usr/lib/libsasl2.so.2 || true
rm usr/lib/libSM.so.6 || true
rm usr/lib/libusb-1.0.so.0 || true
rm usr/lib/libuuid.so.1 || true
rm usr/lib/libwind.so.0 || true
rm usr/lib/libz.so.1 || true

# These seem to be available on most systems
rm libffi.so.6 libGL.so.1 libglapi.so.0 libxcb.so.1 libxcb-glx.so.0 || true

rm -r usr/lib/cmake || true
rm -r usr/lib/pkgconfig || true

rm usr/lib/libdivecomputer.a || true
rm usr/lib/libdivecomputer.la || true
rm usr/lib/libdivecomputer.so || true
rm usr/lib/libdivecomputer.so.0 || true
rm usr/lib/libdivecomputer.so.0.0.0 || true
rm usr/lib/libGrantlee_TextDocument.so || true
rm usr/lib/libGrantlee_TextDocument.so.5.0.0 || true
rm usr/lib/libssrfmarblewidget.so || true
rm usr/lib/subsurface || true
rm usr/lib/libstdc* usr/lib/libgobject* usr/lib/libX* usr/lib/libc.so.* || true

rm -r usr/include || true

rm usr/bin/universal || true
rm usr/bin/ostc-fwupdate || true
rm usr/bin/subsurface.debug || true

strip usr/bin/* usr/lib/* || true
# According to http://www.grantlee.org/apidox/using_and_deploying.html
# Grantlee looks for plugins in $QT_PLUGIN_DIR/grantlee/$grantleeversion/
mv ./usr/lib/grantlee/ ./usr/lib/qt5/plugins/
# Fix GDK_IS_PIXBUF errors on older distributions
find /lib -name libpng*.so.* -exec cp {} ./usr/lib/libpng16.so.16 \;
ln -sf ./libpng16.so.16 ./usr/lib/libpng15.so.15 # For Fedora 20
ln -sf ./libpng16.so.16 ./usr/lib/libpng14.so.14 # Just to be sure
ln -sf ./libpng16.so.16 ./usr/lib/libpng13.so.13 # Just to be sure
ln -sf ./libpng16.so.16 ./usr/lib/libpng12.so.12 # Just to be sure
find /usr/lib -name libfreetype.so.6 -exec cp {} usr/lib \; # For Fedora 20
ln -sf ./libpng16.so.16 ./usr/lib/libpng12.so.0 # For the bundled libfreetype.so.6
cd -
find $APP.AppDir/

# Figure out $VERSION
GITVERSION=$(cd subsurface ; git describe | sed -e 's/-g.*$// ; s/^v//')
GITREVISION=$(echo $GITVERSION | sed -e 's/.*-// ; s/.*\..*//')
VERSION=$(echo $GITVERSION | sed -e 's/-/./')
echo $VERSION

if [[ "$ARCH" = "amd64" ]] ; then
	APPIMAGE=$PWD/$APP"_"$VERSION"_x86_64.AppImage"
fi
if [[ "$ARCH" = "i386" ]] ; then
	APPIMAGE=$PWD/$APP"_"$VERSION"_i386.AppImage"
fi

# Convert the AppDir into an AppImage
rm -rf $APPIMAGE
../AppImageKit/AppImageAssistant.AppDir/package ./$APP.AppDir/ $APPIMAGE

ls -lh $APPIMAGE

# Upload from travis-ci to GitHub Releases
if [ "$UPLOAD_TO_TRAVIS" = "1" ] ; then
	cd ..
	wget -c https://raw.githubusercontent.com/probonopd/travis2github/master/travis2github.py
	wget -c https://raw.githubusercontent.com/probonopd/travis2github/master/magic.py
	python travis2github.py $APPIMAGE
fi
