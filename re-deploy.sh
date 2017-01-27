#!/usr/bin/env bash

# Copyright 2017, Rackspace US, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# NOTICE: To run this in an automated fashion run the script via
#   root@HOSTNAME:/opt/openstack-ansible# echo "YES" | bash scripts/run-upgrade.sh

## Shell Opts ----------------------------------------------------------------
set -e -u -v

## Main ----------------------------------------------------------------------
source lib/vars.sh
source lib/functions.sh

### Run the redeploy tasks
# Forget about the old Juno neutron agent container in inventory.
#  This is done to maximize uptime by leaving the old systems in
#  place while the redeployment work is going on.
SCRIPTS_PATH="/opt/leap42/openstack-ansible-${NEWTON_RELEASE}/scripts" \
  MAIN_PATH="/opt/leap42/openstack-ansible-${NEWTON_RELEASE}" \
    ${UPGRADE_UTILS}/neutron-container-forget.sh

link_release "/opt/leap42/openstack-ansible-${NEWTON_RELEASE}"
RUN_TASKS=()
RUN_TASKS+=("${UPGRADE_UTILS}/pip-unify.yml -e release_version=\"${NEWTON_RELEASE}\"")
RUN_TASKS+=("${UPGRADE_UTILS}/db-stop.yml")
RUN_TASKS+=("${UPGRADE_UTILS}/ansible_fact_cleanup.yml")
RUN_TASKS+=("${UPGRADE_UTILS}/destroy-old-containers.yml")
RUN_TASKS+=("${UPGRADE_UTILS}/nova-libvirt-fix.yml")
RUN_TASKS+=("lxc-hosts-setup.yml")
RUN_TASKS+=("lxc-containers-create.yml")
RUN_TASKS+=("setup-infrastructure.yml")
RUN_TASKS+=("${UPGRADE_UTILS}/db-force-upgrade.yml")

# This will need to be broken out
RUN_TASKS+=("setup-openstack.yml")
# This will need to be broken out

RUN_TASKS+=("${UPGRADE_UTILS}/post-redeploy-cleanup.yml")
run_items "/opt/openstack-ansible"
### Run the redeploy tasks
