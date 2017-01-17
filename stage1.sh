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
source lib/functions.sh
source lib/vars.sh

pre_flight

# Build the releases. This will clone all of the releases and check them out
#  separately in addition to creating all of the venvs needed for a successful migration.
if [[ ! -f "/opt/leap42/openstack-ansible-${KILO_RELEASE}-prep.leap" ]]; then
  clone_release ${KILO_RELEASE}
  build_venv ${KILO_RELEASE}
fi
if [[ ! -f "/opt/leap42/openstack-ansible-${LIBERTY_RELEASE}-prep.leap" ]]; then
  clone_release ${LIBERTY_RELEASE}
  build_venv ${LIBERTY_RELEASE}
fi
if [[ ! -f "/opt/leap42/openstack-ansible-${MITAKA_RELEASE}-prep.leap" ]]; then
  clone_release ${MITAKA_RELEASE}
  build_venv ${MITAKA_RELEASE}
fi
if [[ ! -f "/opt/leap42/openstack-ansible-${NEWTON_RELEASE}-prep.leap" ]]; then
  clone_release ${NEWTON_RELEASE}
  build_venv ${NEWTON_RELEASE}
fi

RUN_TASKS+=("${UPGRADE_UTILS}/cinder-volume-container-lvm-check.yml")
run_items "/opt/leap42/openstack-ansible-${KILO_RELEASE}"
