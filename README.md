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
# Add /usr/local/bin to PATH so you can use kubectl
sudo echo "export PATH=$PATH:/usr/local/bin" >> /root/.bashrc
sudo su root
echo "export PATH=$PATH:/usr/local/bin" >> ~/.bashrc
source ~/.bashrc
kubectl get pods --all-namespaces
```

## Install GlusterFS/Heketi

- On k8s-master

We will use [gluster-kubernetes](https://github.com/gluster/gluster-kubernetes) to deploy GlusterFS with Heketi

- Fix a symlink so glusterfs refers to your cluster config
```bash
cd ./contrib/network-storage/glusterfs
rm group-vars
ln -s ../../../inventory/$CLUSTER/group-vars
```

- Provision the glusterfs nodes (see ./contrib/network-storage/glusterfs for details)
```bash
ansible-playbook -b --become-user=root -i inventory/$CLUSTER/hosts ./contrib/network-storage/glusterfs/glusterfs.yml

- Setup gluster-kubernetes

git clone https://github.com/gluster/gluster-kubernetes

- Setup topology file

Replace "manage" and "storage" fields with the hostnames and IP addresses of the k8s-node servers

cd gluster-kubernetes/deploy
mv topology.json.sample topology.json

EDIT topology.json

{
  "clusters": [
    {
      "nodes": [
        {
          "node": {
            "hostnames": {
              "manage": [
                "stochss-dev-k8s-node-nf-1"
              ],
              "storage": [
                "10.0.0.13"
              ]
            },
            "zone": 1
          },
          "devices": [
            "/dev/sdb"
          ]
        },
        {
          "node": {
            "hostnames": {
              "manage": [
                "stochss-dev-k8s-node-nf-2"
              ],
              "storage": [
                "10.0.0.10"
              ]
            },
            "zone": 1
          },
          "devices": [
            "/dev/sdb"
          ]
        },
        {
          "node": {
            "hostnames": {
              "manage": [
                "stochss-dev-k8s-node-nf-3"
              ],
              "storage": [
                "10.0.0.8"
              ]
            },
            "zone": 1
          },
          "devices": [
            "/dev/sdb"
          ]
        }
      ]
    }
  ]
}

END Edit topology.json

- Run the deploy script with the modified topology.json

./gk-deploy -g

- Create a StorageClass for dynamic provisioning

EDIT gluster-storage-class.yml

apiVersion: storage.k8s.io/v1beta1
kind: StorageClass
metadata:
  name: glusterfs-storage
provisioner: kubernetes.io/glusterfs
parameters:
  resturl: http://10.233.66.6:8080
  restuser: "heketi"
  restuserkey: "My Heketi Key"

END EDIT

- Create the storage class on the cluster

kubectl create -f gluster-storage-class.yml


- Setup config.template.yaml, secret.template.yaml, and setup_binderhub script from git:stochss/minikube

config.template.yaml 

config:
  BinderHub:
    use_registry: true
    image_prefix: DOCKERID/binder-
    hub_url: dev.stochss.org/jh
    build_namespace: binder

ingress:
  enabled: true
  hosts:
    - dev.stochss.org

jupyterhub:
  hub:
    baseUrl: /jh
  ingress:
    enabled: true
    hosts:
      - dev.stochss.org
  singleuser:
    memory:
      limit: 200M
      guarantee: 200M
    cpu:
      limit: .2
      guarantee: .2
    storage:
      capacity: 1Gi
      dynamic:
        storageClass: glusterfs-storage
        pvcNameTemplate: claim-{username}{servername}
        volumeNameTemplate: volume-{username}{servername}


--- END config.template.yaml ---

secret.template.yaml 

jupyterhub:
  hub:
    services:
      binder:
        apiToken: BINDERTOKEN
  proxy:
    secretToken: PROXYTOKEN
registry:
  username: DOCKERID
  password: DOCKERPASSWD

--- END secret.template.yaml ---


- Modify `bhug_conf_gen` to only generate config files

`bhub_conf_gen` 

```
#!/bin/bash

echo "Generating tokens..."
BINDER_TOKEN=$(openssl rand -hex 32)
PROXY_TOKEN=$(openssl rand -hex 32)

# Get Docker Hub credentials from the user
read -p "What is your docker hub username? " DOCKER_ID

while true
do
  read -s -p "What is your docker hub password? " DOCKER_PASSWD
  echo
  read -s -p "Enter your password again: " PASSWD_VERIFY
  echo

  if [[ "$DOCKER_PASSWD" != "$PASSWD_VERIFY" ]]; then
    echo "Passwords don't match, let's try that again..."
  else
    break
  fi
done

# Create secret.yaml
echo "Creating secret.yaml..."
cat secret.template.yaml | \
  sed -e "s/BINDERTOKEN/$BINDER_TOKEN/g" \
      -e "s/PROXYTOKEN/$PROXY_TOKEN/g" \
      -e "s/DOCKERID/$DOCKER_ID/g" \
      -e "s/DOCKERPASSWD/$DOCKER_PASSWD/g" \
  | cat - > secret.yaml

# Create config.yaml
echo "Creating config.yaml..."
cat config.template.yaml | \
  sed -e "s/DOCKERID/$DOCKER_ID/g" \
  | cat - > config.yaml
```


- Set `bhub_conf_gen` to executable

```chmod +x bhub_conf_gen```

- Add the jupyterhub helm repo (for jupyterhub and binderhub)

helm repo add jupyterhub https://jupyterhub.github.io/helm-chart
helm repo update

helm install jupyterhub/binderhub --version=0.2.0-908c443   --name=binder --namespace=binder -f secret.yaml -f config.yaml




References:

Thanks to Andrea Zonca for this [excellent guide](https://zonca.github.io/2018/09/kubernetes-jetstream-kubespray.html).

