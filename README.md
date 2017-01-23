# OpenStack-Ansible leap upgrade

## Jump upgrade from OpenStack Juno to Newton using OpenStack-Ansible

**This currently a POC**

### Uses

This utility can be used to upgrade any OpenStack-Ansible deployment running
Juno to the latest Newton release. The process will upgrade the OSA system
components, sync the database through the various releases, and then deploy
OSA using the Newton release. While this method will help a deploy skip
several releases  deployers should be aware that skipping releases is not
something OpenStack supports. To make this possible the active cloud will
have the OpenStack services stopped. Active workloads "*should*" remain online
for the most part though at this stage no effort is being put into maximizing
uptime as the tool set is being developed to easy multi-release upgrades in
the shortest possible time while maintaining data-integrity.

#### Requirements

  * **You must** have a Juno based OpenStack cloud as deployed by
    OpenStack-Ansible.
  * If you are running cinder-volume with LVM in an LXC container **you must**
    migrate the cinder-volume service to the physical host.
  * **You must** have the Ubuntu Trusty Backports repo enabled before you start.

#### Process

If you need to run everything the script ``run-stages.sh`` will execute
everything needed to migrate the environment.

``` bash
bash ./run-stages.sh
```

If you want to preload the stages you can do so by running the various stages
independently.

``` bash
bash ./prep.sh
bash ./upgrade.sh
bash ./migrations.sh
bash ./re-deploy.sh
```

Once all of the stages are complete the cloud will be running OpenStack
Newton.

----

## Setting up a Test environment.

Testing on a multi-node environment can be accomplished using the
https://github.com/openstack/openstack-ansible-ops/tree/master/multi-node-aio
repo. To create this environment for testing a single physical host can be
used; Rackspace OnMetal V1 deployed Ubuntu 14.04 on an IO flavor has worked
very well for development. To run the deployment execute the following commands

#### Requirements

  * When testing the host which is being tested on will need to start with Kernel
    less than or equal to "3.13". Later kernels will cause neutron to fail to run
  * Start the deployment w/ ubuntu 14.04.2 to ensure the deployment version is
    limited in terms of package availability.

#### Process

Clone the ops tooling and change directory to the multi-node-aio tooling

``` bash
git clone https://github.com/openstack/openstack-ansible-ops /opt/openstack-ansible-ops
```

Run the following commands to prep the environment.

``` bash
setup-host.sh
setup-cobbler.sh
setup-virsh-net.sh
deploy-vms.sh
```

After the environment has been deployed clone the RPC configurations which support Juno
based clouds.

``` bash
git clone https://github.com/os-cloud/leapfrog-juno-config /etc/rpc_deploy
```

Now clone the Juno playbooks into place.

``` bash
git clone --branch leapfrog https://github.com/os-cloud/leapfrog-juno-playbooks /opt/openstack-ansible
```

Finally, run the bootstrap script and the haproxy and setup playbooks to deploy the cloud environment.

``` bash
cd /opt/openstack-ansible/rpc_deployment

./scripts/bootstrap-ansible.sh

openstack-ansible playbooks/haproxy-install.yml

openstack-ansible playbooks/setup-everything.yml
```

To test the cloud's functionality you can execute the OpenStack resource test script located in the scripts directory
of the playbooks cloned earlier.

``` bash
cd /opt/openstack-ansible/rpc_deployment
ansible -m script -a /opt/openstack-ansible/scripts/setup-openstack-for-test.sh 'utility_all[0]'
```

The previous script will create new flavors, L2 and L3 networks, routers, setup security groups, create test images, 2 L2 network test VMs, 2 L3 network test VMs w/ floating IPs, 2 Cinder-volume test VMs, 2 new cinder volumes which will be attached to the Cinder-volume test VMs, and upload a mess of files into a Test-Swift container.


Once the cloud is operational it's recommended that images be created so that the environment can be
reverted to a previous state should there ever be a need. See
https://github.com/openstack/openstack-ansible-ops/tree/master/multi-node-aio#snapshotting-an-environment-before-major-testing
for more on creating snapshots.
