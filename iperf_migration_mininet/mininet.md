### Starting multipass machine
multipass launch --name mininet-vm --mem 2G --disk 10G
multipass shell mininet-vm

sudo apt update
sudo apt install mininet
sudo apt-get install python3-pip
sudo pip3 install ryu
sudo apt install python3-venv

# Need virtual env, because ubuntu is configured to protect the system-wide Python environment
sudo apt update
sudo apt upgrade

sudo apt install python3-openssl
sudo apt install -y make build-essential libssl-dev zlib1g-dev \
libbz2-dev libreadline-dev libsqlite3-dev wget curl llvm \
libncurses5-dev libncursesw5-dev xz-utils tk-dev libffi-dev liblzma-dev python-openssl git


### Starting mininet with ryu controller
nano custom_topology.py



ryu-manager ryu.app.simple_switch_13
sudo python custom_topology.py
