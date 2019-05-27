# Change this path to your config directory
CONFIG_DIR="/config"

cd /tmp
echo "Working in $(pwd)"
# Install LIBC6
curl -OL http://archive.ubuntu.com/ubuntu/pool/main/g/glibc/libc6_2.27-3ubuntu1_amd64.deb
curl -OL http://archive.ubuntu.com/ubuntu/pool/main/g/glibc/libc6-dev_2.27-3ubuntu1_amd64.deb

apt install ./libc6_2.27-3ubuntu1_amd64.deb
apt install ./libc6-dev_2.27-3ubuntu1_amd64.deb

# Clone the latest code from GitHub
echo "Cloning model repo to $(pwd)/tensorflow-models"
git clone --depth 1 https://github.com/tensorflow/models.git tensorflow-models

echo "DEBUG: $(ls /tmp)"

# download protobuf 3.4
echo "Retreiving protoc"
curl -OL https://github.com/google/protobuf/releases/download/v3.4.0/protoc-3.4.0-linux-x86_64.zip
echo "Extracting protobuf"
unzip -a protoc-3.4.0-linux-x86_64.zip -d protobuf
echo "Moving protobuf binary to /tmp/tensorflow-models/research"
mv protobuf/bin /tmp/tensorflow-models/research

# Build the protobuf models
cd /tmp/tensorflow-models/research/
echo "Building object detection in directory $(pwd)"
./bin/protoc object_detection/protos/*.proto --python_out=.

# Copy only necessary files
echo "Setting up configuration directories"
rm -rf ${CONFIG_DIR}/tensorflow/object_detection
mkdir -p ${CONFIG_DIR}/tensorflow/object_detection
touch ${CONFIG_DIR}/tensorflow/object_detection/__init__.py

echo "Moving object detection data to configuration directory"
mv object_detection/data ${CONFIG_DIR}/tensorflow/object_detection
mv object_detection/utils ${CONFIG_DIR}/tensorflow/object_detection
mv object_detection/protos ${CONFIG_DIR}/tensorflow/object_detection

# Cleanup
echo "Cleaning up"
#rm -rf /tmp/*
