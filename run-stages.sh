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

## Stages --------------------------------------------------------------------
pre_flight

source prep.sh
source upgrade.sh
source migrations.sh
source re-deploy.sh

echo -e "\n====================================================="
notice "All Leaps successful."
echo -e "=====================================================\n"
exit 0
