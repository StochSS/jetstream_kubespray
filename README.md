Setup instructions for provisioning openstack resources and setting up kubernetes for StochSS

## Install Terraform
- [Download Terraform 0.11.14](https://releases.hashicorp.com/terraform/0.11.14)
- Install the binary somewhere in PATH (see Terraform's [install guide](https://learn.hashicorp.com/terraform/getting-started/install.html))


## Install the Openstack client
- Install [python-openstackclient](https://pypi.org/project/python-openstackclient/) from PyPI


## Obtain Jetstream OpenStack API access

- Ask the project PI to set up API access for you. If you're using your own XSEDE allocation, follow [these instructions](https://iujetstream.atlassian.net/wiki/spaces/JWT/pages/39682057/Using+the+Jetstream+API).

- After you have been granted API access, follow [these instructions](https://iujetstream.atlassian.net/wiki/spaces/JWT/pages/31391748/After+API+access+has+been+granted). Reset your TACC password if you need to (this is different from your XSEDE password).

- Find the section on [this page](https://iujetstream.atlassian.net/wiki/spaces/JWT/pages/39682064/Setting+up+openrc.sh) called "Use the Horizon dashboard to generate openrc.sh." Follow the instructions to download your OpenStack configuration script. Save the file somewhere like your home directory.

- Load the script and enter your TACC password when prompted: `source XX-XXXXXXX-openrc.sh`.

- Test it: `openstack flavor list`. The result should be a list of server sizes.


## Setup OpenStack Resources

- Clone the stochss kubespray repository. Make sure you're on branch `branch_v2.8.2`.
```bash
# HTTPS
git clone https://github.com/stochss/jetstream_kubespray
# SSH
git clone git@github.com:stochss/jetstream_kubespray
```

- For setting up your own cluster, copy the stochss-dev template. **You MUST set the CLUSTER shell variable!**
```bash
export CLUSTER=$USER
cp -LRp inventory/stochss-dev inventory/$CLUSTER
```

- Generate a keypair with `ssh-keygen` that you'll use to access the master server

- Open `inventory/$CLUSTER/cluster.tf` in a text editor
  - Change the value of `public_key_path` to match the key you just generated
  - Change the network name to something unique, like the expanded form of `$CLUSTER_network`
  - Run this command to get a list of images enabled for the OpenStack API: `openstack image list | grep "JS-API"`
  - Verify the value of `image` in `cluster.tf` shows up in the result of the previous command. If it doesn't, replace the value of `image` in `cluster.tf` with the most similar image name in the list of returned results from the `image list` command (a newer CentOS 7 image). The image MUST have 'JS-API-Featured' in the name.

- Verify that the `public` network is available: `openstack network list`.

- Initialize Terraform (from `inventory/$CLUSTER/`)

```bash
bash terraform_init.sh
```

- Create the resources:
```bash
bash terraform_apply.sh
```

- The output of the previous command have the IP address of the master node. Wait for it to boot and then ssh into it:
```bash
ssh centos@IP
```

- Check out the OpenStack resources you just made
```bash
openstack server list
openstack network list
```

- If you ever want to destroy EVERYTHING, run the following command. This script may need to be refactored to only destroy cluster-specific resources, so take care.
```bash
# Beware!
bash terraform_destroy.sh
```


## Install Kubernetes

- Navigate back to the root of the `jetstream_kubespray` repository.

- Install pipenv, the package manger for python:
```bash
pip install -U pipenv
```

- Install `ansible` and other requirements:
```bash
pipenv install -r requirements.txt
```

- Open a pipenv shell to access ansible CLI tools:
```bash
pipenv shell
```

- Setup ssh for ansible:
```bash
eval $(ssh-agent -s)
# Is this the key set in cluster.tf?
ssh-add ~/.ssh/stochss_rsa
```

- Test the connection with ansible:
```bash
ansible -i inventory/$CLUSTER/hosts -m ping all
```

- If a server is not responding to the ping, try rebooting it first:
```bash
openstack server reboot $CLUSTER-k8s-node-nf-1
```

- Run this workaround for a bug:
```bash
export OS_TENANT_ID=$OS_PROJECT_ID
```

- Now run the playbook to install kubernetes (this will take several minutes):
```bash
ansible-playbook --become -i inventory/$CLUSTER/hosts cluster.yml
```

If the playbook fails with "cannot lock the administrative directory", it means the server is updating and has locked the APT directory. Just run the playbook again in a minute or so. If the playbook gives any error, try it again. Sometimes there are temporary failed tasks. Ansible is designed to be executed multiple times with consistent results.

When the playbook finishes, you should have a kubernetes cluster setup on your openstack servers. Test it with:
```bash
ssh centos@IP
sudo -i
# Add /usr/local/bin to PATH so you can use kubectl
echo "export PATH=$PATH:/usr/local/bin" >> .bashrc
source .bashrc
kubectl get pods --all-namespaces
```

## Install GlusterFS

- Fix a symlink so glusterfs refers to your cluster config
```bash
cd ./contrib/network-storage/glusterfs
rm group-vars
ln -s ../../../inventory/$CLUSTER/group-vars
```

- Provision the glusterfs nodes (see ./contrib/network-storage/glusterfs for details)
```bash
ansible-playbook -b --become-user=root -i inventory/$CLUSTER/hosts ./contrib/network-storage/glusterfs/glusterfs.yml
```

- Todo: setup heketi management server for glusterfs
