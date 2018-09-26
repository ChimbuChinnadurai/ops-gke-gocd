# GoCD on Google Kuberentes Engine (GKE) [![Build Status](https://travis-ci.org/lzysh/ops-gke-gocd.svg?branch=master)](https://travis-ci.org/lzysh/ops-gke-gocd)
[Terraform](https://www.terraform.io) code for running [ThoughtWorks GoCD](https://www.gocd.org/) on [Google Kubernetes Engine (GKE)](https://cloud.google.com/kubernetes-engine).
# Dependencies
This project uses:
* [external-dns](https://github.com/kubernetes-incubator/external-dns) to synchronize Kubernetes ingress resources.
* [cert-manager](https://github.com/jetstack/cert-manager) to provision and manage TLS certificates using Let's Encrypt
# IaC Development Sandbox Setup on Linux
## Install Google Cloud SDK
```none
curl https://sdk.cloud.google.com | bash
exec -l $SHELL
gcloud init
gcloud components install kubectl
```
## Set Sandbox Tools Project
```none
export tools=<your project id>
gcloud config set project ${tools}
```
## Create Managed DNS Zone
```none
gcloud dns managed-zones create sb-domain-com --description="My Sandbox Zone" --dns-name="sb.domain.com"
```
## Add Record Set to Your Primary DNS Zone
```none
$ gcloud dns record-sets list --zone sb-domain-com
NAME          TYPE  TTL    DATA
sb.domain.com.  NS    21600  ns-cloud-a1.googledomains.com.,ns-cloud-a2.googledomains.com.,ns-cloud-a3.googledomains.com.,ns-cloud-a4.googledomains.com.
sb.domain.com.  SOA   21600  ns-cloud-a1.googledomains.com. cloud-dns-hostmaster.google.com. 1 21600 3600 259200 300
```
That shows your NS record, grab the DATA and and create a NS record on your primary zone. If you use Google Cloud DNS for that you can simply run the following: 
```none
gcloud --project <dns-project> dns record-sets transaction start -z=domain-com
gcloud --project <dns-project> dns record-sets transaction add -z=domain-com --name="sb.domain.com." --type=NS --ttl=300 "ns-cloud-a1.googledomains.com." "ns-cloud-a2.googledomains.com." "ns-cloud-a3.googledomains.com." "ns-cloud-a4.googledomains.com."
gcloud --project <dns-project> dns record-sets transaction execute -z=domain-com
```
## Create Bucket for Terraform Remote State
```none
gsutil mb -p ${tools} -c multi_regional -l US gs://${tools}_tf_state
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
terraform init -backend-config="bucket=${tools}_tf_state" -backend-config="project=${tools}"
```
> NOTE: At this point you are setup to use [remote state](https://www.terraform.io/docs/state/remote.html) in Terraform. 
## Setup Variables
Create a `local.tfvars` file and edit to fit you needs:
```none
cp local.tfvars.EXAMPLE local.tfvars
```
>NOTE: The folder_id variable will be the ID of the Sanbox folder your have the proper IAM roles set on.
## Terraform Plan & Apply
```none
random=$RANDOM
terraform plan -out="plan.out" -var-file="local.tfvars" -var="project=<gocd-project>-${random}-sb" -var="host=gocd-${random}"
terraform apply "plan.out"
```
It will take about 5-10 minutes after terraform apply is successful for the GoCD instance to be accessible. Ingress is doing its thing, DNS is being propagated and SSL certificates are being issued.

## Terraform Destroy
```none
terraform destroy -var-file="local.tfvars" -var="project=<gocd-project>-${random}-sb -var="host=gocd-${random}"
```
