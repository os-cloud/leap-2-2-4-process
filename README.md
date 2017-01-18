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

### Requirements

  * **You must** have a Juno based OpenStack cloud as deployed by
    OpenStack-Ansible.
  * If you are running cinder-volume with LVM in an LXC container **you must**
    migrate the cinder-volume service to the physical host.
  * **You must** have the Ubuntu Trusty Backports repo enabled.

### Process

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
```

Once all of the stages are complete the cloud will be running OpenStack
Newton.
