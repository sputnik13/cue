#!/bin/bash

TOP_DIR=$(cd $(dirname "$0") && pwd)


# lib/dib
# Install and build images with **diskimage-builder**

# Dependencies:
#
# - functions
# - DEST, DATA_DIR must be defined

# stack.sh
# ---------
# - install_dib

# Save trace setting
XTRACE=$(set +o | grep xtrace)
set +o xtrace

# Defaults
# --------

DEST=${DEST:-/opt/stack}

# set up default directories
DIB_DIR=$DEST/diskimage-builder
TIE_DIR=$DEST/tripleo-image-elements

# NOTE: Setting DIB_APT_SOURCES assumes you will be building
# Debian/Ubuntu based images. Leave unset for other flavors.
DIB_APT_SOURCES=${DIB_APT_SOURCES:-""}
DIB_BUILD_OFFLINE=$(trueorfalse False DIB_BUILD_OFFLINE)
DIB_IMAGE_CACHE=$DATA_DIR/diskimage-builder/image-create
DIB_PIP_REPO=$DATA_DIR/diskimage-builder/pip-repo
DIB_PIP_REPO_PORT=${DIB_PIP_REPO_PORT:-8899}

OCC_DIR=$DEST/os-collect-config
ORC_DIR=$DEST/os-refresh-config
OAC_DIR=$DEST/os-apply-config

# Tripleo elements for diskimage-builder images
TIE_REPO=${TIE_REPO:-${GIT_BASE}/openstack/tripleo-image-elements.git}
TIE_BRANCH=${TIE_BRANCH:-master}

# QEMU Image Options
DIB_QEMU_IMG_OPTIONS='compat=0.10'

# Functions
# ---------

# install_dib() - Collect source and prepare
function install_dib {
    pip_install diskimage-builder

    git_clone $TIE_REPO $TIE_DIR $TIE_BRANCH
    git_clone $OCC_REPO $OCC_DIR $OCC_BRANCH
    git_clone $ORC_REPO $ORC_DIR $ORC_BRANCH
    git_clone $OAC_REPO $OAC_DIR $OAC_BRANCH
    mkdir -p $DIB_IMAGE_CACHE
}

# disk_image_create_upload() - Creates and uploads a diskimage-builder built image
function disk_image_create_upload {
    local image_name=$1
    local image_elements=$2
    local elements_path=$3

    local image_path=$TOP_DIR/files/$image_name.qcow2

    # Include the apt-sources element in builds if we have an
    # alternative sources.list specified.
    if [ -n "$DIB_APT_SOURCES" ]; then
        if [ ! -e "$DIB_APT_SOURCES" ]; then
            die $LINENO "DIB_APT_SOURCES set but not found at $DIB_APT_SOURCES"
        fi
        local extra_elements="apt-sources"
    fi

    # Set the local pip repo as the primary index mirror so the
    # image is built with local packages
    local pypi_mirror_url=http://$SERVICE_HOST:$DIB_PIP_REPO_PORT/
    local pypi_mirror_url_1

    if [ -a $HOME/.pip/pip.conf ]; then
        # Add the current pip.conf index-url as an extra-index-url
        # in the image build
        pypi_mirror_url_1=$(iniget $HOME/.pip/pip.conf global index-url)
    else
        # If no pip.conf, set upstream pypi as an extra mirror
        # (this also sets the .pydistutils.cfg index-url)
        pypi_mirror_url_1=http://pypi.python.org/simple
    fi

    QEMU_IMG_OPTION=""
    if [ ! -z "${DIB_QEMU_IMG_OPTIONS}" ]; then
        QEMU_IMG_OPTION="--qemu-img-options ${DIB_QEMU_IMG_OPTIONS}"
    fi

    # The disk-image-create command to run
    ELEMENTS_PATH=$elements_path \
    DIB_APT_SOURCES=$DIB_APT_SOURCES \
    DIB_OFFLINE=$DIB_BUILD_OFFLINE \
    PYPI_MIRROR_URL=$pypi_mirror_url \
    PYPI_MIRROR_URL_1=$pypi_mirror_url_1 \
    disk-image-create -a amd64 $image_elements ${extra_elements:-} \
        --image-cache $DIB_IMAGE_CACHE \
        ${QEMU_IMG_OPTION} \
        -o $image_path

    local token=$(openstack token issue | grep ' id ' | get_field 2)
    die_if_not_set $LINENO token "Keystone fail to get token"

    openstack --os-token $token --os-url $GLANCE_SERVICE_PROTOCOL://$GLANCE_HOSTPORT \
        image create --container-format bare --disk-format qcow2 --public \
        --min-disk 2 --file $image_path $image_name
}

