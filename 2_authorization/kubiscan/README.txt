kubectl apply -f - << EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: kubiscan-sa
  namespace: default
---
kind: ClusterRoleBinding
apiVersion: rbac.authorization.k8s.io/v1beta1
metadata: 
  name: kubiscan-clusterrolebinding
subjects: 
- kind: ServiceAccount 
  name: kubiscan-sa
  namespace: default
  apiGroup: ""
roleRef: 
  kind: ClusterRole
  name: kubiscan-clusterrole
  apiGroup: ""
---
kind: ClusterRole
apiVersion: rbac.authorization.k8s.io/v1beta1
metadata: 
  name: kubiscan-clusterrole
rules: 
- apiGroups: ["*"]
  resources: ["roles", "clusterroles", "rolebindings", "clusterrolebindings", "pods"]
  verbs: ["get", "list"]
EOF

kubectl get secrets $(kubectl get sa kubiscan-sa -o json | jq -r '.secrets[0].name') -o json | jq -r '.data.token' | base64 -d > token

docker cp kind-control-plane:/etc/kubernetes/pki/ca.crt .
docker run -it --rm -v $PWD/token:/token -v $PWD/ca.crt:/ca.crt --net=host cyberark/kubiscan
# Get API server IP inside ~/.kube/config
kubiscan -ho 127.0.0.1:38803 -t /token -c /ca.crt -rs
