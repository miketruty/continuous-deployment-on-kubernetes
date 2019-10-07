#!/bin/bash -xe

# This script automates the setup and execution of a tutorial to show
# Jenkins, running on a GKE cluster. It uses Helm to install Jenkins
# on the GKE cluster.

# TODO(truty): my personal setup.
set -o vi
export EDITOR=vim
alias cls=clear
alias dir="ls -Al --color=auto"

# Easy access to pinned versions.
GKE_VERSION=1.12
GKE_ZONE=us-east1-d
# HELM_VERSION=2.14.1
HELM_VERSION=2.14.3
# JENKINS_CHART_VERSION=1.2.2
JENKINS_CHART_VERSION=1.7.3

# Get the tutorial code.
git clone https://github.com/GoogleCloudPlatform/continuous-deployment-on-kubernetes.git
cd continuous-deployment-on-kubernetes

# Set up the GKE cluster.
gcloud config set compute/zone $GKE_ZONE
gcloud beta container clusters create jenkins-cd \
  --machine-type n1-standard-2 --num-nodes "2" \
  --cluster-version $GKE_VERSION \
  --workload-metadata-from-node "EXPOSED" \
  --scopes "https://www.googleapis.com/auth/projecthosting","https://www.googleapis.com/auth/cloud-platform","https://www.googleapis.com/auth/source.read_only"
gcloud container clusters get-credentials jenkins-cd
kubectl get pods
kubectl create clusterrolebinding cluster-admin-binding --clusterrole=cluster-admin --user=$(gcloud config get-value account)

# Get and set up for Helm to install Jenkins on the cluster.
wget https://storage.googleapis.com/kubernetes-helm/helm-v$HELM_VERSION-linux-amd64.tar.gz
tar zxfv helm-v$HELM_VERSION-linux-amd64.tar.gz
cp linux-amd64/helm .

kubectl create serviceaccount tiller --namespace kube-system
kubectl create clusterrolebinding tiller-admin-binding --clusterrole=cluster-admin --serviceaccount=kube-system:tiller
./helm init --service-account=tiller
./helm repo update
sleep 30
./helm version
./helm install -n cd stable/jenkins -f jenkins/values.yaml --version $JENKINS_CHART_VERSION --wait
kubectl get pods
kubectl create clusterrolebinding jenkins-deploy --clusterrole=cluster-admin --serviceaccount=default:cd-jenkins
kubectl get svc

# Set up the sample application running on GKE.
cd sample-app/
kubectl create ns production
kubectl --namespace=production apply -f k8s/production
kubectl --namespace=production apply -f k8s/canary
kubectl --namespace=production apply -f k8s/services
kubectl --namespace=production scale deployment gceme-frontend-production --replicas=4

# Set up the application repo, which the Jenkins pipeline will watch.
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

# Waiting for the application external IP to be visible.
kubectl --namespace=production get service gceme-frontend
sleep 50
kubectl --namespace=production get service gceme-frontend

# Set up to access the Jenkins UI.
export POD_NAME=$(kubectl get pods -l "app.kubernetes.io/component=jenkins-master" -o jsonpath="{.items[0].metadata.name}")
kubectl port-forward $POD_NAME 8080:8080 >> /dev/null &
printf $(kubectl get secret cd-jenkins -o jsonpath="{.data.jenkins-admin-password}" | base64 --decode);echo

# Print the path to the repo, to be used by the Jenkins pipeline.
echo "https://source.developers.google.com/p/$GOOGLE_CLOUD_PROJECT/r/gceme"

# Go ahead and make the first change, to the canary branch.
git checkout -b canary
sed -i -e "s/REPLACE_WITH_YOUR_PROJECT_ID/$GOOGLE_CLOUD_PROJECT/g" ./Jenkinsfile
sed -i -e "s/card blue/card orange/g" ./html.go
sed -i -e "s/1\.0\.0/2\.0\.0/g" ./main.go
git add Jenkinsfile html.go main.go
git commit -m "Version 2"
git push origin canary

echo Done.