# Restore xtrace
$XTRACE

# Tell emacs to use shell-script-mode
## Local variables:
## mode: shell-script
## End:



# lib/cue
# Install and start **Cue** service

# To enable Cue services, add the following to localrc
# enable_service cue,cue-api,cue-worker

# stack.sh
# ---------
# install_cue
# configure_cue
# init_cue
# start_cue
# stop_cue
# cleanup_cue

# Save trace setting
XTRACE=$(set +o | grep xtrace)
set +o xtrace


# Defaults
# --------
CUE_PLUGINS=$TOP_DIR/lib/cue_plugins

# Set up default repos
CUE_REPO=${CUE_REPO:-${GIT_BASE}/openstack/cue.git}
CUE_BRANCH=${CUE_BRANCH:-master}
CUECLIENT_REPO=${CUECLIENT_REPO:-${GIT_BASE}/openstack/python-cueclient.git}
CUECLIENT_BRANCH=${CUECLIENT_BRANCH:-master}
CUEDASHBOARD_REPO=${CUEDASHBOARD_REPO:-${GIT_BASE}/openstack/cue-dashboard.git}
CUEDASHBOARD_BRANCH=${CUEDASHBOARD_BRANCH:-master}
CUE_MANAGEMENT_NETWORK_SUBNET=${CUE_MANAGEMENT_NETWORK_SUBNET-"172.16.0.0/24"}

# Set up default paths
CUE_BIN_DIR=$(get_python_exec_prefix)
CUE_DIR=$DEST/cue
CUECLIENT_DIR=$DEST/python-cueclient
CUEDASHBOARD_DIR=$DEST/cue-dashboard
CUE_CONF_DIR=/etc/cue
CUE_STATE_PATH=${CUE_STATE_PATH:=$DATA_DIR/cue}
CUE_CONF=$CUE_CONF_DIR/cue.conf
CUE_LOG_DIR=/var/log/cue
CUE_AUTH_CACHE_DIR=${CUE_AUTH_CACHE_DIR:-/var/cache/cue}

CUE_TF_DB=${CUE_TF_DB:-cue_taskflow}
CUE_TF_PERSISTENCE=${CUE_TF_PERSISTENCE:-}
CUE_TF_CREATE_CLUSTER_NODE_VM_ACTIVE_RETRY_COUNT=${CUE_TF_CREATE_CLUSTER_NODE_VM_ACTIVE_RETRY_COUNT:-12}

# Public IP/Port Settings
CUE_SERVICE_PROTOCOL=${CUE_SERVICE_PROTOCOL:-$SERVICE_PROTOCOL}
CUE_SERVICE_HOST=${CUE_SERVICE_HOST:-$SERVICE_HOST}
CUE_SERVICE_PORT=${CUE_SERVICE_PORT:-8795}

CUE_DEFAULT_BROKER_NAME=${CUE_DEFAULT_BROKER_NAME:-rabbitmq}

CUE_MANAGEMENT_KEY='cue-mgmt-key'
CUE_RABBIT_SECURITY_GROUP='cue-rabbitmq'

CUE_RABBIT_IMAGE_MINDISK=4

CUE_FLAVOR=cue.small
CUE_FLAVOR_PARAMS="--id 8795 --ram 512 --disk $CUE_RABBIT_IMAGE_MINDISK --vcpus 1"
CUE_RABBIT_SECURITY_GROUP='cue-rabbitmq'
CUE_MANAGEMENT_NETWORK_NAME='cue_management_net'
CUE_MANAGEMENT_SUBNET_NAME='cue_management_subnet'

CUE_RABBIT_IMAGE_ELEMENTS=${CUE_RABBIT_IMAGE_ELEMENTS:-\
vm ubuntu os-refresh-config os-apply-config ntp hosts \
ifmetric cue-rabbitmq-base}

