#!/bin/bash

build_dir="wasm"
use_threads=0
clean=0
reconfigure=0
ffopts=""

TOOLCHAIN_FILE=$EMSDK/upstream/emscripten/cmake/Modules/Platform/Emscripten.cmake

#configure usage
if test x"$1" = x"-h" -o x"$1" = x"--help" ; then
bdir_wasm_th=$build_dir"_thread"
    cat << EOF

Configure GPAC extra libs for Emscripten build. Available options:
--buildir=DIR          sets build directory name - default $build_dir for unthreaded builds and $bdir_wasm_th for threaded builds
--enable-threading     enables pthread support in libraries
--clean                clean before compiling
--reconfigure          reconfigures all packages
--help, -h             prints help

In non-threaded modes, libraries requiring pthread support are disabled

EOF
exit 1
fi
#end help


for opt do
    case "$opt" in
    --buildir=*) build_dir=`echo $opt | cut -d '=' -f 2`
        ;;
    --enable-threading) use_threads=1
        ;;
    --clean)
		clean=1
        ;;
    --reconfigure)
		reconfigure=1
		clean=1
        ;;
	*)	echo "unrecognize option $opt, ignoring"
	;;
	esac
done

if test $use_threads = 1 -a "$build_dir" = "wasm"; then
build_dir="wasm_thread"
fi

if test $use_threads = 1 ; then
CFLAGS="-sUSE_PTHREADS=1"
CXXFLAGS="-sUSE_PTHREADS=1"
fi

echo "CFLAGS $CFLAGS"

root_dir="`pwd`"

mkdir -p $build_dir
rm -rf $build_dir/lib
mkdir -p $build_dir/lib
rm -rf $build_dir/include
mkdir -p $build_dir/include

cd $build_dir
# Warning !! emconfigure uses EM_PKG_CONFIG_PATH to override PKG_CONFIG_PATH !!
prefix="`pwd`"
cd $root_dir

export EM_PKG_CONFIG_PATH=$prefix/lib/pkgconfig
echo "Building dependencies in $build_dir ($prefix) - threading enabled: $use_threads"

has_pck=0;

compile_package()
{
name=$1
subdir=$2
th_flags=$3
target=$4
ff_flag=$5
flags=$6

has_pck=0;

if [ ! -d $name ] ; then
	echo "$name not present"
	return;
fi

if [ "$th_flags" = "disabled" -a $use_threads = 0 ] ; then
	echo "$name cannot be compiled without threading support"
	return
fi

root="../.."
cd $name

if [ "$name" = "x265" ] ; then
cd source
fi

#out of tree build
mkdir -p "build"
cd "build"
mkdir -p $build_dir
cd $build_dir

if test "$subdir" != "" ; then
mkdir -p $subdir
cd $subdir
root="$root/.."
name="$name-$subdir"
fi

#reset config
if test $reconfigure = 1 ; then
	rm -f Makefile 2> /dev/null
fi

#configure
if [ ! -f Makefile ] ; then
	th_opt=""
	extra_cflags=1
	if test $use_threads = 0 ; then
		th_opt="$th_flags"
	fi

	#run autogen at root
	if [ -f "$root/autogen.sh" ] ; then
		dir=`pwd`
		cd $root
		emconfigure "./autogen.sh"
		cd $dir
		extra_cflags=0
	fi

	if [ -f "$root/configure" ] ; then
		#for autogen use CFLAGS env var, not --extra-cflags
		if [ $extra_cflags = 0 ] ; then
			emconfigure "$root/configure" $flags $th_opt --prefix="$prefix"
		else
			emconfigure "$root/configure" $flags $th_opt --prefix="$prefix" --extra-cflags="$CFLAGS"
		fi
		ret=$?
	elif [ -f "$root/CMakeLists.txt" ] ; then
		emmake cmake "$root" $flags $th_opt -DCMAKE_INSTALL_PREFIX="$prefix" -DCMAKE_CXX_FLAGS="$CXXFLAGS" -DCMAKE_C_FLAGS="$CFLAGS"
		ret=$?
	else
		ret=1
	fi

	if test $ret != 0 ; then
		cd $root_dir
		return $ret;
	fi
fi

#clean
if test $clean = 1 ; then
	emmake make clean
fi

#build
emmake make -j
ret=$?
if test $ret != 0 ; then
	cd $root_dir
	return $ret
fi

if test "$target" != "" ; then
	emmake make $target
fi
echo ""
echo "$name OK !"
echo ""
has_pck=1;

if test "$ff_flag" != "" ; then
	ffopts="$ffopts $ff_flag"
fi

cd $root_dir
}


