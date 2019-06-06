# Terraform destroy does not allow to exclude a resource
# we need to list all the resources we want to destroy
# we need to also preserve the "router" resource which is
# a dependency of the floating ip resource
# this works for any number of master or nodes
# you can update this by running:
# `terraform plan -destroy -out=tf.plan` (also add other args from `terraform_destroy.sh` except -auto-approve
# and then `terraform show tf.plan`
terraform destroy -var-file=cluster.tf -var "cluster_name=${CLUSTER/_/-}" \
    -target=module.compute.openstack_compute_floatingip_associate_v2.k8s_master \
    -target=module.compute.openstack_compute_instance_v2.k8s_master \
    -target=module.compute.openstack_compute_instance_v2.k8s_node_no_floating_ip \
    -target=module.compute.openstack_compute_keypair_v2.k8s \
    -target=module.compute.openstack_networking_secgroup_rule_v2.bastion \
    -target=module.compute.openstack_networking_secgroup_rule_v2.k8s \
    -target=module.compute.openstack_networking_secgroup_rule_v2.k8s_master \
    -target=module.compute.openstack_networking_secgroup_rule_v2.k8s_master_http \
    -target=module.compute.openstack_networking_secgroup_rule_v2.k8s_master_https \
    -target=module.compute.openstack_networking_secgroup_rule_v2.k8s_master_ping \
    -target=module.compute.openstack_networking_secgroup_rule_v2.worker \
    -target=module.compute.openstack_networking_secgroup_v2.bastion \
    -target=module.compute.openstack_networking_secgroup_v2.k8s \
    -target=module.compute.openstack_networking_secgroup_v2.k8s_master \
    -target=module.compute.openstack_networking_secgroup_v2.worker \
    -target=module.network.openstack_networking_network_v2.k8s \
    -target=module.network.openstack_networking_subnet_v2.k8s \
     ../../contrib/terraform/openstack
