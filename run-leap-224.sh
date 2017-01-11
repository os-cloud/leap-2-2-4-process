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

## Env Vars ------------------------------------------------------------------
export MAIN_PATH="/opt/openstack-ansible"

## Functions -----------------------------------------------------------------
function run_lock {
  set +e
  run_item="${RUN_TASKS[$1]}"
  file_part="${run_item}"

  # note(sigmavirus24): this handles tasks like:
  # "-e 'rabbitmq_upgrade=true' setup-infrastructure.yml"
  # "/tmp/fix_container_interfaces.yml || true"
  # so we can get the appropriate basename for the upgrade_marker
  for part in $run_item; do
    if [[ "$part" == *.yml ]];then
      file_part="$part"
      break
    fi
  done

  if [ ! -d  "/etc/openstack_deploy/upgrade-newton" ]; then
      mkdir -p "/etc/openstack_deploy/upgrade-newton"
  fi

  upgrade_marker_file=$(basename ${file_part} .yml)
  upgrade_marker="/etc/openstack_deploy/upgrade-newton/$upgrade_marker_file.complete"

  if [ ! -f "$upgrade_marker" ];then
    # note(sigmavirus24): use eval so that we properly turn strings like
    # "/tmp/fix_container_interfaces.yml || true"
    # into a command, otherwise we'll get an error that there's no playbook
    # named ||
    eval "openstack-ansible $2"
    playbook_status="$?"
    echo "ran $run_item"

    if [ "$playbook_status" == "0" ];then
      RUN_TASKS=("${RUN_TASKS[@]/$run_item}")
      touch "$upgrade_marker"
      echo "$run_item has been marked as success"
    else
      echo "******************** failure ********************"
      echo "The upgrade script has encountered a failure."
      echo "Failed on task \"$run_item\""
      echo "Re-run the run-upgrade.sh script, or"
      echo "execute the remaining tasks manually:"
      # NOTE:
      # List the remaining, incompleted tasks from the tasks array.
      # Using seq to genertate a sequence which starts from the spot
      # where previous exception or failures happened.
      # run the tasks in order
      for item in $(seq $1 $((${#RUN_TASKS[@]} - 1))); do
        if [ -n "${RUN_TASKS[$item]}" ]; then
          echo "openstack-ansible ${RUN_TASKS[$item]}"
        fi
      done
      echo "******************** failure ********************"
      exit 99
    fi
  else
    RUN_TASKS=("${RUN_TASKS[@]/$run_item.*}")
  fi
  set -e
}

function pre_flight {
    ## Pre-flight Check ----------------------------------------------------------
    # Clear the screen and make sure the user understands whats happening.
    clear

    # Notify the user.
    echo -e "
    This script will perform a LEAP upgrade from Juno to Newton.
    Once you start the upgrade there's no going back.

    **Note, this is an OFFLINE upgrade**

    Are you ready to perform this upgrade now?
    "

    # Confirm the user is ready to upgrade.
    read -p 'Enter "YES" to continue or anything else to quit: ' UPGRADE
    if [ "${UPGRADE}" == "YES" ]; then
      echo "Running LEAP Upgrade"
    else
      exit 99
    fi
}

function run_items {
    ### Run system upgrade processes
    pushd ${1}
      # Source the scripts lib
      source "scripts/scripts-library.sh"

      # Install ansible for system migrations
      bash scripts/bootstrap-ansible.sh

      pushd playbooks
        # Run the tasks in order
        for item in ${!RUN_TASKS[@]}; do
          echo "Running:" "run_lock $item" "${RUN_TASKS[$item]}"
        done
      popd
    popd
}

function clone_release {
    if [[ -d "/opt/openstack-ansible-$1" ]]; then
      rm -rf "/opt/openstack-ansible-$1"
    fi
    git clone https://git.openstack.org/openstack/openstack-ansible /opt/openstack-ansible-$1
    pushd /opt/openstack-ansible-$1
      git checkout $1
    popd
}

## Main ----------------------------------------------------------------------

function main {
    pre_flight

    ### Kilo System Upgrade
    clone_release 11.2.17
    pushd "/opt/openstack-ansible-11.2.17"
      UPGRADE_SCRIPTS="$(pwd)/upgrade-utilities-kilo/scripts"
      ${UPGRADE_SCRIPTS}/create-new-openstack-deploy-structure.sh
      ${UPGRADE_SCRIPTS}/bootstrap-new-ansible.sh
      ${UPGRADE_SCRIPTS}/juno-rpc-extras-create.py
      ${UPGRADE_SCRIPTS}/new-variable-prep.sh
      # Convert LDAP variables if any are found
      if grep '^keystone_ldap.*' /etc/openstack_deploy/user_variables.yml;then
        ${UPGRADE_SCRIPTS}/juno-kilo-ldap-conversion.py
      fi
      # Create the repo servers entries from the same entries found within the infra_hosts group.
      if ! grep -r '^repo-infra_hosts\:' /etc/openstack_deploy/openstack_user_config.yml /etc/openstack_deploy/conf.d/;then
        if [ ! -f "/etc/openstack_deploy/conf.d/repo-servers.yml" ];then
          ${UPGRADE_SCRIPTS}/juno-kilo-add-repo-infra.py
        fi
      fi
      ${UPGRADE_SCRIPTS}/juno-is-metal-preserve.py
      ${UPGRADE_SCRIPTS}/old-variable-remove.sh
    popd

    UPGRADE_PLAYBOOKS="$(pwd)/upgrade-utilities-kilo/playbooks"
    RUN_TASKS+=("${UPGRADE_PLAYBOOKS}/user-secrets-adjustments.yml")
    RUN_TASKS+=("haproxy-install.yml || true")
    RUN_TASKS+=("${UPGRADE_PLAYBOOKS}/host-adjustments.yml")
    RUN_TASKS+=("${UPGRADE_PLAYBOOKS}/keystone-adjustments.yml")
    RUN_TASKS+=("${UPGRADE_PLAYBOOKS}/horizon-adjustments.yml")
    RUN_TASKS+=("${UPGRADE_PLAYBOOKS}/cinder-adjustments.yml")
    RUN_TASKS+=("${UPGRADE_PLAYBOOKS}/remove-juno-log-rotate.yml || true")
    RUN_TASKS+=("${UPGRADE_PLAYBOOKS}/nova-extra-migrations.yml")
    if [ "$(ansible 'swift_hosts' --list-hosts)" != "No hosts matched" ]; then
      RUN_TASKS+=("${UPGRADE_PLAYBOOKS}/swift-ring-adjustments.yml")
      RUN_TASKS+=("${UPGRADE_PLAYBOOKS}/swift-repo-adjustments.yml")
    fi
    run_items "/opt/openstack-ansible-11.2.17"
    ### Kilo System Upgrade

    ### Liberty System Upgrade
    clone_release 12.2.8
    UPGRADE_PLAYBOOKS="$(pwd)/upgrade-utilities-liberty/playbooks"
    RUN_TASKS+=("${UPGRADE_PLAYBOOKS}/ansible_fact_cleanup.yml")
    RUN_TASKS+=("${UPGRADE_PLAYBOOKS}/deploy-config-changes.yml")
    RUN_TASKS+=("${UPGRADE_PLAYBOOKS}/user-secrets-adjustment.yml")
    RUN_TASKS+=("${UPGRADE_PLAYBOOKS}/mariadb-apt-cleanup.yml")
    RUN_TASKS+=("${UPGRADE_PLAYBOOKS}/repo-server-pip-conf-removal.yml")
    RUN_TASKS+=("${UPGRADE_PLAYBOOKS}/disable-neutron-port-security.yml")
    RUN_TASKS+=("${UPGRADE_PLAYBOOKS}/nova-flavor-migration.yml")
    RUN_TASKS+=("${UPGRADE_PLAYBOOKS}/cleanup-rabbitmq-vhost.yml")
    RUN_TASKS+=("${UPGRADE_PLAYBOOKS}/glance-db-storage-url-fix.yml")
    run_items "/opt/openstack-ansible-12.2.8"
    ### Liberty System Upgrade

    ### Mitaka System Upgrade
    clone_release 13.3.11
    UPGRADE_PLAYBOOKS="$(pwd)/upgrade-utilities-mitaka/playbooks"
    RUN_TASKS+=("${UPGRADE_PLAYBOOKS}/01_ansible_fact_cleanup.yml")
    RUN_TASKS+=("${UPGRADE_PLAYBOOKS}/deploy-config-changes.yml")
    RUN_TASKS+=("${UPGRADE_PLAYBOOKS}/user-secrets-adjustment.yml")
    RUN_TASKS+=("${UPGRADE_PLAYBOOKS}/pip-conf-removal.yml")
    RUN_TASKS+=("${UPGRADE_PLAYBOOKS}/old-hostname-compatibility.yml")
    RUN_TASKS+=("${UPGRADE_PLAYBOOKS}/02_ansible_fact_cleanup.yml")
    RUN_TASKS+=("${UPGRADE_PLAYBOOKS}/neutron-mtu-migration.yml")
    RUN_TASKS+=("${UPGRADE_PLAYBOOKS}/rfc1034_1035-cleanup.yml -e 'destroy_ok=yes'")
    run_items "/opt/openstack-ansible-13.3.11"
    ### Mitaka System Upgrade

    ### Newton Deploy
    clone_release 14.0.4
    UPGRADE_PLAYBOOKS="$(pwd)/upgrade-utilities-newton/playbooks"
    RUN_TASKS+=("${UPGRADE_PLAYBOOKS}/lbaas-version-check.yml")
    RUN_TASKS+=("${UPGRADE_PLAYBOOKS}/ansible_fact_cleanup.yml")
    RUN_TASKS+=("${UPGRADE_PLAYBOOKS}/deploy-config-changes.yml")
    RUN_TASKS+=("${UPGRADE_PLAYBOOKS}/user-secrets-adjustment.yml")
    RUN_TASKS+=("${UPGRADE_PLAYBOOKS}/mariadb-apt-cleanup.yml")
    RUN_TASKS+=("${UPGRADE_PLAYBOOKS}/db-collation-alter.yml")
    RUN_TASKS+=("${UPGRADE_PLAYBOOKS}/pip-conf-removal.yml")
    RUN_TASKS+=("${UPGRADE_PLAYBOOKS}/old-hostname-compatibility.yml")
    run_items "/opt/openstack-ansible-14.0.4"
    ### Newton Deploy

    ### Run the redeploy tasks
    RUN_TASKS+=("setup-everything.yml")
    pushd ${MAIN_PATH}/playbooks
        # Run the tasks in order
        for item in ${!RUN_TASKS[@]}; do
          run_lock $item "${RUN_TASKS[$item]}"
        done
    popd
    ### Run the redeploy tasks
}

main