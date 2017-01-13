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

## Script Vars ---------------------------------------------------------------
KILO_RELEASE="11.2.17"
LIBERTY_RELEASE="12.2.8"
MITAKA_RELEASE="13.3.11"
NEWTON_RELEASE="14.0.4"

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

  if [ ! -d  "/etc/openstack_deploy/upgrade-leap" ]; then
      mkdir -p "/etc/openstack_deploy/upgrade-leap"
  fi

  upgrade_marker_file=$(basename ${file_part} .yml)
  upgrade_marker="/etc/openstack_deploy/upgrade-leap/$upgrade_marker_file.complete"

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

    mkdir -p /opt/leap42/venvs

    pushd /opt/leap42
      # Using this lookup plugin because it allows us to complile exact service releaes and build a complete venv from it
      wget https://raw.githubusercontent.com/openstack/openstack-ansible-plugins/e069d558b3d6ae8fc505d406b13a3fb66201a9c7/lookup/py_pkgs.py
      chmod +x py_pkgs.py
    popd

    # Install virtual env for building migration venvs
    pip install "virtualenv==15.1.0" --isolated --upgrade

    # Install liberasurecode-dev which will be used in the venv creation process
    apt-get update && apt-get -y install liberasurecode-dev
}

function run_items {
    ### Run system upgrade processes
    pushd ${1}
      # Before running anything execute inventory to ensure functionality
      python playbooks/inventory/dynamic_inventory.py > /dev/null

      # Source the scripts lib
      source "scripts/scripts-library.sh"

      # Install ansible for system migrations
      bash scripts/bootstrap-ansible.sh

      pushd playbooks
        # Run the tasks in order
        for item in ${!RUN_TASKS[@]}; do
          run_lock $item "${RUN_TASKS[$item]}"
        done
      popd
    popd
}

function clone_release {
    if [[ -d "/opt/openstack-ansible" ]]; then
      rm -rf "/opt/openstack-ansible"
    fi
    if [[ -d "/opt/leap42/openstack-ansible-$1" ]]; then
      rm -rf "/opt/leap42/openstack-ansible-$1"
    fi
    git clone https://git.openstack.org/openstack/openstack-ansible /opt/leap42/openstack-ansible-$1
    pushd /opt/leap42/openstack-ansible-$1
      git checkout $1
    popd
    ln -s "/opt/leap42/openstack-ansible-$1" "/opt/openstack-ansible"
}

function build_venv {
    # If the venv exists delete it
    if [[ ! -f "/opt/leap42/venvs/openstack-ansible-$1.tgz" ]]; then
      # Create venv
      virtualenv --never-download --always-copy "/opt/leap42/venvs/openstack-ansible-$1"
      PS1="\\u@\h \\W]\\$" . "/opt/leap42/venvs/openstack-ansible-$1/bin/activate"
      pip install pip --upgrade --force-reinstall

      # Modern Ansible is needed to run the package lookup
      pip install "ansible==2.1.1.0"

      # Get package dump from the OSA release
      PKG_DUMP=$(python /opt/leap42/py_pkgs.py /opt/leap42/openstack-ansible-$1/playbooks/defaults/repo_packages)
      PACKAGES=$(python <<EOC
import json
packages = json.loads("""$PKG_DUMP""")
remote_packages = packages[0]['remote_packages']
print(' '.join([i for i in remote_packages if 'openstack' in i]))
EOC)
      pip install --isolated $PACKAGES mysql-python
      deactivate
      # Create venv archive
      pushd /opt/leap42/venvs
        find "openstack-ansible-$1" -name '*.pyc' -exec rm {} \;
        tar -czf "openstack-ansible-$1.tgz" "openstack-ansible-$1"
      popd
    else
      echo "the venv \"/opt/leap42/venvs/openstack-ansible-$1.tgz\" already exists. If you need to recreate this venv, delete it."
    fi
}

## Main ----------------------------------------------------------------------

