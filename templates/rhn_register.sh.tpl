#!/bin/bash

exec 3>&1 4>&2 1> >(tee $0.log.$$ >&3) 2> >(tee $0.log.$$ >&4)

# Script to register with redhat and enable the packages required to install openshift on bastion machine.

# Unregister with softlayer subscription

subscription-manager unregister

if [ -e /etc/rhsm/rhsm.conf.rpmnew ]; then
    # SL case where they are registered to internal satellite
    mv /etc/rhsm/rhsm.conf.rpmnew /etc/rhsm/rhsm.conf
fi

subscription-manager register --username=${rhel_user_name} --password=${rhel_password}
subscription-manager refresh
subscription-manager attach --pool=${subscription_pool}
subscription-manager repos --disable="*"
subscription-manager repos --enable='rhel-7-server-rpms'
