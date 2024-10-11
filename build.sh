#!/bin/bash

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
root_dir=$(dirname $(readlink -f "$0"))
cd "$root_dir" || exit 1

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
    cd "$root_dir" || exit 1
fi
echo "boost is installed."

if [ ! -d "$third_party_dir/jemalloc/build" ]; then
    cd $third_party_dir/jemalloc || exit 1
    ./configure --prefix="$PWD/build"
    make && make install
    cd "$root_dir" || exit 1
fi
echo "jemalloc is installed."

echo "All dependencies are satisfied, start compiling..."
rm -rf build
mkdir build && cd build || exit 1
cmake ..
make -j