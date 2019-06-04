sed 's/10\.0\.0\.[[:digit:]]\+/127.0.0.1/g' inventory/$CLUSTER/artifacts/admin.conf > $HOME/.kube/config