# cleanup_cue - Remove residual data files, anything left over from previous
# runs that a clean run would need to clean up
function cleanup_cue {
    sudo rm -rf $CUE_STATE_PATH $CUE_AUTH_CACHE_DIR
}

# configure_cue - Set config files, create data dirs, etc
function configure_cue {
    [ ! -d $CUE_CONF_DIR ] && sudo mkdir -m 755 -p $CUE_CONF_DIR
    sudo chown $STACK_USER $CUE_CONF_DIR

    [ ! -d $CUE_LOG_DIR ] &&  sudo mkdir -m 755 -p $CUE_LOG_DIR
    sudo chown $STACK_USER $CUE_LOG_DIR

    # (Re)create ``cue.conf``
    rm -f $CUE_CONF

    iniset_rpc_backend cue $CUE_CONF DEFAULT
    iniset $CUE_CONF DEFAULT debug $ENABLE_DEBUG_LOG_LEVEL
    iniset $CUE_CONF DEFAULT verbose True
    iniset $CUE_CONF DEFAULT state_path $CUE_STATE_PATH
    iniset $CUE_CONF database connection `database_connection_url cue`

    # Support db as a persistence backend
    if [ "$CUE_TF_PERSISTENCE" == "db" ]; then
        iniset $CUE_CONF taskflow persistence_connection `database_connection_url $CUE_TF_DB`
    fi

    # Set cluster node check timeouts
    iniset $CUE_CONF taskflow cluster_node_check_timeout 30
    iniset $CUE_CONF taskflow cluster_node_check_max_count 120

    # Set flow create cluster node vm active retry count
    iniset $CUE_CONF flow_options create_cluster_node_vm_active_retry_count $CUE_TF_CREATE_CLUSTER_NODE_VM_ACTIVE_RETRY_COUNT

    iniset $CUE_CONF openstack os_auth_url $KEYSTONE_AUTH_PROTOCOL://$KEYSTONE_AUTH_HOST:$KEYSTONE_AUTH_PORT/v3
    iniset $CUE_CONF openstack os_project_name admin
    iniset $CUE_CONF openstack os_username admin
    iniset $CUE_CONF openstack os_password $ADMIN_PASSWORD
    iniset $CUE_CONF openstack os_project_domain_name default
    iniset $CUE_CONF openstack os_user_domain_name default
    iniset $CUE_CONF openstack os_auth_version 3

    if [ "$SYSLOG" != "False" ]; then
        iniset $CUE_CONF DEFAULT use_syslog True
    fi

    # Format logging
    if [ "$LOG_COLOR" == "True" ] && [ "$SYSLOG" == "False" ]; then
        setup_colorized_logging $CUE_CONF DEFAULT "tenant" "user"
    fi

    # Set some libraries' log level to INFO so that the log isn't overrun with useless DEBUG messages
    iniset $CUE_CONF DEFAULT default_log_levels "kazoo.client=INFO,stevedore=INFO"

    if is_service_enabled key; then
        # Setup the Keystone Integration
        iniset $CUE_CONF service:api auth_strategy keystone
        configure_auth_token_middleware $CUE_CONF cue $CUE_AUTH_CACHE_DIR
    fi

    iniset $CUE_CONF service:api api_host $CUE_SERVICE_HOST
    iniset $CUE_CONF service:api api_base_uri $CUE_SERVICE_PROTOCOL://$CUE_SERVICE_HOST:$CUE_SERVICE_PORT/
    if is_service_enabled tls-proxy; then
        # Set the service port for a proxy to take the original
        iniset $CUE_CONF service:api api_port $CUE_SERVICE_PORT_INT
    else
        iniset $CUE_CONF service:api api_port $CUE_SERVICE_PORT
    fi

    # Install the policy file for the API server
    cp $CUE_DIR/etc/cue/policy.json $CUE_CONF_DIR/policy.json
    iniset $CUE_CONF DEFAULT policy_file $CUE_CONF_DIR/policy.json
}

# create_cue_accounts - Set up common required cue accounts

