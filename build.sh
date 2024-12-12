#!/bin/bash

TOPDIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

BUILD_SH=$TOPDIR/build.sh

CMAKE_COMMAND="cmake -DCMAKE_EXPORT_COMPILE_COMMANDS=1 --log-level=STATUS"

ALL_ARGS=("$@")
BUILD_ARGS=()
MAKE_ARGS=()
MAKE=make

echo "$0 ${ALL_ARGS[@]}"

function usage
{
  echo "Usage:"
  echo "./build.sh -h"
  echo "./build.sh init # install dependence"
  echo "./build.sh clean"
  echo "./build.sh [BuildType] [--make [MakeOptions]]"
  echo ""
  echo "OPTIONS:"
  echo "BuildType => debug(default), release"
  echo "MakeOptions => Options to make command, default: -j N"

  echo ""
  echo "Examples:"
  echo "# Init."
  echo "./build.sh init"
  echo ""
  echo "# Build by debug mode and make with -j24."
  echo "./build.sh debug --make -j24"
}


function parse_args
{
  make_start=false
  for arg in "${ALL_ARGS[@]}"; do
    if [[ "$arg" == "--make" ]]
    then
      make_start=true
    elif [[ $make_start == false ]]
    then
      BUILD_ARGS+=("$arg")
    else
      MAKE_ARGS+=("$arg")
    fi

  done
}

function do_init
{
    # Check if the build tools are installed
    tools=("gcc" "g++" "make" "cmake")
    check_status=0

    for tool in "${tools[@]}"; do
        if ! command -v $tool &> /dev/null; then
            check_status=1
            echo "$tool is not installed."
            break
        fi
    done

    if [ "$check_status" -eq 1 ]; then
        if grep -qsi "Ubuntu" /etc/os-release; then
            echo "Installing build-essential and cmake..."
            sudo apt update --fix-missing
            sudo apt install -y build-essential cmake
        else
            echo "Make sure you have a C++ compiler and CMake installed!"
            exit 1
        fi
    fi

    # Make sure the current directory is the root directory of the project
    cd "$TOPDIR" || exit 1

    # Load third party libraries
    third_party_dir="third_party"

    if [ ! -d "$third_party_dir" ]; then
        echo "Creating third_party directory..."
        mkdir "$third_party_dir"
    fi

    declare -A links

    links["jemalloc"]="https://github.com/jemalloc/jemalloc/releases/download/5.3.0/jemalloc-5.3.0.tar.bz2"
    links["boost"]="https://boostorg.jfrog.io/artifactory/main/release/1.86.0/source/boost_1_86_0_rc1.tar.gz"
    links["gflags"]="https://github.com/gflags/gflags/archive/refs/tags/v2.2.2.tar.gz"
    links["glog"]="https://github.com/google/glog/archive/refs/tags/v0.7.1.tar.gz"
    links["googletest"]="https://github.com/google/googletest/releases/download/v1.15.2/googletest-1.15.2.tar.gz"

    check_status=0
    for dep in "${!links[@]}"; do
        if [ -d "$third_party_dir/$dep" ]; then
            echo "$dep already exists. Skipping download."
            continue
        fi
        check_status=1
        link=${links[$dep]}
        filename=$(basename "$link")
        if [ -f "$third_party_dir/tmp/$filename" ]; then
            echo "$filename already exists. Skipping download."
        else
            echo "Downloading $link..."
            wget -P "$third_party_dir/tmp" "$link"
        fi
    done

    if [ "$check_status" -eq 0 ]; then
        echo "All dependencies are already downloaded and extracted."
    else
        compressed_files=($(find "$third_party_dir/tmp" -name "*.tar.*"))
        for file in "${compressed_files[@]}"; do
            echo "Extracting $file..."
            if [[ $file == *.tar.bz2 ]]; then
                tar -jxf "$file" -C "$third_party_dir/tmp"
            else
                tar -zxf "$file" -C "$third_party_dir/tmp"
            fi
        done

        folders=$(ls "$third_party_dir/tmp" | grep -v '\.tar\.\|.tar')
        for folder in $folders; do
            new_folder=$(echo "$folder" | sed 's/[^a-zA-Z]\+/\n/g' | head -n 1)
            if [ -d "$third_party_dir/$new_folder" ]; then
                echo "$new_folder already exists. Skipping extraction."
                continue
            fi
            mv "$third_party_dir/tmp/$folder" "$third_party_dir/$new_folder"
        done
    fi


    if [ ! -d "$third_party_dir/boost/build" ]; then
        cd $third_party_dir/boost || exit 1
        ./bootstrap.sh --prefix="$PWD/build"  
        ./b2 --prefix="$PWD/build" --buildtype=complete install
        cd "$TOPDIR" || exit 1
    fi
    echo "boost is installed."

    if [ ! -d "$third_party_dir/jemalloc/build" ]; then
        cd $third_party_dir/jemalloc || exit 1
        ./configure --prefix="$PWD/build"
        make && make install
        cd "$TOPDIR" || exit 1
    fi
    echo "jemalloc is installed."
}

# try call command make, if use give --make in command line.
function try_make
{
  if [[ $MAKE != false ]]
  then
    # use single thread `make` if concurrent building failed
    $MAKE "${MAKE_ARGS[@]}" || $MAKE
  fi
}

# create build directory and cd it.
function prepare_build_dir
{
  TYPE=$1
  mkdir -p ${TOPDIR}/build_${TYPE}
  rm -f build
  echo "create soft link for build_${TYPE}, linked by directory named build"
  ln -s build_${TYPE} build
  cd ${TOPDIR}/build_${TYPE}
}

function do_build
{
  TYPE=$1; shift
  prepare_build_dir $TYPE || return
  echo "${CMAKE_COMMAND} ${TOPDIR} $@"
  ${CMAKE_COMMAND} -S ${TOPDIR} $@
}

function do_clean
{
  echo "clean build_* dirs"
  find . -maxdepth 1 -type d -name 'build_*' | xargs rm -rf
}

function build
{
  set -- "${BUILD_ARGS[@]}"
  case "x$1" in
    xrelease)
      do_build "$@" -DCMAKE_BUILD_TYPE=RelWithDebInfo -DDEBUG=OFF
      ;;
    xdebug)
      do_build "$@" -DCMAKE_BUILD_TYPE=Debug -DDEBUG=ON
      ;;
    *)
      BUILD_ARGS=(debug "${BUILD_ARGS[@]}")
      build
      ;;
  esac
}



function main
{
  case "$1" in
    -h)
      usage
      ;;
    init)
      do_init
      ;;
    clean)
      do_clean
      ;;
    *)
      parse_args
      build
      try_make
      ;;
  esac
}

main "$@"