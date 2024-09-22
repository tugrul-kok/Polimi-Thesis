from mininet.net import Mininet
from mininet.node import Controller, OVSKernelSwitch, RemoteController
from mininet.cli import CLI
from mininet.log import setLogLevel
from mininet.link import TCLink
from time import sleep

def customNet():
    net = Mininet(controller=RemoteController, link=TCLink, switch=OVSKernelSwitch)

    # Create nodes
    h1 = net.addHost('h1', ip='10.0.0.1', mac='00:00:00:00:00:01')
    h2 = net.addHost('h2', ip='10.0.0.2', mac='00:00:00:00:00:02')
    h3 = net.addHost('h3', ip='10.0.0.3', mac='00:00:00:00:00:03')
    s1 = net.addSwitch('s1')

    # Create links
    net.addLink(h1, s1)
    net.addLink(h2, s1)
    net.addLink(h3, s1)

    # Add Controller
    c0 = net.addController('c0', controller=RemoteController, ip='127.0.0.1', port=6633)

    # Start network
    print("[INFO] Starting the network...")
    net.start()

    # Start iPerf server on h1
    print("[INFO] Starting iPerf server on h1...")
    h1.cmd('iperf -s -u -i 1 > h1_iperf_server.txt &')

    # Start iPerf client on h2
    print("[INFO] Starting iPerf client on h2...")
    h2.cmd('iperf -c 10.0.0.1 -u -t 120 -i 1 > h2_iperf_client.txt &')

    # Wait for some time and then migrate IP and MAC from h1 to h3
    print("[INFO] Waiting for 20 seconds before migrating IP and MAC addresses...")
    sleep(20)

    # Migrate IP and MAC from h1 to h3
    print("[INFO] Migrating IP and MAC address from h1 to h3...")
    h3.cmd('ifconfig h3-eth0 down')
    h3.cmd('ifconfig h3-eth0 hw ether 00:00:00:00:00:01')
    h3.cmd('ifconfig h3-eth0 10.0.0.1 up')
    h3.cmd('iperf -s -u -i 1 > h3_iperf_server.txt &')

    # Update OpenFlow rules to redirect traffic to h3 only
    print("[INFO] Updating OpenFlow rules to direct traffic to h3 (port 3)...")
    s1.cmd('ovs-ofctl del-flows s1')
    s1.cmd('ovs-ofctl add-flow s1 priority=65535,ip,nw_dst=10.0.0.1,actions=output:3')
    print("[INFO] Sleeping 20s after network update...")

    sleep(20)
    # Run CLI for manual interaction
    print("[INFO] Running Mininet CLI...")
    CLI(net)

    # After CLI command, stop network
    print("[INFO] Stopping the network...")
    net.stop()

if __name__ == '__main__':
    setLogLevel('info')
    print("[INFO] Starting the custom network script...")
    customNet()
    print("[INFO] Custom network script completed.")