# Tenant               User       Roles
# ------------------------------------------------------------------
# service              cue  admin        # if enabled
function create_cue_accounts {
    local admin_role=$(openstack role list | awk "/ admin / { print \$2 }")

    if [[ "$ENABLED_SERVICES" =~ "cue-api" ]]; then
        local cue_user=$(get_or_create_user "cue" \
            "$SERVICE_PASSWORD" "default")
        get_or_add_user_project_role $admin_role $cue_user $SERVICE_TENANT_NAME

        if [[ "$KEYSTONE_CATALOG_BACKEND" = 'sql' ]]; then
            local cue_service=$(get_or_create_service "cue" \
                "message-broker" "Message Broker Provisioning Service")
            get_or_create_endpoint $cue_service \
                "$REGION_NAME" \
                "$CUE_SERVICE_PROTOCOL://$CUE_SERVICE_HOST:$CUE_SERVICE_PORT/" \
                "$CUE_SERVICE_PROTOCOL://$CUE_SERVICE_HOST:$CUE_SERVICE_PORT/" \
                "$CUE_SERVICE_PROTOCOL://$CUE_SERVICE_HOST:$CUE_SERVICE_PORT/"
        fi
    fi
}

function create_cue_initial_resources {
    #ADMIN_TENANT_ID=$(keystone tenant-list | grep " admin " | get_field 1)
    echo "Creating initial resources."
}

