RabbitMQ disk images for the Cue service
========================================

These elements are used to build disk images for the Cue service.

#Notes on building disk images

Building images involves using the Tripleo `diskimage-builder` tools that are found in 
the GitHub repository given below. 

Note that recent changes to this package mean that before the `diskimage-builder` tools 
can be used it is necessary to install `dib-utils` as shown below in order to satisfy 
all dependencies. The modified `PATH` definition should be included in `.profile`, or 
somewhere similarly appropriate. 
```
$ git clone https://github.com/openstack/diskimage-builder
$ export PATH=$HOME/diskimage-builder/bin:$PATH
$ pip install dib-utils
```

In addition (and in accordance with the instructions provided for the `diskimage-builder`
package) it is also necessary to install the `qemu-utils` and `kpartx` packages:
```
$ sudo apt-get install qemu-utils
$ sudo apt-get install kpartx
```

It should now be possible to execute commands such as the following to create disk images. 
```
$ disk-image-create -a amd64 -o ubuntu-amd64 vm ubuntu
```

The next step is to fold in our Cue-specific image elements (the elements found here). This 
is straightforward, and basically just involves defining `ELEMENT_PATH` to include the 
locations of all applicable elements as a colon-separated list. But first, we need to be 
aware that Cue images is going to require some elements from Tripleo (namely `iptables` and 
`sysctl`), so before getting too carried away, we need to clone the repository containing 
these elements:
```
$ git clone https://github.com/openstack/tripleo-image-elements
```

Now, assuming that we have our Cue-specific elements in `./cue-image-elements/elements`, we 
can define `ELEMENT_PATH` as follows, and then try building an image:
```
$ export ELEMENTS_PATH=$HOME/cue/cue-image-elements/elements:$HOME/tripleo-image-elements/elements
$ disk-image-create -a amd64 -o ubuntu-amd64-brc-rabbit vm ubuntu cue-rabbitmq-plugins
```

Change the base image (in this case Ubuntu) and other parameters as appropriate. Assuming that all is well, the above command sequence
will result in the creation of an image named `ubuntu-amd64-brc-rabbit.qcow2`, which can then be loaded into glance and tested.

#What is currently in the Cue service RabbitMQ image
The intention is to keep the RabbitMQ disk image for Cue relatively simple. The image will provide little more than a basic installation of 
RabbitMQ with the Keystone and managemnent plugins enabled; however the initial `rabbitmq.config` will not specify the use of the Keystone 
plugin for authentication. After the disk image is booted and RabbitMQ started, the Cue service will be expected to perform the necessary 
sequence of operations to construct a cluster (if more than one node) and activate Keystone-based authentication.

##Some point(s) to note
- The image includes a fairly basic `rabbitmq.config` that should be retained until after the cluster has been created. Once the cluster has 
been created and verified, this initial `rabbitmq.config` should be replaced by the Cue service using the template configuration file 
`rabbitmq.config.cue-template` (both files are to be found in `/etc/rabbitmq`), populating it with the desired Keystone endpoint. Additional 
notes on this matter can be found below.
- For testing purposes, the `rabbitmq.config` currently included in the image enables `guest` logon (`{loopback_users,[]}`). This should be 
disabled before generating any production images!
- Two targets are provided in the `elements` directory, namely `cue-rabbitmq-base` and `cue-rabbitmq-plugins`. The former can be used to 
create an image that includes a bare-bones vanilla RabbitMQ installation with no plugins enabled. The latter depends on (inherits) `cue-rabbitmq-base` 
and can be used to create iamges with the management and Keystone authentication plugins enabled.


#Notes about what the Cue service needs to do
Once the Cue service is satisfied that all nodes have successfully booted and RabbitMQ is available, the service should perform the following 
general sequence of events to cluster the nodes (if necessary) and activate Keystone-based authentication.

- Update `/etc/hosts` on all nodes to include the IP addresses of the cluster nodes

- Create a cookie file (`/var/lib/rabbitq/.erlang.cookie`) on each node (using the same cookie). A reasonable choice for the cookie string 
might be the UUID generated by Cue to uniquely identify the cluster. Ensure that the cookie file has the correct permissions and owner.

```
$ sudo chmod 400 /var/lib/rabbitmq/.erlang.cookie
$ sudo chown rabbitmq:rabbitmq /var/lib/rabbitmq/.erlang.cookie
```

Once the above two steps have been performed, it is possible to construct the cluster.

- On all one of the cluster nodes issue the following commands (replacing `your-hostname` as appropriate):
```
$ sudo rabbitmqctl stop_app
$ sudo rabbitmqctl reset
$ sudo rabbitmqctl join_cluster rabbit@your-hostname
$ sudo rabbitmqctl start_app
$ sudo rabbitmqctl cluster_status # to check the status of the cluster
```

- Once the cluster has formed, replace the management plugin with the version patched for Cue and Keystone, and replace the existing 
`rabbitmq.config` file using the template configuration file (replace `X.Y.Z` with the relevant RabbitMQ version number, and replace the 
Keystone endpoint as appropriate):
```
$ sudo cp /usr/lib/rabbitmq/lib/rabbitmq_server-X.Y.Z/plugins/rabbitmq_management-X.Y.Z.ez.cue /usr/lib/rabbitmq/lib/rabbitmq_server-X.Y.Z/plugins//rabbitmq_management-X.Y.Z.ez
$ sed 's/##keystone_url##/https:\/\/region-a.geo-1.identity.hpcloudsvc.com:35357\/v3\/auth\/tokens/' /etc/rabbitmq/rabbitmq.config.cue-template > /etc/rabbitmq/rabbitmq.config
```

- Systematically restart each cluster node, waiting until the node comes back up before restarting the next node.
- Finally, create the user (using the users' Keystone username) and grant them appropriate permissions (replacing `keystone-username` with the relevant username). For good measure, also delete the `guest` user:
```
$ sudo rabbitmqctl add_user keystone-username nopassword
$ sudo rabbitmqctl set_permissions -p / keystone-username ".*" ".*" ".*"
$ sudo rabbitmqctl set_user_tags keystone-username administrator
$ sudo rabbitmqctl delete_user guest
```
The user can now be informed that the cluster is ready for use.
