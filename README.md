# GoCD on Google Kuberentes Engine [![Build Status](https://travis-ci.org/lzysh/ops-gke-gocd.svg?branch=master)](https://travis-ci.org/lzysh/ops-gke-gocd)

Operations code for running [ThoughtWorks GoCD](https://www.gocd.org/) on [Google Kubernetes Engine GKE](https://cloud.google.com/kubernetes-engine) with [Terraform](https://www.terraform.io)
# IaC Development Setup on Linux
## Install Google Cloud SDK
```none
curl https://sdk.cloud.google.com | bash
exec -l $SHELL
gcloud init
gcloud components install kubectl
```
## Set Project
```none
export sandbox=<your project id>
gcloud config set project ${sandbox}
```
## Create Managed DNS Zone
*NOTE: You don't actually need to have a domain registrar for code to run, however it’s needed if you want to generate a usable application with DNS and a SSL certificate from Let’s Encrypt.*
```none
gcloud dns managed-zones create obs-lzy-sh --description="My Sandbox Zone" --dns-name="obs.lzy.sh"
```
## Add Record Set to Your Tools Project Zone
```none
$ gcloud dns record-sets list --zone obs-lzy-sh
NAME          TYPE  TTL    DATA
obs.lzy.sh.  NS    21600  ns-cloud-a1.googledomains.com.,ns-cloud-a2.googledomains.com.,ns-cloud-a3.googledomains.com.,ns-cloud-a4.googledomains.com.
obs.lzy.sh.  SOA   21600  ns-cloud-a1.googledomains.com. cloud-dns-hostmaster.google.com. 1 21600 3600 259200 300
```
This will show your NS record, grab the DATA and and create a NS record on your registrar. The next step needs to be completed by a user with DNS Administrator IAM role for the tools project.
```none
gcloud --project ops-tools-prod dns record-sets transaction start -z=lzy-sh
gcloud --project ops-tools-prod dns record-sets transaction add -z=lzy-sh --name="obs.lzy.sh." --type=NS --ttl=300 "ns-cloud-a1.googledomains.com." "ns-cloud-a2.googledomains.com." "ns-cloud-a3.googledomains.com." "ns-cloud-a4.googledomains.com."
gcloud --project ops-tools-prod dns record-sets transaction execute -z=lzy-sh
```
## Create Bucket for Terraform Remote State
```none
gsutil mb -p ${sandbox} -c multi_regional -l US gs://${sandbox}_tf_state
```
## Install Terraform
```none
curl -O https://releases.hashicorp.com/terraform/0.11.8/terraform_0.11.8_linux_amd64.zip
sudo unzip terraform_0.11.8_linux_amd64.zip -d /usr/local/bin
```
## Setup Google Application Default Credentials
```none
gcloud auth application-default login
```
## Clone Project
```none
git clone git@github.com:lzysh/ops-gke-gocd.git
```
## Initialize Terraform
```none
cd ops-gke-gocd/terraform
terraform init -backend-config="bucket=${sandbox}_tf_state" -backend-config="project=${sandbox}"
```
> NOTE: At this point you are setup to use [remote state](https://www.terraform.io/docs/state/remote.html) in Terraform. 
Create a `local.tfvars` file and edit to fit you needs:
```none
cp local.tfvars.EXAMPLE local.tfvars
```
>NOTE: The folder_id variable will be the ID of the Sanbox folder your have the proper IAM roles set on.
## Terraform Plan & Apply
```none
random=$RANDOM
terraform plan -out="plan.out" -var-file="local.tfvars" -var="project=ops-gocd-${random}-sb" -var="host=gocd-${random}"
terraform apply "plan.out"
```
It will take about 5-10 minutes after terraform apply is successful for the Vault instance to be accessible. Ingress is doing its thing, DNS is being propagated and SSL certificates are being issued.