# init_cue - Initialize etc.
function init_cue {
    # Create cache dir
    sudo mkdir -p $CUE_AUTH_CACHE_DIR
    sudo chown $STACK_USER $CUE_AUTH_CACHE_DIR
    rm -f $CUE_AUTH_CACHE_DIR/*

    # (Re)create cue database
    recreate_database cue utf8

    # Init and migrate cue database
    cue-manage --config-file $CUE_CONF database upgrade

    # Init and migrate cue pool-manager-cache
    if [ "$CUE_TF_PERSISTENCE" == "db" ]; then
        recreate_database $CUE_TF_DB utf8
        cue-manage --config-file $CUE_CONF taskflow upgrade
    fi


    NEUTRON_OS_URL="${Q_PROTOCOL}://$Q_HOST:$Q_PORT"
    OPENSTACK_CMD="openstack"
    NEUTRON_CMD="neutron"

    # Create cue specific flavor if one does not exist
    if [[ -z $($OPENSTACK_CMD flavor list | grep $CUE_FLAVOR) ]]; then
        $OPENSTACK_CMD flavor create $CUE_FLAVOR_PARAMS $CUE_FLAVOR
    fi

    # Set os_security_group
    if [[ -z $($OPENSTACK_CMD security group list | grep $CUE_RABBIT_SECURITY_GROUP) ]]; then
        $OPENSTACK_CMD security group create --description "Cue RabbitMQ broker security group" $CUE_RABBIT_SECURITY_GROUP
        $OPENSTACK_CMD security group rule create --src-ip 0.0.0.0/0 --proto tcp --dst-port 5672:5672 $CUE_RABBIT_SECURITY_GROUP
        $OPENSTACK_CMD security group rule create --src-ip 0.0.0.0/0 --proto tcp --dst-port 4369:4369 $CUE_RABBIT_SECURITY_GROUP
        $OPENSTACK_CMD security group rule create --src-ip 0.0.0.0/0 --proto tcp --dst-port 61000:61000 $CUE_RABBIT_SECURITY_GROUP
        $OPENSTACK_CMD security group rule create --src-ip 0.0.0.0/0 --proto tcp --dst-port 15672:15672 $CUE_RABBIT_SECURITY_GROUP
    fi

    CUE_RABBIT_SECURITY_GROUP_ID=$($OPENSTACK_CMD security group list | grep $CUE_RABBIT_SECURITY_GROUP | tr -d ' ' | cut -f 2 -d '|')
    if [ $CUE_RABBIT_SECURITY_GROUP_ID ]; then
        iniset $CUE_CONF DEFAULT os_security_group $CUE_RABBIT_SECURITY_GROUP_ID
    fi

    # Set VM management key
    if [ $CUE_MANAGEMENT_KEY ]; then
        iniset $CUE_CONF openstack os_key_name $CUE_MANAGEMENT_KEY
    fi

    # Create cue management-network
    if [[ -z $($NEUTRON_CMD net-list | grep $CUE_MANAGEMENT_NETWORK_NAME) ]]; then
        $NEUTRON_CMD net-create $CUE_MANAGEMENT_NETWORK_NAME --provider:network-type local
        CUE_MANAGEMENT_SUBNET_ROUTER_IP="$(echo $CUE_MANAGEMENT_NETWORK_SUBNET | cut -f 1-3 -d '.').1"
        $NEUTRON_CMD subnet-create $CUE_MANAGEMENT_NETWORK_NAME $CUE_MANAGEMENT_NETWORK_SUBNET --name $CUE_MANAGEMENT_SUBNET_NAME --host-route destination=$FLOATING_RANGE,nexthop=$CUE_MANAGEMENT_SUBNET_ROUTER_IP
        $NEUTRON_CMD router-interface-add $Q_ROUTER_NAME $CUE_MANAGEMENT_SUBNET_NAME
    fi

    # Configure host route to management-network
    CUE_MANAGEMENT_SUBNET_IP=$(echo $CUE_MANAGEMENT_NETWORK_SUBNET | cut -f 1 -d '/')
    if [[ -z $(netstat -rn | grep $CUE_MANAGEMENT_SUBNET_IP ) ]]; then
        if [[ ! -z $($NEUTRON_CMD router-show $Q_ROUTER_NAME 2>/dev/null) ]]; then
            ROUTER_IP=$($NEUTRON_CMD router-show $Q_ROUTER_NAME | grep ip_address | cut -f 16 -d '"')
            sudo route add -net $CUE_MANAGEMENT_NETWORK_SUBNET gw $ROUTER_IP
        fi
    fi

    # Set management-network id
    CUE_MANAGEMENT_NETWORK_ID=$($NEUTRON_CMD net-list | grep $CUE_MANAGEMENT_NETWORK_NAME | tr -d ' ' | cut -f 2 -d '|')
    if [ $CUE_MANAGEMENT_NETWORK_ID ]; then
        iniset $CUE_CONF DEFAULT management_network_id $CUE_MANAGEMENT_NETWORK_ID
    fi

    set_broker

    configure_scenario_rally_tests

    build_cue_rabbit_test_image
}

# install_cue - Collect source and prepare
function install_cue {
    git_clone $CUE_REPO $CUE_DIR $CUE_BRANCH
    setup_develop $CUE_DIR
}

# install_cueclient - Collect source and prepare
function install_cueclient {
    git_clone $CUECLIENT_REPO $CUECLIENT_DIR $CUECLIENT_BRANCH
    setup_develop $CUECLIENT_DIR
}

# install_cuedashboard - Collect source and prepare
function install_cuedashboard {

    if is_service_enabled horizon; then
        git_clone $CUEDASHBOARD_REPO $CUEDASHBOARD_DIR $CUEDASHBOARD_BRANCH
        mv $CUEDASHBOARD_DIR/test-requirements.txt $CUEDASHBOARD_DIR/_test-requirements.txt
        setup_develop $CUEDASHBOARD_DIR

        if ! [ -h $DEST/horizon/openstack_dashboard/local/enabled/_70_cue_panel_group.py ]; then
            ln -s $DEST/cue-dashboard/_70_cue_panel_group.py $DEST/horizon/openstack_dashboard/local/enabled/_70_cue_panel_group.py
        fi
        if ! [ -h  $DEST/horizon/openstack_dashboard/local/enabled/_71_cue_panel.py ]; then
            ln -s $DEST/cue-dashboard/_71_cue_panel.py $DEST/horizon/openstack_dashboard/local/enabled/_71_cue_panel.py
        fi
        mv $CUEDASHBOARD_DIR/_test-requirements.txt $CUEDASHBOARD_DIR/test-requirements.txt
    fi
}

# configure Cue Scenario Rally tests
function configure_scenario_rally_tests {

    if ! [ -d $HOME/.rally/plugins ]; then
        mkdir -p $HOME/.rally/plugins/cue_scenarios

        SCENARIOS=$(find $DEST/cue/rally-jobs/plugins -type f -name "*.py")
        for SCENARIO in $SCENARIOS
        do
            FILE_NAME=$(echo $SCENARIO | rev | cut -d/ -f1 | rev)
            ln -s $SCENARIO $HOME/.rally/plugins/cue_scenarios/$FILE_NAME
        done
    fi
}

# start_cue - Start running processes, including screen
function start_cue {
    run_process cue-api "$CUE_BIN_DIR/cue-api --config-file $CUE_CONF"
    run_process cue-worker "$CUE_BIN_DIR/cue-worker --config-file $CUE_CONF"
    run_process cue-monitor "$CUE_BIN_DIR/cue-monitor --config-file $CUE_CONF"

    # Start proxies if enabled
    if is_service_enabled cue-api && is_service_enabled tls-proxy; then
        start_tls_proxy '*' $CUE_SERVICE_PORT $CUE_SERVICE_HOST $CUE_SERVICE_PORT_INT &
    fi

    if ! timeout $SERVICE_TIMEOUT sh -c "while ! wget --no-proxy -q -O- $CUE_SERVICE_PROTOCOL://$CUE_SERVICE_HOST:$CUE_SERVICE_PORT; do sleep 1; done"; then
        die $LINENO "Cue did not start"
    fi
}

# stop_cue - Stop running processes
function stop_cue {
    # Kill the cue screen windows
    stop_process cue-api
}

# build_cue_rabbit_test_image() - Build and upload functional test image
function build_cue_rabbit_test_image {
    if is_service_enabled dib; then
        local image_name=cue-rabbitmq-test-image

        # Elements path for tripleo-image-elements and cue-image-elements
        local elements_path=$TIE_DIR/elements:$CUE_DIR/contrib/image-elements

        disk_image_create_upload "$image_name" "$CUE_RABBIT_IMAGE_ELEMENTS" "$elements_path"

        # Set image_id
        RABBIT_IMAGE_ID=$($OPENSTACK_CMD image list | grep $image_name | tr -d ' ' | cut -f 2 -d '|')
        if [ "$RABBIT_IMAGE_ID" ]; then
            cue-manage --config-file $CUE_CONF broker add_metadata $BROKER_ID --image $RABBIT_IMAGE_ID
        fi

    else
        echo "Error, Builing RabbitMQ Image requires dib" >&2
        echo "Add \"enable_service dib\" to your localrc" >&2
        exit 1
    fi
}

# set_broker - Set default broker
function set_broker {
    cue-manage --config-file $CUE_CONF broker add $CUE_DEFAULT_BROKER_NAME true
    BROKER_ID=$(cue-manage --config-file $CUE_CONF broker list | grep $CUE_DEFAULT_BROKER_NAME | tr -d ' ' | cut -f 2 -d '|')
}

# Set up cue for testing
function setup_cue {
    IPTABLES_RULE='iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE'

    # Create NAT rule to allow VMs to NAT to host IP
    if [[ -z $(sudo iptables -t nat -L | grep MASQUERADE | tr -d ' ' | grep anywhereanywhere) ]]; then
        sudo $IPTABLES_RULE
    fi

    # Make VM NAT rule persistent
    # TODO(sputnik13): this should ideally be somewhere other than /etc/rc.local
    if [[ -z $(grep "$IPTABLES_RULE" /etc/rc.local) ]]; then
        sudo sed -i -e "s/^exit 0/$IPTABLES_RULE\nexit 0/" /etc/rc.local
    fi

    if [[ ! -x /etc/rc.local ]]; then
        sudo chmod +x /etc/rc.local
    fi

    # Generate an ssh keypair to add to devstack
    if [[ ! -f ~/.ssh/id_rsa ]]; then
        ssh-keygen -q -t rsa -N "" -f ~/.ssh/id_rsa
        # copying key to /tmp so that tests can access it
        cp ~/.ssh/id_rsa /tmp/cue-mgmt-key
        chmod 644 /tmp/cue-mgmt-key
    fi

    if [[ -z $CUE_MANAGEMENT_KEY ]]; then
        CUE_MANAGEMENT_KEY='vagrant'
    fi

    # Add ssh keypair to admin account
    if [[ -z $(openstack keypair list | grep $CUE_MANAGEMENT_KEY) ]]; then
        openstack keypair create --public-key ~/.ssh/id_rsa.pub $CUE_MANAGEMENT_KEY
    fi

    # Add ping and ssh rules to rabbitmq security group
    neutron security-group-rule-create --direction ingress --protocol icmp --remote-ip-prefix 0.0.0.0/0 $CUE_RABBIT_SECURITY_GROUP
    neutron security-group-rule-create --direction ingress --protocol tcp --port-range-min 22 --port-range-max 22 --remote-ip-prefix 0.0.0.0/0 $CUE_RABBIT_SECURITY_GROUP

    # Add static nameserver to private-subnet
    neutron subnet-update --dns-nameserver 8.8.8.8 private-subnet

    unset OS_PROJECT_DOMAIN_ID
    unset OS_REGION_NAME
    unset OS_USER_DOMAIN_ID
    unset OS_IDENTITY_API_VERSION
    unset OS_PASSWORD
    unset OS_AUTH_URL
    unset OS_USERNAME
    unset OS_PROJECT_NAME
    unset OS_TENANT_NAME
    unset OS_VOLUME_API_VERSION
    unset COMPUTE_API_VERSION
    unset OS_NO_CACHE

    # Add ssh keypair to demo account
    #IDENTITY_API_VERSION=3 source $TOP_DIR/openrc demo demo
    #if [[ -z $(openstack keypair list | grep $CUE_MANAGEMENT_KEY) ]]; then
    #    openstack keypair create --public-key ~/.ssh/id_rsa.pub $CUE_MANAGEMENT_KEY
    #fi
}

# Restore xtrace
$XTRACE


# Devstack plugin script to install diskimage-builder
if is_service_enabled dib; then
    if [[ "$1" == "source" ]]; then
        # Initial source
        source $TOP_DIR/lib/dib
    elif [[ "$1" == "stack" && "$2" == "install" ]]; then
        echo_summary "Installing diskimage-builder"
        install_dib
    elif [[ "$1" == "stack" && "$2" == "post-config" ]]; then
        # no-op
        :
    elif [[ "$1" == "stack" && "$2" == "extra" ]]; then
        # no-op
        :
    fi

    if [[ "$1" == "unstack" ]]; then
        # no-op
        :
    fi

    if [[ "$1" == "clean" ]]; then
        # no-op
        :
    fi
fi


# Devstack plugin script to install cue
if is_service_enabled cue; then

    if [[ "$1" == "source" ]]; then
        # Initial source of lib script
        source $TOP_DIR/lib/cue
    fi

    if [[ "$1" == "stack" && "$2" == "install" ]]; then
        echo_summary "Installing Cue"
        install_cue

        echo_summary "Installing Cue Client"
        install_cueclient

        echo_summary "Installing Cue Dashboard"
        install_cuedashboard

    elif [[ "$1" == "stack" && "$2" == "post-config" ]]; then
        echo_summary "Configuring Cue"
        configure_cue

        if is_service_enabled key; then
            echo_summary "Creating Cue Keystone Accounts"
            create_cue_accounts
        fi

    elif [[ "$1" == "stack" && "$2" == "extra" ]]; then
        echo_summary "Creating Initial Cue Resources"
        create_cue_initial_resources

        echo_summary "Initializing Cue"
        init_cue

        echo_summary "Starting Cue"
        start_cue

        echo_summary "Setting up cue for testing"
        setup_cue
    fi

    if [[ "$1" == "unstack" ]]; then
        stop_cue
    fi

    if [[ "$1" == "clean" ]]; then
        echo_summary "Cleaning Cue"
        cleanup_cue
    fi
fi


# Devstack plugin script to configure Rally for cue
if [[ "$1" == "stack" && "$2" == "post-config" ]]; then
    if [[ ! -z $RALLY_AUTH_URL ]]; then
        # rally deployment create
        tmpfile=$(mktemp)
        _create_deployment_config $tmpfile

        iniset $RALLY_CONF_DIR/$RALLY_CONF_FILE database connection `database_connection_url rally`
        recreate_database rally utf8
        # Recreate rally database
        $RALLY_BIN_DIR/rally-manage --config-file $RALLY_CONF_DIR/$RALLY_CONF_FILE db recreate

        rally --config-file /etc/rally/rally.conf deployment create --name cue-devstack2 --file $tmpfile
    fi
fi


# _create_deployment_config filename
function _create_deployment_config() {
    cat >$1 <<EOF
{
    "type": "ExistingCloud",
    "auth_url": "$KEYSTONE_AUTH_PROTOCOL://$KEYSTONE_AUTH_HOST:$KEYSTONE_AUTH_PORT/$RALLY_AUTH_VERSION",
    "admin": {
        "username": "admin",
        "password": "$ADMIN_PASSWORD",
        "project_name": "admin"
    }
}
EOF
}



