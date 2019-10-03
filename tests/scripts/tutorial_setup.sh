#!/bin/bash -xe

set -o vi
export EDITOR=vim
alias cls=clear
alias dir="ls -Al --color=auto"
gcloud config set compute/zone us-east1-d
git clone https://github.com/GoogleCloudPlatform/continuous-deployment-on-kubernetes.git
cd continuous-deployment-on-kubernetes
gcloud container clusters create jenkins-cd --num-nodes 2 --machine-type n1-standard-2 --metadata disable-legacy-endpoints=FALSE --cluster-version 1.13 --scopes "cloud-source-repos-ro,cloud-platform"
gcloud container clusters get-credentials jenkins-cd
kubectl get pods
wget https://storage.googleapis.com/kubernetes-helm/helm-v2.14.3-linux-amd64.tar.gz
tar zxfv helm-v2.14.3-linux-amd64.tar.gz
cp linux-amd64/helm .
kubectl create clusterrolebinding cluster-admin-binding --clusterrole=cluster-admin --user=$(gcloud config get-value account)
kubectl create serviceaccount tiller --namespace kube-system                                                                            
./helm init --service-account=tiller
./helm repo update
./helm version
./helm install -n cd stable/jenkins -f jenkins/values.yaml --version 1.7.3 --wait
kubectl get pods
kubectl create clusterrolebinding jenkins-deploy --clusterrole=cluster-admin --serviceaccount=default:cd-jenkins
export POD_NAME=$(kubectl get pods -l "app.kubernetes.io/component=jenkins-master" -o jsonpath="{.items[0].metadata.name}")
kubectl port-forward $POD_NAME 8080:8080 >> /dev/null &
kubectl get svc
cd sample-app/
kubectl create ns production
kubectl --namespace=production apply -f k8s/production
kubectl --namespace=production apply -f k8s/canary
kubectl --namespace=production apply -f k8s/services
kubectl --namespace=production scale deployment gceme-frontend-production --replicas=4
cd sample-app
git init
git config credential.helper gcloud.sh
gcloud source repos create gceme
git remote add origin https://source.developers.google.com/p/$GOOGLE_CLOUD_PROJECT/r/gceme
git remote -v
git config --global user.email "$USER@qwiklabs.net"
git config --global user.name "$USER"
git config --global -l
git add .
git commit -m "Initial commit"
git push origin master
kubectl --namespace=production get service gceme-frontend
printf $(kubectl get secret cd-jenkins -o jsonpath="{.data.jenkins-admin-password}" | base64 --decode);echo
echo "https://source.developers.google.com/p/$GOOGLE_CLOUD_PROJECT/r/gceme"