function main {
    pre_flight

    # Build the releases
    if [[ ! -f "/opt/leap42/openstack-ansible-${KILO_RELEASE}.leap" ]]; then
      clone_release ${KILO_RELEASE}
      build_venv ${KILO_RELEASE}
    fi
    if [[ ! -f "/opt/leap42/openstack-ansible-${LIBERTY_RELEASE}.leap" ]]; then
      clone_release ${LIBERTY_RELEASE}
      build_venv ${LIBERTY_RELEASE}
    fi
    if [[ ! -f "/opt/leap42/openstack-ansible-${MITAKA_RELEASE}.leap" ]]; then
      clone_release ${MITAKA_RELEASE}
      build_venv ${MITAKA_RELEASE}
    fi
    if [[ ! -f "/opt/leap42/openstack-ansible-${NEWTON_RELEASE}.leap" ]]; then
      clone_release ${NEWTON_RELEASE}
      build_venv ${NEWTON_RELEASE}
    fi

    ### Kilo System Upgrade
    # Run tasks
    UPGRADE_SCRIPTS="$(pwd)/upgrade-utilities-kilo/scripts"
    pushd "/opt/leap42/openstack-ansible-${KILO_RELEASE}"
      SCRIPTS_PATH="/opt/leap42/openstack-ansible-${KILO_RELEASE}/scripts" MAIN_PATH="/opt/leap42/openstack-ansible-${KILO_RELEASE}" ${UPGRADE_SCRIPTS}/create-new-openstack-deploy-structure.sh
      ${UPGRADE_SCRIPTS}/juno-rpc-extras-create.py
      SCRIPTS_PATH="/opt/leap42/openstack-ansible-${KILO_RELEASE}/scripts" MAIN_PATH="/opt/leap42/openstack-ansible-${KILO_RELEASE}" ${UPGRADE_SCRIPTS}/new-variable-prep.sh
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
      SCRIPTS_PATH="/opt/leap42/openstack-ansible-${KILO_RELEASE}/scripts" MAIN_PATH="/opt/leap42/openstack-ansible-${KILO_RELEASE}" ${UPGRADE_SCRIPTS}/old-variable-remove.sh
    popd
    UPGRADE_PLAYBOOKS="$(pwd)/upgrade-utilities-kilo/playbooks"
    RUN_TASKS+=("${UPGRADE_PLAYBOOKS}/user-secrets-adjustments-kilo.yml -e 'osa_playbook_dir=/opt/leap42/openstack-ansible-${KILO_RELEASE}'")
    RUN_TASKS+=("${UPGRADE_PLAYBOOKS}/host-adjustments.yml")
    RUN_TASKS+=("${UPGRADE_PLAYBOOKS}/remove-juno-log-rotate.yml || true")
    if [ "$(ansible 'swift_hosts' --list-hosts)" != "No hosts matched" ]; then
      RUN_TASKS+=("${UPGRADE_PLAYBOOKS}/swift-ring-adjustments.yml")
      RUN_TASKS+=("${UPGRADE_PLAYBOOKS}/swift-repo-adjustments.yml")
    fi
    RUN_TASKS+=("${UPGRADE_PLAYBOOKS}/db-migrations-kilo.yml -e 'venv_tar_location=/opt/leap42/venvs/openstack-ansible-${KILO_RELEASE}.tgz'")
    run_items "/opt/leap42/openstack-ansible-${KILO_RELEASE}"
    touch "/opt/leap42/openstack-ansible-${KILO_RELEASE}.leap"
    ### Kilo System Upgrade

    ### Liberty System Upgrade
    # Run tasks
    UPGRADE_PLAYBOOKS="$(pwd)/upgrade-utilities-liberty/playbooks"
    RUN_TASKS+=("${UPGRADE_PLAYBOOKS}/ansible_fact_cleanup-liberty.yml -e 'osa_playbook_dir=/opt/leap42/openstack-ansible-${LIBERTY_RELEASE}'")
    RUN_TASKS+=("${UPGRADE_PLAYBOOKS}/deploy-config-changes-liberty.yml -e 'osa_playbook_dir=/opt/leap42/openstack-ansible-${LIBERTY_RELEASE}'")
    RUN_TASKS+=("${UPGRADE_PLAYBOOKS}/user-secrets-adjustment-liberty.yml -e 'osa_playbook_dir=/opt/leap42/openstack-ansible-${LIBERTY_RELEASE}'")
    RUN_TASKS+=("${UPGRADE_PLAYBOOKS}/mariadb-apt-cleanup.yml")
    RUN_TASKS+=("${UPGRADE_PLAYBOOKS}/disable-neutron-port-security.yml")
    RUN_TASKS+=("${UPGRADE_PLAYBOOKS}/cleanup-rabbitmq-vhost.yml")
    RUN_TASKS+=("${UPGRADE_PLAYBOOKS}/glance-db-storage-url-fix.yml")
    RUN_TASKS+=("${UPGRADE_PLAYBOOKS}/db-migrations-liberty.yml -e 'venv_tar_location=/opt/leap42/venvs/openstack-ansible-${LIBERTY_RELEASE}.tgz'")
    run_items "/opt/leap42/openstack-ansible-${LIBERTY_RELEASE}"
    touch "/opt/leap42/openstack-ansible-${LIBERTY_RELEASE}.leap"
    ### Liberty System Upgrade

echo "Liberty upgrade success and break point has been hit."
echo "System Exit to begin working on the next section"
exit 99

    ### Mitaka System Upgrade
    # Run tasks
    UPGRADE_PLAYBOOKS="$(pwd)/upgrade-utilities-mitaka/playbooks"
    RUN_TASKS+=("${UPGRADE_PLAYBOOKS}/ansible_fact_cleanup-mitaka-1.yml -e 'osa_playbook_dir=/opt/leap42/openstack-ansible-${MITAKA_RELEASE}'")
    RUN_TASKS+=("${UPGRADE_PLAYBOOKS}/deploy-config-changes-mitaka.yml -e 'osa_playbook_dir=/opt/leap42/openstack-ansible-${MITAKA_RELEASE}'")
    RUN_TASKS+=("${UPGRADE_PLAYBOOKS}/user-secrets-adjustment-mitaka.yml -e 'osa_playbook_dir=/opt/leap42/openstack-ansible-${MITAKA_RELEASE}'")
    RUN_TASKS+=("${UPGRADE_PLAYBOOKS}/pip-conf-removal.yml")
    RUN_TASKS+=("${UPGRADE_PLAYBOOKS}/old-hostname-compatibility-mitaka.yml")
    RUN_TASKS+=("${UPGRADE_PLAYBOOKS}/ansible_fact_cleanup-mitaka-2.yml -e 'osa_playbook_dir=/opt/leap42/openstack-ansible-${MITAKA_RELEASE}'")
    RUN_TASKS+=("${UPGRADE_PLAYBOOKS}/rfc1034_1035-cleanup.yml -e 'destroy_ok=yes'")
#### This needs to be written    RUN_TASKS+=("${UPGRADE_PLAYBOOKS}/db-migrations.yml -e 'venv_tar_location=/opt/leap42/venvs/openstack-ansible-${MITAKA_RELEASE}.tgz'")
    RUN_TASKS+=("${UPGRADE_PLAYBOOKS}/neutron-mtu-migration.yml")
    run_items "/opt/leap42/openstack-ansible-${MITAKA_RELEASE}"
    touch "/opt/leap42/openstack-ansible-${MITAKA_RELEASE}.leap"
    ### Mitaka System Upgrade

    ### Newton Deploy
    # Run tasks
    UPGRADE_PLAYBOOKS="$(pwd)/upgrade-utilities-newton/playbooks"
    RUN_TASKS+=("${UPGRADE_PLAYBOOKS}/lbaas-version-check.yml")
    RUN_TASKS+=("${UPGRADE_PLAYBOOKS}/ansible_fact_cleanup-newton.yml -e 'osa_playbook_dir=/opt/leap42/openstack-ansible-${NEWTON_RELEASE}'")
    RUN_TASKS+=("${UPGRADE_PLAYBOOKS}/deploy-config-changes-newton.yml -e 'osa_playbook_dir=/opt/leap42/openstack-ansible-${NEWTON_RELEASE}'")
    RUN_TASKS+=("${UPGRADE_PLAYBOOKS}/user-secrets-adjustment-newton.yml -e 'osa_playbook_dir=/opt/leap42/openstack-ansible-${NEWTON_RELEASE}'")
    RUN_TASKS+=("${UPGRADE_PLAYBOOKS}/db-collation-alter.yml")
    RUN_TASKS+=("${UPGRADE_PLAYBOOKS}/old-hostname-compatibility-newton.yml")
#### This needs to be written    RUN_TASKS+=("${UPGRADE_PLAYBOOKS}/db-migrations.yml -e 'venv_tar_location=/opt/leap42/venvs/openstack-ansible-${NEWTON_RELEASE}.tgz'")
    run_items "/opt/leap42/openstack-ansible-${NEWTON_RELEASE}"
    touch "/opt/leap42/openstack-ansible-${NEWTON_RELEASE}.leap"
    ### Newton Deploy

    ### Run the redeploy tasks
    RUN_TASKS+=("setup-everything.yml")
    run_items "/opt/openstack-ansible"
    ### Run the redeploy tasks
}

main
