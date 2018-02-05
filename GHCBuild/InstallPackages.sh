#!/bin/sh

#  InstallPackages.sh
#  GHCBuild
#
#  Created by Manuel M T Chakravarty on 07.12.16.
#  Copyright © [2016..2018] Manuel M T Chakravarty. All rights reserved.

GHCBASE=$CONFIGURATION_BUILD_DIR/$CONTENTS_FOLDER_PATH/usr
GHCBIN=$GHCBASE/bin
GHC_WRAPPER=`pwd`/GHCBuild/ghc-dylib-rpath-wrapper.sh
CC_WRAPPER=`pwd`/GHCBuild/cc-dylib-rpath-wrapper.sh

GHC_VERSION=`$GHCBIN/ghc --numeric-version`

GHCLIB=$GHCBASE/lib/ghc-${GHC_VERSION}
GHCSHARE=$GHCBASE/share

echo "Using --package-db=$GHCLIB/package.conf.d"

# Install further packages
PKGS=`cat $SOURCE_ROOT/GHCBuild/extra-packages`
if [ $CONFIGURATION = "Debug" ];
then
  EXTRA_ARGS="$EXTRA_ARGS --disable-documentation"
else
  EXTRA_ARGS="$EXTRA_ARGS --with-haddock=$GHCBIN/haddock"
fi

echo "/Library/Haskell/bin/cabal --config-file=$SOURCE_ROOT/GHCBuild/cabal.config update"
/Library/Haskell/bin/cabal --config-file=$SOURCE_ROOT/GHCBuild/cabal.config update

# Current cabal version doesn't let us leave out the global or user package DB. We
# must use --reinstall to avoid that an existing package in the global or user DB with
# the same version suppresses the installation.
CABAL_CMD="/Library/Haskell/bin/cabal --config-file=$SOURCE_ROOT/GHCBuild/cabal.config install -j --prefix=$GHCLIB --bindir=$GHCLIB/bin --libdir=$GHCLIB --libexecdir=$GHCLIB/libexec --datadir=$GHCSHARE --package-db=$GHCLIB/package.conf.d --with-compiler=$GHC_WRAPPER --with-hc-pkg=$GHCBIN/ghc-pkg --with-alex=/Library/Haskell/bin/alex --with-happy=/Library/Haskell/bin/happy --with-hsc2hs=$GHCBIN/hsc2hs --allow-newer --ghc-option=-optl-Wl,-headerpad_max_install_names --ghc-option=-pgml${CC_WRAPPER} $EXTRA_ARGS"
echo "$CABAL_CMD <PACKAGE LIST>"
$CABAL_CMD $PKGS

for path in `otool -l $GHCLIB/bin/cpphs | grep ' path ' | grep DerivedData | cut -d ' ' -f 11`; do
  install_name_tool -delete_rpath $path $GHCLIB/bin/cpphs
  install_name_tool -add_rpath "@loader_path/../`basename $path`" $GHCLIB/bin/cpphs
done

# We build the executables separately, so they already get the RPATHs and names of the relocatable libs.
$CABAL_CMD alex happy cabal-install c2hs

# Remove absolute RPATHs embedded in the binaries
BINS="alex cabal happy c2hs"
for BIN in $BINS; do
  for path in `otool -l $GHCLIB/bin/$BIN | grep ' path ' | grep DerivedData | cut -d ' ' -f 11`; do
    install_name_tool -delete_rpath $path $GHCLIB/bin/$BIN
  done
done

echo "Download stack 1.5.1"
curl -fSL https://github.com/commercialhaskell/stack/releases/download/v1.5.1/stack-1.5.1-linux-x86_64-static.tar.gz -o ${TARGET_TEMP_DIR}/stack.tar.gz
tar --strip-components 1 -C ${GHCBIN} -xzf ${TARGET_TEMP_DIR}/stack.tar.gz stack-1.5.1-linux-x86_64-static/stack

# We don't want sample etc binaries of library packages.
rm -f $GHCLIB/bin/operational-TicTacToe
rm -f $GHCLIB/bin/aeson-pretty
rm -f $GHCLIB/bin/mkReadme
