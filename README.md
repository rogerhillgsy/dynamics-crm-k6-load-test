# Dynamics 365 CRM k6 load test

A standalone k6 project for exercising the Dynamics 365 / Dataverse Web API from a manually triggered Azure Container Apps Job. Each k6 iteration:

1. Looks up a contact by a generated email address or telephone number.
2. Creates the contact if it does not already exist.
3. Creates a phone call associated with that contact.
4. Waits a random 60-120 seconds.
5. Updates the phone call.

The generated contact identity includes the test run ID, virtual-user number, and iteration number. Reusing a `TEST_RUN_ID` lets a later run find the contacts from the earlier run instead of creating them again. Use a new run ID when you want fresh contacts.

## Project layout

- `k6/dynamics-crm.js` - k6 scenario and Dynamics Web API requests.
- `Dockerfile` - packages the script in the official k6 image.
- `infra/registry/main.bicep` and `infra/registry/registry.bicep` - create the resource group and Azure Container Registry.
- `infra/main.bicep` and `infra/workload.bicep` - deploy the Log Analytics workspace, Container Apps Environment, pull identity, and manual Job.
- `.github/workflows/validate.yml` - validates Bicep, the k6 script, and the container image on pushes and pull requests.

## Prerequisites

- An Azure subscription with permission to deploy the listed resources and create the `AcrPull` role assignment. The identity used for `az acr login` also needs `AcrPush` on the registry.
- A Microsoft Entra application configured for client-credentials authentication and a Dynamics 365 application user with permissions to read/create contacts and create/read/update phone calls.
- Docker for local image builds and tests; Azure CLI with the Bicep extension for deployment.
- A globally unique lowercase Azure Container Registry name (5-50 alphanumeric characters).

The application user must have the necessary Dataverse security roles in the target environment. Grant only the privileges required for the test. Keep all load testing within an authorized, non-production environment and within Dynamics service-protection limits.

## Configure and deploy

Sign in and set the subscription:

```powershell
az login
az account set --subscription "<subscription-id>"
```

Create the resource group and registry, then build and push an image. The registry template is safe to run again; the full deployment reuses its existing registry.

```powershell
$location = "eastus"
$resourceGroup = "rg-dynamics-crm-k6"
$registry = "<globally-unique-acr-name>"
$environment = "cae-dynamics-crm-k6"
$job = "job-dynamics-crm-k6"
$imageTag = "latest"
$crmUrl = "https://<environment>.crm.dynamics.com"
$tenantId = "<tenant-id>"
$clientId = "<application-client-id>"
$clientSecret = Read-Host "Dynamics application client secret" -AsSecureString
$clientSecretText = [System.Net.NetworkCredential]::new("", $clientSecret).Password
```

Create the registry:

```powershell
az deployment sub create `
  --name "dynamics-crm-k6-registry" `
  --location $location `
  --template-file infra/registry/main.bicep `
  --parameters `
    location=$location `
    resourceGroupName=$resourceGroup `
    registryName=$registry
```

Build and push the image:

```powershell
az acr login --name $registry
docker build --tag "${registry}.azurecr.io/dynamics-crm-k6:${imageTag}" .
docker push "${registry}.azurecr.io/dynamics-crm-k6:${imageTag}"
```

Deploy the Container Apps resources using the pushed image tag:

```powershell
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
    lookupField="email" `
    iterations=10 `
    virtualUsers=2 `
    maxDuration="30m"
```

The secure client-secret parameter updates the Job's secret; it is not emitted as a deployment output. For telephone lookup, set `lookupField="telephone"` and supply a `contactTelephonePrefix` appropriate for your test data. Synthetic email addresses use the `loadtest.example.invalid` domain by default; choose a domain accepted by your Dataverse environment if it validates email addresses.

The Job image is configured by Bicep but is not run during deployment. Start it explicitly:

```powershell
az containerapp job start `
  --name $job `
  --resource-group $resourceGroup
```

Inspect job executions and logs:

```powershell
az containerapp job execution list `
  --name $job `
  --resource-group $resourceGroup `
  --output table
```

Remove the resource group when the environment is no longer needed:

```powershell
az group delete --name $resourceGroup --yes --no-wait
```

## Run locally

Set the required environment variables before running the container. Use a test Entra application secret with the minimum necessary permissions; do not commit credentials or `.env` files.

```powershell
$env:CRM_BASE_URL = "https://<environment>.crm.dynamics.com"
$env:CRM_TENANT_ID = "<tenant-id>"
$env:CRM_CLIENT_ID = "<application-client-id>"
$env:CRM_CLIENT_SECRET = "<application-client-secret>"
$env:LOOKUP_FIELD = "email"
$env:ITERATIONS = "1"
$env:VUS = "1"
$env:TEST_RUN_ID = "local-smoke-test"

docker build --tag dynamics-crm-k6:local .
docker run --rm `
  --env CRM_BASE_URL `
  --env CRM_TENANT_ID `
  --env CRM_CLIENT_ID `
  --env CRM_CLIENT_SECRET `
  --env LOOKUP_FIELD `
  --env ITERATIONS `
  --env VUS `
  --env TEST_RUN_ID `
  dynamics-crm-k6:local
```

## GitHub

This directory is an independent project and can be published as its own repository. Create an empty repository in GitHub, then from this directory:

```powershell
git remote add origin https://github.com/<owner>/dynamics-crm-k6-load-test.git
git push --set-upstream origin main
```

The validation workflow needs no Azure credentials. Configure an Azure federated identity and a separate deployment workflow before automating deployments; keep the CRM client secret in a protected GitHub Environment secret or Azure Key Vault, never in repository variables or source control.


Ymc8Q~gMifH_MwrYwVLhx8mEcOFN0QHRlIdOubqB