$location = "uksouth"
$resourceGroup = "rg-dynamics-crm-k6"
$registry = "rbhconsultingacr"
$environment = "cae-dynamics-crm-k6"
$job = "job-dynamics-crm-k6"
$imageTag = "latest"
$crmUrl = "https://rbhcuk.crm11.dynamics.com"
$tenantId = "0699e5de-8e14-4867-bd8f-fef147a2b3e2"
$clientId = "e8c1ab45-d373-48bf-98b0-fa9a82008151"
$clientSecret = Read-Host "Dynamics application client secret" -AsSecureString
$clientSecretText = [System.Net.NetworkCredential]::new("", $clientSecret).Password

##
az deployment sub create `
  --name "dynamics-crm-k6-registry" `
  --location $location `
  --template-file infra/registry/main.bicep `
  --parameters `
    location=$location `
    resourceGroupName=$resourceGroup `
    registryName=$registry


az acr login --name $registry
docker build --tag "${registry}.azurecr.io/dynamics-crm-k6:${imageTag}" .
docker push "${registry}.azurecr.io/dynamics-crm-k6:${imageTag}"

##

az deployment sub create `
  --name "dynamics-crm-k6-job" `
  --location $location `
  --template-file infra/main.bicep `
  --parameters `
    location=$location `
    resourceGroupName=$resourceGroup `
    registryName=$registry `
    containerAppsEnvironmentName=$environment `
    jobName=$job `
    imageTag=$imageTag `
    crmBaseUrl=$crmUrl `
    crmTenantId=$tenantId `
    crmClientId=$clientId `
    crmClientSecret=$clientSecretText `
    lookupField="emailaddress1" `
    iterations=10 `
    virtualUsers=2 `
    maxDuration="30m"

    ##

    az containerapp job start `
  --name $job `
  --resource-group $resourceGroup

  ##
  az containerapp job execution list `
  --name $job `
  --resource-group $resourceGroup `
  --output table