function compile_x265()
{

if [ ! -d x265 ] ; then
	echo 'x265 not present'
	return;
fi
if [ $use_threads = 0 ] ; then
	echo 'x265 cannot be compiled without threading support'
	return;
fi

compile_package "x265" "12bit" ""  "" "" "-DCMAKE_TOOLCHAIN_FILE=$TOOLCHAIN_FILE -DENABLE_ASSEMBLY=OFF -DENABLE_LIBNUMA=OFF -DENABLE_SHARED=OFF -DENABLE_CLI=OFF -DEXTRA_LINK_FLAGS=-lpthread -DHIGH_BIT_DEPTH=ON -DEXPORT_C_API=OFF -DMAIN12=ON"
if [ $has_pck = 0 ] ; then
	return;
fi

compile_package "x265" "10bit" ""  "" "" "-DCMAKE_TOOLCHAIN_FILE=$TOOLCHAIN_FILE -DENABLE_ASSEMBLY=OFF -DENABLE_LIBNUMA=OFF -DENABLE_SHARED=OFF -DENABLE_CLI=OFF -DEXTRA_LINK_FLAGS=-lpthread -DHIGH_BIT_DEPTH=ON -DEXPORT_C_API=OFF"
if [ $has_pck = 0 ] ; then
	return;
fi

cd $root_dir
bdir=x265/source/build/$build_dir
mkdir $bdir/main

rm $bdir/main/libx265_main12.a
cp $bdir/12bit/libx265.a $bdir/main/libx265_main12.a

rm $bdir/main/libx265_main10.a
cp $bdir/10bit/libx265.a $bdir/main/libx265_main10.a

compile_package "x265" "main" ""  "" "" "-DCMAKE_TOOLCHAIN_FILE=$TOOLCHAIN_FILE -DENABLE_ASSEMBLY=OFF -DENABLE_LIBNUMA=OFF -DENABLE_SHARED=OFF -DENABLE_CLI=OFF -DEXTRA_LIB=\"x265_main10.a;x265_main12.a\" -DEXTRA_LINK_FLAGS=\"-L..,-lpthread\" -DLINKED_10BIT=ON -DLINKED_12BIT=ON"
if [ $has_pck = 0 ] ; then
	return;
fi

cd $root_dir
mv $bdir/main/libx265.a $bdir/main/libx265_main.a

cd $bdir/main

echo "Rebuilding libx265 archive"
emar -M <<EOF
CREATE libx265.a
ADDLIB libx265_main.a
ADDLIB libx265_main10.a
ADDLIB libx265_main12.a
SAVE
END
EOF

emmake make install

ffopts="$ffopts --enable-libx265"
echo "x265 OK"

cd $root_dir
}


#compile all our packages

compile_package "x264" "" "--disable-thread" "install-lib-static" "--enable-libx264" "--host=i686-gnu --enable-static --disable-cli --disable-asm"

compile_package "opus" "" "" "install" "--enable-libopus" "--host=i686-gnu --enable-shared=no --disable-asm --disable-rtcd --disable-doc --disable-extra-programs --disable-stack-protector"

compile_package "kvazaar" "" "disabled" "install" "--enable-libkvazaar" "--enable-shared=no --disable-asm"

compile_x265


#compile ffmpeg

if [ $use_threads = 1 ] ; then
#for pthread in configure for x265
ffopts="$ffopts --extra-libs=-lpthread"
fi

compile_package "ffmpeg" "" "--disable-pthreads --disable-w32threads --disable-os2threads" "install" "" "--target-os=none --arch=x86_32 --enable-cross-compile --disable-x86asm \
		--disable-inline-asm --disable-stripping --disable-programs --disable-swresample --disable-avdevice --disable-debug \
		--disable-doc --extra-cflags= --extra-cxxflags= --extra-ldflags= \
		--nm=emnm --ar=emar --as=llvm-as --ranlib=emranlib --cc=emcc --cxx=em++ --objcc=emcc --dep-cc=emcc \
		--enable-gpl $ffopts"
ret=$?
if test $ret != 0 ; then
echo "Failed to build FFMPEG and dependencies $ffopts"
cd $root_dir
exit $ret
fi

echo "FFMPEG build successfull with libraries $ffopts"


cat << EOF > $EM_PKG_CONFIG_PATH/libcaption.pc
prefix=$prefix
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include

Name: libcaption
Description: libcaption
Version: 1
Libs: -L\${libdir} -lcaption
Libs.private:
Cflags: -I\${includedir}
EOF

compile_package "libcaption" "" "" "install/local/fast" "" "-DENABLE_RE2C=OFF -DBUILD_EXAMPLES=OFF -DCMAKE_POSITION_INDEPENDENT_CODE=ON"


sed -i 's/git@github.com:/https:\/\/github.com\//'  mpeghdec/CMakeLists.txt

compile_package "mpeghdec" "" "" "" "" " -DCMAKE_BUILD_TYPE=Release -Dmpeghdec_BUILD_BINARIES=OFF -Dmpeghdec_BUILD_DOC=OFF"
cp -av mpeghdec/build/$build_dir/lib/*.a $build_dir/lib/
cp -av mpeghdec/include/mpeghdecoder.h $build_dir/include/

cat << EOF > $EM_PKG_CONFIG_PATH/mpeghdec.pc
prefix=$prefix
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include

Name: mpeghdec
Description: mpeghdec
Version: 1
Libs: -L\${libdir} -lMpeghDec -lMpegTPDec -lPCMutils -lIGFdec -lArithCoding -lFormatConverter -lgVBAPRenderer -lDRCdec -lUIManager -lSYS -lFDK -lm
Libs.private:
Cflags: -I\${includedir}
EOF


pushd $root_dir/libcaca
autoreconf -i
emconfigure ./configure  --prefix="$prefix" --disable-doc --disable-slang --disable-java --disable-csharp --disable-ruby --disable-imlib2  --disable-x11 --disable-vga
pushd caca
make -j4
make install
popd
popd
